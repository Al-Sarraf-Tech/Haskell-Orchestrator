-- | Configuration loading and validation for Orchestrator.
module Orchestrator.Config
  ( OrchestratorConfig (..),
    ScanConfig (..),
    PolicyConfig (..),
    OutputConfig (..),
    ResourceConfig (..),
    ParallelismProfile (..),
    CustomRuleConfig (..),
    RuleCondition (..),
    loadConfig,
    defaultConfig,
    validateConfig,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON (..), withObject, (.!=), (.:?))
import Data.ByteString qualified as BS
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Yaml qualified as Yaml
import Orchestrator.Types (OrchestratorError (..))

-- | Parallelism profile for resource control.
data ParallelismProfile = Safe | Balanced | Fast
  deriving stock (Eq, Show, Read)

instance FromJSON ParallelismProfile where
  parseJSON = Yaml.withText "ParallelismProfile" $ \t ->
    case t of
      "safe" -> pure Safe
      "balanced" -> pure Balanced
      "fast" -> pure Fast
      _ -> fail $ "Unknown parallelism profile: " ++ show t

-- | Scan-related configuration.
data ScanConfig = ScanConfig
  { scTargets :: ![Text],
    scExclude :: ![Text],
    scMaxDepth :: !Int,
    scFollowSymlinks :: !Bool
  }
  deriving stock (Eq, Show)

instance FromJSON ScanConfig where
  parseJSON = withObject "ScanConfig" $ \o ->
    ScanConfig
      <$> o .:? "targets" .!= []
      <*> o .:? "exclude" .!= []
      <*> o .:? "max_depth" .!= 10
      <*> o .:? "follow_symlinks" .!= False

-- | Policy-related configuration.
data PolicyConfig = PolicyConfig
  { pcPack :: !Text,
    pcMinSeverity :: !Text,
    pcDisabled :: ![Text]
  }
  deriving stock (Eq, Show)

instance FromJSON PolicyConfig where
  parseJSON = withObject "PolicyConfig" $ \o ->
    PolicyConfig
      <$> o .:? "pack" .!= "standard"
      <*> o .:? "min_severity" .!= "info"
      <*> o .:? "disabled" .!= []

-- | Output configuration.
data OutputConfig = OutputConfig
  { ocFormat :: !Text,
    ocVerbose :: !Bool,
    ocColor :: !Bool
  }
  deriving stock (Eq, Show)

instance FromJSON OutputConfig where
  parseJSON = withObject "OutputConfig" $ \o ->
    OutputConfig
      <$> o .:? "format" .!= "text"
      <*> o .:? "verbose" .!= False
      <*> o .:? "color" .!= True

-- | Resource control configuration.
data ResourceConfig = ResourceConfig
  { rcJobs :: !(Maybe Int),
    rcProfile :: !ParallelismProfile
  }
  deriving stock (Eq, Show)

instance FromJSON ResourceConfig where
  parseJSON = withObject "ResourceConfig" $ \o ->
    ResourceConfig
      <$> o .:? "jobs"
      <*> o .:? "profile" .!= Safe

-- | A condition that a custom rule checks against a workflow.
data RuleCondition
  = -- | Workflow permissions contain this string
    PermissionContains !Text
  | -- | Any action is not SHA-pinned
    ActionNotPinned
  | -- | Jobs missing a specific field (e.g., "timeout-minutes")
    JobMissingField !Text
  | -- | Workflow name must match this regex pattern
    WorkflowNamePattern !Text
  | -- | Step uses: field matches this pattern
    StepUsesPattern !Text
  | -- | Triggers contain this event name
    TriggerContains !Text
  | -- | Environment has this key
    EnvKeyPresent !Text
  | -- | Runner specification contains this string
    RunnerMatches !Text
  deriving stock (Eq, Show)

instance FromJSON RuleCondition where
  parseJSON = withObject "RuleCondition" $ \o -> do
    let tryField name constructor = fmap constructor <$> o .:? name
    mPermission <- tryField "permission_contains" PermissionContains
    mActionPin <- o .:? "action_not_pinned" :: Yaml.Parser (Maybe Bool)
    mJobField <- tryField "job_missing_field" JobMissingField
    mWfName <- tryField "workflow_name_pattern" WorkflowNamePattern
    mStepUses <- tryField "step_uses_pattern" StepUsesPattern
    mTrigger <- tryField "trigger_contains" TriggerContains
    mEnvKey <- tryField "env_key_present" EnvKeyPresent
    mRunner <- tryField "runner_matches" RunnerMatches
    let candidates =
          catMaybes
            [ mPermission,
              mJobField,
              mWfName,
              mStepUses,
              mTrigger,
              mEnvKey,
              mRunner,
              if mActionPin == Just True then Just ActionNotPinned else Nothing
            ]
    case candidates of
      [cond] -> pure cond
      [] -> fail "Custom rule condition must specify exactly one condition type"
      _ -> fail "Custom rule condition must specify exactly one condition type"

-- | Configuration for a user-defined policy rule.
data CustomRuleConfig = CustomRuleConfig
  { crcId :: !Text,
    crcName :: !Text,
    crcSeverity :: !Text,
    crcCategory :: !Text,
    crcConditions :: ![RuleCondition]
  }
  deriving stock (Eq, Show)

instance FromJSON CustomRuleConfig where
  parseJSON = withObject "CustomRuleConfig" $ \o ->
    CustomRuleConfig
      <$> o .:? "id" .!= "CUSTOM-000"
      <*> o .:? "name" .!= "Custom Rule"
      <*> o .:? "severity" .!= "Warning"
      <*> o .:? "category" .!= "Structure"
      <*> o .:? "conditions" .!= []

-- | Top-level configuration.
data OrchestratorConfig = OrchestratorConfig
  { cfgScan :: !ScanConfig,
    cfgPolicy :: !PolicyConfig,
    cfgOutput :: !OutputConfig,
    cfgResources :: !ResourceConfig,
    cfgCustomRules :: ![CustomRuleConfig]
  }
  deriving stock (Eq, Show)

instance FromJSON OrchestratorConfig where
  parseJSON = withObject "OrchestratorConfig" $ \o ->
    OrchestratorConfig
      <$> o .:? "scan" .!= defaultScanConfig
      <*> o .:? "policy" .!= defaultPolicyConfig
      <*> o .:? "output" .!= defaultOutputConfig
      <*> o .:? "resources" .!= defaultResourceConfig
      <*> o .:? "custom_rules" .!= []

defaultScanConfig :: ScanConfig
defaultScanConfig = ScanConfig [] [] 10 False

defaultPolicyConfig :: PolicyConfig
defaultPolicyConfig = PolicyConfig "standard" "info" []

defaultOutputConfig :: OutputConfig
defaultOutputConfig = OutputConfig "text" False True

defaultResourceConfig :: ResourceConfig
defaultResourceConfig = ResourceConfig Nothing Safe

-- | Default configuration.
defaultConfig :: OrchestratorConfig
defaultConfig =
  OrchestratorConfig
    { cfgScan = defaultScanConfig,
      cfgPolicy = defaultPolicyConfig,
      cfgOutput = defaultOutputConfig,
      cfgResources = defaultResourceConfig,
      cfgCustomRules = []
    }

-- | Load configuration from a YAML file.
loadConfig :: FilePath -> IO (Either OrchestratorError OrchestratorConfig)
loadConfig fp = do
  result <- try (BS.readFile fp) :: IO (Either SomeException BS.ByteString)
  case result of
    Left err ->
      pure $
        Left $
          ConfigError $
            "Failed to read config " <> showT fp <> ": " <> showT err
    Right bs -> case Yaml.decodeEither' bs of
      Left err ->
        pure $
          Left $
            ConfigError $
              "Failed to parse config "
                <> showT fp
                <> ": "
                <> showT (Yaml.prettyPrintParseException err)
      Right cfg -> pure $ validateConfig cfg
  where
    showT :: (Show a) => a -> Text
    showT = T.pack . show

-- | Validate a loaded configuration.
validateConfig :: OrchestratorConfig -> Either OrchestratorError OrchestratorConfig
validateConfig cfg
  | scMaxDepth (cfgScan cfg) < 1 =
      Left $ ConfigError "scan.max_depth must be >= 1"
  | scMaxDepth (cfgScan cfg) > 100 =
      Left $ ConfigError "scan.max_depth must be <= 100"
  | maybe False (< 1) (rcJobs (cfgResources cfg)) =
      Left $ ConfigError "resources.jobs must be >= 1"
  | maybe False (> 64) (rcJobs (cfgResources cfg)) =
      Left $ ConfigError "resources.jobs must be <= 64"
  | not (null invalidCustomIds) =
      Left $
        ConfigError $
          "Custom rule IDs must start with 'CUSTOM-': "
            <> T.intercalate ", " invalidCustomIds
  | not (null emptyConditions) =
      Left $
        ConfigError $
          "Custom rules must have at least one condition: "
            <> T.intercalate ", " emptyConditions
  | not (null dupIds) =
      Left $
        ConfigError $
          "Duplicate custom rule IDs: "
            <> T.intercalate ", " dupIds
  | otherwise = Right cfg
  where
    customRules = cfgCustomRules cfg
    invalidCustomIds =
      [ crcId r
      | r <- customRules,
        not (T.isPrefixOf "CUSTOM-" (crcId r))
      ]
    emptyConditions =
      [ crcId r
      | r <- customRules,
        null (crcConditions r)
      ]
    dupIds = findDups (map crcId customRules)
    findDups [] = []
    findDups (x : xs)
      | x `elem` xs = x : findDups (filter (/= x) xs)
      | otherwise = findDups xs
