-- | CLI option parsing for the Orchestrator executable.
module CLI
  ( Command (..)
  , Options (..)
  , OutputMode (..)
  , parseOptions
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Options.Applicative
import Orchestrator.Version (orchestratorVersion, orchestratorEdition)

-- | Output format selection.
data OutputMode = OutText | OutJSON | OutSarif | OutMarkdown
  deriving stock (Eq, Show)

-- | Top-level CLI options.
data Options = Options
  { optConfigFile :: !(Maybe FilePath)
  , optVerbose    :: !Bool
  , optOutput     :: !OutputMode
  , optJobs       :: !(Maybe Int)
  , optBaseline   :: !(Maybe FilePath)
  , optFailOn     :: !(Maybe Text)
  , optTags       :: ![Text]
  , optCommand    :: !Command
  } deriving stock (Show)

-- | CLI subcommands.
data Command
  = CmdScan !FilePath
  | CmdValidate !FilePath
  | CmdDiff !FilePath
  | CmdPlan !FilePath
  | CmdFix !FilePath !Bool         -- ^ path, write mode
  | CmdDemo
  | CmdDoctor
  | CmdInit
  | CmdExplain !Text
  | CmdVerify
  | CmdRules
  | CmdBaseline !FilePath          -- ^ save baseline
  | CmdUpgradePath !FilePath       -- ^ show upgrade path
  | CmdUI !FilePath !(Maybe Int)   -- ^ path, optional port
  deriving stock (Show)

parseOptions :: ParserInfo Options
parseOptions = info (optionsParser <**> helper)
  ( fullDesc
    <> header "orchestrator — GitHub Actions workflow standardization and governance"
    <> progDesc "Discover workflow sprawl, detect drift, validate against policies, \
                \and generate remediation plans. Run 'orchestrator demo' for a quick tour."
    <> footer (T.unpack $ orchestratorEdition <> " Edition v" <> orchestratorVersion <> " — 36 built-in rules. \
              \For multi-repo batch scanning, see Business edition. \
              \For org-wide governance, see Enterprise edition.")
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
  <*> outputModeParser
  <*> optional (option auto
        ( long "jobs"
        <> short 'j'
        <> metavar "N"
        <> help "Number of parallel workers (default: conservative)"
        ))
  <*> optional (strOption
        ( long "baseline"
        <> metavar "FILE"
        <> help "Compare against a saved baseline (show only new findings)"
        ))
  <*> optional (strOption
        ( long "fail-on"
        <> metavar "SEVERITY"
        <> help "Exit with failure if any finding meets or exceeds SEVERITY (info|warning|error|critical)"
        ))
  <*> many (T.pack <$> strOption
        ( long "tags"
        <> metavar "TAG"
        <> help "Filter rules by tag (security|performance|cost|style|structure). Repeatable."
        ))
  <*> commandParser

outputModeParser :: Parser OutputMode
outputModeParser =
  flag' OutJSON (long "json" <> help "Output results as JSON")
  <|> flag' OutSarif (long "sarif" <> help "Output results as SARIF v2.1.0")
  <|> flag' OutMarkdown (long "markdown" <> long "md" <> help "Output results as Markdown")
  <|> pure OutText

commandParser :: Parser Command
commandParser = subparser
  ( command "scan"
      (info (CmdScan <$> pathArg)
        (progDesc "Scan workflows and evaluate policies (36 rules)"))
  <> command "validate"
      (info (CmdValidate <$> pathArg)
        (progDesc "Validate workflow structure"))
  <> command "diff"
      (info (CmdDiff <$> pathArg)
        (progDesc "Show current issues"))
  <> command "plan"
      (info (CmdPlan <$> pathArg)
        (progDesc "Generate a remediation plan"))
  <> command "fix"
      (info (CmdFix <$> pathArg <*> switch (long "write" <> help "Actually modify files (default: dry-run)"))
        (progDesc "Auto-fix safe, mechanical issues (permissions, timeouts, concurrency)"))
  <> command "demo"
      (info (pure CmdDemo)
        (progDesc "Run demo with synthetic fixtures (no external access)"))
  <> command "doctor"
      (info (pure CmdDoctor)
        (progDesc "Diagnose environment, config, and connectivity"))
  <> command "init"
      (info (pure CmdInit)
        (progDesc "Create a new .orchestrator.yml config file"))
  <> command "explain"
      (info (CmdExplain . T.pack <$> strArgument (metavar "RULE_ID" <> help "Rule ID to explain"))
        (progDesc "Explain a policy rule in detail"))
  <> command "rules"
      (info (pure CmdRules)
        (progDesc "List all available policy rules"))
  <> command "verify"
      (info (pure CmdVerify)
        (progDesc "Verify the current configuration"))
  <> command "baseline"
      (info (CmdBaseline <$> pathArg)
        (progDesc "Save current findings as a baseline for future comparison"))
  <> command "upgrade-path"
      (info (CmdUpgradePath <$> pathArg)
        (progDesc "Show what Business/Enterprise editions would add"))
  <> command "ui"
      (info (CmdUI <$> pathArg <*> optional (option auto
              (long "port" <> short 'p' <> metavar "PORT" <> help "Server port (default: 8420)")))
        (progDesc "Launch web dashboard (LAN + Tailscale only)"))
  )

pathArg :: Parser FilePath
pathArg = strArgument (metavar "PATH" <> help "Repository path to scan")
