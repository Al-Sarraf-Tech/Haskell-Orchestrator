module Test.ActionsCatalog (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Actions.Catalog
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
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

-- | A well-known pinned SHA (40 hex chars)
pinnedSHA :: T.Text
pinnedSHA = "a6347daa26fa9f3c7b1234567890abcdef123456"

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "ActionsCatalog"
  [ testGroup "catalogActions"
      [ testCase "returns empty list for workflow with no steps" $ do
          let wf = mkWf [mkJob "build" []]
              infos = catalogActions wf
          infos @?= []

      , testCase "returns empty list for run-only steps" $ do
          let wf = mkWf [mkJob "build" [mkRunStep "cabal build"]]
              infos = catalogActions wf
          infos @?= []

      , testCase "catalogues a single external action" $ do
          let wf = mkWf [mkJob "build" [mkUsesStep "actions/checkout@v4"]]
              infos = catalogActions wf
          length infos @?= 1
          actionOwner (head infos) @?= "actions"
          actionName  (head infos) @?= "checkout"
          actionCurrentRef (head infos) @?= "v4"

      , testCase "catalogues multiple actions across jobs" $ do
          let step1 = mkUsesStep "actions/checkout@v4"
              step2 = mkUsesStep "actions/setup-haskell@v1"
              wf = mkWf [ mkJob "build" [step1]
                        , mkJob "test"  [step2]
                        ]
              infos = catalogActions wf
          length infos @?= 2

      , testCase "excludes local composite actions (./ prefix)" $ do
          let wf = mkWf [mkJob "build" [mkUsesStep "./.github/actions/my-action"]]
              infos = catalogActions wf
          infos @?= []

      , testCase "excludes docker actions (docker:// prefix)" $ do
          let wf = mkWf [mkJob "build" [mkUsesStep "docker://alpine:3.18"]]
              infos = catalogActions wf
          infos @?= []

      , testCase "identifies first-party actions (actions/ owner)" $ do
          let wf = mkWf [mkJob "build" [mkUsesStep "actions/checkout@v4"]]
              infos = catalogActions wf
          assertBool "actions/checkout should be first-party"
            (actionIsFirstParty (head infos))

      , testCase "identifies third-party actions" $ do
          let wf = mkWf [mkJob "build" [mkUsesStep "some-org/some-action@v1"]]
              infos = catalogActions wf
          assertBool "some-org action should not be first-party"
            (not (actionIsFirstParty (head infos)))
      ]

  , testGroup "checkActionHealth"
      [ testCase "Healthy for SHA-pinned action" $ do
          let ai = ActionInfo "actions" "checkout" pinnedSHA True True False
          checkActionHealth ai @?= Healthy

      , testCase "Unpinned for tag-versioned action" $ do
          let ai = ActionInfo "actions" "checkout" "v4" False True False
          checkActionHealth ai @?= Unpinned

      , testCase "Deprecated for deprecated action" $ do
          let ai = ActionInfo "actions" "create-release" "v1" False True True
          checkActionHealth ai @?= Deprecated

      , testCase "Deprecated takes priority over Unpinned" $ do
          let ai = ActionInfo "actions" "create-release" "v1" False True True
          checkActionHealth ai @?= Deprecated
      ]

  , testGroup "deprecatedActions"
      [ testCase "deprecatedActions is non-empty" $
          assertBool "Should have some deprecated actions"
            (not (Map.null deprecatedActions))

      , testCase "actions/create-release is deprecated" $
          assertBool "actions/create-release should be deprecated"
            (Map.member "actions/create-release" deprecatedActions)

      , testCase "deprecated action has a replacement" $ do
          let replacement = Map.lookup "actions/create-release" deprecatedActions
          assertBool "Deprecated action should have replacement"
            (maybe False (not . T.null) replacement)
      ]

  , testGroup "actionHealthRule"
      [ testCase "rule has correct ID" $
          ruleId actionHealthRule @?= "ACT-001"

      , testCase "rule severity is Warning" $
          ruleSeverity actionHealthRule @?= Warning

      , testCase "detects unpinned action" $ do
          let wf = mkWf [mkJob "build" [mkUsesStep "actions/checkout@v4"]]
              findings = ruleCheck actionHealthRule wf
          assertBool "Should find ACT-001 for unpinned action" (not (null findings))
          findingRuleId (head findings) @?= "ACT-001"

      , testCase "no finding for SHA-pinned action" $ do
          let wf = mkWf [mkJob "build" [mkUsesStep ("actions/checkout@" <> pinnedSHA)]]
              findings = ruleCheck actionHealthRule wf
          assertBool "SHA-pinned action should not trigger ACT-001" (null findings)

      , testCase "no finding for run-only workflow" $ do
          let wf = mkWf [mkJob "build" [mkRunStep "cabal build"]]
              findings = ruleCheck actionHealthRule wf
          assertBool "Run-only workflow should not trigger ACT-001" (null findings)

      , testCase "no finding for empty workflow" $ do
          let wf = mkWf []
              findings = ruleCheck actionHealthRule wf
          assertBool "Empty workflow should not trigger ACT-001" (null findings)
      ]
  ]
