-- | HTTP server for the Orchestrator web dashboard.
--
-- Serves the embedded dashboard HTML and JSON API endpoints on
-- LAN and Tailscale interfaces only. Never binds to 0.0.0.0.
module Orchestrator.UI.Server
  ( -- * Server
    startDashboard
  , ServerConfig (..)
  , defaultServerConfig
    -- * Binding
  , BindAddress (..)
  ) where

import Control.Concurrent (forkIO)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Network.HTTP.Types (status200, status404)
import Network.HTTP.Types.Header (hContentType)
import Network.Wai (Application, Response, pathInfo, responseLBS)
import Network.Wai.Handler.Warp
    ( Port, defaultSettings, runSettings, setHost, setPort )
import Data.String (fromString)
import System.IO (hPutStrLn, stderr)
import System.Process (callCommand)
import Control.Exception (try, SomeException)

import Orchestrator.Config (OrchestratorConfig (..), defaultConfig)
import Orchestrator.Policy.Extended (extendedPolicyPack)
import Orchestrator.Scan (scanLocalPath)
import Orchestrator.Types
import Orchestrator.UI (DashboardData (..), renderDashboardHTML, renderAPIJSON)

-- | Which address to bind to.
data BindAddress
  = BindLAN           -- ^ 192.168.50.5 (enp5s0)
  | BindTailscale     -- ^ 100.111.198.19 (tailscale0)
  | BindSpecific !Text -- ^ Custom IP address
  deriving stock (Eq, Show)

-- | Server configuration.
data ServerConfig = ServerConfig
  { scPort      :: !Port
  , scBindAddrs :: ![BindAddress]
  , scScanPath  :: !FilePath
  , scOpenBrowser :: !Bool
  } deriving stock (Eq, Show)

-- | Default server config: LAN + Tailscale, port 8420, auto-open browser.
defaultServerConfig :: FilePath -> ServerConfig
defaultServerConfig path = ServerConfig
  { scPort = 8420
  , scBindAddrs = [BindLAN, BindTailscale]
  , scScanPath = path
  , scOpenBrowser = True
  }

-- | Resolve a BindAddress to an IP string.
resolveAddr :: BindAddress -> String
resolveAddr BindLAN = "192.168.50.5"
resolveAddr BindTailscale = "100.111.198.19"
resolveAddr (BindSpecific ip) = T.unpack ip

-- | Start the dashboard server on configured interfaces.
-- Spawns one warp instance per bind address.
startDashboard :: ServerConfig -> IO ()
startDashboard cfg = do
  -- Initial scan
  TIO.putStrLn "Scanning workflows..."
  let pack = extendedPolicyPack
      scfg = cfgScan defaultConfig
  scanResult <- scanLocalPath pack scfg (scScanPath cfg)

  -- Build dashboard data
  dataRef <- newIORef $ case scanResult of
    Left _ -> DashboardData [] Nothing 21 "2.5.0" "Enterprise"
    Right sr -> DashboardData
      { ddFindings = scanFindings sr
      , ddScanResult = Just sr
      , ddRuleCount = 21
      , ddVersion = "2.5.0"
      , ddEdition = "Enterprise"
      }

  let app = dashboardApp dataRef (scScanPath cfg)
      port = scPort cfg
      addrs = scBindAddrs cfg

  -- Report binding info
  TIO.putStrLn ""
  TIO.putStrLn "Orchestrator Dashboard v2.5.0"
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
    (primary:rest) -> do
      -- Start secondary addresses in background threads
      mapM_ (\ba -> do
        let addr = resolveAddr ba
        TIO.putStrLn $ "  Listening on http://" <> T.pack addr <> ":" <> T.pack (show port)
        let settings = setHost (fromString addr) $ setPort port defaultSettings
        _ <- forkIO $ runSettings settings app
        pure ()
        ) rest
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
dashboardApp :: IORef DashboardData -> FilePath -> Application
dashboardApp dataRef scanPath req respond = do
  let path = pathInfo req
  case path of
    -- Root: serve the HTML dashboard
    [] -> serveDashboard dataRef respond
    [""] -> serveDashboard dataRef respond

    -- API endpoints
    ["api", "health"] -> do
      dd <- readIORef dataRef
      respond $ jsonResponse $ renderAPIJSON dd

    ["api", "scan"] -> do
      dd <- readIORef dataRef
      respond $ jsonResponse $ renderAPIJSON dd

    ["api", "rescan"] -> do
      -- Re-scan and update
      let pack = extendedPolicyPack
          scfg = cfgScan defaultConfig
      result <- scanLocalPath pack scfg scanPath
      case result of
        Right sr -> do
          writeIORef dataRef $ DashboardData
            { ddFindings = scanFindings sr
            , ddScanResult = Just sr
            , ddRuleCount = 21
            , ddVersion = "2.5.0"
            , ddEdition = "Enterprise"
            }
          dd <- readIORef dataRef
          respond $ jsonResponse $ renderAPIJSON dd
        Left _ ->
          respond $ jsonResponse "{\"error\": \"scan failed\"}"

    -- 404
    _ -> respond $ responseLBS status404
           [(hContentType, "text/plain")]
           "404 Not Found"

-- | Serve the HTML dashboard page.
serveDashboard :: IORef DashboardData -> (Response -> IO b) -> IO b
serveDashboard dataRef respond = do
  dd <- readIORef dataRef
  let html = renderDashboardHTML dd
  respond $ responseLBS status200
    [(hContentType, "text/html; charset=utf-8")]
    (LBS.fromStrict $ TE.encodeUtf8 html)

-- | Create a JSON response.
jsonResponse :: Text -> Response
jsonResponse body = responseLBS status200
  [(hContentType, "application/json; charset=utf-8")]
  (LBS.fromStrict $ TE.encodeUtf8 body)

-- | Try to open the dashboard in the default browser.
openBrowser :: String -> Port -> IO ()
openBrowser addr port = do
  let url = "http://" ++ addr ++ ":" ++ show port
  result <- try (callCommand $ "xdg-open " ++ url ++ " 2>/dev/null &") :: IO (Either SomeException ())
  case result of
    Left _ -> hPutStrLn stderr $ "Open " ++ url ++ " in your browser."
    Right _ -> pure ()

-- | Control.Monad.when
when :: Bool -> IO () -> IO ()
when True action = action
when False _ = pure ()
