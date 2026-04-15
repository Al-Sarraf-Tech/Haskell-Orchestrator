-- | Tests for supply chain security rules.
module Test.SupplyChain (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Rules.SupplyChain
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

------------------------------------------------------------------------
-- Test helpers
------------------------------------------------------------------------

mkWf :: [WorkflowTrigger] -> [Job] -> Workflow
mkWf triggers jobs =
  Workflow "Test" "test.yml" triggers jobs Nothing Nothing Map.empty

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

mkRunStep :: T.Text -> Step
mkRunStep cmd =
  Step Nothing Nothing Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

mkUseStep :: T.Text -> Step
mkUseStep action =
  Step Nothing Nothing (Just action) Nothing Map.empty Map.empty Nothing Nothing

-- | Checkout step with an explicit ref input.
mkCheckoutWithRef :: T.Text -> Step
mkCheckoutWithRef ref =
  Step
    Nothing
    Nothing
    (Just "actions/checkout@v4")
    Nothing
    (Map.fromList [("ref", ref)])
    Map.empty
    Nothing
    Nothing

-- | Checkout step with NO ref input (default checkout).
mkCheckoutNoRef :: Step
mkCheckoutNoRef = mkUseStep "actions/checkout@v4"

prtTrigger :: WorkflowTrigger
prtTrigger =
  TriggerEvents
    [TriggerEvent "pull_request_target" [] [] []]

prTrigger :: WorkflowTrigger
prTrigger =
  TriggerEvents
    [TriggerEvent "pull_request" [] [] []]

pushTrigger :: WorkflowTrigger
pushTrigger =
  TriggerEvents
    [TriggerEvent "push" [] [] []]

wfRunTrigger :: WorkflowTrigger
wfRunTrigger =
  TriggerEvents
    [TriggerEvent "workflow_run" [] [] []]

idTokenWritePerms :: Permissions
idTokenWritePerms = PermissionsMap (Map.fromList [("id-token", PermWrite)])

------------------------------------------------------------------------
-- SEC-003 tests
------------------------------------------------------------------------

sec003Tests :: TestTree
sec003Tests =
  testGroup
    "SEC-003 Workflow Run Privilege Escalation"
    [ testCase "Detects PRT + head.ref checkout" $ do
        let step = mkCheckoutWithRef "${{ github.head_ref }}"
            job = mkJob "build" [step]
            wf = mkWf [prtTrigger] [job]
            findings = ruleCheck sec003Rule wf
        assertBool "Expected a finding" (not (null findings))
        findingRuleId (head findings) @?= "SEC-003",
      testCase "Detects PRT + pull_request.head.ref checkout" $ do
        let step = mkCheckoutWithRef "${{ github.event.pull_request.head.sha }}"
            job = mkJob "build" [step]
            wf = mkWf [prtTrigger] [job]
            findings = ruleCheck sec003Rule wf
        assertBool "Expected a finding" (not (null findings)),
      testCase "No finding for regular pull_request with head ref" $ do
        let step = mkCheckoutWithRef "${{ github.head_ref }}"
            job = mkJob "build" [step]
            wf = mkWf [prTrigger] [job]
            findings = ruleCheck sec003Rule wf
        findings @?= [],
      testCase "No finding for PRT without explicit ref" $ do
        let job = mkJob "build" [mkCheckoutNoRef]
            wf = mkWf [prtTrigger] [job]
            findings = ruleCheck sec003Rule wf
        findings @?= [],
      testCase "No finding for PRT with non-head ref" $ do
        let step = mkCheckoutWithRef "main"
            job = mkJob "build" [step]
            wf = mkWf [prtTrigger] [job]
            findings = ruleCheck sec003Rule wf
        findings @?= []
    ]

------------------------------------------------------------------------
-- SEC-004 tests
------------------------------------------------------------------------

sec004Tests :: TestTree
sec004Tests =
  testGroup
    "SEC-004 Artifact Poisoning"
    [ testCase "Detects download-artifact + run in same job" $ do
        let steps =
              [ mkUseStep "actions/download-artifact@v4",
                mkRunStep "./run-artifact.sh"
              ]
            job = mkJob "exec" steps
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck sec004Rule wf
        assertBool "Expected a finding" (not (null findings))
        findingRuleId (head findings) @?= "SEC-004",
      testCase "No finding when only download, no run" $ do
        let steps = [mkUseStep "actions/download-artifact@v4"]
            job = mkJob "exec" steps
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck sec004Rule wf
        findings @?= [],
      testCase "No finding when only run, no download" $ do
        let steps = [mkRunStep "echo hello"]
            job = mkJob "exec" steps
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck sec004Rule wf
        findings @?= [],
      testCase "Elevated to Error severity on workflow_run trigger" $ do
        let steps =
              [ mkUseStep "actions/download-artifact@v4",
                mkRunStep "./run-artifact.sh"
              ]
            job = mkJob "exec" steps
            wf = mkWf [wfRunTrigger] [job]
            findings = ruleCheck sec004Rule wf
        case findings of
          (f : _) -> findingSeverity f @?= Error
          [] -> assertBool "Expected a finding" False,
      testCase "No finding when run precedes download" $ do
        -- run before download should not flag (no run AFTER download)
        let steps =
              [ mkRunStep "prepare.sh",
                mkUseStep "actions/download-artifact@v4"
              ]
            job = mkJob "exec" steps
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck sec004Rule wf
        findings @?= []
    ]

------------------------------------------------------------------------
-- SEC-005 tests
------------------------------------------------------------------------

sec005Tests :: TestTree
sec005Tests =
  testGroup
    "SEC-005 OIDC Token Scope"
    [ testCase "Detects id-token write without deploy step" $ do
        let wf =
              (mkWf [pushTrigger] [mkJob "build" [mkRunStep "echo hi"]])
                { wfPermissions = Just idTokenWritePerms
                }
            findings = ruleCheck sec005Rule wf
        assertBool "Expected a finding" (not (null findings))
        findingRuleId (head findings) @?= "SEC-005",
      testCase "No finding when aws-actions deploy step present" $ do
        let step = mkUseStep "aws-actions/configure-aws-credentials@v4"
            job = mkJob "deploy" [step]
            wf =
              (mkWf [pushTrigger] [job])
                { wfPermissions = Just idTokenWritePerms
                }
            findings = ruleCheck sec005Rule wf
        findings @?= [],
      testCase "No finding when azure/login deploy step present" $ do
        let step = mkUseStep "azure/login@v2"
            job = mkJob "deploy" [step]
            wf =
              (mkWf [pushTrigger] [job])
                { wfPermissions = Just idTokenWritePerms
                }
            findings = ruleCheck sec005Rule wf
        findings @?= [],
      testCase "No finding when google-github-actions/auth present" $ do
        let step = mkUseStep "google-github-actions/auth@v2"
            job = mkJob "deploy" [step]
            wf =
              (mkWf [pushTrigger] [job])
                { wfPermissions = Just idTokenWritePerms
                }
            findings = ruleCheck sec005Rule wf
        findings @?= [],
      testCase "No finding without id-token write" $ do
        let wf = mkWf [pushTrigger] [mkJob "build" [mkRunStep "echo hi"]]
            findings = ruleCheck sec005Rule wf
        findings @?= []
    ]

------------------------------------------------------------------------
-- SUPPLY-001 tests
------------------------------------------------------------------------

supply001Tests :: TestTree
supply001Tests =
  testGroup
    "SUPPLY-001 Abandoned Action"
    [ testCase "No finding for first-party actions/checkout" $ do
        let job = mkJob "build" [mkUseStep "actions/checkout@v4"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply001Rule wf
        findings @?= [],
      testCase "No finding for github/ actions" $ do
        let job = mkJob "build" [mkUseStep "github/codeql-action@v3"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply001Rule wf
        findings @?= [],
      testCase "No finding for local ./ action" $ do
        let job = mkJob "build" [mkUseStep "./.github/actions/my-action"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply001Rule wf
        findings @?= [],
      testCase "No finding for third-party not in abandoned list" $ do
        -- The abandoned list is currently empty, so nothing should be flagged
        let job = mkJob "build" [mkUseStep "some-org/some-action@v1"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply001Rule wf
        findings @?= []
    ]

------------------------------------------------------------------------
-- SUPPLY-002 tests
------------------------------------------------------------------------

supply002Tests :: TestTree
supply002Tests =
  testGroup
    "SUPPLY-002 Typosquat Risk"
    [ testCase "Detects action/checkout (missing s)" $ do
        let job = mkJob "build" [mkUseStep "action/checkout@v4"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply002Rule wf
        assertBool "Expected a finding" (not (null findings))
        findingRuleId (head findings) @?= "SUPPLY-002",
      testCase "No finding for exact actions/checkout" $ do
        let job = mkJob "build" [mkUseStep "actions/checkout@v4"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply002Rule wf
        findings @?= [],
      testCase "Detects action/setup-node (missing s)" $ do
        let job = mkJob "build" [mkUseStep "action/setup-node@v4"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply002Rule wf
        assertBool "Expected a finding" (not (null findings)),
      testCase "No finding for actions/setup-node exact match" $ do
        let job = mkJob "build" [mkUseStep "actions/setup-node@v4"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply002Rule wf
        findings @?= [],
      testCase "No finding for completely different action" $ do
        -- edit distance > 2 from all popular actions
        let job = mkJob "build" [mkUseStep "completelydifferent/xyz-tool@v1"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply002Rule wf
        findings @?= [],
      testCase "No finding for local ./ action" $ do
        let job = mkJob "build" [mkUseStep "./.github/actions/checkout"]
            wf = mkWf [pushTrigger] [job]
            findings = ruleCheck supply002Rule wf
        findings @?= []
    ]

------------------------------------------------------------------------
-- Test tree
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "SupplyChain"
    [ sec003Tests,
      sec004Tests,
      sec005Tests,
      supply001Tests,
      supply002Tests
    ]
