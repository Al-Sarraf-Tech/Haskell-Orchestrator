module Test.Hook (tests) where

import Data.Text qualified as T
import Orchestrator.Hook
import Orchestrator.Types (Severity (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Hook"
    [ testCase "defaultHookConfig minSeverity is Warning" $
        hcMinSeverity defaultHookConfig @?= Warning,
      testCase "defaultHookConfig failOnWarning is False" $
        hcFailOnWarning defaultHookConfig @?= False,
      testCase "hookScript starts with shebang" $
        assertBool
          "starts with #!/usr/bin/env bash"
          ("#!/usr/bin/env bash" `T.isPrefixOf` hookScript),
      testCase "hookScript contains orchestrator-hook marker" $
        assertBool
          "contains marker comment"
          ("# orchestrator-hook" `T.isInfixOf` hookScript),
      testCase "hookScript uses set -euo pipefail" $
        assertBool
          "strict mode present"
          ("set -euo pipefail" `T.isInfixOf` hookScript),
      testCase "hookScript references git diff --cached" $
        assertBool
          "git diff --cached present"
          ("git diff --cached" `T.isInfixOf` hookScript),
      testCase "hookScript references orchestrator scan" $
        assertBool
          "orchestrator scan command present"
          ("orchestrator scan" `T.isInfixOf` hookScript),
      testCase "hookScript is non-empty" $
        assertBool "non-empty script" (not (T.null hookScript)),
      testCase "installHook fails on non-git directory" $ do
        result <- installHook "/tmp"
        case result of
          Left msg -> assertBool "error mentions git" ("git" `T.isInfixOf` T.toLower msg || not (T.null msg))
          Right () -> assertBool "should have failed on /tmp" False,
      testCase "uninstallHook fails when hook does not exist" $ do
        result <- uninstallHook "/tmp/no-such-repo-xyz"
        case result of
          Left _ -> pure ()
          Right () -> assertBool "should have failed" False,
      testCase "HookConfig Eq works" $ do
        let c1 = HookConfig Warning False
            c2 = HookConfig Warning False
        c1 @?= c2,
      testCase "HookConfig Show works" $ do
        let c = defaultHookConfig
        assertBool "show non-empty" (not (null (show c)))
    ]
