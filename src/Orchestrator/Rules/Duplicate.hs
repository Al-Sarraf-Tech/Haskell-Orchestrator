-- | Rules for cross-workflow duplicate detection.
--
-- Detects copy-pasted job blocks across workflow files in the same repo.
module Orchestrator.Rules.Duplicate
  ( duplicateJobRule
  ) where

import Data.List (group, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Rule: detect jobs across workflows that look like copies.
-- Uses a structural fingerprint of each job (steps uses/run, runner)
-- to find duplicates.
duplicateJobRule :: PolicyRule
duplicateJobRule = PolicyRule
  { ruleId = "DUP-001"
  , ruleName = "Cross-Workflow Duplicate Detection"
  , ruleDescription = "Detect copy-pasted job blocks across workflow files"
  , ruleSeverity = Info
  , ruleCategory = Duplication
  , ruleCheck = \wf ->
      -- This rule produces findings at the workflow level.
      -- For cross-workflow detection, a multi-workflow variant exists
      -- in the batch scanner. Here we detect intra-workflow duplicates.
      let jobs = wfJobs wf
          fingerprints = map (\j -> (jobFingerprint j, jobId j)) jobs
          grouped = group $ sort $ map fst fingerprints
          dups = [ fp | fps <- grouped, length fps > 1, let fp = head fps ]
          dupJobs = [ (jid, fp)
                    | (fp, jid) <- fingerprints
                    , fp `elem` dups
                    ]
      in if null dupJobs
         then []
         else [ Finding
                  { findingSeverity = Info
                  , findingCategory = Duplication
                  , findingRuleId = "DUP-001"
                  , findingMessage =
                      "Workflow '" <> wfName wf <> "' contains "
                      <> T.pack (show (length dups))
                      <> " groups of structurally identical jobs. "
                      <> "Consider extracting shared logic into reusable workflows."
                  , findingFile = wfFileName wf
                  , findingLocation = Nothing
                  , findingRemediation = Just $
                      "Extract duplicate job logic into a reusable workflow "
                      <> "(workflow_call) or a composite action."
                  , findingAutoFixable = False
                  , findingEffort = Nothing
                  , findingLinks = []
                  }
              ]
  }

------------------------------------------------------------------------
-- Fingerprinting
------------------------------------------------------------------------

-- | Create a structural fingerprint of a job for comparison.
-- Ignores names, IDs, and if-conditions — focuses on what the job does.
jobFingerprint :: Job -> Text
jobFingerprint j =
  let runner = case jobRunsOn j of
        StandardRunner r -> r
        MatrixRunner r   -> r
        CustomLabel r    -> r
      steps = map stepFingerprint (jobSteps j)
  in runner <> "|" <> T.intercalate ";" steps

-- | Fingerprint a single step.
stepFingerprint :: Step -> Text
stepFingerprint s =
  let uses = maybe "" id (stepUses s)
      run = maybe "" (T.take 50) (stepRun s)  -- First 50 chars of run
  in uses <> "~" <> run
