module Test.Changelog (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Changelog
import Orchestrator.Model
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

mkWfNamed :: T.Text -> [Job] -> Workflow
mkWfNamed nm jobs =
  Workflow
    nm
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
mkStep nm = Step (Just nm) (Just nm) Nothing (Just "echo hi") Map.empty Map.empty Nothing Nothing

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "Changelog"
    [ testDiffIdentical,
      testDiffName,
      testDiffJobAdded,
      testDiffJobRemoved,
      testDiffStepAdded,
      testDiffStepRemoved,
      testDiffRunner,
      testDiffTrigger,
      testRenderEmpty,
      testRenderNonEmpty
    ]

-- | Identical workflows → no changes
testDiffIdentical :: TestTree
testDiffIdentical = testCase "diffWorkflows/identical-no-changes" $ do
  let wf = mkWf [mkJob "build" [mkStep "checkout"]]
  diffWorkflows wf wf @?= []

-- | Name change detected as Modified
testDiffName :: TestTree
testDiffName = testCase "diffWorkflows/name-change-detected" $ do
  let old = mkWfNamed "OldName" []
      new = mkWfNamed "NewName" []
      entries = diffWorkflows old new
  assertBool "at least one change" (not (null entries))
  assertBool "name change is Modified" (any (\e -> ceChangeType e == Modified) entries)

-- | New job added
testDiffJobAdded :: TestTree
testDiffJobAdded = testCase "diffWorkflows/job-added" $ do
  let old = mkWf []
      new = mkWf [mkJob "build" []]
      entries = diffWorkflows old new
  assertBool "added entry present" (any (\e -> ceChangeType e == Added) entries)
  assertBool "description mentions build" (any (\e -> "build" `T.isInfixOf` ceDescription e) entries)

-- | Job removed
testDiffJobRemoved :: TestTree
testDiffJobRemoved = testCase "diffWorkflows/job-removed" $ do
  let old = mkWf [mkJob "build" []]
      new = mkWf []
      entries = diffWorkflows old new
  assertBool "removed entry present" (any (\e -> ceChangeType e == Removed) entries)
  assertBool "description mentions build" (any (\e -> "build" `T.isInfixOf` ceDescription e) entries)

-- | Step added to existing job
testDiffStepAdded :: TestTree
testDiffStepAdded = testCase "diffWorkflows/step-added" $ do
  let old = mkWf [mkJob "build" [mkStep "checkout"]]
      new = mkWf [mkJob "build" [mkStep "checkout", mkStep "lint"]]
      entries = diffWorkflows old new
  assertBool "step-added entry present" (any (\e -> ceChangeType e == Added && "lint" `T.isInfixOf` ceDescription e) entries)

-- | Step removed from existing job
testDiffStepRemoved :: TestTree
testDiffStepRemoved = testCase "diffWorkflows/step-removed" $ do
  let old = mkWf [mkJob "build" [mkStep "checkout", mkStep "lint"]]
      new = mkWf [mkJob "build" [mkStep "checkout"]]
      entries = diffWorkflows old new
  assertBool "step-removed entry present" (any (\e -> ceChangeType e == Removed && "lint" `T.isInfixOf` ceDescription e) entries)

-- | Runner change detected as Modified
testDiffRunner :: TestTree
testDiffRunner = testCase "diffWorkflows/runner-change-detected" $ do
  let oldJob =
        Job
          "build"
          (Just "build")
          (StandardRunner "ubuntu-20.04")
          []
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
      newJob = oldJob {jobRunsOn = StandardRunner "ubuntu-latest"}
      old = mkWf [oldJob]
      new = mkWf [newJob]
      entries = diffWorkflows old new
  assertBool "runner modified entry" (any (\e -> ceChangeType e == Modified && "runner" `T.isInfixOf` ceDescription e) entries)

-- | Added trigger detected
testDiffTrigger :: TestTree
testDiffTrigger = testCase "diffWorkflows/trigger-added" $ do
  let old = mkWf []
      new =
        Workflow
          "Test"
          "test.yml"
          [ TriggerEvents [TriggerEvent "push" ["main"] [] []],
            TriggerDispatch
          ]
          []
          Nothing
          Nothing
          Map.empty
      entries = diffWorkflows old new
  assertBool "trigger-added entry present" (any (\e -> ceChangeType e == Added) entries)

-- | renderChangelog with empty list returns "No changes"
testRenderEmpty :: TestTree
testRenderEmpty = testCase "renderChangelog/empty-returns-no-changes" $ do
  let txt = renderChangelog []
  assertBool "contains No changes" ("No changes" `T.isInfixOf` txt)

-- | renderChangelog with entries contains sections
testRenderNonEmpty :: TestTree
testRenderNonEmpty = testCase "renderChangelog/non-empty-has-sections" $ do
  let entries =
        [ ChangeEntry Added "Job added: build" "test.yml",
          ChangeEntry Removed "Job removed: lint" "test.yml",
          ChangeEntry Modified "Runner changed" "test.yml"
        ]
      txt = renderChangelog entries
  assertBool "contains Added section" ("Added" `T.isInfixOf` txt)
  assertBool "contains Removed section" ("Removed" `T.isInfixOf` txt)
  assertBool "contains Modified section" ("Modified" `T.isInfixOf` txt)
