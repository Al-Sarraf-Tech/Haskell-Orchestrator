-- | Performance rules for GitHub Actions workflow analysis.
--
-- Detects common performance anti-patterns: missing dependency caches
-- and independent jobs that could run in parallel but are sequential.
module Orchestrator.Rules.Performance
  ( missingCacheRule
  , sequentialParallelizableRule
  ) where

import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Rule PERF-001: detect build jobs that do not use any caching step.
--
-- A job is classified as a "build job" if it:
--   - has a run step containing a recognised build command, OR
--   - uses a setup action (actions\/setup-*, haskell-actions\/setup,
--     dtolnay\/rust-toolchain)
--
-- A job is considered to have caching if any step uses an action
-- whose reference contains the word "cache" (case-insensitive).
missingCacheRule :: PolicyRule
missingCacheRule = PolicyRule
  { ruleId = "PERF-001"
  , ruleName = "Missing Cache"
  , ruleDescription = "Build workflows should cache dependencies to reduce build time"
  , ruleSeverity = Warning
  , ruleCategory = Performance
  , ruleTags = [TagPerformance]
  , ruleCheck = \wf ->
      concatMap (\j ->
        let isBuild = jobIsBuildJob j
            hasCache = jobHasCache j
        in [ mkFinding' Warning Performance "PERF-001"
                ( "Job '" <> jobId j
                  <> "' appears to build dependencies but has no caching step. "
                  <> "Add a cache action to speed up subsequent runs."
                )
                (wfFileName wf)
                (Just $ "Job: " <> jobId j)
                (Just "Add 'uses: actions/cache@...' or use the built-in cache \
                      \input on setup actions (e.g. 'cache: npm' on actions/setup-node).")
           | isBuild && not hasCache
           ]
      ) (wfJobs wf)
  }

-- | Rule PERF-002: detect 3 or more independent jobs that could run in parallel.
--
-- Only fires when the workflow has more than 2 jobs AND at least 3 of those
-- jobs have an empty 'needs:' list (no declared dependencies).  One finding
-- is emitted per workflow, not per job.
sequentialParallelizableRule :: PolicyRule
sequentialParallelizableRule = PolicyRule
  { ruleId = "PERF-002"
  , ruleName = "Sequential Parallelizable Jobs"
  , ruleDescription = "Workflows with multiple independent jobs may benefit from explicit parallelism documentation"
  , ruleSeverity = Info
  , ruleCategory = Performance
  , ruleTags = [TagPerformance]
  , ruleCheck = \wf ->
      let jobs = wfJobs wf
          independentJobs = filter (null . jobNeeds) jobs
          totalJobs = length jobs
          independentCount = length independentJobs
      in [ mkFinding' Info Performance "PERF-002"
              ( "Workflow has " <> T.pack (show independentCount)
                <> " independent jobs with no 'needs:' dependencies. "
                <> "These already run in parallel on GitHub Actions. "
                <> "Consider documenting the intended execution order."
              )
              (wfFileName wf)
              Nothing
              (Just "Add 'needs:' declarations to express dependencies explicitly, \
                    \or document that parallel execution is intentional.")
         | totalJobs > 2 && independentCount >= 3
         ]
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- | Recognised build commands found in run steps.
buildCommands :: [T.Text]
buildCommands =
  [ "npm install", "npm ci", "npm run build"
  , "yarn install"
  , "cargo build"
  , "cabal build"
  , "stack build"
  , "go build"
  , "pip install"
  , "poetry install"
  , "mvn"
  , "gradle"
  , "dotnet build"
  , "make"
  ]

-- | Setup actions that imply a build environment is being prepared.
setupActions :: [T.Text]
setupActions =
  [ "actions/setup-node"
  , "actions/setup-python"
  , "actions/setup-java"
  , "actions/setup-go"
  , "haskell-actions/setup"
  , "dtolnay/rust-toolchain"
  ]

-- | Check whether a job qualifies as a build job.
jobIsBuildJob :: Job -> Bool
jobIsBuildJob j = any stepIsBuildStep (jobSteps j)

-- | Check whether a single step looks like a build step.
stepIsBuildStep :: Step -> Bool
stepIsBuildStep s = hasBuildRun s || hasSetupAction s

hasBuildRun :: Step -> Bool
hasBuildRun s = case stepRun s of
  Nothing  -> False
  Just cmd -> any (`T.isInfixOf` cmd) buildCommands

hasSetupAction :: Step -> Bool
hasSetupAction s = case stepUses s of
  Nothing   -> False
  Just uses -> any (`T.isPrefixOf` uses) setupActions

-- | Check whether a job has at least one caching step.
jobHasCache :: Job -> Bool
jobHasCache j = any stepHasCache (jobSteps j)

stepHasCache :: Step -> Bool
stepHasCache s = case stepUses s of
  Nothing   -> False
  Just uses -> "cache" `T.isInfixOf` T.toLower uses
