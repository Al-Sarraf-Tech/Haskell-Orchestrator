-- | Rules for cost-efficiency analysis.
--
-- Detects GitHub Actions patterns that waste money:
-- matrix jobs with if-conditions that exclude entries before they do
-- useful work, and redundant artifact uploads across multiple jobs.
module Orchestrator.Rules.Cost
  ( matrixWasteRule,
    redundantArtifactUploadRule,
  )
where

import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Rule: detect matrix jobs with job-level if conditions that exclude entries.
--
-- A job-level @if@ containing @matrix.@ combined with @!=@ or @!contains@
-- still starts the runner before the condition is evaluated, wasting compute.
-- The correct approach is @strategy.matrix.exclude@ which prevents those
-- entries from being scheduled at all.
matrixWasteRule :: PolicyRule
matrixWasteRule =
  PolicyRule
    { ruleId = "COST-001",
      ruleName = "Matrix Waste",
      ruleDescription =
        "Matrix jobs with if-conditions that exclude entries waste runner start-up time",
      ruleSeverity = Warning,
      ruleCategory = Cost,
      ruleTags = [TagCost],
      ruleCheck = \wf ->
        concatMap
          ( \j ->
              case (jobRunsOn j, jobIf j) of
                (MatrixRunner _, Just cond)
                  | hasMatrixExclusion cond ->
                      [ mkFinding'
                          Warning
                          Cost
                          "COST-001"
                          ( "Job '"
                              <> jobId j
                              <> "' uses a matrix runner but its if-condition excludes "
                              <> "matrix entries ("
                              <> cond
                              <> "). The runner still starts before the condition is "
                              <> "evaluated, wasting compute."
                          )
                          (wfFileName wf)
                          (Just ("Job: " <> jobId j))
                          ( Just
                              "Use 'strategy.matrix.exclude' to prevent unwanted \
                              \matrix entries from being scheduled."
                          )
                      ]
                _ -> []
          )
          (wfJobs wf)
    }

-- | Rule: detect multiple jobs in the same workflow uploading artifacts.
--
-- When more than one job calls @actions/upload-artifact@, it usually
-- indicates that an intermediate job is uploading and re-uploading the same
-- artifact, or that consolidation is possible.  One finding is raised per
-- workflow.
redundantArtifactUploadRule :: PolicyRule
redundantArtifactUploadRule =
  PolicyRule
    { ruleId = "COST-002",
      ruleName = "Redundant Artifact Upload",
      ruleDescription =
        "Multiple jobs uploading artifacts in the same workflow is often redundant",
      ruleSeverity = Info,
      ruleCategory = Cost,
      ruleTags = [TagCost],
      ruleCheck = \wf ->
        let uploaderCount = length $ filter jobUploadsArtifact (wfJobs wf)
         in [ mkFinding'
                Info
                Cost
                "COST-002"
                ( "Workflow '"
                    <> wfName wf
                    <> "' has "
                    <> T.pack (show uploaderCount)
                    <> " jobs uploading artifacts. "
                    <> "Consider consolidating uploads to reduce storage costs and \
                       \workflow complexity."
                )
                (wfFileName wf)
                Nothing
                ( Just
                    "Merge artifact uploads into a single job, or use \
                    \'actions/upload-artifact' only in the final job of a \
                    \pipeline."
                )
            | uploaderCount > 1
            ]
    }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- | Return True when a job-level if-condition both references a matrix
-- variable and applies an exclusion operator (@!=@ or @!contains@).
hasMatrixExclusion :: T.Text -> Bool
hasMatrixExclusion cond =
  "matrix." `T.isInfixOf` cond
    && ( "!=" `T.isInfixOf` cond
           || "!contains" `T.isInfixOf` cond
       )

-- | Return True when any step in the job calls @actions/upload-artifact@.
jobUploadsArtifact :: Job -> Bool
jobUploadsArtifact j =
  any stepUploadsArtifact (jobSteps j)

stepUploadsArtifact :: Step -> Bool
stepUploadsArtifact s =
  case stepUses s of
    Just uses -> "upload-artifact" `T.isInfixOf` uses
    Nothing -> False
