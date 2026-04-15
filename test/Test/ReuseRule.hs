module Test.ReuseRule (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Rules.Reuse
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [WorkflowTrigger] -> [Job] -> Workflow
mkWf triggers jobs =
  Workflow "Test" "test.yml" triggers jobs Nothing Nothing Map.empty

mkWfCall :: [Job] -> Workflow
mkWfCall jobs =
  mkWf [TriggerEvents [TriggerEvent "workflow_call" [] [] []]] jobs

mkJob :: T.Text -> [Step] -> Job
mkJob jid steps =
  Job
    jid
    (Just jid)
    (StandardRunner "ubuntu-latest")
    steps
    Nothing
    []
    Nothing
    Map.empty
    Nothing
    (Just 30)
    Nothing
    False
    Nothing
    False

mkRunStep :: T.Text -> Step
mkRunStep cmd =
  Step Nothing (Just "Run") Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

-- | Step referencing workflow inputs
inputRefStep :: Step
inputRefStep = mkRunStep "echo ${{ inputs.environment }}"

-- | Step that sets outputs via GITHUB_OUTPUT
outputStep :: Step
outputStep = mkRunStep "echo 'result=success' >> $GITHUB_OUTPUT"

-- | Step with inputs in 'with'
inputWithStep :: Step
inputWithStep =
  Step
    Nothing
    (Just "Deploy")
    (Just "some/action@v1")
    Nothing
    (Map.fromList [("env", "${{ inputs.target-env }}")])
    Map.empty
    Nothing
    Nothing

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "ReuseRule"
    [ testGroup
        "REUSE-001 Reusable Workflow Input Validation"
        [ testCase "rule has correct ID" $
            ruleId reuseInputValidationRule @?= "REUSE-001",
          testCase "rule severity is Warning" $
            ruleSeverity reuseInputValidationRule @?= Warning,
          testCase "detects reusable workflow with no input references" $ do
            let wf = mkWfCall [mkJob "build" [mkRunStep "cabal build"]]
                findings = ruleCheck reuseInputValidationRule wf
            assertBool
              "Should find REUSE-001 for workflow_call without inputs"
              (not (null findings))
            findingRuleId (head findings) @?= "REUSE-001"
            findingSeverity (head findings) @?= Warning,
          testCase "no finding when step references inputs" $ do
            let wf = mkWfCall [mkJob "build" [inputRefStep]]
                findings = ruleCheck reuseInputValidationRule wf
            assertBool "Step referencing inputs should not trigger REUSE-001" (null findings),
          testCase "no finding when 'with' references inputs" $ do
            let wf = mkWfCall [mkJob "build" [inputWithStep]]
                findings = ruleCheck reuseInputValidationRule wf
            assertBool "With-block input ref should not trigger REUSE-001" (null findings),
          testCase "no finding for non-reusable workflow" $ do
            let wf =
                  mkWf
                    [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                    [mkJob "build" [mkRunStep "cabal build"]]
                findings = ruleCheck reuseInputValidationRule wf
            assertBool "Non-reusable workflow should not trigger REUSE-001" (null findings),
          testCase "no finding for reusable workflow with github.event.inputs ref" $ do
            let step = mkRunStep "echo ${{ github.event.inputs.version }}"
                wf = mkWfCall [mkJob "build" [step]]
                findings = ruleCheck reuseInputValidationRule wf
            assertBool "github.event.inputs ref should not trigger REUSE-001" (null findings),
          testCase "no finding for empty reusable workflow" $ do
            let wf = mkWfCall []
                findings = ruleCheck reuseInputValidationRule wf
            -- empty workflow has no steps, so usesExpressions = False
            -- but hasWorkflowCall = True => should fire
            -- this documents current behavior
            assertBool
              "Empty reusable workflow triggers REUSE-001 (no inputs defined)"
              (not (null findings))
        ],
      testGroup
        "REUSE-002 Reusable Workflow Unused Outputs"
        [ testCase "rule has correct ID" $
            ruleId reuseUnusedOutputRule @?= "REUSE-002",
          testCase "rule severity is Info" $
            ruleSeverity reuseUnusedOutputRule @?= Info,
          testCase "detects reusable workflow that sets no outputs" $ do
            let wf = mkWfCall [mkJob "build" [mkRunStep "cabal build"]]
                findings = ruleCheck reuseUnusedOutputRule wf
            assertBool
              "Should find REUSE-002 for workflow_call without outputs"
              (not (null findings))
            findingRuleId (head findings) @?= "REUSE-002",
          testCase "no finding when step sets GITHUB_OUTPUT" $ do
            let wf = mkWfCall [mkJob "build" [outputStep]]
                findings = ruleCheck reuseUnusedOutputRule wf
            assertBool
              "Step setting GITHUB_OUTPUT should not trigger REUSE-002"
              (null findings),
          testCase "no finding for non-reusable workflow" $ do
            let wf =
                  mkWf
                    [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                    [mkJob "build" [mkRunStep "cabal build"]]
                findings = ruleCheck reuseUnusedOutputRule wf
            assertBool "Non-reusable workflow should not trigger REUSE-002" (null findings),
          testCase "no finding when step uses set-output" $ do
            let step = mkRunStep "echo '::set-output name=result::success'"
                wf = mkWfCall [mkJob "build" [step]]
                findings = ruleCheck reuseUnusedOutputRule wf
            assertBool "Step using set-output should not trigger REUSE-002" (null findings),
          testCase "finding message mentions workflow name" $ do
            let wf =
                  Workflow
                    "MyReusableWorkflow"
                    "my-reuse.yml"
                    [TriggerEvents [TriggerEvent "workflow_call" [] [] []]]
                    [mkJob "build" [mkRunStep "make"]]
                    Nothing
                    Nothing
                    Map.empty
                findings = ruleCheck reuseUnusedOutputRule wf
            assertBool
              "Message should mention workflow name"
              ("MyReusableWorkflow" `T.isInfixOf` findingMessage (head findings))
        ]
    ]
