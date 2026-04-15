module Test.UI (tests) where

import Data.Text qualified as T
import Orchestrator.Types
import Orchestrator.UI
import Orchestrator.UI.Server
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "UI"
    [ -- renderDashboardHTML
      testCase "renderDashboardHTML produces valid HTML structure" $ do
        let html = renderDashboardHTML emptyDashboard
        assertBool "starts with DOCTYPE" ("<!DOCTYPE html>" `T.isPrefixOf` html),
      testCase "renderDashboardHTML contains closing html tag" $ do
        let html = renderDashboardHTML emptyDashboard
        assertBool "contains </html>" ("</html>" `T.isInfixOf` html),
      testCase "renderDashboardHTML includes edition text" $ do
        let dd = emptyDashboard {ddEdition = "Community"}
            html = renderDashboardHTML dd
        assertBool "Community in HTML" ("Community" `T.isInfixOf` html),
      testCase "renderDashboardHTML includes version text" $ do
        let dd = emptyDashboard {ddVersion = "4.0.0"}
            html = renderDashboardHTML dd
        assertBool "version in HTML" ("4.0.0" `T.isInfixOf` html),
      testCase "renderDashboardHTML shows empty state when no findings" $ do
        let html = renderDashboardHTML emptyDashboard
        assertBool
          "empty state message present"
          ("No findings" `T.isInfixOf` html),
      testCase "renderDashboardHTML includes findings count" $ do
        let dd = emptyDashboard {ddFindings = [mkFinding Warning]}
            html = renderDashboardHTML dd
        assertBool "findings count 1 present" ("1" `T.isInfixOf` html),
      -- renderAPIJSON
      testCase "renderAPIJSON produces valid JSON object" $ do
        let json = renderAPIJSON emptyDashboard
        assertBool "starts with {" (T.isPrefixOf "{" json)
        assertBool "ends with }" (T.isSuffixOf "}" json),
      testCase "renderAPIJSON contains version field" $ do
        let dd = emptyDashboard {ddVersion = "4.0.0"}
            json = renderAPIJSON dd
        assertBool "version key present" ("\"version\"" `T.isInfixOf` json),
      testCase "renderAPIJSON contains edition field" $ do
        let json = renderAPIJSON emptyDashboard
        assertBool "edition key present" ("\"edition\"" `T.isInfixOf` json),
      testCase "renderAPIJSON totalFindings is 0 for empty" $ do
        let json = renderAPIJSON emptyDashboard
        assertBool "totalFindings 0" ("\"totalFindings\":0" `T.isInfixOf` json),
      testCase "renderAPIJSON summary section present" $ do
        let json = renderAPIJSON emptyDashboard
        assertBool "summary key present" ("\"summary\"" `T.isInfixOf` json),
      -- ServerConfig / parseBindAddrs
      testCase "defaultServerConfig uses port 8420" $ do
        let sc = defaultServerConfig "."
        scPort sc @?= 8420,
      testCase "defaultServerConfig binds to localhost only" $ do
        let sc = defaultServerConfig "."
        scBindAddrs sc @?= [BindLocalhost],
      testCase "parseBindAddrs parses localhost" $ do
        let addrs = parseBindAddrs "localhost"
        addrs @?= [BindLocalhost],
      testCase "parseBindAddrs parses 127.0.0.1 as BindLocalhost" $ do
        let addrs = parseBindAddrs "127.0.0.1"
        addrs @?= [BindLocalhost],
      testCase "parseBindAddrs parses ::1 as BindLocalhost6" $ do
        let addrs = parseBindAddrs "::1"
        addrs @?= [BindLocalhost6],
      testCase "parseBindAddrs parses comma-separated list" $ do
        let addrs = parseBindAddrs "localhost,::1"
        length addrs @?= 2,
      testCase "parseBindAddrs ignores empty segments" $ do
        let addrs = parseBindAddrs ""
        addrs @?= [],
      testCase "parseBindAddrs treats unknown IP as BindSpecific" $ do
        let addrs = parseBindAddrs "10.0.0.1"
        addrs @?= [BindSpecific "10.0.0.1"]
    ]

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

emptyDashboard :: DashboardData
emptyDashboard =
  DashboardData
    { ddFindings = [],
      ddScanResult = Nothing,
      ddRuleCount = 0,
      ddVersion = "4.0.0",
      ddEdition = "Community"
    }

mkFinding :: Severity -> Finding
mkFinding sev =
  Finding
    { findingSeverity = sev,
      findingCategory = Security,
      findingRuleId = "TEST-001",
      findingMessage = "test finding",
      findingFile = "test.yml",
      findingLocation = Nothing,
      findingRemediation = Nothing,
      findingAutoFixable = False,
      findingEffort = Nothing,
      findingLinks = []
    }
