-- | HTTP server for the Orchestrator web dashboard.
--
-- Serves the embedded dashboard HTML and JSON API endpoints on
-- configured interfaces. Never binds to 0.0.0.0.
module Orchestrator.UI.Server
  ( -- * Server
    startDashboard,
    ServerConfig (..),
    defaultServerConfig,

    -- * Binding
    BindAddress (..),
    parseBindAddrs,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar, readMVar)
import Control.Exception (SomeException, try)
import Control.Monad (void)
import Data.ByteString.Lazy qualified as LBS
import Data.String (fromString)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Network.HTTP.Types (status200, status404)
import Network.HTTP.Types.Header (hContentType)
import Network.Wai (Application, Response, pathInfo, responseLBS)
import Network.Wai.Handler.Warp
  ( Port,
    defaultSettings,
    runSettings,
    setHost,
    setPort,
  )
import Orchestrator.Config (OrchestratorConfig (..), defaultConfig)
import Orchestrator.Policy (PolicyPack (..), packRules)
import Orchestrator.Policy.Extended (extendedPolicyPack)
import Orchestrator.Scan (scanLocalPath)
import Orchestrator.Types
import Orchestrator.UI (DashboardData (..), renderAPIJSON, renderDashboardHTML)
import Orchestrator.Version (orchestratorEdition, orchestratorVersion)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)
import System.Info qualified as SI
import System.Process (CreateProcess (..), StdStream (..), createProcess, proc)
import Text.Read (readMaybe)

-- | Which address to bind to.
data BindAddress
  = -- | 127.0.0.1 (IPv4 loopback)
    BindLocalhost
  | -- | ::1 (IPv6 loopback)
    BindLocalhost6
  | -- | Custom IP address
    BindSpecific !Text
  deriving stock (Eq, Show)

-- | Server configuration.
data ServerConfig = ServerConfig
  { scPort :: !Port,
    scBindAddrs :: ![BindAddress],
    scScanPath :: !FilePath,
    scOpenBrowser :: !Bool
  }
  deriving stock (Eq, Show)

-- | Default server config: localhost only, port 8420, auto-open browser.
defaultServerConfig :: FilePath -> ServerConfig
defaultServerConfig path =
  ServerConfig
    { scPort = 8420,
      scBindAddrs = [BindLocalhost],
      scScanPath = path,
      scOpenBrowser = True
    }

-- | Resolve a BindAddress to an IP string.
resolveAddr :: BindAddress -> String
resolveAddr BindLocalhost = "127.0.0.1"
resolveAddr BindLocalhost6 = "::1"
resolveAddr (BindSpecific ip) = T.unpack ip

-- | Parse a comma-separated list of bind addresses.
parseBindAddrs :: Text -> [BindAddress]
parseBindAddrs input =
  let addrs = map T.strip $ T.splitOn "," input
   in map parseOne (filter (not . T.null) addrs)
  where
    parseOne "localhost" = BindLocalhost
    parseOne "127.0.0.1" = BindLocalhost
    parseOne "::1" = BindLocalhost6
    parseOne ip = BindSpecific ip

-- | Apply environment variable overrides to a ServerConfig.
applyEnvOverrides :: ServerConfig -> IO ServerConfig
applyEnvOverrides cfg = do
  mbBind <- lookupEnv "ORCHESTRATOR_BIND_ADDR"
  mbPort <- lookupEnv "ORCHESTRATOR_PORT"
  let cfg1 = case mbBind of
        Just s | not (null s) -> cfg {scBindAddrs = parseBindAddrs (T.pack s)}
        _ -> cfg
      cfg2 = case mbPort >>= readMaybe of
        Just p -> cfg1 {scPort = p}
        Nothing -> cfg1
  pure cfg2

-- | Compute rule count dynamically from the policy pack.
dynamicRuleCount :: Int
dynamicRuleCount = length (packRules extendedPolicyPack)

-- | Start the dashboard server on configured interfaces.
-- Spawns one warp instance per bind address.
startDashboard :: ServerConfig -> IO ()
startDashboard cfg0 = do
  -- Apply environment variable overrides
  cfg <- applyEnvOverrides cfg0

  -- Initial scan
  TIO.putStrLn "Scanning workflows..."
  let pack = extendedPolicyPack
      scfg = cfgScan defaultConfig
  scanResult <- scanLocalPath pack scfg (scScanPath cfg)

  -- Build dashboard data
  case scanResult of
    Left err -> hPutStrLn stderr $ "Initial scan failed: " ++ show err
    Right _ -> pure ()
  dataRef <- newMVar $ case scanResult of
    Left _ -> DashboardData [] Nothing dynamicRuleCount orchestratorVersion orchestratorEdition
    Right sr ->
      DashboardData
        { ddFindings = scanFindings sr,
          ddScanResult = Just sr,
          ddRuleCount = dynamicRuleCount,
          ddVersion = orchestratorVersion,
          ddEdition = orchestratorEdition
        }

  let app = dashboardApp dataRef (scScanPath cfg)
      port = scPort cfg
      addrs = scBindAddrs cfg

  -- Report binding info
  TIO.putStrLn ""
  TIO.putStrLn $ "Orchestrator Dashboard v" <> orchestratorVersion
  TIO.putStrLn (T.replicate 50 "─")

  -- Start a server on each configured interface
  case addrs of
    [] -> do
      TIO.putStrLn "ERROR: No bind addresses configured"
      pure ()
    [single] -> do
      let addr = resolveAddr single
      TIO.putStrLn $ "  Listening on http://" <> T.pack addr <> ":" <> T.pack (show port)
      TIO.putStrLn (T.replicate 50 "─")
      TIO.putStrLn "Press Ctrl+C to stop."
      TIO.putStrLn ""
      when (scOpenBrowser cfg) $ openBrowser addr port
      let settings = setHost (fromString addr) $ setPort port defaultSettings
      runSettings settings app
    (primary : rest) -> do
      -- Start secondary addresses in background threads
      mapM_
        ( \ba -> do
            let addr = resolveAddr ba
            TIO.putStrLn $ "  Listening on http://" <> T.pack addr <> ":" <> T.pack (show port)
            let settings = setHost (fromString addr) $ setPort port defaultSettings
            _ <- forkIO $ runSettings settings app
            pure ()
        )
        rest
      -- Start primary in foreground (blocks)
      let primaryAddr = resolveAddr primary
      TIO.putStrLn $ "  Listening on http://" <> T.pack primaryAddr <> ":" <> T.pack (show port)
      TIO.putStrLn (T.replicate 50 "─")
      TIO.putStrLn "Press Ctrl+C to stop."
      TIO.putStrLn ""
      when (scOpenBrowser cfg) $ openBrowser primaryAddr port
      let settings = setHost (fromString primaryAddr) $ setPort port defaultSettings
      runSettings settings app

-- | WAI application serving the dashboard.
dashboardApp :: MVar DashboardData -> FilePath -> Application
dashboardApp dataRef scanPath req respond = do
  let path = pathInfo req
  case path of
    -- Root: serve the HTML dashboard
    [] -> serveDashboard dataRef respond
    [""] -> serveDashboard dataRef respond
    -- API endpoints
    ["api", "health"] -> do
      dd <- readMVar dataRef
      respond $ jsonResponse $ renderAPIJSON dd
    ["api", "scan"] -> do
      dd <- readMVar dataRef
      respond $ jsonResponse $ renderAPIJSON dd
    ["api", "rescan"] -> do
      -- Re-scan and update
      let pack = extendedPolicyPack
          scfg = cfgScan defaultConfig
      result <- scanLocalPath pack scfg scanPath
      case result of
        Right sr -> do
          modifyMVar_ dataRef $ \_ ->
            pure $
              DashboardData
                { ddFindings = scanFindings sr,
                  ddScanResult = Just sr,
                  ddRuleCount = dynamicRuleCount,
                  ddVersion = orchestratorVersion,
                  ddEdition = orchestratorEdition
                }
          dd <- readMVar dataRef
          respond $ jsonResponse $ renderAPIJSON dd
        Left err -> do
          hPutStrLn stderr $ "Rescan failed: " ++ show err
          respond $ jsonResponse "{\"error\": \"scan failed\"}"

    -- 404
    _ ->
      respond $
        responseLBS
          status404
          [(hContentType, "text/plain")]
          "404 Not Found"

-- | Serve the HTML dashboard page.
serveDashboard :: MVar DashboardData -> (Response -> IO b) -> IO b
serveDashboard dataRef respond = do
  dd <- readMVar dataRef
  let html = renderDashboardHTML dd
  respond $
    responseLBS
      status200
      [(hContentType, "text/html; charset=utf-8")]
      (LBS.fromStrict $ TE.encodeUtf8 html)

-- | Create a JSON response.
jsonResponse :: Text -> Response
jsonResponse body =
  responseLBS
    status200
    [(hContentType, "application/json; charset=utf-8")]
    (LBS.fromStrict $ TE.encodeUtf8 body)

-- | Try to open the dashboard in the default browser.
openBrowser :: String -> Port -> IO ()
openBrowser addr port = do
  let url = "http://" ++ addr ++ ":" ++ show port
      cmd = case SI.os of
        "darwin" -> "open"
        "mingw32" -> "start"
        _ -> "xdg-open"
      cp =
        (proc cmd [url])
          { std_in = NoStream,
            std_out = NoStream,
            std_err = NoStream,
            close_fds = True
          }
  result <- try (void (createProcess cp)) :: IO (Either SomeException ())
  case result of
    Left _ -> hPutStrLn stderr $ "Open " ++ url ++ " in your browser."
    Right _ -> pure ()

-- | Control.Monad.when
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = pure ()
