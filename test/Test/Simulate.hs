module Test.Simulate (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Simulate
import Orchestrator.Simulate.Conditions (evaluateCondition)
import Orchestrator.Simulate.Matrix (estimateMatrixSize, expandMatrix)
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

mkStep :: T.Text -> Step
mkStep nm = Step Nothing (Just nm) Nothing (Just "echo hello") Map.empty Map.empty Nothing Nothing

-- | Build a matrix job that references matrix.os in its runner
mkMatrixJob :: T.Text -> [Step] -> Job
mkMatrixJob jid steps =
  Job
    jid
    (Just jid)
    (MatrixRunner "${{ matrix.os }}")
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

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "Simulate"
    [ testSimulateBasic,
      testSimulateSkipped,
      testSimulateEmpty,
      testSimulateRender,
      testConditionAlways,
      testConditionFailure,
      testConditionEventMatch,
      testConditionEventMismatch,
      testConditionTrue,
      testConditionFalse,
      testMatrixExpand,
      testMatrixEmpty,
      testMatrixSize
    ]

-- | Basic push-to-main workflow triggers correctly, job runs
testSimulateBasic :: TestTree
testSimulateBasic = testCase "simulateWorkflow/basic-push-runs-job" $ do
  let wf = mkWf [mkJob "build" [mkStep "Step1"]]
      ctx = defaultContext
      res = simulateWorkflow ctx wf
  simTotalJobs res @?= 1
  simRunningJobs res @?= 1
  simSkippedJobs res @?= 0

-- | Wrong event → workflow not triggered → job skipped
testSimulateSkipped :: TestTree
testSimulateSkipped = testCase "simulateWorkflow/wrong-event-skips-job" $ do
  let wf = mkWf [mkJob "build" [mkStep "Step1"]]
      ctx = defaultContext {ctxEventName = "schedule"}
      res = simulateWorkflow ctx wf
  simSkippedJobs res @?= 1
  simRunningJobs res @?= 0

-- | Empty job list
testSimulateEmpty :: TestTree
testSimulateEmpty = testCase "simulateWorkflow/no-jobs" $ do
  let wf = mkWf []
      res = simulateWorkflow defaultContext wf
  simTotalJobs res @?= 0
  simRunningJobs res @?= 0

-- | renderSimulation produces non-empty text with key fields
testSimulateRender :: TestTree
testSimulateRender = testCase "renderSimulation/contains-workflow-name" $ do
  let wf = mkWf [mkJob "build" []]
      res = simulateWorkflow defaultContext wf
      txt = renderSimulation res
  assertBool "contains workflow name" ("Test" `T.isInfixOf` txt)
  assertBool "contains WILL RUN or SKIP" ("WILL RUN" `T.isInfixOf` txt || "SKIP" `T.isInfixOf` txt)

-- | always() → WillRun
testConditionAlways :: TestTree
testConditionAlways = testCase "evaluateCondition/always" $ do
  let ctx = defaultContext
  evaluateCondition ctx "always()" @?= WillRun

-- | failure() → WillSkip
testConditionFailure :: TestTree
testConditionFailure = testCase "evaluateCondition/failure" $ do
  let ctx = defaultContext
  case evaluateCondition ctx "failure()" of
    WillSkip _ -> pure ()
    other -> fail $ "Expected WillSkip, got: " <> show other

-- | github.event_name == 'push' matches
testConditionEventMatch :: TestTree
testConditionEventMatch = testCase "evaluateCondition/event-match" $ do
  let ctx = defaultContext {ctxEventName = "push"}
  evaluateCondition ctx "github.event_name == 'push'" @?= WillRun

-- | github.event_name == 'release' doesn't match
testConditionEventMismatch :: TestTree
testConditionEventMismatch = testCase "evaluateCondition/event-mismatch-skips" $ do
  let ctx = defaultContext {ctxEventName = "push"}
  case evaluateCondition ctx "github.event_name == 'release'" of
    WillSkip _ -> pure ()
    other -> fail $ "Expected WillSkip, got: " <> show other

-- | true literal → WillRun
testConditionTrue :: TestTree
testConditionTrue = testCase "evaluateCondition/true-literal" $ do
  evaluateCondition defaultContext "true" @?= WillRun

-- | false literal → WillSkip
testConditionFalse :: TestTree
testConditionFalse = testCase "evaluateCondition/false-literal" $ do
  case evaluateCondition defaultContext "false" of
    WillSkip _ -> pure ()
    other -> fail $ "Expected WillSkip, got: " <> show other

-- | Matrix job with matrix.os runner expands to multiple combinations
testMatrixExpand :: TestTree
testMatrixExpand = testCase "expandMatrix/os-dimension-expands" $ do
  let j = mkMatrixJob "test" []
      res = expandMatrix j
  assertBool "matrix expands to >1 combination" (length res > 1)

-- | Non-matrix job returns empty expansions
testMatrixEmpty :: TestTree
testMatrixEmpty = testCase "expandMatrix/no-matrix-returns-empty" $ do
  let j = mkJob "build" []
      res = expandMatrix j
  res @?= []

-- | estimateMatrixSize for non-matrix job is 1
testMatrixSize :: TestTree
testMatrixSize = testCase "estimateMatrixSize/no-matrix-is-1" $ do
  let j = mkJob "build" []
  estimateMatrixSize j @?= 1
