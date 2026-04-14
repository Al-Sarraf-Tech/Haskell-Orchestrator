module Test.PolicyConflicts (tests) where

import Data.Text qualified as T
import Orchestrator.Policy (PolicyPack (..), PolicyRule (..), defaultPolicyPack)
import Orchestrator.Policy.Conflicts
  ( ConflictType (..)
  , RuleConflict (..)
  , detectConflicts
  , renderConflicts
  )
import Orchestrator.Types (Severity (..), FindingCategory (..), RuleTag (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

tests :: TestTree
tests = testGroup "PolicyConflicts"
  [ testCase "No conflicts on empty pack" $ do
      let pack = PolicyPack { packName = "empty", packRules = [] }
          conflicts = detectConflicts pack
      conflicts @?= []

  , testCase "Duplicate rule IDs are Contradictory" $ do
      let r1 = mkRule "DUP-001" "Rule One" Info Security [TagSecurity]
          r2 = mkRule "DUP-001" "Rule Two" Warning Security [TagSecurity]
          pack = PolicyPack { packName = "dup-pack", packRules = [r1, r2] }
          conflicts = detectConflicts pack
      assertBool "Should detect at least one conflict" (not (null conflicts))
      let types = map conflictType conflicts
      assertBool "Duplicate IDs should be Contradictory" (Contradictory `elem` types)

  , testCase "Clean pack with distinct rules returns no duplicate conflicts" $ do
      let conflicts = filter (\c -> conflictType c == Contradictory) (detectConflicts defaultPolicyPack)
      -- defaultPolicyPack has unique IDs; no Contradictory duplicate conflicts expected
      assertBool "No Contradictory conflicts in default pack" (null conflicts)

  , testCase "PERM-001 and PERM-002 detected as Overlapping" $ do
      let conflicts = detectConflicts defaultPolicyPack
          permConflicts = filter (\c -> (ruleA c == "PERM-001" && ruleB c == "PERM-002") ||
                                        (ruleA c == "PERM-002" && ruleB c == "PERM-001")) conflicts
      assertBool "PERM-001/PERM-002 overlap should be detected" (not (null permConflicts))
      let types = map conflictType permConflicts
      assertBool "Should be Overlapping" (Overlapping `elem` types)

  , testCase "renderConflicts empty returns no-conflict message" $ do
      let rendered = renderConflicts []
      assertBool "Should contain 'No rule conflicts'" ("No rule conflicts" `T.isInfixOf` rendered)

  , testCase "renderConflicts non-empty contains rule IDs" $ do
      let r1 = mkRule "DUP-999" "R1" Warning Security [TagSecurity]
          r2 = mkRule "DUP-999" "R2" Error Security [TagSecurity]
          pack = PolicyPack { packName = "p", packRules = [r1, r2] }
          conflicts = detectConflicts pack
          rendered = renderConflicts conflicts
      assertBool "Rendered text should contain the conflicting rule ID"
        ("DUP-999" `T.isInfixOf` rendered)

  , testCase "Redundant same-category same-severity same-tag rules detected" $ do
      let r1 = mkRule "PERF-X" "Perf One" Warning Performance [TagPerformance]
          r2 = mkRule "PERF-Y" "Perf Two" Warning Performance [TagPerformance]
          pack = PolicyPack { packName = "perf-pack", packRules = [r1, r2] }
          conflicts = detectConflicts pack
      assertBool "Should detect Redundant conflict" (any (\c -> conflictType c == Redundant) conflicts)
  ]

-- | Minimal PolicyRule builder for tests (no real check function needed).
mkRule :: T.Text -> T.Text -> Severity -> FindingCategory -> [RuleTag] -> PolicyRule
mkRule rid rname sev cat tags = PolicyRule
  { ruleId          = rid
  , ruleName        = rname
  , ruleDescription = "Test rule " <> rname
  , ruleSeverity    = sev
  , ruleCategory    = cat
  , ruleTags        = tags
  , ruleCheck       = const []
  }
