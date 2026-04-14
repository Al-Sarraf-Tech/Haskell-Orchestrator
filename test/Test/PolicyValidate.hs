module Test.PolicyValidate (tests) where

import Data.Text qualified as T
import Orchestrator.Config (CustomRuleConfig (..), RuleCondition (..))
import Orchestrator.Policy (PolicyPack (..), PolicyRule (..))
import Orchestrator.Policy.Validate
  ( IssueSeverity (..)
  , ValidationIssue (..)
  , validateCustomRule
  , validatePolicyPack
  , renderValidationIssues
  )
import Orchestrator.Types (Severity (..), FindingCategory (..), RuleTag (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

tests :: TestTree
tests = testGroup "PolicyValidate"
  [ testCase "Valid pack produces no errors" $ do
      let pack = PolicyPack
            { packName = "valid"
            , packRules = [mkRule "OK-001" "Good Rule" Warning Security [TagSecurity]]
            }
          issues = validatePolicyPack pack
          errors = filter (\i -> issueSeverity i == IssueError) issues
      assertBool "No IssueError on valid pack" (null errors)

  , testCase "Empty pack name is IssueError" $ do
      let pack = PolicyPack { packName = "", packRules = [] }
          issues = validatePolicyPack pack
      assertBool "Should find error for empty name"
        (any (\i -> issueSeverity i == IssueError && "name" `T.isInfixOf` issueMessage i) issues)

  , testCase "Duplicate rule IDs produce IssueError" $ do
      let r1 = mkRule "DUP-001" "R1" Warning Security [TagSecurity]
          r2 = mkRule "DUP-001" "R2" Error   Security [TagSecurity]
          pack = PolicyPack { packName = "dp", packRules = [r1, r2] }
          issues = validatePolicyPack pack
          errors = filter (\i -> issueSeverity i == IssueError) issues
      assertBool "Should have IssueError for duplicate IDs" (not (null errors))

  , testCase "Empty ruleId produces IssueError" $ do
      let r = mkRule "" "Some Rule" Warning Security [TagSecurity]
          pack = PolicyPack { packName = "p", packRules = [r] }
          issues = validatePolicyPack pack
          errors = filter (\i -> issueSeverity i == IssueError) issues
      assertBool "Should report error for empty ruleId" (not (null errors))

  , testCase "Empty ruleName produces IssueError" $ do
      let r = mkRule "TST-001" "" Warning Security [TagSecurity]
          pack = PolicyPack { packName = "p", packRules = [r] }
          issues = validatePolicyPack pack
          errors = filter (\i -> issueSeverity i == IssueError) issues
      assertBool "Should report error for empty ruleName" (not (null errors))

  , testCase "Rule with no tags produces IssueWarning" $ do
      let r = mkRule "TST-002" "No Tags" Warning Security []
          pack = PolicyPack { packName = "p", packRules = [r] }
          issues = validatePolicyPack pack
          warnings = filter (\i -> issueSeverity i == IssueWarning) issues
      assertBool "Should warn about missing tags" (not (null warnings))

  -- CustomRuleConfig tests --------------------------------------------------

  , testCase "Valid custom rule produces no issues" $ do
      let crc = validCrc
          issues = validateCustomRule crc
      issues @?= []

  , testCase "Invalid severity produces IssueError" $ do
      let crc = validCrc { crcSeverity = "BADLEVEL" }
          issues = validateCustomRule crc
          errors = filter (\i -> issueSeverity i == IssueError) issues
      assertBool "Should error on invalid severity" (not (null errors))

  , testCase "Empty custom rule ID produces IssueError" $ do
      let crc = validCrc { crcId = "" }
          issues = validateCustomRule crc
          errors = filter (\i -> issueSeverity i == IssueError) issues
      assertBool "Should error on empty ID" (not (null errors))

  , testCase "Lowercase-start ID produces IssueError" $ do
      let crc = validCrc { crcId = "custom-001" }
          issues = validateCustomRule crc
          errors = filter (\i -> issueSeverity i == IssueError) issues
      assertBool "Should error on non-uppercase-start ID" (not (null errors))

  , testCase "Empty name produces IssueError" $ do
      let crc = validCrc { crcName = "" }
          issues = validateCustomRule crc
          errors = filter (\i -> issueSeverity i == IssueError) issues
      assertBool "Should error on empty name" (not (null errors))

  , testCase "No conditions produces IssueError" $ do
      let crc = validCrc { crcConditions = [] }
          issues = validateCustomRule crc
          errors = filter (\i -> issueSeverity i == IssueError) issues
      assertBool "Should error on missing conditions" (not (null errors))

  , testCase "Unknown job field produces IssueWarning" $ do
      let crc = validCrc { crcConditions = [JobMissingField "unknown-field"] }
          issues = validateCustomRule crc
          warnings = filter (\i -> issueSeverity i == IssueWarning) issues
      assertBool "Should warn on unknown job field" (not (null warnings))

  -- Rendering ---------------------------------------------------------------

  , testCase "renderValidationIssues empty returns pass message" $ do
      let rendered = renderValidationIssues []
      assertBool "Should contain 'Validation passed'"
        ("Validation passed" `T.isInfixOf` rendered)

  , testCase "renderValidationIssues non-empty contains issue message" $ do
      let issue = ValidationIssue IssueError "TST-999" "Something went wrong"
          rendered = renderValidationIssues [issue]
      assertBool "Rendered text should contain issue message"
        ("Something went wrong" `T.isInfixOf` rendered)
      assertBool "Rendered text should contain rule ID"
        ("TST-999" `T.isInfixOf` rendered)
  ]

-- Helpers -------------------------------------------------------------------

mkRule :: T.Text -> T.Text -> Severity -> FindingCategory -> [RuleTag] -> PolicyRule
mkRule rid rname sev cat tags = PolicyRule
  { ruleId          = rid
  , ruleName        = rname
  , ruleDescription = if T.null rname then "" else "Description for " <> rname
  , ruleSeverity    = sev
  , ruleCategory    = cat
  , ruleTags        = tags
  , ruleCheck       = const []
  }

validCrc :: CustomRuleConfig
validCrc = CustomRuleConfig
  { crcId         = "CUSTOM-001"
  , crcName       = "My Custom Rule"
  , crcSeverity   = "warning"
  , crcCategory   = "Security"
  , crcConditions = [TriggerContains "push"]
  }
