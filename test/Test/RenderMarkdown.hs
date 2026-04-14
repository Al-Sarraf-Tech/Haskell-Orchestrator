module Test.RenderMarkdown (tests) where

import Data.Text qualified as T
import Orchestrator.Render.Markdown
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool)

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkFinding :: Severity -> FindingCategory -> T.Text -> T.Text -> Finding
mkFinding sev cat rid msg = Finding
  { findingSeverity    = sev
  , findingCategory    = cat
  , findingRuleId      = rid
  , findingMessage     = msg
  , findingFile        = "test.yml"
  , findingLocation    = Nothing
  , findingRemediation = Just "Fix it"
  , findingAutoFixable = False
  , findingEffort      = Nothing
  , findingLinks       = []
  }

warnFinding :: Finding
warnFinding = mkFinding Warning Security "SEC-001" "Missing token permissions"

errFinding :: Finding
errFinding = mkFinding Error Security "SEC-002" "Critical secret exposed"

infoFinding :: Finding
infoFinding = mkFinding Info Structure "STR-001" "Naming issue"

mkPlan :: Plan
mkPlan = Plan
  { planTarget  = LocalPath "."
  , planSteps   =
      [ RemediationStep 1 "Add permissions block" "workflow.yml" (Just "- permissions: read-all\n+ permissions: {}")
      , RemediationStep 2 "Pin action to SHA" "workflow.yml" Nothing
      ]
  , planSummary = "2 remediation steps required"
  }

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "RenderMarkdown"
  [ testGroup "renderMarkdownFindings"
      [ testCase "empty findings produces no-findings message" $ do
          let out = renderMarkdownFindings []
          assertBool "Empty findings should produce '_No findings._'"
            ("_No findings._" `T.isInfixOf` out)

      , testCase "output contains table header pipes" $ do
          let out = renderMarkdownFindings [warnFinding]
          assertBool "Should contain pipe character for table"
            (T.isInfixOf "|" out)

      , testCase "output contains severity separator row" $ do
          let out = renderMarkdownFindings [warnFinding]
          assertBool "Should contain markdown table separator dashes"
            ("---" `T.isInfixOf` out)

      , testCase "output contains rule ID" $ do
          let out = renderMarkdownFindings [warnFinding]
          assertBool "Should contain rule ID SEC-001"
            ("SEC-001" `T.isInfixOf` out)

      , testCase "output contains severity label" $ do
          let out = renderMarkdownFindings [warnFinding]
          assertBool "Should contain Warning severity"
            ("Warning" `T.isInfixOf` out)

      , testCase "output contains file name" $ do
          let out = renderMarkdownFindings [warnFinding]
          assertBool "Should contain file name"
            ("test.yml" `T.isInfixOf` out)

      , testCase "multiple findings all appear in output" $ do
          let out = renderMarkdownFindings [warnFinding, errFinding, infoFinding]
          assertBool "Should contain SEC-001" ("SEC-001" `T.isInfixOf` out)
          assertBool "Should contain SEC-002" ("SEC-002" `T.isInfixOf` out)
          assertBool "Should contain STR-001" ("STR-001" `T.isInfixOf` out)
      ]

  , testGroup "renderMarkdownSummary"
      [ testCase "empty findings produces no-summary message" $ do
          let out = renderMarkdownSummary []
          assertBool "Empty findings should produce no-summary message"
            ("_No findings to summarize._" `T.isInfixOf` out)

      , testCase "output contains Scan Summary header" $ do
          let out = renderMarkdownSummary [warnFinding]
          assertBool "Should contain '## Scan Summary'"
            ("## Scan Summary" `T.isInfixOf` out)

      , testCase "output contains total count" $ do
          let out = renderMarkdownSummary [warnFinding, errFinding, infoFinding]
          assertBool "Should contain count 3" ("3" `T.isInfixOf` out)

      , testCase "output contains By Category section" $ do
          let out = renderMarkdownSummary [warnFinding]
          assertBool "Should contain By Category header"
            ("By Category" `T.isInfixOf` out)

      , testCase "output contains table separators" $ do
          let out = renderMarkdownSummary [warnFinding]
          assertBool "Should contain pipe separators" ("|" `T.isInfixOf` out)
      ]

  , testGroup "renderMarkdownPlan"
      [ testCase "output contains Remediation Plan header" $ do
          let out = renderMarkdownPlan mkPlan
          assertBool "Should contain '## Remediation Plan'"
            ("## Remediation Plan" `T.isInfixOf` out)

      , testCase "output contains plan summary" $ do
          let out = renderMarkdownPlan mkPlan
          assertBool "Should contain plan summary"
            ("2 remediation steps required" `T.isInfixOf` out)

      , testCase "output contains step file reference" $ do
          let out = renderMarkdownPlan mkPlan
          assertBool "Should contain step file"
            ("workflow.yml" `T.isInfixOf` out)

      , testCase "output contains diff block for step with diff" $ do
          let out = renderMarkdownPlan mkPlan
          assertBool "Should contain diff code block"
            ("```diff" `T.isInfixOf` out)

      , testCase "output contains step numbers" $ do
          let out = renderMarkdownPlan mkPlan
          assertBool "Should contain step number 1" ("Step 1" `T.isInfixOf` out)
          assertBool "Should contain step number 2" ("Step 2" `T.isInfixOf` out)

      , testCase "step without diff has no code block" $ do
          let plan = Plan (LocalPath ".") [RemediationStep 1 "Do something" "foo.yml" Nothing] "1 step"
              out = renderMarkdownPlan plan
          assertBool "Step without diff should not have diff block"
            (not ("```diff" `T.isInfixOf` out))
      ]
  ]
