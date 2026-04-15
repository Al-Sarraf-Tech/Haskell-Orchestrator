module Test.Errors (tests) where

import Data.Text qualified as T
import Orchestrator.Errors (ErrorContext (..), formatError, suggestFix)
import Orchestrator.Types (OrchestratorError (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Errors"
    [ testCase "suggestFix on ParseError with 'on' returns Just" $ do
        let err = ParseError ".github/workflows/ci.yml" "unexpected key 'on' at line 5"
        assertBool "Should suggest fix for on-trigger" (suggestFix err /= Nothing),
      testCase "suggestFix on ParseError with indentation returns Just" $ do
        let err = ParseError "ci.yml" "unexpected indent at line 10"
        assertBool "Should suggest fix for indent" (suggestFix err /= Nothing),
      testCase "suggestFix on ConfigError with 'severity' returns Just" $ do
        let err = ConfigError "invalid severity value"
        assertBool "Should suggest fix for severity" (suggestFix err /= Nothing),
      testCase "suggestFix on ScanError with 'not found' returns Just" $ do
        let err = ScanError "no workflow files not found in directory"
        assertBool "Should suggest fix for scan not-found" (suggestFix err /= Nothing),
      testCase "suggestFix on IOError' with 'no such file' returns Just" $ do
        let err = IOError' "no such file or directory: /tmp/x.yml"
        assertBool "Should suggest fix for IO not-found" (suggestFix err /= Nothing),
      testCase "suggestFix on unknown error returns Nothing" $ do
        let err = ScanError "an utterly unknown internal condition zyx"
        suggestFix err @?= Nothing,
      testCase "formatError produces multi-line text" $ do
        let err = ParseError ".github/workflows/ci.yml" "missing 'on' key at line 15"
            out = formatError err
        assertBool "Output should be multi-line" (length (T.lines out) > 1),
      testCase "formatError includes file path for ParseError" $ do
        let err = ParseError ".github/workflows/ci.yml" "bad yaml"
            out = formatError err
        assertBool "Output should contain file path" (T.isInfixOf "ci.yml" out),
      testCase "formatError includes line number when extractable" $ do
        let err = ParseError "ci.yml" "parse failure at line 7: unexpected scalar"
            out = formatError err
        assertBool "Output should contain line number" (T.isInfixOf "7" out),
      testCase "ErrorContext errSuggestion accessible" $ do
        let ctx =
              ErrorContext
                { errFile = Just "ci.yml",
                  errLine = Just 3,
                  errMessage = "test message",
                  errSuggestion = Just "do the thing"
                }
        errSuggestion ctx @?= Just "do the thing"
    ]
