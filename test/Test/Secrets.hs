module Test.Secrets (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Secrets
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

tests :: TestTree
tests = testGroup "Secrets"
  [ testCase "analyzeSecrets empty workflow has no refs" $
      analyzeSecrets emptyWorkflow @?= []

  , testCase "analyzeSecrets detects secret in step run command" $ do
      let wf = wfWithStep (stepWithRun "echo ${{ secrets.MY_TOKEN }}")
          refs = analyzeSecrets wf
      assertBool "found at least one ref" (not (null refs))
      assertBool "ref name is MY_TOKEN"
        (any (\r -> srSecretName r == "MY_TOKEN") refs)

  , testCase "analyzeSecrets detects secret in step env" $ do
      let wf = wfWithStep (stepWithEnv "TOKEN" "${{ secrets.API_KEY }}")
          refs = analyzeSecrets wf
      assertBool "found at least one ref" (not (null refs))
      assertBool "ref name is API_KEY"
        (any (\r -> srSecretName r == "API_KEY") refs)

  , testCase "analyzeSecrets records correct job id" $ do
      let wf = wfWithStep (stepWithRun "echo ${{ secrets.TOKEN }}")
          refs = analyzeSecrets wf
      assertBool "job id is 'build'"
        (all (\r -> srJob r == "build") refs)

  , testCase "analyzeSecrets records context as run" $ do
      let wf = wfWithStep (stepWithRun "echo ${{ secrets.TOKEN }}")
          refs = analyzeSecrets wf
      assertBool "context is run"
        (any (\r -> srContext r == "run") refs)

  , testCase "buildSecretScopes empty refs returns empty" $
      buildSecretScopes [] @?= []

  , testCase "buildSecretScopes aggregates same secret across jobs" $ do
      let refs = [ SecretRef "TOKEN" "ci.yml" "job1" Nothing "run"
                 , SecretRef "TOKEN" "ci.yml" "job2" Nothing "run"
                 ]
          scopes = buildSecretScopes refs
      length scopes @?= 1
      length (ssJobs (head scopes)) @?= 2

  , testCase "buildSecretScopes tracks multiple secrets" $ do
      let refs = [ SecretRef "TOKEN" "ci.yml" "job1" Nothing "run"
                 , SecretRef "DEPLOY_KEY" "ci.yml" "job1" Nothing "env"
                 ]
          scopes = buildSecretScopes refs
      length scopes @?= 2

  , testCase "secretScopeRule has correct rule id" $
      ruleId secretScopeRule @?= "SEC-003"

  , testCase "secretScopeRule does not fire when secret used in <=3 jobs" $ do
      let wf = wfWithStep (stepWithRun "echo ${{ secrets.TOKEN }}")
          findings = ruleCheck secretScopeRule wf
      findings @?= []

  , testCase "SecretRef Eq works" $ do
      let r1 = SecretRef "TOKEN" "ci.yml" "build" Nothing "run"
          r2 = SecretRef "TOKEN" "ci.yml" "build" Nothing "run"
      r1 @?= r2

  , testCase "SecretScope shows ssSecretName" $ do
      let refs = [SecretRef "MY_SECRET" "ci.yml" "build" Nothing "run"]
          scopes = buildSecretScopes refs
      case scopes of
        [s] -> ssSecretName s @?= "MY_SECRET"
        _   -> fail "expected exactly one scope"
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

wfWithStep :: Step -> Workflow
wfWithStep s = emptyWorkflow
  { wfJobs = [job]
  }
  where
    job = Job
      { jobId     = "build"
      , jobName   = Just "Build"
      , jobRunsOn = StandardRunner "ubuntu-latest"
      , jobSteps  = [s]
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

stepWithRun :: Text -> Step
stepWithRun cmd = Step
  { stepId    = Nothing
  , stepName  = Just "Run"
  , stepUses  = Nothing
  , stepRun   = Just cmd
  , stepWith  = Map.empty
  , stepEnv   = Map.empty
  , stepIf    = Nothing
  , stepShell = Nothing
  }

stepWithEnv :: Text -> Text -> Step
stepWithEnv k v = Step
  { stepId    = Nothing
  , stepName  = Just "Run"
  , stepUses  = Nothing
  , stepRun   = Nothing
  , stepWith  = Map.empty
  , stepEnv   = Map.fromList [(k, v)]
  , stepIf    = Nothing
  , stepShell = Nothing
  }
