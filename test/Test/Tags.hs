module Test.Tags (tests) where

import Data.Text (Text)
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Tags
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Tags"
    [ testCase "parseRuleTag parses security" $
        parseRuleTag "security" @?= Just TagSecurity,
      testCase "parseRuleTag parses performance" $
        parseRuleTag "performance" @?= Just TagPerformance,
      testCase "parseRuleTag parses cost" $
        parseRuleTag "cost" @?= Just TagCost,
      testCase "parseRuleTag parses style" $
        parseRuleTag "style" @?= Just TagStyle,
      testCase "parseRuleTag parses structure" $
        parseRuleTag "structure" @?= Just TagStructure,
      testCase "parseRuleTag rejects unknown" $
        parseRuleTag "foobar" @?= Nothing,
      testCase "filterByTags with empty list returns all" $ do
        let rules = [mkRule "R1" [TagSecurity], mkRule "R2" [TagStyle]]
        length (filterByTags [] rules) @?= 2,
      testCase "filterByTags keeps matching rules" $ do
        let rules = [mkRule "R1" [TagSecurity], mkRule "R2" [TagStyle]]
            filtered = filterByTags [TagSecurity] rules
        length filtered @?= 1
        ruleId (head filtered) @?= "R1",
      testCase "filterByTags with multiple tags is union" $ do
        let rules =
              [ mkRule "R1" [TagSecurity],
                mkRule "R2" [TagStyle],
                mkRule "R3" [TagPerformance]
              ]
            filtered = filterByTags [TagSecurity, TagStyle] rules
        length filtered @?= 2
        assertBool "Contains R1" (any (\r -> ruleId r == "R1") filtered)
        assertBool "Contains R2" (any (\r -> ruleId r == "R2") filtered)
    ]

-- | Helper: minimal PolicyRule with given ID and tags.
mkRule :: Text -> [RuleTag] -> PolicyRule
mkRule rid tags =
  PolicyRule
    { ruleId = rid,
      ruleName = rid,
      ruleDescription = "test rule",
      ruleSeverity = Info,
      ruleCategory = Structure,
      ruleTags = tags,
      ruleCheck = const []
    }
