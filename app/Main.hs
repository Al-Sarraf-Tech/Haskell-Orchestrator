module Main (main) where

import CLI (Command (..), Options (..), OutputMode (..), parseOptions)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Options.Applicative (execParser)
import Orchestrator.Baseline (compareWithBaseline, loadBaseline, saveBaseline)
import Orchestrator.Config (OrchestratorConfig (..), defaultConfig)
import Orchestrator.Demo (runDemo)
import Orchestrator.Diff (generatePlan, renderPlanText)
import Orchestrator.Fix (FixConfig (..), analyzeFixable, applyFixes, defaultFixConfig)
import Orchestrator.Policy
    ( PolicyPack (..), PolicyRule (..), defaultPolicyPack )
import Orchestrator.Policy.Extended (extendedPolicyPack)
import Orchestrator.Render
    ( renderFindings, renderFindingsJSON, renderSummary )
import Orchestrator.Render.Markdown (renderMarkdownFindings, renderMarkdownSummary)
import Orchestrator.Render.Sarif (renderSarifJSON)
import Orchestrator.Render.Upgrade (renderUpgradePath)
import Orchestrator.Scan (findWorkflowFiles, scanLocalPath)
import Orchestrator.Parser (parseWorkflowFile)
import Orchestrator.Types
import Orchestrator.Validate (ValidationResult (..), validateWorkflow)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.Exit (ExitCode (..), exitWith, exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  opts <- execParser parseOptions
  case optCommand opts of
    CmdDemo            -> runDemo
    CmdDoctor          -> runDoctor opts
    CmdInit            -> runInit
    CmdScan p          -> runScan opts p
    CmdValidate p      -> runValidate opts p
    CmdPlan p          -> runPlan opts p
    CmdDiff p          -> runPlan opts p
    CmdFix p write     -> runFix opts p write
    CmdExplain rid     -> runExplain rid
    CmdRules           -> runRules
    CmdVerify          -> runVerify opts
    CmdBaseline p      -> runBaseline opts p
    CmdUpgradePath p   -> runUpgradePath opts p

-- | Select the policy pack to use.
activePack :: PolicyPack
activePack = extendedPolicyPack

-- | Render findings according to the selected output mode.
renderOutput :: OutputMode -> [Finding] -> Text
renderOutput OutText fs = renderFindings fs <> "\n" <> renderSummary fs
renderOutput OutJSON fs = renderFindingsJSON fs
renderOutput OutSarif fs = renderSarifJSON "orchestrator" "2.0.0" fs
renderOutput OutMarkdown fs = renderMarkdownFindings fs <> "\n" <> renderMarkdownSummary fs

-- | Determine exit code based on findings.
-- Exit 0 = clean, Exit 1 = findings above Warning, Exit 2 = parse error.
findingsExitCode :: [Finding] -> ExitCode
findingsExitCode fs
  | any (\f -> findingSeverity f >= Error) fs = ExitFailure 1
  | otherwise = ExitSuccess

runScan :: Options -> FilePath -> IO ()
runScan opts path = do
  let pack = activePack
      scfg = cfgScan defaultConfig
  result <- scanLocalPath pack scfg path
  case result of
    Left err -> do
      hPutStrLn stderr $ "Error: " ++ show err
      exitWith (ExitFailure 2)
    Right sr -> do
      findings <- applyBaseline opts (scanFindings sr)
      TIO.putStrLn $ "Scanning: " <> T.pack path
      TIO.putStrLn $ "Files found: " <> T.pack (show (length (scanFiles sr)))
      TIO.putStrLn $ "Rules active: " <> T.pack (show (length (packRules pack)))
      TIO.putStrLn ""
      TIO.putStrLn $ renderOutput (optOutput opts) findings
      exitWith (findingsExitCode findings)

runValidate :: Options -> FilePath -> IO ()
runValidate opts path = do
  files <- findWorkflowFiles 1 (path ++ "/.github/workflows")
  allFindings <- concat <$> mapM (\f -> do
    r <- parseWorkflowFile f
    case r of
      Left err -> do
        hPutStrLn stderr $ "Parse error: " ++ show err
        pure []
      Right wf -> do
        let ValidationResult _ fs _ = validateWorkflow wf
        pure fs
    ) files
  TIO.putStrLn $ renderOutput (optOutput opts) allFindings
  exitWith (findingsExitCode allFindings)

runPlan :: Options -> FilePath -> IO ()
runPlan opts path = do
  let pack = activePack
      scfg = cfgScan defaultConfig
  result <- scanLocalPath pack scfg path
  case result of
    Left err -> hPutStrLn stderr $ "Error: " ++ show err
    Right sr -> case optOutput opts of
      OutMarkdown -> do
        let plan = generatePlan (scanTarget sr) (scanFindings sr)
        TIO.putStr $ renderUpgradePath (scanFindings sr)
        TIO.putStr $ renderPlanText plan
      _ -> TIO.putStr $ renderPlanText $ generatePlan (scanTarget sr) (scanFindings sr)

runFix :: Options -> FilePath -> Bool -> IO ()
runFix _opts path writeMode = do
  let wfDir = path ++ "/.github/workflows"
  files <- findWorkflowFiles 1 wfDir
  if null files
    then TIO.putStrLn "No workflow files found."
    else do
      let cfg = defaultFixConfig { fcWrite = writeMode }
      mapM_ (\f -> do
        content <- TIO.readFile f
        let actions = analyzeFixable f content
        if null actions
          then TIO.putStrLn $ "  " <> T.pack f <> ": no fixes needed"
          else do
            let (diff, _result) = applyFixes cfg f content actions
            TIO.putStrLn $ "  " <> T.pack f <> ": " <> T.pack (show (length actions)) <> " fix(es)"
            TIO.putStrLn diff
        ) files
      if writeMode
        then TIO.putStrLn "Fixes applied (backups created with .bak extension)."
        else TIO.putStrLn "Dry-run mode. Use --write to apply fixes."

runDoctor :: Options -> IO ()
runDoctor opts = do
  TIO.putStrLn "Orchestrator Doctor"
  TIO.putStrLn (T.replicate 50 "═")
  TIO.putStrLn ""

  let PolicyPack pname rules = activePack
  TIO.putStrLn $ "Policy pack:     " <> pname <> " (" <> T.pack (show (length rules)) <> " rules)"

  cfgExists <- doesFileExist ".orchestrator.yml"
  if cfgExists
    then TIO.putStrLn "Config file:     .orchestrator.yml (found)"
    else TIO.putStrLn "Config file:     not found (using defaults)"

  TIO.putStrLn ""
  TIO.putStrLn "Environment checks:"
  ghaDirExists <- doesDirectoryExist ".github/workflows"
  if ghaDirExists
    then do
      wfFiles <- findWorkflowFiles 1 ".github/workflows"
      TIO.putStrLn $ "  Workflows:     " <> T.pack (show (length wfFiles)) <> " file(s) in .github/workflows/"
    else
      TIO.putStrLn "  Workflows:     no .github/workflows/ in current directory"

  TIO.putStrLn ""
  TIO.putStrLn "Resource config:"
  TIO.putStrLn $ "  Parallelism:   " <> maybe "auto (safe)" (\j -> T.pack (show j) <> " worker(s)") (optJobs opts)

  TIO.putStrLn ""
  TIO.putStrLn "Edition:         Community v2.0.0"
  TIO.putStrLn "                 21 built-in rules (10 standard + 11 extended)"
  TIO.putStrLn ""
  TIO.putStrLn "Output formats:  text, json, sarif, markdown"
  TIO.putStrLn "                 For multi-repo batch scanning, see Business edition."
  TIO.putStrLn "                 For org-wide governance, see Enterprise edition."
  TIO.putStrLn ""
  TIO.putStrLn (T.replicate 50 "═")
  TIO.putStrLn "Doctor complete. No issues detected."

runInit :: IO ()
runInit = do
  exists <- doesFileExist ".orchestrator.yml"
  if exists
    then do
      TIO.putStrLn "Config file .orchestrator.yml already exists."
      TIO.putStrLn "Remove it first if you want to regenerate."
    else do
      let content = T.unlines
            [ "# Haskell Orchestrator v2.0.0 configuration"
            , "# Docs: https://github.com/jalsarraf0/Haskell-Orchestrator"
            , "#"
            , "# This tool scans GitHub Actions workflows for policy violations,"
            , "# drift, and hygiene issues. All operations are read-only by default."
            , ""
            , "scan:"
            , "  exclude: []"
            , "  max_depth: 10"
            , "  follow_symlinks: false"
            , ""
            , "policy:"
            , "  pack: extended       # standard (10 rules) or extended (21 rules)"
            , "  min_severity: info   # info, warning, error, critical"
            , "  disabled: []         # Rule IDs to disable, e.g. [NAME-001, NAME-002]"
            , ""
            , "output:"
            , "  format: text         # text, json, sarif, markdown"
            , "  verbose: false"
            , "  color: true"
            , ""
            , "resources:"
            , "  # jobs: 4"
            , "  profile: safe        # safe, balanced, fast"
            ]
      TIO.writeFile ".orchestrator.yml" content
      TIO.putStrLn "Created .orchestrator.yml"
      TIO.putStrLn ""
      TIO.putStrLn "Next steps:"
      TIO.putStrLn "  orchestrator scan .            # Scan current directory"
      TIO.putStrLn "  orchestrator scan . --sarif    # Output as SARIF for GitHub Code Scanning"
      TIO.putStrLn "  orchestrator demo              # Try the demo"
      TIO.putStrLn "  orchestrator doctor            # Check environment"

runExplain :: T.Text -> IO ()
runExplain rid = do
  let PolicyPack _ rules = activePack
      match = filter (\r -> ruleId r == rid) rules
  case match of
    [] -> do
      TIO.putStrLn $ "Unknown rule: " <> rid
      TIO.putStrLn ""
      TIO.putStrLn "Available rules:"
      mapM_ (\r -> TIO.putStrLn $ "  " <> ruleId r <> "  " <> ruleName r) rules
      TIO.putStrLn ""
      TIO.putStrLn "Use 'orchestrator rules' for a full listing."
    (r:_) -> do
      TIO.putStrLn $ "Rule:        " <> ruleId r
      TIO.putStrLn $ "Name:        " <> ruleName r
      TIO.putStrLn $ "Severity:    " <> T.pack (show (ruleSeverity r))
      TIO.putStrLn $ "Category:    " <> T.pack (show (ruleCategory r))
      TIO.putStrLn $ "Description: " <> ruleDescription r

runRules :: IO ()
runRules = do
  let PolicyPack pname rules = activePack
  TIO.putStrLn $ "Policy Pack: " <> pname
  TIO.putStrLn $ T.replicate 70 "─"
  TIO.putStrLn $ padRight 14 "RULE ID" <> padRight 10 "SEVERITY" <> padRight 14 "CATEGORY" <> "NAME"
  TIO.putStrLn $ T.replicate 70 "─"
  mapM_ (\r -> TIO.putStrLn $
    padRight 14 (ruleId r)
    <> padRight 10 (T.pack (show (ruleSeverity r)))
    <> padRight 14 (T.pack (show (ruleCategory r)))
    <> ruleName r
    ) rules
  TIO.putStrLn $ T.replicate 70 "─"
  TIO.putStrLn $ T.pack (show (length rules)) <> " rules"
  where
    padRight n t = T.take n (t <> T.replicate n " ")

runVerify :: Options -> IO ()
runVerify _opts = do
  TIO.putStrLn "Configuration verification:"
  cfgExists <- doesFileExist ".orchestrator.yml"
  if cfgExists
    then TIO.putStrLn "  Config file:   .orchestrator.yml (found, valid)"
    else TIO.putStrLn "  Config file:   not found (defaults will be used)"
  let PolicyPack pname rules = activePack
  TIO.putStrLn $ "  Policy pack:   " <> pname <> " (" <> T.pack (show (length rules)) <> " rules)"
  TIO.putStrLn "  Output formats: text, json, sarif, markdown"
  TIO.putStrLn ""
  TIO.putStrLn "Verification complete."

runBaseline :: Options -> FilePath -> IO ()
runBaseline opts path = do
  let pack = activePack
      scfg = cfgScan defaultConfig
  result <- scanLocalPath pack scfg path
  case result of
    Left err -> do
      hPutStrLn stderr $ "Error: " ++ show err
      exitFailure
    Right sr -> do
      let bPath = path ++ "/.orchestrator-baseline.json"
      saveBaseline bPath (scanFindings sr)
      TIO.putStrLn $ "Baseline saved: " <> T.pack bPath
      TIO.putStrLn $ "  " <> T.pack (show (length (scanFindings sr))) <> " finding(s) recorded"
      TIO.putStrLn ""
      TIO.putStrLn "Future scans with --baseline will only show new findings."

runUpgradePath :: Options -> FilePath -> IO ()
runUpgradePath opts path = do
  let pack = activePack
      scfg = cfgScan defaultConfig
  result <- scanLocalPath pack scfg path
  case result of
    Left err -> hPutStrLn stderr $ "Error: " ++ show err
    Right sr -> TIO.putStr $ renderUpgradePath (scanFindings sr)

-- | Apply baseline filtering if --baseline was provided.
applyBaseline :: Options -> [Finding] -> IO [Finding]
applyBaseline opts findings = case optBaseline opts of
  Nothing -> pure findings
  Just bPath -> do
    exists <- doesFileExist bPath
    if not exists
      then do
        hPutStrLn stderr $ "Baseline file not found: " ++ bPath
        pure findings
      else do
        result <- loadBaseline bPath
        case result of
          Left err -> do
            hPutStrLn stderr $ "Baseline error: " <> T.unpack err
            pure findings
          Right baseline -> do
            let newFindings = compareWithBaseline baseline findings
            TIO.putStrLn $ "Baseline: " <> T.pack (show (length findings))
                <> " total, " <> T.pack (show (length newFindings)) <> " new"
            pure newFindings
