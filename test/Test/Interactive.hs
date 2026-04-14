module Test.Interactive (tests) where

import Data.Text qualified as T
import Orchestrator.Interactive (renderRuleMenu)
import Orchestrator.Policy (defaultPolicyPack, PolicyPack (..), PolicyRule (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

tests :: TestTree
tests = testGroup "Interactive"
  [ testCase "renderRuleMenu contains all rule IDs" $ do
      let pack = defaultPolicyPack
          menu = renderRuleMenu pack
          rules = packRules pack
      mapM_ (\r -> assertBool
                ("Menu should contain rule ID: " <> T.unpack (ruleId r))
                (T.isInfixOf (ruleId r) menu)
              ) rules

  , testCase "renderRuleMenu produces numbered lines" $ do
      let pack = defaultPolicyPack
          menu = renderRuleMenu pack
          ls   = T.lines menu
          -- Skip header line; check that we have at least as many lines as rules
          numRules = length (packRules pack)
      assertBool "Should have header plus rule lines" (length ls > numRules)

  , testCase "renderRuleMenu first data line contains '1.'" $ do
      let menu = renderRuleMenu defaultPolicyPack
          ls   = filter (T.isInfixOf "1.") (T.lines menu)
      assertBool "Should have a line with '1.'" (not (null ls))

  , testCase "renderRuleMenu line count matches rules + header" $ do
      let pack = defaultPolicyPack
          menu = renderRuleMenu pack
          -- T.unlines adds a trailing newline, so last split element may be empty
          nonEmpty = filter (not . T.null) (T.lines menu)
          -- header + one line per rule
          expected = 1 + length (packRules pack)
      length nonEmpty @?= expected
  ]
