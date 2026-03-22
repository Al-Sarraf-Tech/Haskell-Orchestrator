module Test.Policy (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "Policy"
  [ testCase "Missing permissions detected" $ do
      let wf = mkWorkflow Nothing Nothing
          findings = evaluatePolicies defaultPolicyPack wf
          permFindings = filter (\f -> findingRuleId f == "PERM-001") findings
      assertBool "Should find missing permissions" (not $ null permFindings)

  , testCase "Write-all permissions detected" $ do
      let wf = mkWorkflow (Just (PermissionsAll PermWrite)) Nothing
          findings = evaluatePolicies defaultPolicyPack wf
          broadFindings = filter (\f -> findingRuleId f == "PERM-002") findings
      assertBool "Should find broad permissions" (not $ null broadFindings)

  , testCase "Good permissions pass" $ do
      let perms = Just (PermissionsMap (Map.fromList [("contents", PermRead)]))
          wf = mkWorkflowWithTimeout perms Nothing
          findings = evaluatePolicies defaultPolicyPack wf
          permFindings = filter (\f -> findingCategory f == Permissions) findings
      assertBool "No permission findings" (null permFindings)

  , testCase "Unpinned action detected" $ do
      let wf = mkWorkflowWithAction "third-party/action@v1"
          findings = evaluatePolicies defaultPolicyPack wf
          secFindings = filter (\f -> findingRuleId f == "SEC-001") findings
      assertBool "Should find unpinned action" (not $ null secFindings)

  , testCase "Pinned action passes" $ do
      let wf = mkWorkflowWithAction "third-party/action@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
          findings = evaluatePolicies defaultPolicyPack wf
          secFindings = filter (\f -> findingRuleId f == "SEC-001") findings
      assertBool "Pinned action should pass" (null secFindings)

  , testCase "Missing timeout detected" $ do
      let wf = mkWorkflow Nothing Nothing
          findings = evaluatePolicies defaultPolicyPack wf
          resFindings = filter (\f -> findingRuleId f == "RES-001") findings
      assertBool "Should find missing timeout" (not $ null resFindings)

  , testCase "Filter by severity" $ do
      let findings = [ mkTestFinding Info, mkTestFinding Warning, mkTestFinding Error ]
          filtered = filterBySeverity Warning findings
      length filtered @?= 2

  , testCase "Group by category" $ do
      let findings = [ mkTestFindingCat Permissions, mkTestFindingCat Security, mkTestFindingCat Security ]
          grouped = groupByCategory findings
      Map.size grouped @?= 2
  ]

mkWorkflow :: Maybe Permissions -> Maybe ConcurrencyConfig -> Workflow
mkWorkflow perms conc = Workflow
  { wfName = "Test Workflow"
  , wfFileName = "test.yml"
  , wfTriggers = [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  , wfJobs = [Job "build" (Just "Build") (StandardRunner "ubuntu-latest")
               [Step Nothing (Just "Run") Nothing (Just "echo test") Map.empty Map.empty Nothing]
               Nothing [] Nothing Map.empty Nothing Nothing Nothing False Nothing False]
  , wfPermissions = perms
  , wfConcurrency = conc
  , wfEnv = Map.empty
  }

mkWorkflowWithTimeout :: Maybe Permissions -> Maybe ConcurrencyConfig -> Workflow
mkWorkflowWithTimeout perms conc = Workflow
  { wfName = "Test Workflow"
  , wfFileName = "test.yml"
  , wfTriggers = [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  , wfJobs = [Job "build" (Just "Build") (StandardRunner "ubuntu-latest")
               [Step Nothing (Just "Run") Nothing (Just "echo test") Map.empty Map.empty Nothing]
               Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False]
  , wfPermissions = perms
  , wfConcurrency = conc
  , wfEnv = Map.empty
  }

mkWorkflowWithAction :: T.Text -> Workflow
mkWorkflowWithAction action = Workflow
  { wfName = "Test Workflow"
  , wfFileName = "test.yml"
  , wfTriggers = [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  , wfJobs = [Job "build" (Just "Build") (StandardRunner "ubuntu-latest")
               [Step Nothing (Just "Action") (Just action) Nothing Map.empty Map.empty Nothing]
               Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False]
  , wfPermissions = Just (PermissionsMap (Map.fromList [("contents", PermRead)]))
  , wfConcurrency = Nothing
  , wfEnv = Map.empty
  }

mkTestFinding :: Severity -> Finding
mkTestFinding sev = Finding sev Permissions "TEST" "test" "test.yml" Nothing Nothing False Nothing []

mkTestFindingCat :: FindingCategory -> Finding
mkTestFindingCat cat = Finding Warning cat "TEST" "test" "test.yml" Nothing Nothing False Nothing []
