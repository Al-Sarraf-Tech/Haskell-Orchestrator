-- | Policy engine for evaluating workflows against configurable rules.
--
-- Provides a set of built-in rules for common GitHub Actions best practices
-- and security hygiene.  Rules produce typed findings with severity levels
-- and remediation suggestions.
module Orchestrator.Policy
  ( -- * Types
    PolicyRule (..)
  , PolicyPack (..)
    -- * Evaluation
  , evaluatePolicy
  , evaluatePolicies
    -- * Filtering
  , filterBySeverity
  , groupByCategory
    -- * Built-in packs
  , defaultPolicyPack
    -- * Custom rules
  , customRuleToPolicy
  , parseSeverity
  , parseCategory
    -- * Individual rules
  , permissionsRequiredRule
  , broadPermissionsRule
  , selfHostedRunnerRule
  , missingConcurrencyRule
  , unpinnedActionRule
  , missingTimeoutRule
  , workflowNamingRule
  , jobNamingRule
  , triggerWildcardRule
  , secretInRunRule
  ) where

import Data.Char (isDigit, isLower)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Config (CustomRuleConfig (..), RuleCondition (..))
import Orchestrator.Model
import Orchestrator.Types

-- | A single policy rule with an embedded check function.
data PolicyRule = PolicyRule
  { ruleId          :: !Text
  , ruleName        :: !Text
  , ruleDescription :: !Text
  , ruleSeverity    :: !Severity
  , ruleCategory    :: !FindingCategory
  , ruleCheck       :: Workflow -> [Finding]
  }

-- | A named collection of policy rules.
data PolicyPack = PolicyPack
  { packName  :: !Text
  , packRules :: ![PolicyRule]
  }

-- | Evaluate a single policy rule against a workflow.
evaluatePolicy :: PolicyRule -> Workflow -> [Finding]
evaluatePolicy rule wf = ruleCheck rule wf

-- | Evaluate all rules in a pack against a workflow.
evaluatePolicies :: PolicyPack -> Workflow -> [Finding]
evaluatePolicies pack wf = concatMap (`evaluatePolicy` wf) (packRules pack)

-- | Filter findings by minimum severity.
filterBySeverity :: Severity -> [Finding] -> [Finding]
filterBySeverity minSev = filter (\f -> findingSeverity f >= minSev)

-- | Group findings by category.
groupByCategory :: [Finding] -> Map.Map FindingCategory [Finding]
groupByCategory = foldl (\m f -> Map.insertWith (++) (findingCategory f) [f] m) Map.empty

------------------------------------------------------------------------
-- Custom rule support
------------------------------------------------------------------------

-- | Convert a custom rule configuration to a PolicyRule.
customRuleToPolicy :: CustomRuleConfig -> PolicyRule
customRuleToPolicy crc = PolicyRule
  { ruleId          = crcId crc
  , ruleName        = crcName crc
  , ruleDescription = "Custom rule: " <> crcName crc
  , ruleSeverity    = parseSeverity (crcSeverity crc)
  , ruleCategory    = parseCategory (crcCategory crc)
  , ruleCheck       = \wf ->
      if all (checkCondition wf) (crcConditions crc)
        then [Finding
          { findingSeverity    = parseSeverity (crcSeverity crc)
          , findingCategory    = parseCategory (crcCategory crc)
          , findingRuleId      = crcId crc
          , findingMessage     = crcName crc
          , findingFile        = wfFileName wf
          , findingLocation    = Nothing
          , findingRemediation = Just ("Address custom rule: " <> crcName crc)
          , findingAutoFixable = False
          , findingEffort      = Nothing
          , findingLinks       = []
          }]
        else []
  }

-- | Evaluate a single condition against a workflow.
checkCondition :: Workflow -> RuleCondition -> Bool
checkCondition wf cond = case cond of
  PermissionContains txt ->
    case wfPermissions wf of
      Just (PermissionsAll PermWrite) -> T.toCaseFold "write" == T.toCaseFold txt
      Just (PermissionsMap m) -> any (\k -> T.toCaseFold txt `T.isInfixOf` T.toCaseFold k) (Map.keys m)
      _ -> False
  ActionNotPinned ->
    any hasUnpinnedAction (concatMap jobSteps (wfJobs wf))
  JobMissingField field ->
    case T.toLower field of
      "timeout-minutes" -> any (\j -> jobTimeoutMin j == Nothing) (wfJobs wf)
      _ -> False
  WorkflowNamePattern pat ->
    simplePatternMatch pat (wfName wf)
  StepUsesPattern pat ->
    any (\s -> maybe False (simplePatternMatch pat) (stepUses s))
        (concatMap jobSteps (wfJobs wf))
  TriggerContains evtName ->
    any (triggerHasEvent evtName) (wfTriggers wf)
  EnvKeyPresent key ->
    Map.member key (wfEnv wf) ||
    any (\j -> Map.member key (jobEnv j)) (wfJobs wf)
  RunnerMatches txt ->
    any (\j -> txt `T.isInfixOf` showRunner (jobRunsOn j)) (wfJobs wf)

hasUnpinnedAction :: Step -> Bool
hasUnpinnedAction step = case stepUses step of
  Nothing -> False
  Just uses
    | "./" `T.isPrefixOf` uses -> False
    | "docker://" `T.isPrefixOf` uses -> False
    | "@" `T.isInfixOf` uses ->
        let ref = T.drop 1 $ T.dropWhile (/= '@') uses
        in T.length ref /= 40 || not (T.all isHexDigit ref)
    | otherwise -> True
  where
    isHexDigit c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')

simplePatternMatch :: Text -> Text -> Bool
simplePatternMatch pat txt
  | T.null pat = T.null txt
  | T.isSuffixOf "*" pat = T.dropEnd 1 pat `T.isPrefixOf` txt
  | T.isPrefixOf "*" pat = T.drop 1 pat `T.isSuffixOf` txt
  | otherwise = pat == txt

triggerHasEvent :: Text -> WorkflowTrigger -> Bool
triggerHasEvent evtName (TriggerEvents evts) = any (\e -> triggerName e == evtName) evts
triggerHasEvent _ (TriggerCron _) = False
triggerHasEvent evtName TriggerDispatch = evtName == "workflow_dispatch"

showRunner :: RunnerSpec -> Text
showRunner (StandardRunner t) = t
showRunner (MatrixRunner t) = t
showRunner (CustomLabel t) = t

-- | Parse a severity string to a Severity value.
parseSeverity :: Text -> Severity
parseSeverity t = case T.toLower t of
  "info"     -> Info
  "warning"  -> Warning
  "error"    -> Error
  "critical" -> Critical
  _          -> Warning

-- | Parse a category string to a FindingCategory value.
parseCategory :: Text -> FindingCategory
parseCategory t = case T.toLower t of
  "permissions"  -> Permissions
  "runners"      -> Runners
  "triggers"     -> Triggers
  "naming"       -> Naming
  "concurrency"  -> Concurrency
  "security"     -> Security
  "structure"    -> Structure
  "duplication"  -> Duplication
  "drift"        -> Drift
  _              -> Structure

-- | The default community policy pack.
defaultPolicyPack :: PolicyPack
defaultPolicyPack = PolicyPack
  { packName = "standard"
  , packRules =
      [ permissionsRequiredRule
      , broadPermissionsRule
      , selfHostedRunnerRule
      , missingConcurrencyRule
      , unpinnedActionRule
      , missingTimeoutRule
      , workflowNamingRule
      , jobNamingRule
      , triggerWildcardRule
      , secretInRunRule
      ]
  }

------------------------------------------------------------------------
-- Helper
------------------------------------------------------------------------

mkFinding :: Severity -> FindingCategory -> Text -> Text -> FilePath -> Maybe Text -> Finding
mkFinding sev cat rid msg fp rem' = Finding
  { findingSeverity = sev
  , findingCategory = cat
  , findingRuleId = rid
  , findingMessage = msg
  , findingFile = fp
  , findingLocation = Nothing
  , findingRemediation = rem'
  , findingAutoFixable = False
  , findingEffort = Nothing
  , findingLinks = []
  }

------------------------------------------------------------------------
-- Rules
------------------------------------------------------------------------

permissionsRequiredRule :: PolicyRule
permissionsRequiredRule = PolicyRule
  { ruleId = "PERM-001"
  , ruleName = "Permissions Required"
  , ruleDescription = "Workflows should declare explicit permissions"
  , ruleSeverity = Warning
  , ruleCategory = Permissions
  , ruleCheck = \wf ->
      case wfPermissions wf of
        Nothing ->
          [ mkFinding Warning Permissions "PERM-001"
              "Workflow does not declare a top-level permissions block. \
              \Without explicit permissions, the workflow runs with default \
              \token permissions which may be overly broad."
              (wfFileName wf)
              (Just "Add a 'permissions:' block to restrict token scope.")
          ]
        Just _ -> []
  }

broadPermissionsRule :: PolicyRule
broadPermissionsRule = PolicyRule
  { ruleId = "PERM-002"
  , ruleName = "Broad Permissions"
  , ruleDescription = "Detect overly broad permission grants"
  , ruleSeverity = Error
  , ruleCategory = Permissions
  , ruleCheck = \wf ->
      let fp = wfFileName wf
          chk label perms = case perms of
            Just (PermissionsAll PermWrite) ->
              [ mkFinding Error Permissions "PERM-002"
                  (label <> " uses 'write-all' permissions, granting broad access.")
                  fp (Just "Use fine-grained permissions instead of 'write-all'.")
              ]
            _ -> []
      in chk "Workflow" (wfPermissions wf)
         ++ concatMap (\j -> chk ("Job '" <> jobId j <> "'") (jobPermissions j)) (wfJobs wf)
  }

selfHostedRunnerRule :: PolicyRule
selfHostedRunnerRule = PolicyRule
  { ruleId = "RUN-001"
  , ruleName = "Self-Hosted Runner Detection"
  , ruleDescription = "Flag jobs using non-standard or self-hosted runners"
  , ruleSeverity = Info
  , ruleCategory = Runners
  , ruleCheck = \wf ->
      concatMap (\j -> case jobRunsOn j of
        CustomLabel label
          | "self-hosted" `T.isInfixOf` label -> []  -- Deliberate self-hosted runner choice
          | otherwise ->
          [ mkFinding Info Runners "RUN-001"
              ("Job '" <> jobId j <> "' uses non-standard runner: " <> label)
              (wfFileName wf)
              (Just "Consider using GitHub-hosted runners for portability.")
          ]
        _ -> []
      ) (wfJobs wf)
  }

missingConcurrencyRule :: PolicyRule
missingConcurrencyRule = PolicyRule
  { ruleId = "CONC-001"
  , ruleName = "Missing Concurrency"
  , ruleDescription = "PR workflows should set concurrency cancellation"
  , ruleSeverity = Info
  , ruleCategory = Concurrency
  , ruleCheck = \wf ->
      let hasPR = any isPRTrigger (wfTriggers wf)
      in if hasPR && null (wfConcurrency wf)
         then [ mkFinding Info Concurrency "CONC-001"
                  "Workflow has pull_request trigger but no concurrency config. \
                  \Duplicate runs may waste resources."
                  (wfFileName wf)
                  (Just "Add 'concurrency:' with cancel-in-progress for PR workflows.")
              ]
         else []
  }

isPRTrigger :: WorkflowTrigger -> Bool
isPRTrigger (TriggerEvents evts) = any (\e -> triggerName e == "pull_request") evts
isPRTrigger _ = False

unpinnedActionRule :: PolicyRule
unpinnedActionRule = PolicyRule
  { ruleId = "SEC-001"
  , ruleName = "Unpinned Actions"
  , ruleDescription = "Third-party actions should be pinned to a commit SHA"
  , ruleSeverity = Warning
  , ruleCategory = Security
  , ruleCheck = \wf ->
      concatMap (\j ->
        concatMap (\s -> case stepUses s of
          Just uses
            | not (isFirstParty uses) && not (isPinned uses) ->
              [ mkFinding Warning Security "SEC-001"
                  ("Step uses unpinned action: " <> uses <>
                   ". Supply-chain risk: tag references can be mutated.")
                  (wfFileName wf)
                  (Just "Pin to a full commit SHA instead of a tag.")
              ]
          _ -> []
        ) (jobSteps j)
      ) (wfJobs wf)
  }

isFirstParty :: Text -> Bool
isFirstParty t = "actions/" `T.isPrefixOf` t || "github/" `T.isPrefixOf` t

isPinned :: Text -> Bool
isPinned t =
  case T.breakOn "@" t of
    (_, after) | not (T.null after) ->
      let sha = T.drop 1 after
      in T.length sha == 40 && T.all (\c -> isDigit c || (c >= 'a' && c <= 'f')) sha
    _ -> False

missingTimeoutRule :: PolicyRule
missingTimeoutRule = PolicyRule
  { ruleId = "RES-001"
  , ruleName = "Missing Timeout"
  , ruleDescription = "Jobs should set timeout-minutes to prevent runaway builds"
  , ruleSeverity = Warning
  , ruleCategory = Structure
  , ruleCheck = \wf ->
      concatMap (\j ->
        -- Skip reusable workflow caller jobs (uses: at job level).
        -- These have no steps and inherit the callee's timeout.
        if null (jobSteps j) then []
        else case jobTimeoutMin j of
          Nothing ->
            [ mkFinding Warning Structure "RES-001"
                ("Job '" <> jobId j <> "' has no timeout-minutes. \
                 \Runaway jobs can consume resources indefinitely.")
                (wfFileName wf)
                (Just "Add 'timeout-minutes:' to bound execution time.")
            ]
          Just _ -> []
      ) (wfJobs wf)
  }

workflowNamingRule :: PolicyRule
workflowNamingRule = PolicyRule
  { ruleId = "NAME-001"
  , ruleName = "Workflow Naming"
  , ruleDescription = "Workflow names should be descriptive"
  , ruleSeverity = Info
  , ruleCategory = Naming
  , ruleCheck = \wf ->
      if T.length (wfName wf) < 3
      then [ mkFinding Info Naming "NAME-001"
               "Workflow has a very short or missing name."
               (wfFileName wf)
               (Just "Use a descriptive workflow name (e.g., 'CI', 'Release').")
           ]
      else []
  }

jobNamingRule :: PolicyRule
jobNamingRule = PolicyRule
  { ruleId = "NAME-002"
  , ruleName = "Job Naming Convention"
  , ruleDescription = "Job IDs should use kebab-case"
  , ruleSeverity = Info
  , ruleCategory = Naming
  , ruleCheck = \wf ->
      concatMap (\j ->
        if not (isKebabCase (jobId j))
        then [ mkFinding Info Naming "NAME-002"
                 ("Job ID '" <> jobId j <> "' does not follow kebab-case.")
                 (wfFileName wf)
                 (Just "Use kebab-case for job IDs (e.g., 'build-and-test').")
             ]
        else []
      ) (wfJobs wf)
  }

isKebabCase :: Text -> Bool
isKebabCase t = not (T.null t) && T.all (\c -> isLower c || isDigit c || c == '-') t

triggerWildcardRule :: PolicyRule
triggerWildcardRule = PolicyRule
  { ruleId = "TRIG-001"
  , ruleName = "Wildcard Triggers"
  , ruleDescription = "Detect triggers matching all branches"
  , ruleSeverity = Info
  , ruleCategory = Triggers
  , ruleCheck = \wf ->
      concatMap (\t -> case t of
        TriggerEvents evts -> concatMap (\e ->
          if any ("**" `T.isInfixOf`) (triggerBranches e)
          then [ mkFinding Info Triggers "TRIG-001"
                   ("Trigger '" <> triggerName e <> "' uses wildcard branch pattern.")
                   (wfFileName wf)
                   (Just "Restrict to specific branches for tighter control.")
               ]
          else []
          ) evts
        _ -> []
      ) (wfTriggers wf)
  }

secretInRunRule :: PolicyRule
secretInRunRule = PolicyRule
  { ruleId = "SEC-002"
  , ruleName = "Secret in Run Step"
  , ruleDescription = "Detect direct secret references in shell commands"
  , ruleSeverity = Error
  , ruleCategory = Security
  , ruleCheck = \wf ->
      concatMap (\j ->
        concatMap (\s -> case stepRun s of
          Just cmd
            | "secrets." `T.isInfixOf` cmd ->
              [ mkFinding Error Security "SEC-002"
                  "Run step references secrets directly. Secrets in shell \
                  \commands risk exposure in build logs."
                  (wfFileName wf)
                  (Just "Pass secrets via environment variables instead.")
              ]
          _ -> []
        ) (jobSteps j)
      ) (wfJobs wf)
  }
