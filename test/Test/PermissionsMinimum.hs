module Test.PermissionsMinimum (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Orchestrator.Model
import Orchestrator.Permissions.Minimum
import Orchestrator.Policy (PolicyRule (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

tests :: TestTree
tests = testGroup "PermissionsMinimum"
  [ testCase "analyzePermissions empty workflow has no minimum perms" $ do
      let pa = analyzePermissions emptyWorkflow
      minimumPerms pa @?= Map.empty

  , testCase "analyzePermissions checkout action requires contents:read" $ do
      let wf = wfWithUses "actions/checkout@v4"
          pa = analyzePermissions wf
      Map.lookup "contents" (minimumPerms pa) @?= Just PermRead

  , testCase "analyzePermissions upload-artifact requires actions:write" $ do
      let wf = wfWithUses "actions/upload-artifact@v4"
          pa = analyzePermissions wf
      Map.lookup "actions" (minimumPerms pa) @?= Just PermWrite

  , testCase "analyzePermissions no excess when perms match minimum" $ do
      let wf = (wfWithUses "actions/checkout@v4")
                 { wfPermissions = Just (PermissionsMap (Map.fromList [("contents", PermRead)])) }
          pa = analyzePermissions wf
      excessPerms pa @?= Map.empty

  , testCase "analyzePermissions excess when write declared but read needed" $ do
      let wf = (wfWithUses "actions/checkout@v4")
                 { wfPermissions = Just (PermissionsMap (Map.fromList [("contents", PermWrite)])) }
          pa = analyzePermissions wf
      assertBool "has excess" (not (Map.null (excessPerms pa)))

  , testCase "analyzePermissions currentPerms matches workflow declaration" $ do
      let perms = Just (PermissionsAll PermRead)
          wf = emptyWorkflow { wfPermissions = perms }
          pa = analyzePermissions wf
      currentPerms pa @?= perms

  , testCase "actionPermissionCatalog contains actions/checkout" $
      assertBool "catalog has actions/checkout"
        (Map.member "actions/checkout" actionPermissionCatalog)

  , testCase "actionPermissionCatalog contains github/codeql-action" $
      assertBool "catalog has github/codeql-action"
        (Map.member "github/codeql-action" actionPermissionCatalog)

  , testCase "permissionsMinimumRule has correct rule id" $
      ruleId permissionsMinimumRule @?= "PERM-003"

  , testCase "permissionsMinimumRule fires on excess permissions" $ do
      let wf = (wfWithUses "actions/checkout@v4")
                 { wfPermissions = Just (PermissionsMap (Map.fromList [("contents", PermWrite)])) }
          findings = ruleCheck permissionsMinimumRule wf
      assertBool "finding produced" (not (null findings))

  , testCase "permissionsMinimumRule does not fire when no perms declared" $ do
      let wf = wfWithUses "actions/checkout@v4"
          findings = ruleCheck permissionsMinimumRule wf
      findings @?= []

  , testCase "PermissionAnalysis Show works" $ do
      let pa = analyzePermissions emptyWorkflow
      assertBool "show non-empty" (not (null (show pa)))
  ]

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

emptyWorkflow :: Workflow
emptyWorkflow = Workflow
  { wfName = "test"
  , wfFileName = "test.yml"
  , wfTriggers = []
  , wfJobs = []
  , wfPermissions = Nothing
  , wfConcurrency = Nothing
  , wfEnv = Map.empty
  }

wfWithUses :: Text -> Workflow
wfWithUses action = emptyWorkflow
  { wfJobs = [job]
  }
  where
    job = Job
      { jobId     = "build"
      , jobName   = Just "Build"
      , jobRunsOn = StandardRunner "ubuntu-latest"
      , jobSteps  = [step]
      , jobPermissions = Nothing
      , jobNeeds  = []
      , jobConcurrency = Nothing
      , jobEnv    = Map.empty
      , jobIf     = Nothing
      , jobTimeoutMin = Nothing
      , jobEnvironment = Nothing
      , jobEnvironmentUrl = False
      , jobFailFast = Nothing
      , jobMatrixIncludeOnly = False
      }
    step = Step
      { stepId    = Nothing
      , stepName  = Just "Step"
      , stepUses  = Just action
      , stepRun   = Nothing
      , stepWith  = Map.empty
      , stepEnv   = Map.empty
      , stepIf    = Nothing
      , stepShell = Nothing
      }
