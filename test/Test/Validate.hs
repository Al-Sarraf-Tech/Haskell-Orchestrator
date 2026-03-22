module Test.Validate (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Orchestrator.Model
import Orchestrator.Types
import Orchestrator.Validate
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "Validate"
  [ testCase "Valid workflow passes" $ do
      let vr = validateWorkflow goodWf
      vrValid vr @?= True

  , testCase "Empty jobs detected" $ do
      let vr = validateWorkflow (goodWf { wfJobs = [] })
      vrValid vr @?= False
      assertBool "Should have VAL-001" $
        any (\f -> findingRuleId f == "VAL-001") (vrFindings vr)

  , testCase "Duplicate job IDs detected" $ do
      let j = mkJob "build"
          vr = validateWorkflow (goodWf { wfJobs = [j, j] })
      assertBool "Should have VAL-002" $
        any (\f -> findingRuleId f == "VAL-002") (vrFindings vr)

  , testCase "Dangling needs detected" $ do
      let j = (mkJob "deploy") { jobNeeds = ["nonexistent"] }
          vr = validateWorkflow (goodWf { wfJobs = [mkJob "build", j] })
      assertBool "Should have VAL-003" $
        any (\f -> findingRuleId f == "VAL-003") (vrFindings vr)

  , testCase "Empty steps warned" $ do
      let j = (mkJob "empty") { jobSteps = [] }
          vr = validateWorkflow (goodWf { wfJobs = [j] })
      assertBool "Should have VAL-004" $
        any (\f -> findingRuleId f == "VAL-004") (vrFindings vr)

  , testCase "validateWorkflows processes multiple" $ do
      let results = validateWorkflows [goodWf, goodWf { wfJobs = [] }]
      length results @?= 2
  ]

goodWf :: Workflow
goodWf = Workflow
  { wfName = "CI"
  , wfFileName = "ci.yml"
  , wfTriggers = [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  , wfJobs = [mkJob "build"]
  , wfPermissions = Nothing
  , wfConcurrency = Nothing
  , wfEnv = Map.empty
  }

mkJob :: Text -> Job
mkJob jid = Job jid (Just "Test") (StandardRunner "ubuntu-latest")
  [Step Nothing (Just "Run") Nothing (Just "echo ok") Map.empty Map.empty Nothing]
  Nothing [] Nothing Map.empty Nothing Nothing Nothing Nothing False
