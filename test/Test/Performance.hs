module Test.Performance (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (evaluatePolicy)
import Orchestrator.Rules.Performance
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Performance"
    [ testGroup
        "PERF-001 Missing Cache"
        [ testCase "detects Node build without cache" $ do
            let wf = mkWf [mkJob "build" [nodeInstallStep]]
                findings = evaluatePolicy missingCacheRule wf
            assertBool "Should find missing cache" (not $ null findings)
            findingRuleId (head findings) @?= "PERF-001",
          testCase "no finding when cache is present" $ do
            let wf = mkWf [mkJob "build" [nodeInstallStep, cacheStep]]
                findings = evaluatePolicy missingCacheRule wf
            assertBool "Should not find missing cache" (null findings),
          testCase "detects Rust build without cache" $ do
            let wf = mkWf [mkJob "build" [rustBuildStep]]
                findings = evaluatePolicy missingCacheRule wf
            assertBool "Should find missing cache for Rust build" (not $ null findings),
          testCase "no finding for non-build workflow" $ do
            let wf = mkWf [mkJob "notify" [echoStep]]
                findings = evaluatePolicy missingCacheRule wf
            assertBool "Non-build job should not trigger PERF-001" (null findings)
        ],
      testGroup
        "PERF-002 Sequential Parallelizable Jobs"
        [ testCase "detects 3+ independent jobs" $ do
            let wf =
                  mkWf
                    [ mkJob "job-a" [echoStep],
                      mkJob "job-b" [echoStep],
                      mkJob "job-c" [echoStep]
                    ]
                findings = evaluatePolicy sequentialParallelizableRule wf
            assertBool "Should find 3 independent jobs" (not $ null findings)
            findingRuleId (head findings) @?= "PERF-002",
          testCase "no finding when jobs have dependencies" $ do
            let wf =
                  mkWf
                    [ mkJob "job-a" [echoStep],
                      mkJobWithNeeds "job-b" ["job-a"] [echoStep],
                      mkJobWithNeeds "job-c" ["job-b"] [echoStep]
                    ]
                findings = evaluatePolicy sequentialParallelizableRule wf
            assertBool "Jobs with needs should not trigger PERF-002" (null findings),
          testCase "no finding for single job" $ do
            let wf = mkWf [mkJob "build" [echoStep]]
                findings = evaluatePolicy sequentialParallelizableRule wf
            assertBool "Single job should not trigger PERF-002" (null findings),
          testCase "no finding for exactly 2 jobs" $ do
            let wf =
                  mkWf
                    [ mkJob "job-a" [echoStep],
                      mkJob "job-b" [echoStep]
                    ]
                findings = evaluatePolicy sequentialParallelizableRule wf
            assertBool "Two jobs should not trigger PERF-002" (null findings),
          testCase "no finding when only 2 of 3 jobs are independent" $ do
            let wf =
                  mkWf
                    [ mkJob "job-a" [echoStep],
                      mkJob "job-b" [echoStep],
                      mkJobWithNeeds "job-c" ["job-a"] [echoStep]
                    ]
                findings = evaluatePolicy sequentialParallelizableRule wf
            assertBool "Only 2 independent jobs should not trigger PERF-002" (null findings)
        ]
    ]

------------------------------------------------------------------------
-- Workflow / job helpers
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

mkJobWithNeeds :: T.Text -> [T.Text] -> [Step] -> Job
mkJobWithNeeds jid needs steps =
  Job
    jid
    (Just jid)
    (StandardRunner "ubuntu-latest")
    steps
    Nothing
    needs
    Nothing
    Map.empty
    Nothing
    (Just 30)
    Nothing
    False
    Nothing
    False

------------------------------------------------------------------------
-- Step fixtures
------------------------------------------------------------------------

nodeInstallStep :: Step
nodeInstallStep =
  Step
    Nothing
    (Just "Install deps")
    Nothing
    (Just "npm install")
    Map.empty
    Map.empty
    Nothing
    Nothing

rustBuildStep :: Step
rustBuildStep =
  Step
    Nothing
    (Just "Build")
    Nothing
    (Just "cargo build --release")
    Map.empty
    Map.empty
    Nothing
    Nothing

cacheStep :: Step
cacheStep =
  Step
    Nothing
    (Just "Cache")
    (Just "actions/cache@v3")
    Nothing
    Map.empty
    Map.empty
    Nothing
    Nothing

echoStep :: Step
echoStep =
  Step
    Nothing
    (Just "Echo")
    Nothing
    (Just "echo hello")
    Map.empty
    Map.empty
    Nothing
    Nothing
