-- | Filesystem scanning for GitHub Actions workflow files.
--
-- Scans explicitly provided local paths for .github/workflows/*.yml files.
-- Does NOT perform automatic discovery, home-directory crawling, or
-- recursive filesystem traversal outside the specified target.
module Orchestrator.Scan
  ( scanLocalPath,
    scanWorkflowDir,
    findWorkflowFiles,
    isWorkflowFile,
  )
where

import Data.List (isPrefixOf)
import Orchestrator.Config (ScanConfig (..))
import Orchestrator.Parser (parseWorkflowFile)
import Orchestrator.Policy (PolicyPack, evaluatePolicies)
import Orchestrator.Types
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeExtension, takeFileName, (</>))

-- | Scan a local path for GitHub Actions workflows.
--
-- The path must be explicitly provided.  This function will look for
-- .github/workflows/ under the given path and parse all YAML files found.
scanLocalPath :: PolicyPack -> ScanConfig -> FilePath -> IO (Either OrchestratorError ScanResult)
scanLocalPath pack cfg root = do
  let wfDir = root </> ".github" </> "workflows"
  exists <- doesDirectoryExist wfDir
  if not exists
    then
      pure $
        Right
          ScanResult
            { scanTarget = LocalPath root,
              scanFindings = [],
              scanFiles = [],
              scanTime = Nothing
            }
    else do
      files <- findWorkflowFiles (scMaxDepth cfg) wfDir
      results <- mapM parseAndCheck files
      -- Post-scan filter: suppress BIZ-DEP-001 when .github/dependabot.yml exists.
      -- Dependency update automation is a repo-level concern; the rule can't see
      -- files outside the workflow, so we filter at the scan level.
      let depFile = root </> ".github" </> "dependabot.yml"
      hasDependabot <- doesFileExist depFile
      let allFindings = concatMap snd results
          filtered =
            if hasDependabot
              then filter (\f -> findingRuleId f /= "BIZ-DEP-001") allFindings
              else allFindings
      pure $
        Right
          ScanResult
            { scanTarget = LocalPath root,
              scanFindings = filtered,
              scanFiles = files,
              scanTime = Nothing
            }
  where
    parseAndCheck :: FilePath -> IO (FilePath, [Finding])
    parseAndCheck fp = do
      result <- parseWorkflowFile fp
      case result of
        Left (ParseError _ msg) ->
          pure
            ( fp,
              [ Finding
                  { findingSeverity = Error,
                    findingCategory = Structure,
                    findingRuleId = "SCAN-001",
                    findingMessage = "Failed to parse: " <> msg,
                    findingFile = fp,
                    findingLocation = Nothing,
                    findingRemediation = Nothing,
                    findingAutoFixable = False,
                    findingEffort = Nothing,
                    findingLinks = []
                  }
              ]
            )
        Left _ -> pure (fp, [])
        Right wf -> pure (fp, evaluatePolicies pack wf)

-- | Scan a specific workflow directory.
scanWorkflowDir :: PolicyPack -> FilePath -> IO [Finding]
scanWorkflowDir pack dir = do
  files <- findWorkflowFiles 1 dir
  results <-
    mapM
      ( \fp -> do
          r <- parseWorkflowFile fp
          case r of
            Left _ -> pure []
            Right wf -> pure $ evaluatePolicies pack wf
      )
      files
  pure $ concat results

-- | Find workflow YAML files in a directory (bounded depth).
findWorkflowFiles :: Int -> FilePath -> IO [FilePath]
findWorkflowFiles maxDepth dir
  | maxDepth <= 0 = pure []
  | otherwise = do
      exists <- doesDirectoryExist dir
      if not exists
        then pure []
        else do
          entries <- listDirectory dir
          let fullPaths = map (dir </>) entries
          files <- filterM' doesFileExist fullPaths
          let yamlFiles = filter isWorkflowFile files
          -- No recursive descent into subdirectories of workflow dir
          pure yamlFiles

-- | Check if a file looks like a GitHub Actions workflow file.
isWorkflowFile :: FilePath -> Bool
isWorkflowFile fp =
  let ext = takeExtension fp
      name = takeFileName fp
   in ext `elem` [".yml", ".yaml"]
        && not (null name)
        && not ("." `isPrefixOf` name)

-- Strict filterM replacement without Control.Monad dependency
filterM' :: (a -> IO Bool) -> [a] -> IO [a]
filterM' _ [] = pure []
filterM' p (x : xs) = do
  b <- p x
  rest <- filterM' p xs
  pure $ if b then x : rest else rest
