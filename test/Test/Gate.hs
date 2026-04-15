module Test.Gate (tests) where

import Orchestrator.Gate
import Orchestrator.Types
import System.Exit (ExitCode (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Gate"
    [ testCase "No findings always passes" $
        gateFindings Warning [] @?= ExitSuccess,
      testCase "Findings below threshold pass" $ do
        let findings = [mkGateFinding Info]
        gateFindings Warning findings @?= ExitSuccess,
      testCase "Findings at threshold fail" $ do
        let findings = [mkGateFinding Warning]
        gateFindings Warning findings @?= ExitFailure 1,
      testCase "Findings above threshold fail" $ do
        let findings = [mkGateFinding Error]
        gateFindings Warning findings @?= ExitFailure 1,
      testCase "Mixed findings with one above fails" $ do
        let findings = [mkGateFinding Info, mkGateFinding Warning, mkGateFinding Error]
        gateFindings Error findings @?= ExitFailure 1,
      testCase "Critical threshold only fails on Critical" $ do
        let findings = [mkGateFinding Info, mkGateFinding Warning, mkGateFinding Error]
        gateFindings Critical findings @?= ExitSuccess,
      testCase "parseFailOn parses info" $
        parseFailOn "info" @?= Just Info,
      testCase "parseFailOn parses warning" $
        parseFailOn "warning" @?= Just Warning,
      testCase "parseFailOn parses error" $
        parseFailOn "error" @?= Just Error,
      testCase "parseFailOn parses critical" $
        parseFailOn "critical" @?= Just Critical,
      testCase "parseFailOn rejects invalid" $
        parseFailOn "foobar" @?= Nothing,
      testCase "parseFailOn is case insensitive" $ do
        parseFailOn "WARNING" @?= Just Warning
        parseFailOn "Error" @?= Just Error
        parseFailOn "CRITICAL" @?= Just Critical
    ]

-- | Helper: minimal Finding with given severity.
mkGateFinding :: Severity -> Finding
mkGateFinding sev =
  Finding
    { findingSeverity = sev,
      findingCategory = Security,
      findingRuleId = "TEST-001",
      findingMessage = "test",
      findingFile = "test.yml",
      findingLocation = Nothing,
      findingRemediation = Nothing,
      findingAutoFixable = False,
      findingEffort = Nothing,
      findingLinks = []
    }
