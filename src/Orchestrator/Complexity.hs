-- | YAML complexity scoring for GitHub Actions workflows.
--
-- Computes a weighted complexity score across multiple dimensions and
-- provides a policy rule that flags overly complex workflows.
module Orchestrator.Complexity
  ( -- * Types
    ComplexityScore (..)
  , ComplexityDimension (..)
    -- * Scoring
  , computeComplexity
    -- * Policy
  , complexityRule
    -- * Rendering
  , renderComplexity
  ) where

import Data.Maybe (isJust, maybeToList)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Dimensions used to measure workflow complexity.
data ComplexityDimension
  = Lines
  | NestingDepth
  | ExpressionCount
  | MatrixDimensions
  | ConditionalBranches
  | JobCount
  | StepCount
  | ReusableDepth
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)

-- | Result of complexity analysis: an overall score plus per-dimension breakdown.
data ComplexityScore = ComplexityScore
  { csScore     :: !Int            -- ^ Overall score, 1-10
  , csBreakdown :: !(Map Text Int) -- ^ Per-dimension raw scores
  } deriving stock (Eq, Show)

-- | Compute a weighted complexity score for a workflow.
computeComplexity :: Workflow -> ComplexityScore
computeComplexity wf =
  let allSteps   = concatMap jobSteps (wfJobs wf)
      jobs       = wfJobs wf

      -- Dimension: total lines approximation (steps * avg lines per step)
      lineScore  = estimateLines allSteps

      -- Dimension: nesting depth (max job dependency chain length)
      depthScore = nestingDepth jobs

      -- Dimension: expression count (${{ ... }} occurrences)
      exprScore  = countExpressions allSteps

      -- Dimension: matrix dimensions
      matScore   = maxMatrixDims jobs

      -- Dimension: conditional branches (if: blocks)
      condScore  = countConditionals jobs allSteps

      -- Dimension: job count
      jcScore    = length jobs

      -- Dimension: total step count
      scScore    = length allSteps

      -- Dimension: reusable workflow depth (uses: with workflow refs)
      reuseScore = countReusable allSteps

      breakdown = Map.fromList
        [ ("Lines",              lineScore)
        , ("NestingDepth",       depthScore)
        , ("ExpressionCount",    exprScore)
        , ("MatrixDimensions",   matScore)
        , ("ConditionalBranches", condScore)
        , ("JobCount",           jcScore)
        , ("StepCount",          scScore)
        , ("ReusableDepth",      reuseScore)
        ]

      -- Weighted aggregation: each dimension contributes to a 1-10 scale.
      -- Weights: JobCount 2, StepCount 2, ExpressionCount 1.5,
      -- ConditionalBranches 1.5, Lines 1, NestingDepth 1.5,
      -- MatrixDimensions 1.5, ReusableDepth 1
      weighted :: Double
      weighted = fromIntegral jcScore * 0.8
               + fromIntegral scScore * 0.15
               + fromIntegral exprScore * 0.3
               + fromIntegral condScore * 0.5
               + fromIntegral lineScore * 0.02
               + fromIntegral depthScore * 1.0
               + fromIntegral matScore * 1.5
               + fromIntegral reuseScore * 0.8

      -- Clamp to 1-10
      raw = max 1 (min 10 (round weighted :: Int))

  in ComplexityScore
    { csScore     = raw
    , csBreakdown = breakdown
    }

-- | Policy rule that flags workflows scoring >= 7 on complexity.
complexityRule :: PolicyRule
complexityRule = PolicyRule
  { ruleId          = "CMPLX-001"
  , ruleName        = "Workflow Complexity"
  , ruleDescription = "Flag workflows with high complexity scores (>= 7)"
  , ruleSeverity    = Warning
  , ruleCategory    = Structure
  , ruleTags        = [TagStructure]
  , ruleCheck       = \wf ->
      let cs = computeComplexity wf
      in [ Finding
                  { findingSeverity    = Warning
                  , findingCategory    = Structure
                  , findingRuleId      = "CMPLX-001"
                  , findingMessage     =
                      "Workflow has a complexity score of "
                      <> T.pack (show (csScore cs))
                      <> "/10. Consider splitting into smaller workflows."
                  , findingFile        = wfFileName wf
                  , findingLocation    = Nothing
                  , findingRemediation = Just
                      "Break the workflow into smaller, focused workflows or use \
                      \reusable workflows to reduce complexity."
                  , findingAutoFixable = False
                  , findingEffort      = Nothing
                  , findingLinks       = []
                  }
              | csScore cs >= 7
              ]
  }

-- | Render a complexity score as human-readable text.
renderComplexity :: ComplexityScore -> Text
renderComplexity cs =
  let header = "Complexity Score: " <> T.pack (show (csScore cs)) <> "/10\n"
      dims   = Map.toAscList (csBreakdown cs)
      rows   = map (\(k, v) -> "  " <> k <> ": " <> T.pack (show v)) dims
  in header <> T.unlines rows

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- | Estimate total workflow line count from step content lengths.
estimateLines :: [Step] -> Int
estimateLines steps =
  let runLines s = case stepRun s of
        Nothing  -> 2  -- uses-based step ~2 lines
        Just cmd -> max 1 (length (T.lines cmd) + 2)
  in sum (map runLines steps)

-- | Compute nesting depth as max dependency chain length among jobs.
nestingDepth :: [Job] -> Int
nestingDepth jobs =
  let idMap = Map.fromList [(jobId j, j) | j <- jobs]
      depth :: Set.Set Text -> Job -> Int
      depth visited j = case jobNeeds j of
        [] -> 0
        ns -> 1 + maximum (map (\n ->
          if Set.member n visited
          then 0
          else maybe 0 (depth (Set.insert n visited)) (Map.lookup n idMap)) ns)
  in if null jobs then 0 else maximum (map (depth Set.empty) jobs)

-- | Count ${{ ... }} expression occurrences across all steps.
countExpressions :: [Step] -> Int
countExpressions = sum . map stepExprCount
  where
    stepExprCount s =
      let texts = concat
            [ maybeToList (stepRun s)
            , maybeToList (stepName s)
            , maybeToList (stepIf s)
            , Map.elems (stepWith s)
            , Map.elems (stepEnv s)
            ]
      in sum (map (countSubstr "${{") texts)

-- | Count occurrences of a substring in text.
countSubstr :: Text -> Text -> Int
countSubstr needle haystack
  | T.null needle = 0
  | otherwise     = go haystack 0
  where
    go t acc
      | T.null t  = acc
      | needle `T.isPrefixOf` t = go (T.drop (T.length needle) t) (acc + 1)
      | otherwise = go (T.drop 1 t) acc

-- | Find max matrix dimension count across all jobs.
maxMatrixDims :: [Job] -> Int
maxMatrixDims jobs =
  let dimCount j =
        let texts = concatMap (\s -> concat
              [ maybeToList (stepRun s)
              , maybeToList (stepName s)
              , maybeToList (stepIf s)
              , maybeToList (stepUses s)
              , Map.elems (stepWith s)
              ]) (jobSteps j)
            runnerText = case jobRunsOn j of
              MatrixRunner t -> t
              _              -> ""
            combined = T.concat (runnerText : texts)
        in length (extractMatrixNames combined)
  in if null jobs then 0 else maximum (map dimCount jobs)

-- | Extract distinct matrix.X variable names from text.
extractMatrixNames :: Text -> [Text]
extractMatrixNames = go []
  where
    go acc t
      | T.null t = acc
      | "matrix." `T.isInfixOf` t =
          let after = T.drop 7 (snd (T.breakOn "matrix." t))
              dim   = T.takeWhile (\c -> c /= ' ' && c /= '}' && c /= ','
                                      && c /= ')' && c /= '"') after
              rest  = T.drop (T.length dim) after
          in if T.null dim || dim `elem` acc
             then go acc rest
             else go (dim : acc) rest
      | otherwise = acc

-- | Count conditional branches: job-level if + step-level if.
countConditionals :: [Job] -> [Step] -> Int
countConditionals jobs steps =
  let jobIfs  = length (filter (isJust . jobIf) jobs)
      stepIfs = length (filter (isJust . stepIf) steps)
  in jobIfs + stepIfs

-- | Count steps that reference reusable workflows (uses: owner/repo/.github/...).
countReusable :: [Step] -> Int
countReusable = length . filter isReusableRef
  where
    isReusableRef s = case stepUses s of
      Just u  -> ".github/workflows/" `T.isInfixOf` u || ".github/actions/" `T.isInfixOf` u
      Nothing -> False
