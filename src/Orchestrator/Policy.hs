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
        CustomLabel label ->
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
      let sha = T.tail after
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
      concatMap (\j -> case jobTimeoutMin j of
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
