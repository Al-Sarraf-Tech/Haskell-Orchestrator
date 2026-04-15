module Test.Suppress (tests) where

import Data.Set qualified as Set
import Data.Text (Text)
import Orchestrator.Suppress
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Suppress"
    [ testCase "Single suppression comment parsed" $ do
        let content = "# orchestrator:disable SEC-001\nname: CI"
            result = parseSuppressedRules content
        Set.member "SEC-001" result @?= True
        Set.size result @?= 1,
      testCase "Multiple suppressions" $ do
        let content = "# orchestrator:disable SEC-001\n# orchestrator:disable PERM-002\nname: CI"
            result = parseSuppressedRules content
        Set.size result @?= 2
        Set.member "SEC-001" result @?= True
        Set.member "PERM-002" result @?= True,
      testCase "Ignore non-suppression comments" $ do
        let content = "# This is a regular comment\n# orchestrator:disable SEC-001\n# Another comment"
            result = parseSuppressedRules content
        Set.size result @?= 1
        Set.member "SEC-001" result @?= True,
      testCase "Case insensitive directive" $ do
        let content = "# ORCHESTRATOR:DISABLE SEC-001\n# Orchestrator:Disable PERM-001"
            result = parseSuppressedRules content
        Set.size result @?= 2
        Set.member "SEC-001" result @?= True
        Set.member "PERM-001" result @?= True,
      testCase "Extra whitespace handling" $ do
        let content = "#   orchestrator:disable   SEC-001  \n  #  orchestrator:disable  PERM-002  "
            result = parseSuppressedRules content
        Set.size result @?= 2
        Set.member "SEC-001" result @?= True
        Set.member "PERM-002" result @?= True,
      testCase "No suppressions in clean file" $ do
        let content = "name: CI\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest"
            result = parseSuppressedRules content
        Set.null result @?= True,
      testCase "applySuppression filters matching findings" $ do
        let suppressed = Set.fromList ["SEC-001", "PERM-001"]
            findings =
              [ mkSuppressFinding "SEC-001",
                mkSuppressFinding "PERM-001",
                mkSuppressFinding "RES-001"
              ]
            result = applySuppression suppressed findings
        length result @?= 1
        findingRuleId (head result) @?= "RES-001",
      testCase "applySuppression with empty set returns all" $ do
        let findings = [mkSuppressFinding "SEC-001", mkSuppressFinding "PERM-001"]
            result = applySuppression Set.empty findings
        length result @?= 2
    ]

-- | Helper: minimal Finding with given rule ID.
mkSuppressFinding :: Text -> Finding
mkSuppressFinding rid =
  Finding
    { findingSeverity = Warning,
      findingCategory = Security,
      findingRuleId = rid,
      findingMessage = "test",
      findingFile = "test.yml",
      findingLocation = Nothing,
      findingRemediation = Nothing,
      findingAutoFixable = False,
      findingEffort = Nothing,
      findingLinks = []
    }
