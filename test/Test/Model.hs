module Test.Model (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Orchestrator.Model
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests = testGroup "Model"
  [ testCase "Workflow has name" $ do
      let wf = minimalWorkflow
      wfName wf @?= "test"

  , testCase "Job has steps" $ do
      let job = minimalJob "build"
      length (jobSteps job) @?= 1

  , testCase "Permissions read-all" $ do
      let p = PermissionsAll PermRead
      p @?= PermissionsAll PermRead

  , testCase "Permissions map lookup" $ do
      let p = PermissionsMap (Map.fromList [("contents", PermRead), ("packages", PermWrite)])
      case p of
        PermissionsMap m -> Map.lookup "contents" m @?= Just PermRead
        _ -> error "unexpected"

  , testCase "Concurrency config" $ do
      let c = ConcurrencyConfig "ci-${{ github.ref }}" True
      concCancelInProgress c @?= True

  , testCase "Runner spec standard" $ do
      StandardRunner "ubuntu-latest" @?= StandardRunner "ubuntu-latest"

  , testCase "Runner spec matrix" $ do
      MatrixRunner "${{ matrix.os }}" @?= MatrixRunner "${{ matrix.os }}"
  ]

minimalWorkflow :: Workflow
minimalWorkflow = Workflow
  { wfName = "test"
  , wfFileName = "test.yml"
  , wfTriggers = [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  , wfJobs = [minimalJob "build"]
  , wfPermissions = Nothing
  , wfConcurrency = Nothing
  , wfEnv = Map.empty
  }

minimalJob :: Text -> Job
minimalJob jid = Job
  { jobId = jid
  , jobName = Just "Build"
  , jobRunsOn = StandardRunner "ubuntu-latest"
  , jobSteps = [minimalStep]
  , jobPermissions = Nothing
  , jobNeeds = []
  , jobConcurrency = Nothing
  , jobEnv = Map.empty
  , jobIf = Nothing
  , jobTimeoutMin = Nothing
  }

minimalStep :: Step
minimalStep = Step
  { stepId = Nothing
  , stepName = Just "Checkout"
  , stepUses = Just "actions/checkout@v4"
  , stepRun = Nothing
  , stepWith = Map.empty
  , stepEnv = Map.empty
  , stepIf = Nothing
  }
