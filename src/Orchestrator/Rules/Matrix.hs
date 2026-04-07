-- | Rules for matrix strategy analysis.
--
-- Detects potential issues with GitHub Actions matrix strategies:
-- explosion risk from large cross-products and missing fail-fast.
module Orchestrator.Rules.Matrix
  ( matrixExplosionRule
  , matrixFailFastRule
  ) where

import Data.Maybe (maybeToList)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Rule: detect matrix strategies that could create too many jobs.
-- Heuristic: if the step 'with' or 'env' maps contain matrix expressions
-- and the workflow has multiple matrix-style patterns, flag it.
matrixExplosionRule :: PolicyRule
matrixExplosionRule = PolicyRule
  { ruleId = "MAT-001"
  , ruleName = "Matrix Explosion Risk"
  , ruleDescription = "Detect matrix strategies that may create excessive job combinations"
  , ruleSeverity = Warning
  , ruleCategory = Structure
  , ruleTags = [TagPerformance, TagCost]
  , ruleCheck = \wf ->
      concatMap (\j -> case jobRunsOn j of
        MatrixRunner _ -> checkMatrixExplosion wf j
        _ -> if hasMatrixRefs j
             then checkMatrixExplosion wf j
             else []
      ) (wfJobs wf)
  }

-- | Rule: detect matrix jobs missing fail-fast configuration.
-- When matrix creates many jobs, fail-fast prevents resource waste.
matrixFailFastRule :: PolicyRule
matrixFailFastRule = PolicyRule
  { ruleId = "MAT-002"
  , ruleName = "Matrix Missing Fail-Fast"
  , ruleDescription = "Matrix jobs should set fail-fast to control failure behavior"
  , ruleSeverity = Info
  , ruleCategory = Structure
  , ruleTags = [TagPerformance, TagCost]
  , ruleCheck = \wf ->
      concatMap (\j ->
        let isMatrix = case jobRunsOn j of
              MatrixRunner _ -> True
              _ -> hasMatrixRefs j
            hasFF = case jobFailFast j of
              Just _  -> True
              Nothing -> False
        in [ Finding
                    { findingSeverity = Info
                    , findingCategory = Structure
                    , findingRuleId = "MAT-002"
                    , findingMessage =
                        "Job '" <> jobId j
                        <> "' uses matrix strategy but fail-fast is not explicitly set. "
                        <> "Default is true, but explicit is better for documentation."
                    , findingFile = wfFileName wf
                    , findingLocation = Nothing
                    , findingRemediation = Just
                        "Add 'strategy: { fail-fast: true/false }' to make failure behavior explicit."
                    , findingAutoFixable = False
                    , findingEffort = Nothing
                    , findingLinks = []
                    }
                | isMatrix && not hasFF
                ]
      ) (wfJobs wf)
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- | Check if a job references matrix variables.
-- Only match GitHub Actions expression patterns (${{ matrix.X }}),
-- not arbitrary strings like "capability-matrix.md".
hasMatrixRefs :: Job -> Bool
hasMatrixRefs j =
  let allText = concatMap stepTexts (jobSteps j)
  in any (\t -> "${{ matrix." `T.isInfixOf` t || "{{matrix." `T.isInfixOf` t) allText

stepTexts :: Step -> [Text]
stepTexts s = concat
  [ maybeToList (stepRun s)
  , maybeToList (stepName s)
  , maybeToList (stepIf s)
  , maybeToList (stepUses s)
  ]

-- | Check for matrix explosion risk indicators.
-- Skip if the matrix uses only 'include:' entries (no cross-product).
checkMatrixExplosion :: Workflow -> Job -> [Finding]
checkMatrixExplosion wf j
  | jobMatrixIncludeOnly j = []
  | otherwise =
  let refs = countMatrixDimensions j
  in [ Finding
              { findingSeverity = Warning
              , findingCategory = Structure
              , findingRuleId = "MAT-001"
              , findingMessage =
                  "Job '" <> jobId j <> "' references " <> T.pack (show refs)
                  <> " matrix dimensions. Large cross-products can create excessive "
                  <> "jobs (N^" <> T.pack (show refs) <> " combinations)."
              , findingFile = wfFileName wf
              , findingLocation = Nothing
              , findingRemediation = Just $
                  "Consider using 'include:' for specific combinations instead "
                  <> "of full cross-product, or limit matrix values."
              , findingAutoFixable = False
              , findingEffort = Nothing
              , findingLinks = []
              }
          | refs >= 3
          ]

-- | Count distinct matrix dimension references in a job.
countMatrixDimensions :: Job -> Int
countMatrixDimensions j =
  let allText = T.concat $ concatMap stepTexts (jobSteps j)
      -- Also check the runner spec
      runnerText = case jobRunsOn j of
        MatrixRunner t -> t
        _ -> ""
      combined = allText <> runnerText
      -- Extract distinct matrix.X references
      dims = extractMatrixDims combined
  in length dims

extractMatrixDims :: Text -> [Text]
extractMatrixDims t = go t []
  where
    go remaining acc
      | T.null remaining = acc
      | "matrix." `T.isInfixOf` remaining =
          let after = T.drop 1 $ snd $ T.breakOn "matrix." remaining
              -- after starts with the dimension name after "atrix."
              dimFull = T.drop 6 after  -- skip "atrix."
              dim = T.takeWhile (\c -> c /= ' ' && c /= '}' && c /= ',' && c /= ')' && c /= '"') dimFull
              rest = T.drop (T.length dim) dimFull
          in if dim `elem` acc || T.null dim
             then go rest acc
             else go rest (dim : acc)
      | otherwise = acc

