module Test.DriftRule (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Orchestrator.Model
import Orchestrator.Policy (evaluatePolicy)
import Orchestrator.Rules.Drift
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests = testGroup "DriftRule"
  [ testCase "Detects same action at different versions across jobs" $ do
      let wf = mkWf
                [ mkJob "job-a" [mkUseStep "actions/checkout@v3"]
                , mkJob "job-b" [mkUseStep "actions/checkout@v4"]
                ]
          findings = evaluatePolicy driftVersionRule wf
      assertBool "Should find drift for actions/checkout" (not (null findings))
      findingRuleId (head findings) @?= "DRIFT-001"

  , testCase "No finding when all versions match" $ do
      let wf = mkWf
                [ mkJob "job-a" [mkUseStep "actions/checkout@v4"]
                , mkJob "job-b" [mkUseStep "actions/checkout@v4"]
                ]
          findings = evaluatePolicy driftVersionRule wf
      assertBool "No drift when versions are the same" (null findings)

  , testCase "No finding for different actions at the same version" $ do
      let wf = mkWf
                [ mkJob "job-a" [mkUseStep "actions/checkout@v4"]
                , mkJob "job-b" [mkUseStep "actions/setup-node@v4"]
                ]
          findings = evaluatePolicy driftVersionRule wf
      assertBool "Different actions do not constitute drift" (null findings)

  , testCase "No finding for single use of an action" $ do
      let wf = mkWf
                [ mkJob "job-a" [mkUseStep "actions/checkout@v4"] ]
          findings = evaluatePolicy driftVersionRule wf
      assertBool "Single use never drifts" (null findings)

  , testCase "Local actions are ignored" $ do
      let wf = mkWf
                [ mkJob "job-a" [mkUseStep "./local-action@v1"]
                , mkJob "job-b" [mkUseStep "./local-action@v2"]
                ]
          findings = evaluatePolicy driftVersionRule wf
      assertBool "Local actions (./prefix) must be skipped" (null findings)

  , testCase "collectActionVersions groups by owner/repo" $ do
      let wf = mkWf
                [ mkJob "job-a" [mkUseStep "actions/checkout@v3"]
                , mkJob "job-b" [mkUseStep "actions/checkout@v4"]
                ]
          vmap = collectActionVersions wf
      Map.member "actions/checkout" vmap @?= True

  , testCase "parseActionRef parses owner/repo@version" $
      parseActionRef "actions/checkout@v4" @?= [("actions/checkout", "v4")]

  , testCase "parseActionRef skips local actions" $
      parseActionRef "./my-action" @?= []

  , testCase "parseActionRef skips refs without @" $
      parseActionRef "actions/checkout" @?= []
  ]

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [Job] -> Workflow
mkWf jobs = Workflow
  { wfName        = "Test Workflow"
  , wfFileName    = "test.yml"
  , wfTriggers    = [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  , wfJobs        = jobs
  , wfPermissions = Nothing
  , wfConcurrency = Nothing
  , wfEnv         = Map.empty
  }

mkJob :: Text -> [Step] -> Job
mkJob jid steps = Job
  { jobId              = jid
  , jobName            = Nothing
  , jobRunsOn          = StandardRunner "ubuntu-latest"
  , jobSteps           = steps
  , jobPermissions     = Nothing
  , jobNeeds           = []
  , jobConcurrency     = Nothing
  , jobEnv             = Map.empty
  , jobIf              = Nothing
  , jobTimeoutMin      = Just 30
  , jobEnvironment     = Nothing
  , jobEnvironmentUrl  = False
  , jobFailFast        = Nothing
  , jobMatrixIncludeOnly = False
  }

mkUseStep :: Text -> Step
mkUseStep uses = Step
  { stepId    = Nothing
  , stepName  = Nothing
  , stepUses  = Just uses
  , stepRun   = Nothing
  , stepWith  = Map.empty
  , stepEnv   = Map.empty
  , stepIf    = Nothing
  , stepShell = Nothing
  }
