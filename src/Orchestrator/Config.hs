-- | Configuration loading and validation for Orchestrator.
module Orchestrator.Config
  ( OrchestratorConfig (..)
  , ScanConfig (..)
  , PolicyConfig (..)
  , OutputConfig (..)
  , ResourceConfig (..)
  , ParallelismProfile (..)
  , loadConfig
  , defaultConfig
  , validateConfig
  ) where

import Data.Aeson (FromJSON (..), (.:?), (.!=), withObject)
import Data.ByteString qualified as BS
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
      "safe"     -> pure Safe
      "balanced" -> pure Balanced
      "fast"     -> pure Fast
      _          -> fail $ "Unknown parallelism profile: " ++ show t

-- | Scan-related configuration.
data ScanConfig = ScanConfig
  { scTargets      :: ![Text]
  , scExclude      :: ![Text]
  , scMaxDepth     :: !Int
  , scFollowSymlinks :: !Bool
  } deriving stock (Eq, Show)

instance FromJSON ScanConfig where
  parseJSON = withObject "ScanConfig" $ \o -> ScanConfig
    <$> o .:? "targets" .!= []
    <*> o .:? "exclude" .!= []
    <*> o .:? "max_depth" .!= 10
    <*> o .:? "follow_symlinks" .!= False

-- | Policy-related configuration.
data PolicyConfig = PolicyConfig
  { pcPack       :: !Text
  , pcMinSeverity :: !Text
  , pcDisabled   :: ![Text]
  } deriving stock (Eq, Show)

instance FromJSON PolicyConfig where
  parseJSON = withObject "PolicyConfig" $ \o -> PolicyConfig
    <$> o .:? "pack" .!= "standard"
    <*> o .:? "min_severity" .!= "info"
    <*> o .:? "disabled" .!= []

-- | Output configuration.
data OutputConfig = OutputConfig
  { ocFormat  :: !Text
  , ocVerbose :: !Bool
  , ocColor   :: !Bool
  } deriving stock (Eq, Show)

instance FromJSON OutputConfig where
  parseJSON = withObject "OutputConfig" $ \o -> OutputConfig
    <$> o .:? "format" .!= "text"
    <*> o .:? "verbose" .!= False
    <*> o .:? "color" .!= True

-- | Resource control configuration.
data ResourceConfig = ResourceConfig
  { rcJobs        :: !(Maybe Int)
  , rcProfile     :: !ParallelismProfile
  } deriving stock (Eq, Show)

instance FromJSON ResourceConfig where
  parseJSON = withObject "ResourceConfig" $ \o -> ResourceConfig
    <$> o .:? "jobs"
    <*> o .:? "profile" .!= Safe

-- | Top-level configuration.
data OrchestratorConfig = OrchestratorConfig
  { cfgScan      :: !ScanConfig
  , cfgPolicy    :: !PolicyConfig
  , cfgOutput    :: !OutputConfig
  , cfgResources :: !ResourceConfig
  } deriving stock (Eq, Show)

instance FromJSON OrchestratorConfig where
  parseJSON = withObject "OrchestratorConfig" $ \o -> OrchestratorConfig
    <$> o .:? "scan" .!= defaultScanConfig
    <*> o .:? "policy" .!= defaultPolicyConfig
    <*> o .:? "output" .!= defaultOutputConfig
    <*> o .:? "resources" .!= defaultResourceConfig

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
defaultConfig = OrchestratorConfig
  { cfgScan = defaultScanConfig
  , cfgPolicy = defaultPolicyConfig
  , cfgOutput = defaultOutputConfig
  , cfgResources = defaultResourceConfig
  }

-- | Load configuration from a YAML file.
loadConfig :: FilePath -> IO (Either OrchestratorError OrchestratorConfig)
loadConfig fp = do
  bs <- BS.readFile fp
  case Yaml.decodeEither' bs of
    Left err -> pure $ Left $ ConfigError $
      "Failed to parse config " <> showT fp <> ": "
      <> showT (Yaml.prettyPrintParseException err)
    Right cfg -> pure $ validateConfig cfg
  where
    showT :: Show a => a -> Text
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
  | otherwise = Right cfg
