module Test.Diff (tests) where

import Data.Text qualified as T
import Orchestrator.Diff
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "Diff"
  [ testCase "Empty findings produce empty plan" $ do
      let plan = generatePlan (LocalPath "/test") []
      length (planSteps plan) @?= 0

  , testCase "Findings produce steps" $ do
      let findings =
            [ Finding Warning Permissions "PERM-001" "test" "f.yml" Nothing (Just "fix it") False Nothing []
            , Finding Error Security "SEC-001" "bad" "f.yml" Nothing Nothing False Nothing []
            ]
          plan = generatePlan (LocalPath "/test") findings
      length (planSteps plan) @?= 2

  , testCase "Info findings excluded from plan" $ do
      let findings =
            [ Finding Info Naming "NAME-001" "info only" "f.yml" Nothing Nothing False Nothing [] ]
          plan = generatePlan (LocalPath "/test") findings
      length (planSteps plan) @?= 0

  , testCase "Plan renders as text" $ do
      let plan = Plan (LocalPath "/test") [] "No steps"
          txt = renderPlanText plan
      assertBool "Contains header" ("Remediation Plan" `T.isInfixOf` txt)
      assertBool "Contains target" ("/test" `T.isInfixOf` txt)
  ]
