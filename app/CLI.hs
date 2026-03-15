-- | CLI option parsing for the Orchestrator executable.
module CLI
  ( Command (..)
  , Options (..)
  , parseOptions
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Options.Applicative

-- | Top-level CLI options.
data Options = Options
  { optConfigFile :: !(Maybe FilePath)
  , optVerbose    :: !Bool
  , optJSON       :: !Bool
  , optJobs       :: !(Maybe Int)
  , optCommand    :: !Command
  } deriving stock (Show)

-- | CLI subcommands.
data Command
  = CmdScan ![FilePath]
  | CmdValidate ![FilePath]
  | CmdDiff ![FilePath]
  | CmdPlan ![FilePath]
  | CmdDemo
  | CmdDoctor
  | CmdInit
  | CmdExplain !Text
  | CmdVerify
  deriving stock (Show)

parseOptions :: ParserInfo Options
parseOptions = info (optionsParser <**> helper)
  ( fullDesc
    <> header "orchestrator — GitHub Actions workflow standardization tool"
    <> progDesc "Scan, validate, and standardize GitHub Actions workflows. \
                \Run 'orchestrator demo' for a quick tour."
  )

optionsParser :: Parser Options
optionsParser = Options
  <$> optional (strOption
        ( long "config"
        <> short 'c'
        <> metavar "FILE"
        <> help "Configuration file (default: .orchestrator.yml)"
        ))
  <*> switch
        ( long "verbose"
        <> short 'v'
        <> help "Enable verbose output"
        )
  <*> switch
        ( long "json"
        <> help "Output results as JSON"
        )
  <*> optional (option auto
        ( long "jobs"
        <> short 'j'
        <> metavar "N"
        <> help "Number of parallel workers (default: conservative)"
        ))
  <*> commandParser

commandParser :: Parser Command
commandParser = subparser
  ( command "scan"
      (info (CmdScan <$> pathsArg)
        (progDesc "Scan workflows in the given paths"))
  <> command "validate"
      (info (CmdValidate <$> pathsArg)
        (progDesc "Validate workflow structure"))
  <> command "diff"
      (info (CmdDiff <$> pathsArg)
        (progDesc "Show current issues as a diff"))
  <> command "plan"
      (info (CmdPlan <$> pathsArg)
        (progDesc "Generate a remediation plan"))
  <> command "demo"
      (info (pure CmdDemo)
        (progDesc "Run demo with synthetic fixtures"))
  <> command "doctor"
      (info (pure CmdDoctor)
        (progDesc "Check environment and configuration"))
  <> command "init"
      (info (pure CmdInit)
        (progDesc "Initialize a new configuration file"))
  <> command "explain"
      (info (CmdExplain . T.pack <$> strArgument (metavar "RULE_ID" <> help "Rule ID to explain"))
        (progDesc "Explain a policy rule"))
  <> command "verify"
      (info (pure CmdVerify)
        (progDesc "Verify the current configuration"))
  )

pathsArg :: Parser [FilePath]
pathsArg = some (strArgument (metavar "PATH..." <> help "Paths to scan"))
