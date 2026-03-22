-- | Git pre-commit hook integration for GitHub Actions workflow scanning.
--
-- Provides installation, removal, and execution of a git pre-commit hook
-- that runs the orchestrator on changed workflow files before each commit.
module Orchestrator.Hook
  ( -- * Configuration
    HookConfig (..)
  , defaultHookConfig
    -- * Hook management
  , installHook
  , uninstallHook
    -- * Hook script
  , hookScript
    -- * Hook execution
  , runHookCheck
  ) where

import Control.Exception (IOException, try)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Directory (doesFileExist, removeFile)
import System.FilePath ((</>))
import System.Process (readProcess)

import Orchestrator.Parser (parseWorkflowFile)
import Orchestrator.Policy (defaultPolicyPack, evaluatePolicies)
import Orchestrator.Types (Finding (..), Severity (..))

-- | Configuration for the pre-commit hook.
data HookConfig = HookConfig
  { hcMinSeverity  :: !Severity
  , hcFailOnWarning :: !Bool
  } deriving stock (Eq, Show)

-- | Default hook configuration: minimum severity 'Warning', fail on warning disabled.
defaultHookConfig :: HookConfig
defaultHookConfig = HookConfig
  { hcMinSeverity   = Warning
  , hcFailOnWarning = False
  }

-- | Install the pre-commit hook into the given repository root.
--
-- Writes a shell script to @.git\/hooks\/pre-commit@ that invokes the
-- orchestrator on changed workflow files.  Returns 'Left' if the @.git@
-- directory does not exist or the hook file already exists.
installHook :: FilePath -> IO (Either Text ())
installHook repoRoot = do
  let gitDir   = repoRoot </> ".git"
      hooksDir = gitDir </> "hooks"
      hookPath = hooksDir </> "pre-commit"
  gitExists <- doesFileExist (gitDir </> "HEAD")
  if not gitExists
    then pure $ Left "Not a git repository: .git/HEAD not found"
    else do
      hookExists <- doesFileExist hookPath
      if hookExists
        then pure $ Left "Pre-commit hook already exists; remove it first"
        else do
          TIO.writeFile hookPath hookScript
          -- Make the hook executable
          _ <- readProcess "chmod" ["+x", hookPath] ""
          pure $ Right ()

-- | Remove the pre-commit hook from the given repository root.
--
-- Only removes the hook if it contains the orchestrator marker comment.
-- Returns 'Left' if the hook does not exist or was not installed by us.
uninstallHook :: FilePath -> IO (Either Text ())
uninstallHook repoRoot = do
  let hookPath = repoRoot </> ".git" </> "hooks" </> "pre-commit"
  hookExists <- doesFileExist hookPath
  if not hookExists
    then pure $ Left "No pre-commit hook found"
    else do
      contents <- TIO.readFile hookPath
      if "# orchestrator-hook" `T.isInfixOf` contents
        then do
          removeFile hookPath
          pure $ Right ()
        else pure $ Left "Pre-commit hook was not installed by orchestrator"

-- | The shell script content for the pre-commit hook.
--
-- Uses bash with strict mode.  Finds changed workflow YAML files in the
-- staging area and runs @orchestrator scan@ with SARIF output on each.
hookScript :: Text
hookScript = T.unlines
  [ "#!/usr/bin/env bash"
  , "# orchestrator-hook — GitHub Actions workflow pre-commit scanner"
  , "set -euo pipefail"
  , ""
  , "# Find changed workflow files in the staging area"
  , "changed_files=$(git diff --cached --name-only --diff-filter=ACM \\"
  , "  | grep -E '^\\.github/workflows/.*\\.ya?ml$' || true)"
  , ""
  , "if [ -z \"$changed_files\" ]; then"
  , "  exit 0"
  , "fi"
  , ""
  , "echo \"[orchestrator] Scanning changed workflow files...\""
  , ""
  , "exit_code=0"
  , "for file in $changed_files; do"
  , "  if ! orchestrator scan \"$file\" --sarif; then"
  , "    exit_code=1"
  , "  fi"
  , "done"
  , ""
  , "if [ \"$exit_code\" -ne 0 ]; then"
  , "  echo \"[orchestrator] Workflow policy violations found. Commit blocked.\""
  , "  echo \"[orchestrator] Run 'orchestrator scan . --fix' to auto-remediate.\""
  , "fi"
  , ""
  , "exit $exit_code"
  ]

-- | Run the hook check programmatically.
--
-- Finds changed workflow files via @git diff --cached --name-only@, parses
-- and evaluates policies on each, and returns all findings.
runHookCheck :: FilePath -> IO [Finding]
runHookCheck repoRoot = do
  result <- try $ readProcess "git"
    ["-C", repoRoot, "diff", "--cached", "--name-only", "--diff-filter=ACM"]
    "" :: IO (Either IOException String)
  case result of
    Left _ -> pure []
    Right output -> do
      let allFiles = lines output
          wfFiles  = filter isWorkflowPath allFiles
          fullPaths = map (repoRoot </>) wfFiles
      findings <- mapM scanOneFile fullPaths
      pure $ concat findings
  where
    isWorkflowPath :: String -> Bool
    isWorkflowPath fp =
      ".github/workflows/" `T.isPrefixOf` T.pack fp
      && (T.isSuffixOf ".yml" (T.pack fp) || T.isSuffixOf ".yaml" (T.pack fp))

    scanOneFile :: FilePath -> IO [Finding]
    scanOneFile fp = do
      parseResult <- parseWorkflowFile fp
      case parseResult of
        Left _ -> pure []
        Right wf -> pure $ evaluatePolicies defaultPolicyPack wf
