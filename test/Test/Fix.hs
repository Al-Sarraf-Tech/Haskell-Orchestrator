module Test.Fix (tests) where

import Data.Text qualified as T
import Orchestrator.Fix
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

------------------------------------------------------------------------
-- Sample YAML content
------------------------------------------------------------------------

-- | A minimal workflow with permissions, timeout, no PR trigger
cleanWorkflow :: T.Text
cleanWorkflow = T.unlines
  [ "name: CI"
  , "on:"
  , "  push:"
  , "    branches: [main]"
  , "permissions:"
  , "  contents: read"
  , "jobs:"
  , "  build:"
  , "    runs-on: ubuntu-latest"
  , "    timeout-minutes: 30"
  , "    steps:"
  , "      - run: echo hello"
  ]

-- | Workflow missing permissions block
noPermissionsWorkflow :: T.Text
noPermissionsWorkflow = T.unlines
  [ "name: CI"
  , "on:"
  , "  push:"
  , "    branches: [main]"
  , "jobs:"
  , "  build:"
  , "    runs-on: ubuntu-latest"
  , "    timeout-minutes: 30"
  , "    steps:"
  , "      - run: echo hello"
  ]

-- | Workflow with PR trigger but no concurrency
noConcurrencyWorkflow :: T.Text
noConcurrencyWorkflow = T.unlines
  [ "name: CI"
  , "on:"
  , "  pull_request:"
  , "    branches: [main]"
  , "permissions:"
  , "  contents: read"
  , "jobs:"
  , "  build:"
  , "    runs-on: ubuntu-latest"
  , "    timeout-minutes: 30"
  , "    steps:"
  , "      - run: echo hello"
  ]

-- | Workflow with job missing timeout
noTimeoutWorkflow :: T.Text
noTimeoutWorkflow = T.unlines
  [ "name: CI"
  , "on:"
  , "  push:"
  , "    branches: [main]"
  , "permissions:"
  , "  contents: read"
  , "jobs:"
  , "  build:"
  , "    runs-on: ubuntu-latest"
  , "    steps:"
  , "      - run: echo hello"
  ]

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "Fix"
  [ testAnalyzeFixableClean
  , testAnalyzeFixableMissingPermissions
  , testAnalyzeFixableMissingConcurrency
  , testAnalyzeFixableMissingTimeout
  , testFixActionFields
  , testDefaultFixConfig
  , testApplyFixesDryRun
  , testRenderFixDiffNoFixes
  , testRenderFixDiffWithFixes
  ]

-- | Clean workflow → no fixable issues
testAnalyzeFixableClean :: TestTree
testAnalyzeFixableClean = testCase "analyzeFixable/clean-workflow-no-fixes" $ do
  let fixes = analyzeFixable "test.yml" cleanWorkflow
  fixes @?= []

-- | Missing permissions → one fix for PERM-001
testAnalyzeFixableMissingPermissions :: TestTree
testAnalyzeFixableMissingPermissions = testCase "analyzeFixable/missing-permissions" $ do
  let fixes = analyzeFixable "test.yml" noPermissionsWorkflow
  assertBool "PERM-001 fix present" (any (\fa -> faRuleId fa == "PERM-001") fixes)

-- | PR workflow without concurrency → CONC-001 fix
testAnalyzeFixableMissingConcurrency :: TestTree
testAnalyzeFixableMissingConcurrency = testCase "analyzeFixable/missing-concurrency" $ do
  let fixes = analyzeFixable "test.yml" noConcurrencyWorkflow
  assertBool "CONC-001 fix present" (any (\fa -> faRuleId fa == "CONC-001") fixes)

-- | Job missing timeout → RES-001 fix
testAnalyzeFixableMissingTimeout :: TestTree
testAnalyzeFixableMissingTimeout = testCase "analyzeFixable/missing-timeout" $ do
  let fixes = analyzeFixable "test.yml" noTimeoutWorkflow
  assertBool "RES-001 fix present" (any (\fa -> faRuleId fa == "RES-001") fixes)

-- | FixAction fields are populated
testFixActionFields :: TestTree
testFixActionFields = testCase "FixAction/fields-populated" $ do
  let fixes = analyzeFixable "myfile.yml" noPermissionsWorkflow
      perm  = filter (\fa -> faRuleId fa == "PERM-001") fixes
  assertBool "perm fix found" (not (null perm))
  let fa = head perm
  faFile fa @?= "myfile.yml"
  assertBool "patch non-empty" (not (T.null (faPatch fa)))
  assertBool "description non-empty" (not (T.null (faDescription fa)))

-- | Default fix config: dry-run, 60 min timeout
testDefaultFixConfig :: TestTree
testDefaultFixConfig = testCase "defaultFixConfig/dry-run-60" $ do
  fcWrite defaultFixConfig @?= False
  fcTimeout defaultFixConfig @?= 60

-- | applyFixes dry-run: result has correct structure
testApplyFixesDryRun :: TestTree
testApplyFixesDryRun = testCase "applyFixes/dry-run-structure" $ do
  let fixes   = analyzeFixable "test.yml" noPermissionsWorkflow
      (diff, res) = applyFixes defaultFixConfig "test.yml" noPermissionsWorkflow fixes
  frFile res @?= "test.yml"
  assertBool "applied list non-empty" (not (null (frApplied res)))
  frBackup res @?= Nothing  -- dry-run = no backup
  assertBool "diff non-empty" (not (T.null diff))

-- | renderFixDiff with no fixes
testRenderFixDiffNoFixes :: TestTree
testRenderFixDiffNoFixes = testCase "renderFixDiff/no-fixes-message" $ do
  let txt = renderFixDiff [] cleanWorkflow
  assertBool "no fixes message" ("No fixes" `T.isInfixOf` txt)

-- | renderFixDiff with fixes contains rule IDs
testRenderFixDiffWithFixes :: TestTree
testRenderFixDiffWithFixes = testCase "renderFixDiff/contains-rule-ids" $ do
  let fixes = analyzeFixable "test.yml" noPermissionsWorkflow
      txt   = renderFixDiff fixes noPermissionsWorkflow
  assertBool "contains PERM-001" ("PERM-001" `T.isInfixOf` txt)
  assertBool "contains +++ (diff header)" ("+++" `T.isInfixOf` txt)
