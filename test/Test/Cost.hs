module Test.Cost (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Rules.Cost
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool)

tests :: TestTree
tests = testGroup "Cost"
  [ testGroup "COST-001 Matrix Waste"
      [ testCase "detects matrix job with exclusion if condition" $ do
          let job = mkMatrixJobWithIf "build" "matrix.os != 'windows-latest'" []
              wf  = mkWf [job]
              findings = ruleCheck matrixWasteRule wf
          assertBool "Should find COST-001" (not (null findings))
          assertBool "Finding is COST-001"
            (all (\f -> findingRuleId f == "COST-001") findings)

      , testCase "detects matrix job with !contains exclusion" $ do
          let job = mkMatrixJobWithIf "build" "!contains(matrix.os, 'windows')" []
              wf  = mkWf [job]
              findings = ruleCheck matrixWasteRule wf
          assertBool "Should find COST-001 for !contains" (not (null findings))

      , testCase "no finding for matrix job without exclusion condition" $ do
          let job = mkMatrixJobWithIf "build" "matrix.os == 'ubuntu-latest'" []
              wf  = mkWf [job]
              findings = ruleCheck matrixWasteRule wf
          assertBool "Should not find COST-001" (null findings)

      , testCase "no finding for standard runner with exclusion if" $ do
          let job = (mkJob "build" [])
                      { jobIf = Just "matrix.os != 'windows'" }
              wf  = mkWf [job]
              findings = ruleCheck matrixWasteRule wf
          assertBool "StandardRunner should not trigger COST-001" (null findings)

      , testCase "no finding when matrix job has no if condition" $ do
          let step = Step Nothing (Just "checkout") (Just "actions/checkout@v4")
                       Nothing Map.empty Map.empty Nothing Nothing
              job  = mkMatrixJobWithIf "build" "" [step]  -- empty if treated as no-exclusion
              wf   = mkWf [job]
              -- empty string has no "!=" or "!contains", so no finding
              findings = ruleCheck matrixWasteRule wf
          assertBool "No exclusion operators — no finding" (null findings)
      ]

  , testGroup "COST-002 Redundant Artifact Upload"
      [ testCase "detects two jobs uploading artifacts" $ do
          let uploadStep = mkUploadStep
              job1 = mkJob "build1" [uploadStep]
              job2 = mkJob "build2" [uploadStep]
              wf   = mkWf [job1, job2]
              findings = ruleCheck redundantArtifactUploadRule wf
          assertBool "Should find COST-002" (not (null findings))
          assertBool "Finding is COST-002"
            (all (\f -> findingRuleId f == "COST-002") findings)

      , testCase "no finding for single job with upload-artifact" $ do
          let uploadStep = mkUploadStep
              job  = mkJob "build" [uploadStep]
              wf   = mkWf [job]
              findings = ruleCheck redundantArtifactUploadRule wf
          assertBool "Single upload — no finding" (null findings)

      , testCase "no finding when no jobs upload artifacts" $ do
          let step = Step Nothing (Just "run") Nothing (Just "echo hi")
                       Map.empty Map.empty Nothing Nothing
              job  = mkJob "build" [step]
              wf   = mkWf [job]
              findings = ruleCheck redundantArtifactUploadRule wf
          assertBool "No uploads — no finding" (null findings)

      , testCase "finding counts three jobs uploading" $ do
          let uploadStep = mkUploadStep
              jobs = map (\n -> mkJob ("job-" <> n) [uploadStep]) ["a","b","c"]
              wf   = mkWf jobs
              findings = ruleCheck redundantArtifactUploadRule wf
          -- One finding per workflow
          assertBool "Should have exactly one finding" (length findings == 1)
      ]
  ]

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [Job] -> Workflow
mkWf jobs = Workflow "Test" "test.yml"
  [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  jobs Nothing Nothing Map.empty

mkJob :: Text -> [Step] -> Job
mkJob jid steps =
  Job jid (Just jid) (StandardRunner "ubuntu-latest")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkMatrixJobWithIf :: Text -> Text -> [Step] -> Job
mkMatrixJobWithIf jid cond steps =
  Job jid (Just jid) (MatrixRunner "${{ matrix.os }}")
    steps Nothing [] Nothing Map.empty (Just cond) (Just 30) Nothing False Nothing False

-- | A step that calls actions/upload-artifact.
mkUploadStep :: Step
mkUploadStep =
  Step Nothing (Just "Upload") (Just "actions/upload-artifact@v4")
    Nothing Map.empty Map.empty Nothing Nothing
