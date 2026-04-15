module Test.Demo (tests) where

import Orchestrator.Demo
import Orchestrator.Model (wfFileName)
import Orchestrator.Policy (defaultPolicyPack, evaluatePolicies)
import Orchestrator.Types (Severity (..), findingSeverity)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Demo"
    [ testCase "Demo workflows are well-formed" $ do
        let wfs = demoWorkflows
        length wfs @?= 3,
      testCase "Good workflow has minimal findings" $ do
        let findings = evaluatePolicies defaultPolicyPack goodWorkflow
            errors = filter (\f -> findingSeverity f >= Error) findings
        assertBool "Good workflow should have no errors" (null errors),
      testCase "Problematic workflow has findings" $ do
        let findings = evaluatePolicies defaultPolicyPack problematicWorkflow
        assertBool "Should have findings" (not $ null findings),
      testCase "Insecure workflow has error findings" $ do
        let findings = evaluatePolicies defaultPolicyPack insecureWorkflow
            errors = filter (\f -> findingSeverity f >= Error) findings
        assertBool "Should have error-level findings" (not $ null errors),
      testCase "Demo workflows have valid filenames" $ do
        mapM_
          (\wf -> assertBool "Filename should not be empty" (not $ null $ wfFileName wf))
          demoWorkflows
    ]
