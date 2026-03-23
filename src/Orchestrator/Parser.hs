-- | YAML parser for GitHub Actions workflow files.
--
-- Parses raw YAML into the typed 'Workflow' domain model defined in
-- "Orchestrator.Model".  Produces structured errors on parse failure.
module Orchestrator.Parser
  ( parseWorkflow
  , parseWorkflowFile
  , parseWorkflowBS
  ) where

import Data.Aeson (Object, Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Control.Exception (SomeException, try)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Yaml qualified as Yaml
import Orchestrator.Model
import Orchestrator.Types (OrchestratorError (..))

-- | Parse a workflow from a file path.
parseWorkflowFile :: FilePath -> IO (Either OrchestratorError Workflow)
parseWorkflowFile fp = do
  result <- try (BS.readFile fp) :: IO (Either SomeException BS.ByteString)
  case result of
    Left err -> pure $ Left $ ParseError fp (T.pack $ show err)
    Right bs -> pure $ parseWorkflowBS fp bs

-- | Parse a workflow from a ByteString with a filename for error context.
parseWorkflowBS :: FilePath -> ByteString -> Either OrchestratorError Workflow
parseWorkflowBS fp bs =
  case Yaml.decodeEither' bs of
    Left err -> Left $ ParseError fp (T.pack $ Yaml.prettyPrintParseException err)
    Right val -> parseWorkflow fp val

-- | Parse a workflow from a decoded YAML Value.
parseWorkflow :: FilePath -> Value -> Either OrchestratorError Workflow
parseWorkflow fp (Object obj) = do
  let name = extractText "name" obj `orDefault` T.pack fp
  triggers <- parseTriggers fp obj
  jobs <- parseJobs fp obj
  let perms = parsePermissions =<< KM.lookup "permissions" obj
  let conc = parseConcurrency =<< KM.lookup "concurrency" obj
  let env = extractEnvMap "env" obj
  Right Workflow
    { wfName = name
    , wfFileName = fp
    , wfTriggers = triggers
    , wfJobs = jobs
    , wfPermissions = perms
    , wfConcurrency = conc
    , wfEnv = env
    }
parseWorkflow fp _ = Left $ ParseError fp "Workflow must be a YAML mapping"

orDefault :: Maybe Text -> Text -> Text
orDefault = flip fromMaybe

extractText :: Text -> Object -> Maybe Text
extractText key obj =
  case KM.lookup (Key.fromText key) obj of
    Just (String t) -> Just t
    Just (Number n) -> Just (T.pack $ show n)
    Just (Bool b)   -> Just (if b then "true" else "false")
    _               -> Nothing

extractEnvMap :: Text -> Object -> EnvMap
extractEnvMap key obj =
  case KM.lookup (Key.fromText key) obj of
    Just (Object envObj) ->
      Map.fromList
        [ (Key.toText k, toText v)
        | (k, v) <- KM.toList envObj
        ]
    _ -> Map.empty

toText :: Value -> Text
toText (String t) = t
toText (Number n) = T.pack $ show n
toText (Bool b)   = if b then "true" else "false"
toText _          = ""

parseTriggers :: FilePath -> Object -> Either OrchestratorError [WorkflowTrigger]
parseTriggers fp obj =
  case KM.lookup "on" obj of
    Nothing -> case KM.lookup (Key.fromText "true") obj of
      -- YAML parses bare `on:` as boolean true sometimes
      _ -> Left $ ParseError fp "Workflow missing 'on' trigger block"
    Just val -> Right $ parseTriggerValue val

parseTriggerValue :: Value -> [WorkflowTrigger]
parseTriggerValue (String s) =
  [TriggerEvents [TriggerEvent s [] [] []]]
parseTriggerValue (Array arr) =
  [TriggerEvents [TriggerEvent (toText v) [] [] [] | v <- foldr (:) [] arr]]
parseTriggerValue (Object obj) =
  let events = mapMaybe parseEventEntry (KM.toList obj)
      scheds = case KM.lookup "schedule" obj of
        Just (Array arr) ->
          [ TriggerCron (fromMaybe "" $ extractText "cron"
              (case v of Object o -> o; _ -> KM.empty))
          | v <- foldr (:) [] arr
          ]
        _ -> []
      dispatch = [TriggerDispatch | KM.member "workflow_dispatch" obj]
  in  (if null events then [] else [TriggerEvents events])
      ++ scheds ++ dispatch
parseTriggerValue _ = []

parseEventEntry :: (Key.Key, Value) -> Maybe TriggerEvent
parseEventEntry (k, _)
  | Key.toText k `elem` ["schedule", "workflow_dispatch"] = Nothing
parseEventEntry (k, Object details) = Just TriggerEvent
  { triggerName = Key.toText k
  , triggerBranches = extractStringList "branches" details
  , triggerPaths = extractStringList "paths" details
  , triggerTags = extractStringList "tags" details
  }
parseEventEntry (k, Null) = Just $ TriggerEvent (Key.toText k) [] [] []
parseEventEntry (k, _) = Just $ TriggerEvent (Key.toText k) [] [] []

extractStringList :: Text -> Object -> [Text]
extractStringList key obj =
  case KM.lookup (Key.fromText key) obj of
    Just (Array arr) -> [toText v | v <- foldr (:) [] arr]
    Just (String s)  -> [s]
    _                -> []

parseJobs :: FilePath -> Object -> Either OrchestratorError [Job]
parseJobs fp obj =
  case KM.lookup "jobs" obj of
    Nothing -> Left $ ParseError fp "Workflow missing 'jobs' block"
    Just (Object jobsObj) ->
      Right [parseJob (Key.toText k) v | (k, v) <- KM.toList jobsObj]
    Just _ -> Left $ ParseError fp "'jobs' must be a mapping"

parseJob :: Text -> Value -> Job
parseJob jid (Object obj) =
  let (ff, inclOnly) = parseStrategy $ KM.lookup "strategy" obj
  in Job
  { jobId = jid
  , jobName = extractText "name" obj
  , jobRunsOn = parseRunner $ KM.lookup "runs-on" obj
  , jobSteps = parseSteps $ KM.lookup "steps" obj
  , jobPermissions = parsePermissions =<< KM.lookup "permissions" obj
  , jobNeeds = extractStringList "needs" obj
  , jobConcurrency = parseConcurrency =<< KM.lookup "concurrency" obj
  , jobEnv = extractEnvMap "env" obj
  , jobIf = extractText "if" obj
  , jobTimeoutMin = case KM.lookup "timeout-minutes" obj of
      Just (Number n) -> Just (round n)
      _               -> Nothing
  , jobEnvironment = parseEnvironment $ KM.lookup "environment" obj
  , jobEnvironmentUrl = parseEnvironmentUrl $ KM.lookup "environment" obj
  , jobFailFast = ff
  , jobMatrixIncludeOnly = inclOnly
  }
parseJob jid _ = Job jid Nothing (StandardRunner "ubuntu-latest") [] Nothing [] Nothing Map.empty Nothing Nothing Nothing False Nothing False

-- | Parse the 'environment:' field. Handles both string form
-- (environment: release) and object form (environment: {name: release, url: ...}).
parseEnvironment :: Maybe Value -> Maybe Text
parseEnvironment (Just (String s)) = Just s
parseEnvironment (Just (Object envObj)) = extractText "name" envObj
parseEnvironment _ = Nothing

-- | Check if the environment object form has a 'url' field.
parseEnvironmentUrl :: Maybe Value -> Bool
parseEnvironmentUrl (Just (Object envObj)) = case extractText "url" envObj of
  Just _ -> True
  Nothing -> False
parseEnvironmentUrl _ = False

-- | Parse the strategy block, extracting fail-fast and whether the matrix
-- uses only 'include:' entries (no cross-product dimensions).
parseStrategy :: Maybe Value -> (Maybe Bool, Bool)
parseStrategy (Just (Object strat)) =
  let ff = case KM.lookup "fail-fast" strat of
        Just (Bool b) -> Just b
        _             -> Nothing
      inclOnly = case KM.lookup "matrix" strat of
        Just (Object mat) ->
          let keys = map Key.toText $ KM.keys mat
          in keys == ["include"]
        _ -> False
  in (ff, inclOnly)
parseStrategy _ = (Nothing, False)

parseRunner :: Maybe Value -> RunnerSpec
parseRunner (Just (String s))
  | "${{" `T.isPrefixOf` s = MatrixRunner s
  | s `elem` knownRunners  = StandardRunner s
  | otherwise              = CustomLabel s
parseRunner (Just (Array arr)) =
  let labels = [toText v | v <- foldr (:) [] arr]
  in CustomLabel (T.intercalate ", " labels)
parseRunner _ = StandardRunner "ubuntu-latest"

knownRunners :: [Text]
knownRunners =
  [ "ubuntu-latest", "ubuntu-22.04", "ubuntu-24.04"
  , "macos-latest", "macos-14", "macos-15"
  , "windows-latest", "windows-2022", "windows-2025"
  ]

parseSteps :: Maybe Value -> [Step]
parseSteps (Just (Array arr)) = map parseStep (foldr (:) [] arr)
parseSteps _ = []

parseStep :: Value -> Step
parseStep (Object obj) = Step
  { stepId   = extractText "id" obj
  , stepName = extractText "name" obj
  , stepUses = extractText "uses" obj
  , stepRun  = extractText "run" obj
  , stepWith = extractEnvMap "with" obj
  , stepEnv  = extractEnvMap "env" obj
  , stepIf   = extractText "if" obj
  , stepShell = extractText "shell" obj
  }
parseStep _ = Step Nothing Nothing Nothing Nothing Map.empty Map.empty Nothing Nothing

parsePermissions :: Value -> Maybe Permissions
parsePermissions (String "read-all")  = Just $ PermissionsAll PermRead
parsePermissions (String "write-all") = Just $ PermissionsAll PermWrite
parsePermissions (Object obj) = Just $ PermissionsMap $
  Map.fromList
    [ (Key.toText k, parsePermLevel v)
    | (k, v) <- KM.toList obj
    ]
parsePermissions _ = Nothing

parsePermLevel :: Value -> PermissionLevel
parsePermLevel (String "read")  = PermRead
parsePermLevel (String "write") = PermWrite
parsePermLevel (String "none")  = PermNone
parsePermLevel _                = PermRead

parseConcurrency :: Value -> Maybe ConcurrencyConfig
parseConcurrency (String s) = Just $ ConcurrencyConfig s False
parseConcurrency (Object obj) = Just ConcurrencyConfig
  { concGroup = fromMaybe "" $ extractText "group" obj
  , concCancelInProgress =
      case KM.lookup "cancel-in-progress" obj of
        Just (Bool b) -> b
        _             -> False
  }
parseConcurrency _ = Nothing
