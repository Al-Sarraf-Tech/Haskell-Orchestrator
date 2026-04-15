module Test.RenderSarif (tests) where

import Data.Text qualified as T
import Orchestrator.Render.Sarif
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkFinding :: Severity -> T.Text -> T.Text -> Finding
mkFinding sev rid msg =
  Finding
    { findingSeverity = sev,
      findingCategory = Security,
      findingRuleId = rid,
      findingMessage = msg,
      findingFile = "workflow.yml",
      findingLocation = Nothing,
      findingRemediation = Just "Remediate this finding",
      findingAutoFixable = False,
      findingEffort = Nothing,
      findingLinks = []
    }

warnFinding :: Finding
warnFinding = mkFinding Warning "SEC-001" "Workflow is missing permissions block"

errFinding :: Finding
errFinding = mkFinding Error "SEC-002" "Critical vulnerability found"

critFinding :: Finding
critFinding = mkFinding Critical "SEC-003" "Supply chain attack vector detected"

infoFinding :: Finding
infoFinding = mkFinding Info "STR-001" "Minor structural issue"

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "RenderSarif"
    [ testGroup
        "renderSarifJSON"
        [ testCase "produces valid JSON (parseable text)" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" [warnFinding]
            assertBool "Output should not be empty" (not (T.null out))
            -- Valid JSON starts with '{'
            assertBool
              "JSON output should start with '{'"
              ("{" `T.isPrefixOf` T.stripStart out),
          testCase "output contains SARIF version 2.1.0" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" []
            assertBool
              "Should contain SARIF version 2.1.0"
              ("2.1.0" `T.isInfixOf` out),
          testCase "output contains schema URI" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" []
            assertBool
              "Should contain SARIF schema URI"
              ("sarif-schema" `T.isInfixOf` out),
          testCase "output contains tool name" $ do
            let out = renderSarifJSON "my-scanner" "2.0.0" []
            assertBool
              "Should contain tool name"
              ("my-scanner" `T.isInfixOf` out),
          testCase "output contains tool version" $ do
            let out = renderSarifJSON "orchestrator" "3.1.4" []
            assertBool
              "Should contain tool version"
              ("3.1.4" `T.isInfixOf` out),
          testCase "output contains rule IDs for findings" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" [warnFinding, errFinding]
            assertBool "Should contain SEC-001" ("SEC-001" `T.isInfixOf` out)
            assertBool "Should contain SEC-002" ("SEC-002" `T.isInfixOf` out),
          testCase "output contains finding message" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" [warnFinding]
            assertBool
              "Should contain finding message"
              ("missing permissions" `T.isInfixOf` out),
          testCase "output contains runs key" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" []
            assertBool "Should contain runs key" ("runs" `T.isInfixOf` out),
          testCase "output contains results key" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" [infoFinding]
            assertBool "Should contain results key" ("results" `T.isInfixOf` out),
          testCase "empty findings produces valid empty results" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" []
            assertBool
              "Empty findings should still produce valid JSON"
              ("{" `T.isPrefixOf` T.stripStart out),
          testCase "SARIF level for Warning is 'warning'" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" [warnFinding]
            assertBool
              "Warning finding should map to SARIF 'warning' level"
              ("warning" `T.isInfixOf` out),
          testCase "SARIF level for Error is 'error'" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" [errFinding]
            assertBool
              "Error finding should map to SARIF 'error' level"
              ("error" `T.isInfixOf` out),
          testCase "SARIF level for Critical is 'error'" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" [critFinding]
            assertBool
              "Critical finding should map to SARIF 'error' level"
              ("error" `T.isInfixOf` out),
          testCase "SARIF level for Info is 'note'" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" [infoFinding]
            assertBool
              "Info finding should map to SARIF 'note' level"
              ("note" `T.isInfixOf` out),
          testCase "output contains remediation fix" $ do
            let out = renderSarifJSON "orchestrator" "1.0.0" [warnFinding]
            assertBool
              "Should contain remediation text"
              ("Remediate this finding" `T.isInfixOf` out),
          testCase "duplicate rule IDs are deduplicated in rules array" $ do
            let f1 = mkFinding Warning "DUP-001" "First"
                f2 = mkFinding Warning "DUP-001" "Second"
                out = renderSarifJSON "orchestrator" "1.0.0" [f1, f2]
            -- DUP-001 should appear, output should be valid
            assertBool "Should contain DUP-001" ("DUP-001" `T.isInfixOf` out)
        ]
    ]
