module Test.LSP (tests) where

import Data.Text qualified as T
import Orchestrator.LSP
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

tests :: TestTree
tests = testGroup "LSP"
  [ testCase "findingsToDiagnostics empty list returns empty" $
      findingsToDiagnostics [] @?= []

  , testCase "findingsToDiagnostics maps Error severity to DiagError" $ do
      let f = mkFinding Error
          ds = findingsToDiagnostics [f]
      case ds of
        [d] -> diagSeverity d @?= DiagError
        _   -> fail "expected exactly one diagnostic"

  , testCase "findingsToDiagnostics maps Warning severity to DiagWarning" $ do
      let f = mkFinding Warning
          ds = findingsToDiagnostics [f]
      case ds of
        [d] -> diagSeverity d @?= DiagWarning
        _   -> fail "expected exactly one diagnostic"

  , testCase "findingsToDiagnostics maps Info severity to DiagInfo" $ do
      let f = mkFinding Info
          ds = findingsToDiagnostics [f]
      case ds of
        [d] -> diagSeverity d @?= DiagInfo
        _   -> fail "expected exactly one diagnostic"

  , testCase "findingsToDiagnostics maps Critical severity to DiagError" $ do
      let f = mkFinding Critical
          ds = findingsToDiagnostics [f]
      case ds of
        [d] -> diagSeverity d @?= DiagError
        _   -> fail "expected exactly one diagnostic"

  , testCase "findingsToDiagnostics preserves rule id as diagCode" $ do
      let f = mkFinding Warning
          ds = findingsToDiagnostics [f]
      case ds of
        [d] -> diagCode d @?= "TEST-001"
        _   -> fail "expected exactly one diagnostic"

  , testCase "findingsToDiagnostics preserves message" $ do
      let f = mkFinding Info
          ds = findingsToDiagnostics [f]
      case ds of
        [d] -> diagMessage d @?= "test message"
        _   -> fail "expected exactly one diagnostic"

  , testCase "finding with no location gets default range (1,1,1,1)" $ do
      let f = mkFinding Warning
          ds = findingsToDiagnostics [f]
      case ds of
        [d] -> do
          let r = diagRange d
          rangeStartLine r @?= 1
          rangeStartCol  r @?= 1
          rangeEndLine   r @?= 1
          rangeEndCol    r @?= 1
        _ -> fail "expected exactly one diagnostic"

  , testCase "finding with 'line 5' location gets range starting at line 5" $ do
      let f = (mkFinding Warning) { findingLocation = Just "line 5" }
          ds = findingsToDiagnostics [f]
      case ds of
        [d] -> rangeStartLine (diagRange d) @?= 5
        _   -> fail "expected exactly one diagnostic"

  , testCase "finding with unparseable location falls back to line 1" $ do
      let f = (mkFinding Error) { findingLocation = Just "bad location" }
          ds = findingsToDiagnostics [f]
      case ds of
        [d] -> rangeStartLine (diagRange d) @?= 1
        _   -> fail "expected exactly one diagnostic"

  , testCase "DiagSeverity enum covers all values" $ do
      let all' = [minBound .. maxBound] :: [DiagSeverity]
      length all' @?= 4

  , testCase "DiagSeverity Ord: DiagError < DiagWarning is False (Error is 0)" $
      assertBool "DiagError <= DiagWarning" (DiagError <= DiagWarning)

  , testCase "renderDiagnostics empty returns no-diagnostics message" $ do
      let txt = renderDiagnostics []
      assertBool "contains 'No diagnostics'"
        ("No diagnostics" `T.isInfixOf` txt)

  , testCase "renderDiagnostics single diagnostic is non-empty" $ do
      let f = mkFinding Warning
          ds = findingsToDiagnostics [f]
          txt = renderDiagnostics ds
      assertBool "non-empty" (not (T.null txt))
  ]

mkFinding :: Severity -> Finding
mkFinding sev = Finding
  { findingSeverity    = sev
  , findingCategory    = Security
  , findingRuleId      = "TEST-001"
  , findingMessage     = "test message"
  , findingFile        = "test.yml"
  , findingLocation    = Nothing
  , findingRemediation = Nothing
  , findingAutoFixable = False
  , findingEffort      = Nothing
  , findingLinks       = []
  }
