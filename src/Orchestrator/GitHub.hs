-- | GitHub API integration for remote workflow scanning.
--
-- Fetches workflow files from GitHub repositories via the REST API.
-- Requires a GITHUB_TOKEN environment variable for private repos.
-- All network I/O is explicit and opt-in — local scanning remains
-- the default with zero network activity.
module Orchestrator.GitHub
  ( -- * Configuration
    GitHubConfig (..)
  , defaultGitHubConfig
    -- * Fetching
  , fetchWorkflowFiles
  , fetchOrgRepos
    -- * Scanning
  , scanRemoteRepo
  , scanRemoteOrg
    -- * Errors
  , GitHubError (..)
  ) where

import Control.Exception (SomeException, try)
import Data.Word (Word8)
import Data.Aeson (FromJSON (..), (.:), (.:?), (.!=), withObject, eitherDecode)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BSC
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Client
    ( Manager, Request (..), Response (..)
    , httpLbs, parseRequest
    , responseBody, responseStatus, responseHeaders
    )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types.Status (statusCode)
import Orchestrator.Parser (parseWorkflowBS)
import Orchestrator.Policy (PolicyPack, evaluatePolicies)
import Orchestrator.Types
import Orchestrator.Version (orchestratorVersion)

-- | Errors specific to GitHub API operations.
data GitHubError
  = GitHubHttpError !Int !Text
  | GitHubRateLimited !Int           -- ^ seconds until reset
  | GitHubNotFound !Text
  | GitHubAuthError !Text
  | GitHubParseError !Text
  | GitHubNetworkError !Text
  deriving stock (Eq, Show)

-- | Configuration for GitHub API access.
data GitHubConfig = GitHubConfig
  { ghcToken       :: !(Maybe Text)   -- ^ GitHub token (from GITHUB_TOKEN)
  , ghcApiUrl      :: !Text           -- ^ Base API URL (default: api.github.com)
  , ghcTimeout     :: !Int            -- ^ Request timeout in seconds
  , ghcMaxWait     :: !Int            -- ^ Max seconds to wait for rate limit reset
  , ghcIncludeArchived :: !Bool       -- ^ Include archived repos in org scans
  , ghcIncludeForks    :: !Bool       -- ^ Include forked repos in org scans
  } deriving stock (Eq, Show)

-- | Default configuration for github.com.
defaultGitHubConfig :: Maybe Text -> GitHubConfig
defaultGitHubConfig mToken = GitHubConfig
  { ghcToken       = mToken
  , ghcApiUrl      = "https://api.github.com"
  , ghcTimeout     = 30
  , ghcMaxWait     = 60
  , ghcIncludeArchived = False
  , ghcIncludeForks    = False
  }

-- | A workflow file fetched from GitHub.
data RemoteWorkflowFile = RemoteWorkflowFile
  { rwfName    :: !Text
  , rwfPath    :: !Text
  , rwfContent :: !BS.ByteString
  } deriving stock (Show)

-- | A repository entry from the GitHub API.
data RepoEntry = RepoEntry
  { reName     :: !Text
  , reFullName :: !Text
  , reArchived :: !Bool
  , reFork     :: !Bool
  } deriving stock (Show)

instance FromJSON RepoEntry where
  parseJSON = withObject "RepoEntry" $ \o -> RepoEntry
    <$> o .: "name"
    <*> o .: "full_name"
    <*> o .:? "archived" .!= False
    <*> o .:? "fork" .!= False

------------------------------------------------------------------------
-- API Helpers
------------------------------------------------------------------------

makeGitHubRequest :: GitHubConfig -> Text -> IO Request
makeGitHubRequest cfg path = do
  let url = T.unpack (ghcApiUrl cfg) <> T.unpack path
  req <- parseRequest url
  let headers = [ ("User-Agent", TE.encodeUtf8 $ "haskell-orchestrator/" <> orchestratorVersion)
                , ("Accept", "application/vnd.github.v3+json")
                ] ++ maybe [] (\t -> [("Authorization", "token " <> TE.encodeUtf8 t)]) (ghcToken cfg)
  pure req { requestHeaders = headers }

doRequest :: Manager -> GitHubConfig -> Text -> IO (Either GitHubError LBS.ByteString)
doRequest mgr cfg path = do
  result <- try $ do
    req <- makeGitHubRequest cfg path
    httpLbs req mgr
  case result of
    Left (e :: SomeException) ->
      pure $ Left $ GitHubNetworkError (T.pack (show e))
    Right resp ->
      let status = statusCode (responseStatus resp)
          body = responseBody resp
      in case status of
        200 -> pure $ Right body
        403 ->
          -- Check for rate limiting
          let retryAfter = lookup "Retry-After" (responseHeaders resp)
          in case retryAfter of
            Just secs -> pure $ Left $ GitHubRateLimited
              (maybe 60 (read . BSC.unpack) (Just secs))
            Nothing -> pure $ Left $ GitHubRateLimited 60
        404 -> pure $ Left $ GitHubNotFound path
        401 -> pure $ Left $ GitHubAuthError "Token is invalid or lacks required scopes"
        _   -> pure $ Left $ GitHubHttpError status
                 (T.pack $ show $ LBS.take 200 body)

------------------------------------------------------------------------
-- Fetching
------------------------------------------------------------------------

-- | Fetch workflow files from a GitHub repository.
fetchWorkflowFiles :: Manager -> GitHubConfig -> Text -> Text
                   -> IO (Either GitHubError [RemoteWorkflowFile])
fetchWorkflowFiles mgr cfg owner repo = do
  let path = "/repos/" <> owner <> "/" <> repo <> "/contents/.github/workflows"
  result <- doRequest mgr cfg path
  case result of
    Left (GitHubNotFound _) -> pure $ Right []  -- No workflows directory
    Left err -> pure $ Left err
    Right body -> case eitherDecode body of
      Left e -> pure $ Left $ GitHubParseError (T.pack e)
      Right entries -> do
        files <- mapM (fetchFileContent mgr cfg owner repo) entries
        pure $ Right [ f | Right f <- files ]

-- | A directory entry from the GitHub API.
data DirEntry = DirEntry
  { deName :: !Text
  , dePath :: !Text
  , deType :: !Text
  } deriving stock (Show)

instance FromJSON DirEntry where
  parseJSON = withObject "DirEntry" $ \o -> DirEntry
    <$> o .: "name"
    <*> o .: "path"
    <*> o .: "type"

fetchFileContent :: Manager -> GitHubConfig -> Text -> Text -> DirEntry
                 -> IO (Either GitHubError RemoteWorkflowFile)
fetchFileContent mgr cfg owner repo entry
  | deType entry /= "file" = pure $ Left $ GitHubParseError "Not a file"
  | not (isWorkflowFile (deName entry)) = pure $ Left $ GitHubParseError "Not a workflow file"
  | otherwise = do
      let path = "/repos/" <> owner <> "/" <> repo <> "/contents/" <> dePath entry
      result <- doRequest mgr cfg (path <> "?ref=HEAD")
      case result of
        Left err -> pure $ Left err
        Right body -> case eitherDecode body of
          Left e -> pure $ Left $ GitHubParseError (T.pack e)
          Right fileResp -> case frContent fileResp of
            Nothing -> pure $ Left $ GitHubParseError "No content in file response"
            Just content ->
              let decoded = decodeBase64 (T.filter (/= '\n') content)
              in pure $ Right RemoteWorkflowFile
                { rwfName = deName entry
                , rwfPath = dePath entry
                , rwfContent = decoded
                }

data FileResponse = FileResponse
  { frContent  :: !(Maybe Text)
  , frEncoding :: !(Maybe Text)
  } deriving stock (Show)

instance FromJSON FileResponse where
  parseJSON = withObject "FileResponse" $ \o -> FileResponse
    <$> o .:? "content"
    <*> o .:? "encoding"

isWorkflowFile :: Text -> Bool
isWorkflowFile name = T.isSuffixOf ".yml" name || T.isSuffixOf ".yaml" name

-- | Simple base64 decoder (GitHub API returns base64-encoded file content).
-- Uses Word8 arithmetic to decode RFC 4648 base64.
decodeBase64 :: Text -> BS.ByteString
decodeBase64 txt =
  let cleaned = filter (\c -> c /= '\n' && c /= '\r' && c /= ' ') (T.unpack txt)
      bytes = map fromEnum cleaned :: [Int]
  in BS.pack (decode64 bytes)
  where
    decode64 :: [Int] -> [Word8]
    decode64 [] = []
    decode64 xs =
      let (chunk, rest) = splitAt 4 xs
      in decodeChunk (map b64val chunk) ++ decode64 rest

    decodeChunk :: [Int] -> [Word8]
    decodeChunk [a, b, c, d]
      | c == -1   = [fromIntegral (a * 4 + b `div` 16)]
      | d == -1   = [fromIntegral (a * 4 + b `div` 16)
                     ,fromIntegral ((b `mod` 16) * 16 + c `div` 4)]
      | otherwise = [fromIntegral (a * 4 + b `div` 16)
                     ,fromIntegral ((b `mod` 16) * 16 + c `div` 4)
                     ,fromIntegral ((c `mod` 4) * 64 + d)]
    decodeChunk _ = []

    b64val :: Int -> Int
    b64val c
      | c >= 65 && c <= 90  = c - 65        -- A-Z
      | c >= 97 && c <= 122 = c - 97 + 26   -- a-z
      | c >= 48 && c <= 57  = c - 48 + 52   -- 0-9
      | c == 43             = 62             -- +
      | c == 47             = 63             -- /
      | c == 61             = -1             -- = (padding)
      | otherwise           = -1

-- | Fetch repository list for an organisation.
fetchOrgRepos :: Manager -> GitHubConfig -> Text
              -> IO (Either GitHubError [RepoEntry])
fetchOrgRepos mgr cfg org = do
  fetchAllPages mgr cfg ("/orgs/" <> org <> "/repos?per_page=100&type=all") []

fetchAllPages :: Manager -> GitHubConfig -> Text -> [RepoEntry]
              -> IO (Either GitHubError [RepoEntry])
fetchAllPages mgr cfg path acc = do
  result <- doRequest mgr cfg path
  case result of
    Left err -> pure $ Left err
    Right body -> case eitherDecode body of
      Left e -> pure $ Left $ GitHubParseError (T.pack e)
      Right entries ->
        let filtered = filterRepos cfg entries
            newAcc = acc ++ filtered
        in if length entries < 100
          then pure $ Right newAcc
          else do
            let nextPage = path <> "&page=" <> T.pack (show (length newAcc `div` 100 + 1))
            fetchAllPages mgr cfg nextPage newAcc

filterRepos :: GitHubConfig -> [RepoEntry] -> [RepoEntry]
filterRepos cfg = filter keep
  where
    keep r = (ghcIncludeArchived cfg || not (reArchived r))
          && (ghcIncludeForks cfg || not (reFork r))

------------------------------------------------------------------------
-- Scanning
------------------------------------------------------------------------

-- | Scan a single remote repository.
scanRemoteRepo :: PolicyPack -> GitHubConfig -> Text -> Text
               -> IO (Either GitHubError ScanResult)
scanRemoteRepo pack cfg owner repo = do
  mgr <- newTlsManager
  result <- fetchWorkflowFiles mgr cfg owner repo
  case result of
    Left err -> pure $ Left err
    Right files -> do
      let parsed = [ parseWorkflowBS (T.unpack (rwfName f)) (rwfContent f)
                   | f <- files ]
          workflows = [ wf | Right wf <- parsed ]
          findings = concatMap (evaluatePolicies pack) workflows
      pure $ Right ScanResult
        { scanTarget = GitHubRepo owner repo
        , scanFindings = findings
        , scanFiles = map (T.unpack . rwfPath) files
        , scanTime = Nothing
        }

-- | Scan all repositories in a GitHub organisation.
scanRemoteOrg :: PolicyPack -> GitHubConfig -> Text
              -> IO (Either GitHubError [ScanResult])
scanRemoteOrg pack cfg org = do
  mgr <- newTlsManager
  reposResult <- fetchOrgRepos mgr cfg org
  case reposResult of
    Left err -> pure $ Left err
    Right repos -> do
      results <- mapM (scanOneRepo mgr pack cfg) repos
      pure $ Right [ sr | Right sr <- results ]

scanOneRepo :: Manager -> PolicyPack -> GitHubConfig -> RepoEntry
            -> IO (Either GitHubError ScanResult)
scanOneRepo mgr pack cfg entry = do
  let (owner, repo) = splitFullName (reFullName entry)
  filesResult <- fetchWorkflowFiles mgr cfg owner repo
  case filesResult of
    Left err -> pure $ Left err
    Right files -> do
      let parsed = [ parseWorkflowBS (T.unpack (rwfName f)) (rwfContent f)
                   | f <- files ]
          workflows = [ wf | Right wf <- parsed ]
          findings = concatMap (evaluatePolicies pack) workflows
      pure $ Right ScanResult
        { scanTarget = GitHubRepo owner repo
        , scanFindings = findings
        , scanFiles = map (T.unpack . rwfPath) files
        , scanTime = Nothing
        }

splitFullName :: Text -> (Text, Text)
splitFullName fullName =
  case T.breakOn "/" fullName of
    (owner, rest)
      | T.null rest -> (fullName, fullName)
      | otherwise   -> (owner, T.drop 1 rest)
