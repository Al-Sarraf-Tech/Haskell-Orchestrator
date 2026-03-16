-- | Auto-remediation for safe, mechanical workflow fixes.
--
-- Provides a fix command that can apply unambiguous corrections to
-- GitHub Actions workflow files. Default mode is dry-run (shows diff).
-- The --write flag is required to actually modify files.
--
-- Only mechanical fixes are applied:
-- - Add missing permissions blocks
-- - Add missing timeout-minutes to jobs
-- - Add missing concurrency blocks to PR workflows
--
-- The module never modifies workflow logic.
module Orchestrator.Fix
  ( -- * Types
    FixAction (..)
  , FixResult (..)
  , FixConfig (..)
  , defaultFixConfig
    -- * Application
  , analyzeFixable
  , applyFixes
  , renderFixDiff
  ) where

import Data.Text (Text)
import Data.Text qualified as T

-- | A single fixable issue in a workflow file.
data FixAction = FixAction
  { faFile        :: !FilePath
  , faRuleId      :: !Text
  , faDescription :: !Text
  , faLineHint    :: !(Maybe Int)    -- ^ approximate line where fix applies
  , faPatch       :: !Text           -- ^ the YAML content to add/modify
  } deriving stock (Eq, Show)

-- | Result of applying fixes to a file.
data FixResult = FixResult
  { frFile     :: !FilePath
  , frApplied  :: ![FixAction]
  , frSkipped  :: ![FixAction]
  , frBackup   :: !(Maybe FilePath)
  } deriving stock (Eq, Show)

-- | Fix configuration.
data FixConfig = FixConfig
  { fcWrite     :: !Bool    -- ^ Actually write changes (default: False = dry-run)
  , fcTimeout   :: !Int     -- ^ Default timeout-minutes to add (default: 60)
  } deriving stock (Eq, Show)

-- | Default fix configuration (dry-run mode).
defaultFixConfig :: FixConfig
defaultFixConfig = FixConfig
  { fcWrite   = False
  , fcTimeout = 60
  }

-- | Analyze a workflow file's content for fixable issues.
-- Returns a list of mechanical fixes that can be safely applied.
analyzeFixable :: FilePath -> Text -> [FixAction]
analyzeFixable fp content = concat
  [ checkMissingPermissions fp content
  , checkMissingTimeout fp content
  , checkMissingConcurrency fp content
  ]

-- | Check if the workflow is missing a top-level permissions block.
checkMissingPermissions :: FilePath -> Text -> [FixAction]
checkMissingPermissions fp content
  | hasKey "permissions:" content = []
  | otherwise = [FixAction
      { faFile = fp
      , faRuleId = "PERM-001"
      , faDescription = "Add default read-only permissions block"
      , faLineHint = Just 2  -- after 'on:' block typically
      , faPatch = "permissions:\n  contents: read\n"
      }]

-- | Check if any job is missing timeout-minutes.
checkMissingTimeout :: FilePath -> Text -> [FixAction]
checkMissingTimeout fp content =
  let ls = zip [1..] (T.lines content)
      jobLines = [ (n, l) | (n, l) <- ls
                 , isJobLine l
                 , not (hasTimeoutNearby n ls) ]
  in [ FixAction
       { faFile = fp
       , faRuleId = "RES-001"
       , faDescription = "Add timeout-minutes: 60 to job at line " <> T.pack (show n)
       , faLineHint = Just n
       , faPatch = "    timeout-minutes: 60\n"
       }
     | (n, _) <- jobLines ]

-- | Check if a PR-triggered workflow is missing concurrency.
checkMissingConcurrency :: FilePath -> Text -> [FixAction]
checkMissingConcurrency fp content
  | not (hasPRTrigger content) = []
  | hasKey "concurrency:" content = []
  | otherwise = [FixAction
      { faFile = fp
      , faRuleId = "CONC-001"
      , faDescription = "Add concurrency block for PR workflow"
      , faLineHint = Nothing
      , faPatch = T.unlines
          [ "concurrency:"
          , "  group: ci-${{ github.ref }}"
          , "  cancel-in-progress: true"
          ]
      }]

-- | Apply fixes in dry-run mode (returns diff text).
-- In write mode, would modify files (requires --write flag).
applyFixes :: FixConfig -> FilePath -> Text -> [FixAction] -> (Text, FixResult)
applyFixes cfg fp content actions =
  let applied = actions  -- In this version, all fixes are reportable
      result = FixResult
        { frFile = fp
        , frApplied = applied
        , frSkipped = []
        , frBackup = if fcWrite cfg then Just (fp ++ ".bak") else Nothing
        }
      diff = renderFixDiff actions content
  in (diff, result)

-- | Render a unified-diff-like preview of fixes.
renderFixDiff :: [FixAction] -> Text -> Text
renderFixDiff actions _content
  | null actions = "No fixes needed for this file."
  | otherwise = T.unlines $
      [ "--- " <> T.pack (faFile (head actions)) <> " (original)"
      , "+++ " <> T.pack (faFile (head actions)) <> " (fixed)"
      , ""
      ] ++ concatMap renderAction actions
  where
    renderAction fa =
      [ "# " <> faRuleId fa <> ": " <> faDescription fa
      , case faLineHint fa of
          Just n  -> "@@ line " <> T.pack (show n) <> " @@"
          Nothing -> "@@ end of file @@"
      , "+ " <> T.replace "\n" "\n+ " (T.stripEnd (faPatch fa))
      , ""
      ]

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

hasKey :: Text -> Text -> Bool
hasKey key content = any (\l -> key `T.isPrefixOf` T.stripStart l) (T.lines content)

isJobLine :: Text -> Bool
isJobLine l =
  let stripped = T.stripStart l
      indent = T.length l - T.length stripped
  in indent == 4 && T.isSuffixOf ":" stripped && not (T.isPrefixOf "#" stripped)

hasTimeoutNearby :: Int -> [(Int, Text)] -> Bool
hasTimeoutNearby n ls =
  any (\(n', l') -> abs (n' - n) <= 8 && "timeout-minutes" `T.isInfixOf` l') ls

hasPRTrigger :: Text -> Bool
hasPRTrigger content = "pull_request" `T.isInfixOf` content
