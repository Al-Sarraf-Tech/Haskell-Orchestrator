-- | Custom rule schema validation and policy pack structural validation.
module Orchestrator.Policy.Validate
  ( ValidationIssue (..)
  , IssueSeverity (..)
  , validatePolicyPack
  , validateCustomRule
  , renderValidationIssues
  ) where

import Data.Char (isAlphaNum, isUpper)
import Data.List (group, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Config (CustomRuleConfig (..), RuleCondition (..))
import Orchestrator.Policy (PolicyPack (..), PolicyRule (..))
import Orchestrator.Policy.Conflicts (detectConflicts, conflictType, ruleA, ruleB, description, ConflictType (..))

-- | Severity of a validation issue (distinct from rule finding Severity).
data IssueSeverity
  = IssueError    -- ^ Must be fixed; pack/rule is invalid
  | IssueWarning  -- ^ Should be investigated; may cause surprising behaviour
  | IssueInfo     -- ^ Informational; does not block usage
  deriving stock (Eq, Ord, Show, Read)

-- | A single issue found during validation.
data ValidationIssue = ValidationIssue
  { issueSeverity :: !IssueSeverity
  , issueRuleId   :: !Text   -- ^ Rule ID the issue applies to, or pack name
  , issueMessage  :: !Text
  } deriving stock (Eq, Show)

------------------------------------------------------------------------
-- PolicyPack validation
------------------------------------------------------------------------

-- | Validate a PolicyPack for structural correctness.
-- Returns a (possibly empty) list of issues ordered by severity.
validatePolicyPack :: PolicyPack -> [ValidationIssue]
validatePolicyPack pack =
     checkPackName pack
  ++ checkDuplicateRuleIds pack
  ++ checkRuleFields pack
  ++ checkRuleTags pack
  ++ conflictsAsWarnings pack

-- | Pack name must be non-empty.
checkPackName :: PolicyPack -> [ValidationIssue]
checkPackName pack
  | T.null (T.strip (packName pack)) =
      [ ValidationIssue IssueError "<pack>" "Policy pack name is empty." ]
  | otherwise = []

-- | No two rules in the pack may share an ID.
checkDuplicateRuleIds :: PolicyPack -> [ValidationIssue]
checkDuplicateRuleIds pack =
  [ ValidationIssue IssueError rid ("Duplicate rule ID \"" <> rid <> "\" in pack \"" <> packName pack <> "\".")
  | rid <- duplicates (map ruleId (packRules pack))
  ]
  where
    duplicates xs = map head . filter ((> 1) . length) . group . sort $ xs

-- | Each rule must have non-empty ID, name, and description.
checkRuleFields :: PolicyPack -> [ValidationIssue]
checkRuleFields pack = concatMap checkOne (packRules pack)
  where
    checkOne r = emptyCheck r "ruleId" (ruleId r)
              ++ emptyCheck r "ruleName" (ruleName r)
              ++ emptyCheck r "ruleDescription" (ruleDescription r)

    emptyCheck r field val
      | T.null (T.strip val) =
          [ ValidationIssue IssueError (ruleId r)
              ("Rule \"" <> ruleId r <> "\" has empty " <> field <> ".")
          ]
      | otherwise = []

-- | Each rule should have at least one tag.
checkRuleTags :: PolicyPack -> [ValidationIssue]
checkRuleTags pack =
  [ ValidationIssue IssueWarning (ruleId r)
      ("Rule \"" <> ruleId r <> "\" has no tags. Tags improve discoverability.")
  | r <- packRules pack
  , null (ruleTags r)
  ]

-- | Emit detected conflicts as IssueWarning entries.
conflictsAsWarnings :: PolicyPack -> [ValidationIssue]
conflictsAsWarnings pack =
  [ ValidationIssue sev (ruleA c <> "/" <> ruleB c) (description c)
  | c <- detectConflicts pack
  , let sev = case conflictType c of
                Contradictory -> IssueError
                Redundant     -> IssueWarning
                Overlapping   -> IssueInfo
  ]

------------------------------------------------------------------------
-- CustomRuleConfig validation
------------------------------------------------------------------------

-- | Validate a single CustomRuleConfig.
validateCustomRule :: CustomRuleConfig -> [ValidationIssue]
validateCustomRule crc =
     checkId crc
  ++ checkDescription crc
  ++ checkSeverity crc
  ++ checkConditions crc

-- | Rule ID must be non-empty and follow UPPER-LETTERS-DIGITS pattern.
-- Community convention: "CUSTOM-NNN" where NNN is digits, but we accept
-- any non-empty identifier containing only alphanumeric chars and hyphens.
checkId :: CustomRuleConfig -> [ValidationIssue]
checkId crc
  | T.null (T.strip (crcId crc)) =
      [ ValidationIssue IssueError "<custom>" "Custom rule ID is empty." ]
  | not (validIdPattern (crcId crc)) =
      [ ValidationIssue IssueError (crcId crc)
          ("Rule ID \"" <> crcId crc <>
           "\" does not match expected pattern (letters, digits, hyphens; \
           \must start with an uppercase letter).")
      ]
  | otherwise = []
  where
    validIdPattern t =
      not (T.null t) &&
      isUpper (T.head t) &&
      T.all (\c -> isAlphaNum c || c == '-') t

-- | Description (name) must be non-empty.
checkDescription :: CustomRuleConfig -> [ValidationIssue]
checkDescription crc
  | T.null (T.strip (crcName crc)) =
      [ ValidationIssue IssueError (crcId crc)
          ("Custom rule \"" <> crcId crc <> "\" has empty name/description.")
      ]
  | otherwise = []

-- | Severity must be one of the four known values.
checkSeverity :: CustomRuleConfig -> [ValidationIssue]
checkSeverity crc
  | T.toLower (crcSeverity crc) `notElem` validSeverities =
      [ ValidationIssue IssueError (crcId crc)
          ("Custom rule \"" <> crcId crc <> "\" has invalid severity \"" <> crcSeverity crc <>
           "\". Valid values: info, warning, error, critical.")
      ]
  | otherwise = []
  where
    validSeverities = ["info", "warning", "error", "critical"]

-- | Rule must have at least one condition, and each condition must reference a valid field.
checkConditions :: CustomRuleConfig -> [ValidationIssue]
checkConditions crc
  | null (crcConditions crc) =
      [ ValidationIssue IssueError (crcId crc)
          ("Custom rule \"" <> crcId crc <> "\" has no conditions defined.")
      ]
  | otherwise = concatMap (validateConditionField (crcId crc)) (crcConditions crc)

validateConditionField :: Text -> RuleCondition -> [ValidationIssue]
validateConditionField rid cond = case cond of
  PermissionContains val
    | T.null (T.strip val) ->
        [ ValidationIssue IssueWarning rid
            "Condition 'permission_contains' has an empty value; it will never match." ]
  JobMissingField field
    | T.toLower field `notElem` knownJobFields ->
        [ ValidationIssue IssueWarning rid
            ("Condition 'job_missing_field' references unknown field \"" <> field <>
             "\". Currently supported: " <> T.intercalate ", " knownJobFields <> ".")
        ]
  WorkflowNamePattern pat
    | T.null (T.strip pat) ->
        [ ValidationIssue IssueWarning rid
            "Condition 'workflow_name_pattern' has an empty pattern; it will match only empty names." ]
  StepUsesPattern pat
    | T.null (T.strip pat) ->
        [ ValidationIssue IssueWarning rid
            "Condition 'step_uses_pattern' has an empty pattern; it will match all steps." ]
  TriggerContains val
    | T.null (T.strip val) ->
        [ ValidationIssue IssueWarning rid
            "Condition 'trigger_contains' has an empty value; it will never match." ]
  EnvKeyPresent key
    | T.null (T.strip key) ->
        [ ValidationIssue IssueWarning rid
            "Condition 'env_key_present' has an empty key name." ]
  RunnerMatches val
    | T.null (T.strip val) ->
        [ ValidationIssue IssueWarning rid
            "Condition 'runner_matches' has an empty value; it will match all runners." ]
  _ -> []

knownJobFields :: [Text]
knownJobFields = ["timeout-minutes"]

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

-- | Render a list of ValidationIssues as human-readable text.
renderValidationIssues :: [ValidationIssue] -> Text
renderValidationIssues [] = "Validation passed — no issues found.\n"
renderValidationIssues issues =
  T.unlines $
    [ "Validation Report"
    , "================="
    , T.pack (show (length issues)) <> " issue(s):"
    , ""
    ] ++
    concatMap renderOne (zip [(1 :: Int) ..] issues)
  where
    renderOne (n, issue) =
      [ T.pack (show n) <> ". [" <> renderSev (issueSeverity issue) <> "] "
        <> "[" <> issueRuleId issue <> "] "
        <> issueMessage issue
      ]

    renderSev IssueError   = "ERROR"
    renderSev IssueWarning = "WARNING"
    renderSev IssueInfo    = "INFO"
