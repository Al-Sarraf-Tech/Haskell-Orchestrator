module Test.RenderUpgrade (tests) where

import Data.Text qualified as T
import Orchestrator.Render.Upgrade
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkFinding :: Severity -> T.Text -> Finding
mkFinding sev rid =
  Finding
    { findingSeverity = sev,
      findingCategory = Security,
      findingRuleId = rid,
      findingMessage = "Test finding",
      findingFile = "workflow.yml",
      findingLocation = Nothing,
      findingRemediation = Nothing,
      findingAutoFixable = False,
      findingEffort = Nothing,
      findingLinks = []
    }

tenFindings :: [Finding]
tenFindings = map (mkFinding Warning . (\n -> "R-" <> T.pack (show n))) [1 :: Int .. 10]

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "RenderUpgrade"
    [ testGroup
        "estimateUpgradeImpact"
        [ testCase "returns Business and Enterprise UpgradeInfo" $ do
            let (biz, ent) = estimateUpgradeImpact []
            uiEdition biz @?= "Business"
            uiEdition ent @?= "Enterprise",
          testCase "Business has 4 additional rules" $ do
            let (biz, _) = estimateUpgradeImpact []
            uiAdditionalRules biz @?= 4,
          testCase "Enterprise has 5 additional rules" $ do
            let (_, ent) = estimateUpgradeImpact []
            uiAdditionalRules ent @?= 5,
          testCase "Business estimated findings at least 1 for empty input" $ do
            let (biz, _) = estimateUpgradeImpact []
            assertBool
              "Business estimated findings >= 1"
              (uiEstimatedFindings biz >= 1),
          testCase "Enterprise estimated findings at least 2 for empty input" $ do
            let (_, ent) = estimateUpgradeImpact []
            assertBool
              "Enterprise estimated findings >= 2"
              (uiEstimatedFindings ent >= 2),
          testCase "Business estimated findings scales with input" $ do
            let (biz, _) = estimateUpgradeImpact tenFindings
            assertBool
              "Business estimate should be at least 1 for 10 findings"
              (uiEstimatedFindings biz >= 1),
          testCase "Business has non-empty capabilities list" $ do
            let (biz, _) = estimateUpgradeImpact []
            assertBool
              "Business should list capabilities"
              (not (null (uiNewCapabilities biz))),
          testCase "Enterprise has non-empty capabilities list" $ do
            let (_, ent) = estimateUpgradeImpact []
            assertBool
              "Enterprise should list capabilities"
              (not (null (uiNewCapabilities ent))),
          testCase "Business capabilities mention batch scanning" $ do
            let (biz, _) = estimateUpgradeImpact []
            assertBool
              "Business capabilities should mention batch scanning"
              (any ("batch" `T.isInfixOf`) (uiNewCapabilities biz)),
          testCase "Enterprise capabilities mention compliance" $ do
            let (_, ent) = estimateUpgradeImpact []
            assertBool
              "Enterprise capabilities should mention compliance"
              (any (\c -> "compliance" `T.isInfixOf` T.toLower c) (uiNewCapabilities ent))
        ],
      testGroup
        "renderUpgradePath"
        [ testCase "output contains Upgrade Path header" $ do
            let out = renderUpgradePath []
            assertBool
              "Should contain 'Upgrade Path'"
              ("Upgrade Path" `T.isInfixOf` out),
          testCase "output contains Community Edition label" $ do
            let out = renderUpgradePath []
            assertBool
              "Should mention Community Edition"
              ("Community Edition" `T.isInfixOf` out),
          testCase "output contains Business Edition section" $ do
            let out = renderUpgradePath []
            assertBool
              "Should contain 'Business Edition'"
              ("Business Edition" `T.isInfixOf` out),
          testCase "output contains Enterprise Edition section" $ do
            let out = renderUpgradePath []
            assertBool
              "Should contain 'Enterprise Edition'"
              ("Enterprise Edition" `T.isInfixOf` out),
          testCase "output shows finding count" $ do
            let out = renderUpgradePath tenFindings
            assertBool
              "Should show finding count"
              ("10" `T.isInfixOf` out),
          testCase "output contains learn more link" $ do
            let out = renderUpgradePath []
            assertBool
              "Should contain learn more URL"
              ("github.com" `T.isInfixOf` out),
          testCase "output contains rule count for Business" $ do
            let out = renderUpgradePath []
            assertBool
              "Should mention +4 additional rules for Business"
              ("+4" `T.isInfixOf` out),
          testCase "output contains rule count for Enterprise" $ do
            let out = renderUpgradePath []
            assertBool
              "Should mention +5 governance policies for Enterprise"
              ("+5" `T.isInfixOf` out)
        ]
    ]
