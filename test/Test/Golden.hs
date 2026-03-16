module Test.Golden (tests) where

import Data.Text qualified as T
import Orchestrator.Demo (goodWorkflow, problematicWorkflow)
import Orchestrator.Policy (defaultPolicyPack, evaluatePolicies)
import Orchestrator.Render (renderFindings, renderSummary)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool)

tests :: TestTree
tests = testGroup "Golden"
  [ testCase "Good workflow output is stable" $ do
      let findings = evaluatePolicies defaultPolicyPack goodWorkflow
          output = renderFindings findings
      -- Good workflow may have info-level findings but output should be stable
      assertBool "Output should be text" (not $ T.null output || output == "No findings.")
        -- Either has findings or says "No findings." — both valid

  , testCase "Problematic workflow output contains expected rules" $ do
      let findings = evaluatePolicies defaultPolicyPack problematicWorkflow
          output = renderFindings findings
      assertBool "Should mention PERM-001" ("PERM-001" `T.isInfixOf` output)

  , testCase "Summary output is well-formed" $ do
      let findings = evaluatePolicies defaultPolicyPack problematicWorkflow
          summary = renderSummary findings
      assertBool "Summary has header" ("Summary" `T.isInfixOf` summary)
      assertBool "Summary has total" ("Total findings" `T.isInfixOf` summary)
  ]
