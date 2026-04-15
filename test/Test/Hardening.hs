module Test.Hardening (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (evaluatePolicy)
import Orchestrator.Rules.Hardening
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [Job] -> Workflow
mkWf jobs =
  Workflow
    "Test"
    "test.yml"
    [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
    jobs
    Nothing
    Nothing
    Map.empty

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

-- | A checkout step with no 'with' entries (missing persist-credentials).
checkoutStepNoPC :: Step
checkoutStepNoPC =
  Step
    { stepId = Nothing,
      stepName = Just "Checkout",
      stepUses = Just "actions/checkout@v4",
      stepRun = Nothing,
      stepWith = Map.empty,
      stepEnv = Map.empty,
      stepIf = Nothing,
      stepShell = Nothing
    }

-- | A checkout step with persist-credentials: false.
checkoutStepWithPC :: Step
checkoutStepWithPC =
  checkoutStepNoPC
    { stepWith = Map.fromList [("persist-credentials", "false")]
    }

-- | A non-checkout action step.
otherActionStep :: Step
otherActionStep =
  Step
    { stepId = Nothing,
      stepName = Just "Some Action",
      stepUses = Just "some-org/some-action@v1",
      stepRun = Nothing,
      stepWith = Map.empty,
      stepEnv = Map.empty,
      stepIf = Nothing,
      stepShell = Nothing
    }

-- | A run step without shell.
runStepNoShell :: Step
runStepNoShell =
  Step
    { stepId = Nothing,
      stepName = Just "Run",
      stepUses = Nothing,
      stepRun = Just "echo hello",
      stepWith = Map.empty,
      stepEnv = Map.empty,
      stepIf = Nothing,
      stepShell = Nothing
    }

-- | A run step with explicit shell.
runStepWithShell :: Step
runStepWithShell = runStepNoShell {stepShell = Just "bash"}

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "Hardening"
    [ testGroup
        "HARD-001 persist-credentials"
        [ testCase "detects checkout without persist-credentials" $ do
            let wf = mkWf [mkJob "build" [checkoutStepNoPC]]
                findings = evaluatePolicy hard001PersistCredentials wf
            assertBool "Should find HARD-001" (not (null findings))
            findingRuleId (head findings) @?= "HARD-001"
            findingSeverity (head findings) @?= Warning,
          testCase "no finding when persist-credentials: false is set" $ do
            let wf = mkWf [mkJob "build" [checkoutStepWithPC]]
                findings = evaluatePolicy hard001PersistCredentials wf
            assertBool "Should not find HARD-001" (null findings),
          testCase "no finding for non-checkout actions" $ do
            let wf = mkWf [mkJob "build" [otherActionStep]]
                findings = evaluatePolicy hard001PersistCredentials wf
            assertBool "Non-checkout step should not trigger HARD-001" (null findings)
        ],
      testGroup
        "HARD-002 default shell unset"
        [ testCase "detects run steps without shell" $ do
            let wf = mkWf [mkJob "build" [runStepNoShell]]
                findings = evaluatePolicy hard002DefaultShellUnset wf
            assertBool "Should find HARD-002" (not (null findings))
            findingRuleId (head findings) @?= "HARD-002"
            findingSeverity (head findings) @?= Info
            -- message should mention count
            assertBool
              "Message mentions step count"
              ("1" `T.isInfixOf` findingMessage (head findings)),
          testCase "no finding when shell is specified" $ do
            let wf = mkWf [mkJob "build" [runStepWithShell]]
                findings = evaluatePolicy hard002DefaultShellUnset wf
            assertBool "Should not find HARD-002" (null findings),
          testCase "no finding for action-only workflow" $ do
            let wf = mkWf [mkJob "build" [checkoutStepNoPC, otherActionStep]]
                findings = evaluatePolicy hard002DefaultShellUnset wf
            assertBool "Action-only workflow should not trigger HARD-002" (null findings),
          testCase "counts multiple unshelled steps in one finding" $ do
            let wf = mkWf [mkJob "build" [runStepNoShell, runStepNoShell]]
                findings = evaluatePolicy hard002DefaultShellUnset wf
            length findings @?= 1
            assertBool
              "Message mentions count 2"
              ("2" `T.isInfixOf` findingMessage (head findings))
        ],
      testGroup
        "HARD-003 pull_request_target risk"
        [ testCase "detects pull_request_target with checkout" $ do
            let wf =
                  Workflow
                    "Test"
                    "test.yml"
                    [TriggerEvents [TriggerEvent "pull_request_target" [] [] []]]
                    [mkJob "build" [checkoutStepNoPC]]
                    Nothing
                    Nothing
                    Map.empty
                findings = evaluatePolicy hard003PullRequestTargetRisk wf
            assertBool "Should find HARD-003" (not (null findings))
            findingRuleId (head findings) @?= "HARD-003"
            findingSeverity (head findings) @?= Error,
          testCase "no finding for regular pull_request trigger" $ do
            let wf =
                  Workflow
                    "Test"
                    "test.yml"
                    [TriggerEvents [TriggerEvent "pull_request" [] [] []]]
                    [mkJob "build" [checkoutStepNoPC]]
                    Nothing
                    Nothing
                    Map.empty
                findings = evaluatePolicy hard003PullRequestTargetRisk wf
            assertBool "Regular pull_request should not trigger HARD-003" (null findings),
          testCase "no finding for pull_request_target without checkout" $ do
            let wf =
                  Workflow
                    "Test"
                    "test.yml"
                    [TriggerEvents [TriggerEvent "pull_request_target" [] [] []]]
                    [mkJob "build" [runStepWithShell]]
                    Nothing
                    Nothing
                    Map.empty
                findings = evaluatePolicy hard003PullRequestTargetRisk wf
            assertBool "No checkout means no HARD-003 finding" (null findings)
        ]
    ]
