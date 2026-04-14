module Test.DuplicateRule (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Rules.Duplicate
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [Job] -> Workflow
mkWf jobs = Workflow "Test" "test.yml"
  [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  jobs Nothing Nothing Map.empty

mkJob :: T.Text -> [Step] -> Job
mkJob jid steps =
  Job jid (Just jid) (StandardRunner "ubuntu-latest")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkUsesStep :: T.Text -> Step
mkUsesStep uses =
  Step Nothing (Just "Action") (Just uses) Nothing Map.empty Map.empty Nothing Nothing

mkRunStep :: T.Text -> Step
mkRunStep cmd =
  Step Nothing (Just "Run") Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

-- | A canonical build job: checkout + build
buildJob :: T.Text -> Job
buildJob jid = mkJob jid
  [ mkUsesStep "actions/checkout@v4"
  , mkRunStep "cabal build all"
  ]

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "DuplicateRule"
  [ testGroup "DUP-001 Cross-Workflow Duplicate Detection"
      [ testCase "rule has correct ID" $
          ruleId duplicateJobRule @?= "DUP-001"

      , testCase "rule severity is Info" $
          ruleSeverity duplicateJobRule @?= Info

      , testCase "detects two structurally identical jobs" $ do
          let wf = mkWf [buildJob "build-1", buildJob "build-2"]
              findings = ruleCheck duplicateJobRule wf
          assertBool "Should find DUP-001 for identical jobs" (not (null findings))
          findingRuleId (head findings) @?= "DUP-001"

      , testCase "no finding for single job" $ do
          let wf = mkWf [buildJob "build"]
              findings = ruleCheck duplicateJobRule wf
          assertBool "Single job should not trigger DUP-001" (null findings)

      , testCase "no finding for structurally different jobs" $ do
          let job1 = mkJob "build" [mkUsesStep "actions/checkout@v4", mkRunStep "cabal build"]
              job2 = mkJob "test"  [mkUsesStep "actions/checkout@v4", mkRunStep "cabal test"]
              wf = mkWf [job1, job2]
              findings = ruleCheck duplicateJobRule wf
          assertBool "Different run commands should not trigger DUP-001" (null findings)

      , testCase "no finding for empty workflow" $ do
          let wf = mkWf []
              findings = ruleCheck duplicateJobRule wf
          assertBool "Empty workflow should not trigger DUP-001" (null findings)

      , testCase "finding message mentions workflow name" $ do
          let wf = mkWf [buildJob "build-1", buildJob "build-2"]
              findings = ruleCheck duplicateJobRule wf
          assertBool "Message should mention workflow name"
            ("Test" `T.isInfixOf` findingMessage (head findings))

      , testCase "three identical jobs still produces one finding" $ do
          let wf = mkWf [buildJob "a", buildJob "b", buildJob "c"]
              findings = ruleCheck duplicateJobRule wf
          assertBool "Three identical jobs should produce at least one finding"
            (not (null findings))

      , testCase "different runners prevent duplicate detection" $ do
          let job1 = Job "build-1" (Just "build-1") (StandardRunner "ubuntu-latest")
                       [mkRunStep "make"] Nothing [] Nothing Map.empty
                       Nothing (Just 30) Nothing False Nothing False
              job2 = Job "build-2" (Just "build-2") (StandardRunner "windows-latest")
                       [mkRunStep "make"] Nothing [] Nothing Map.empty
                       Nothing (Just 30) Nothing False Nothing False
              wf = mkWf [job1, job2]
              findings = ruleCheck duplicateJobRule wf
          assertBool "Different runners should not trigger DUP-001" (null findings)
      ]
  ]
