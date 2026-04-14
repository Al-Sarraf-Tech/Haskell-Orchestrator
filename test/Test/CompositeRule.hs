module Test.CompositeRule (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Rules.Composite
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [WorkflowTrigger] -> [Job] -> Workflow
mkWf triggers jobs =
  Workflow "Test" "test.yml" triggers jobs Nothing Nothing Map.empty

mkWfCall :: T.Text -> [Job] -> Workflow
mkWfCall name jobs =
  Workflow name "test.yml"
    [TriggerEvents [TriggerEvent "workflow_call" [] [] []]]
    jobs Nothing Nothing Map.empty

mkJob :: T.Text -> [Step] -> Job
mkJob jid steps =
  Job jid (Just jid) (StandardRunner "ubuntu-latest")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkRunStep :: T.Text -> Step
mkRunStep cmd =
  Step Nothing (Just "Run") Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

mkRunStepWithShell :: T.Text -> Step
mkRunStepWithShell cmd =
  Step Nothing (Just "Run") Nothing (Just cmd) Map.empty Map.empty Nothing (Just "bash")

mkUsesStep :: T.Text -> Step
mkUsesStep uses =
  Step Nothing (Just "Action") (Just uses) Nothing Map.empty Map.empty Nothing Nothing

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "CompositeRule"
  [ testGroup "COMP-001 Action Missing Description"
      [ testCase "rule has correct ID" $
          ruleId compositeDescriptionRule @?= "COMP-001"

      , testCase "detects generic name in reusable workflow" $ do
          let wf = mkWfCall "CI" []
              findings = ruleCheck compositeDescriptionRule wf
          assertBool "Should find COMP-001 for generic name" (not (null findings))
          findingRuleId (head findings) @?= "COMP-001"
          findingSeverity (head findings) @?= Info

      , testCase "detects very short name in reusable workflow" $ do
          let wf = mkWfCall "Run" []
              findings = ruleCheck compositeDescriptionRule wf
          assertBool "Should find COMP-001 for short name" (not (null findings))

      , testCase "no finding for non-reusable workflow with generic name" $ do
          let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]] []
              wf' = wf { wfName = "CI" }
              findings = ruleCheck compositeDescriptionRule wf'
          assertBool "Non-reusable workflow should not trigger COMP-001" (null findings)

      , testCase "no finding for reusable workflow with descriptive name" $ do
          let wf = mkWfCall "Build and Test Library" []
              findings = ruleCheck compositeDescriptionRule wf
          assertBool "Descriptive name should not trigger COMP-001" (null findings)

      , testCase "no finding for empty workflow list" $ do
          let wf = mkWf [] []
              findings = ruleCheck compositeDescriptionRule wf
          assertBool "Empty workflow should not trigger COMP-001" (null findings)
      ]

  , testGroup "COMP-002 Shell Not Specified"
      [ testCase "rule has correct ID" $
          ruleId compositeShellRule @?= "COMP-002"

      , testCase "detects run steps without shell in reusable workflow" $ do
          let wf = mkWfCall "Deploy Service"
                    [mkJob "build" [mkRunStep "echo hello"]]
              findings = ruleCheck compositeShellRule wf
          assertBool "Should find COMP-002 for run step without shell" (not (null findings))
          findingRuleId (head findings) @?= "COMP-002"
          findingSeverity (head findings) @?= Info

      , testCase "no finding when shell is specified" $ do
          let wf = mkWfCall "Deploy Service"
                    [mkJob "build" [mkRunStepWithShell "echo hello"]]
              findings = ruleCheck compositeShellRule wf
          assertBool "Run step with explicit shell should not trigger COMP-002" (null findings)

      , testCase "no finding for non-reusable workflow with shellless run step" $ do
          let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                    [mkJob "build" [mkRunStep "echo hello"]]
              findings = ruleCheck compositeShellRule wf
          assertBool "Non-reusable should not trigger COMP-002" (null findings)

      , testCase "no finding for reusable workflow with only uses steps" $ do
          let wf = mkWfCall "Deploy Service"
                    [mkJob "build" [mkUsesStep "actions/checkout@v4"]]
              findings = ruleCheck compositeShellRule wf
          assertBool "Uses-only reusable workflow should not trigger COMP-002" (null findings)

      , testCase "caps findings at 3 per workflow" $ do
          let steps = replicate 5 (mkRunStep "echo test")
              wf = mkWfCall "Deploy Service" [mkJob "build" steps]
              findings = ruleCheck compositeShellRule wf
          assertBool "Should have at most 3 findings" (length findings <= 3)

      , testCase "no finding for empty reusable workflow" $ do
          let wf = mkWfCall "Deploy Service" []
              findings = ruleCheck compositeShellRule wf
          assertBool "Empty reusable workflow should not trigger COMP-002" (null findings)
      ]
  ]
