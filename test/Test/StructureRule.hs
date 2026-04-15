module Test.StructureRule (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (evaluatePolicy)
import Orchestrator.Rules.Structure
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "StructureRule"
    [ testGroup
        "STRUCT-001 Unreferenced Reusable Workflow"
        [ testCase "flags workflow with workflow_call trigger" $ do
            let wf = mkWf [TriggerEvents [TriggerEvent "workflow_call" [] [] []]] []
                findings = evaluatePolicy structUnreferencedReusableRule wf
            assertBool "Expected one STRUCT-001 finding" (not (null findings))
            findingRuleId (head findings) @?= "STRUCT-001"
            findingSeverity (head findings) @?= Info,
          testCase "no finding for regular push workflow" $ do
            let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]] []
                findings = evaluatePolicy structUnreferencedReusableRule wf
            assertBool "Expected no findings for push workflow" (null findings)
        ],
      testGroup
        "STRUCT-002 Circular Workflow Call"
        [ testCase "detects self-referencing workflow" $ do
            let selfStep =
                  Step
                    { stepId = Just "self-call",
                      stepName = Just "Call Self",
                      stepUses = Just ".github/workflows/test.yml",
                      stepRun = Nothing,
                      stepWith = Map.empty,
                      stepEnv = Map.empty,
                      stepIf = Nothing,
                      stepShell = Nothing
                    }
                job = mkJob "test-job" [selfStep]
                wf = (mkWf [] [job]) {wfFileName = ".github/workflows/test.yml"}
                findings = evaluatePolicy structCircularCallRule wf
            assertBool "Expected one STRUCT-002 finding" (not (null findings))
            findingRuleId (head findings) @?= "STRUCT-002"
            findingSeverity (head findings) @?= Error,
          testCase "detects self-reference with leading ./ stripped" $ do
            let selfStep =
                  Step
                    { stepId = Just "self-call",
                      stepName = Just "Call Self",
                      stepUses = Just "./.github/workflows/test.yml",
                      stepRun = Nothing,
                      stepWith = Map.empty,
                      stepEnv = Map.empty,
                      stepIf = Nothing,
                      stepShell = Nothing
                    }
                job = mkJob "test-job" [selfStep]
                wf = (mkWf [] [job]) {wfFileName = ".github/workflows/test.yml"}
                findings = evaluatePolicy structCircularCallRule wf
            assertBool "Expected STRUCT-002 finding for ./ prefix" (not (null findings)),
          testCase "no finding for normal reusable call to different file" $ do
            let otherStep =
                  Step
                    { stepId = Just "call-other",
                      stepName = Just "Call Other",
                      stepUses = Just ".github/workflows/other.yml",
                      stepRun = Nothing,
                      stepWith = Map.empty,
                      stepEnv = Map.empty,
                      stepIf = Nothing,
                      stepShell = Nothing
                    }
                job = mkJob "test-job" [otherStep]
                wf = (mkWf [] [job]) {wfFileName = ".github/workflows/test.yml"}
                findings = evaluatePolicy structCircularCallRule wf
            assertBool "Expected no findings for call to different file" (null findings)
        ]
    ]

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [WorkflowTrigger] -> [Job] -> Workflow
mkWf triggers jobs =
  Workflow
    { wfName = "Test",
      wfFileName = "test.yml",
      wfTriggers = triggers,
      wfJobs = jobs,
      wfPermissions = Nothing,
      wfConcurrency = Nothing,
      wfEnv = Map.empty
    }

mkJob :: T.Text -> [Step] -> Job
mkJob jid steps =
  Job
    { jobId = jid,
      jobName = Just jid,
      jobRunsOn = StandardRunner "ubuntu-latest",
      jobSteps = steps,
      jobPermissions = Nothing,
      jobNeeds = [],
      jobConcurrency = Nothing,
      jobEnv = Map.empty,
      jobIf = Nothing,
      jobTimeoutMin = Just 30,
      jobEnvironment = Nothing,
      jobEnvironmentUrl = False,
      jobFailFast = Nothing,
      jobMatrixIncludeOnly = False
    }
