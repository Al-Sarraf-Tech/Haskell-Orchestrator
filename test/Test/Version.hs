module Test.Version (tests) where

import Data.List (isInfixOf, isPrefixOf)
import Data.Text qualified as T
import Orchestrator.Version
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Version"
    [ testCase "orchestratorVersion contains '4'" $
        assertBool "version contains 4" ("4" `T.isInfixOf` orchestratorVersion),
      testCase "orchestratorVersion is non-empty" $
        assertBool "non-empty" (not (T.null orchestratorVersion)),
      testCase "orchestratorVersion matches semver-like pattern" $ do
        let parts = T.splitOn "." orchestratorVersion
        assertBool "at least two dot-separated parts" (length parts >= 2),
      testCase "orchestratorEdition is Community" $
        orchestratorEdition @?= "Community",
      testCase "orchestratorEdition is non-empty" $
        assertBool "non-empty" (not (T.null orchestratorEdition)),
      testCase "userAgentString contains orchestratorVersion" $
        assertBool
          "user-agent contains version"
          (T.unpack orchestratorVersion `isInfixOf` userAgentString),
      testCase "userAgentString starts with haskell-orchestrator" $
        assertBool
          "starts with haskell-orchestrator"
          ("haskell-orchestrator" `isPrefixOf` userAgentString),
      testCase "userAgentString is non-empty" $
        assertBool "non-empty" (not (null userAgentString))
    ]
