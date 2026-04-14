module Test.EnvironmentRule (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Rules.Environment
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: T.Text -> [Job] -> Workflow
mkWf name jobs = Workflow name (T.unpack name <> ".yml")
  [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  jobs Nothing Nothing Map.empty

mkJob :: T.Text -> [Step] -> Job
mkJob jid steps =
  Job jid (Just jid) (StandardRunner "ubuntu-latest")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkJobWithEnv :: T.Text -> T.Text -> [Step] -> Job
mkJobWithEnv jid envName steps =
  Job jid (Just jid) (StandardRunner "ubuntu-latest")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) (Just envName) False Nothing False

mkJobWithEnvUrl :: T.Text -> T.Text -> [Step] -> Job
mkJobWithEnvUrl jid envName steps =
  Job jid (Just jid) (StandardRunner "ubuntu-latest")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) (Just envName) True Nothing False

mkRunStep :: T.Text -> Step
mkRunStep cmd =
  Step Nothing (Just "Run") Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

-- | Step that sets environment_url
envUrlStep :: Step
envUrlStep = mkRunStep "echo 'environment_url=https://example.com' >> $GITHUB_OUTPUT"

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "EnvironmentRule"
  [ testGroup "ENV-001 Missing Environment Approval Gate"
      [ testCase "rule has correct ID" $
          ruleId envApprovalGateRule @?= "ENV-001"

      , testCase "rule severity is Warning" $
          ruleSeverity envApprovalGateRule @?= Warning

      , testCase "detects deploy workflow without environment reference" $ do
          let wf = mkWf "deploy" [mkJob "deploy" [mkRunStep "kubectl apply -f ."]]
              findings = ruleCheck envApprovalGateRule wf
          assertBool "Should find ENV-001 for deploy without environment" (not (null findings))
          findingRuleId (head findings) @?= "ENV-001"
          findingSeverity (head findings) @?= Warning

      , testCase "detects release workflow without environment" $ do
          let wf = mkWf "release" [mkJob "publish" [mkRunStep "cargo publish"]]
              findings = ruleCheck envApprovalGateRule wf
          assertBool "Should find ENV-001 for release without environment" (not (null findings))

      , testCase "no finding when job references environment" $ do
          let wf = mkWf "deploy" [mkJobWithEnv "deploy" "production" [mkRunStep "kubectl apply"]]
              findings = ruleCheck envApprovalGateRule wf
          assertBool "Job with environment should not trigger ENV-001" (null findings)

      , testCase "no finding for non-deployment workflow" $ do
          let wf = mkWf "ci" [mkJob "build" [mkRunStep "cabal build"]]
              findings = ruleCheck envApprovalGateRule wf
          assertBool "Non-deploy workflow should not trigger ENV-001" (null findings)

      , testCase "finding for deploy workflow even with no jobs" $ do
          let wf = mkWf "deploy" []
              findings = ruleCheck envApprovalGateRule wf
          assertBool "Deploy workflow with no jobs still triggers ENV-001 (name-based)" (not (null findings))

      , testCase "detects staging workflow without environment" $ do
          let wf = mkWf "staging" [mkJob "deploy" [mkRunStep "helm upgrade"]]
              findings = ruleCheck envApprovalGateRule wf
          assertBool "Should find ENV-001 for staging without environment" (not (null findings))
      ]

  , testGroup "ENV-002 Environment Missing URL"
      [ testCase "rule has correct ID" $
          ruleId envMissingUrlRule @?= "ENV-002"

      , testCase "rule severity is Info" $
          ruleSeverity envMissingUrlRule @?= Info

      , testCase "detects environment without URL" $ do
          let wf = mkWf "deploy"
                    [mkJobWithEnv "deploy" "production" [mkRunStep "kubectl apply"]]
              findings = ruleCheck envMissingUrlRule wf
          assertBool "Should find ENV-002 for env without URL" (not (null findings))
          findingRuleId (head findings) @?= "ENV-002"

      , testCase "no finding when jobEnvironmentUrl is True" $ do
          let wf = mkWf "deploy"
                    [mkJobWithEnvUrl "deploy" "production" [mkRunStep "kubectl apply"]]
              findings = ruleCheck envMissingUrlRule wf
          assertBool "Job with env URL flag should not trigger ENV-002" (null findings)

      , testCase "no finding when step sets environment_url" $ do
          let wf = mkWf "deploy"
                    [mkJobWithEnv "deploy" "production" [envUrlStep]]
              findings = ruleCheck envMissingUrlRule wf
          assertBool "Step setting env URL should not trigger ENV-002" (null findings)

      , testCase "no finding for job without environment" $ do
          let wf = mkWf "ci" [mkJob "build" [mkRunStep "cabal build"]]
              findings = ruleCheck envMissingUrlRule wf
          assertBool "Job without environment should not trigger ENV-002" (null findings)

      , testCase "no finding for empty workflow" $ do
          let wf = mkWf "deploy" []
              findings = ruleCheck envMissingUrlRule wf
          assertBool "Empty workflow should not trigger ENV-002" (null findings)

      , testCase "finding message mentions job ID" $ do
          let wf = mkWf "deploy"
                    [mkJobWithEnv "publish" "staging" [mkRunStep "echo deploy"]]
              findings = ruleCheck envMissingUrlRule wf
          assertBool "Message should mention job ID"
            ("publish" `T.isInfixOf` findingMessage (head findings))
      ]
  ]
