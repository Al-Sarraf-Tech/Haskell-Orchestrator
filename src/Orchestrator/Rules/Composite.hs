-- | Rules for composite action (action.yml) linting.
--
-- Detects issues in composite action definitions: missing descriptions,
-- missing input descriptions, branding gaps, and shell specification.
module Orchestrator.Rules.Composite
  ( compositeDescriptionRule
  , compositeShellRule
  ) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Rule: detect actions/workflows with missing or minimal descriptions.
-- Good descriptions are critical for action marketplace discoverability.
compositeDescriptionRule :: PolicyRule
compositeDescriptionRule = PolicyRule
  { ruleId = "COMP-001"
  , ruleName = "Action Missing Description"
  , ruleDescription = "Composite actions and reusable workflows should have meaningful descriptions"
  , ruleSeverity = Info
  , ruleCategory = Naming
  , ruleTags = [TagStyle]
  , ruleCheck = \wf ->
      let hasCall = any isWorkflowCall (wfTriggers wf)
          hasShortName = T.length (wfName wf) < 5
          hasGenericName = wfName wf `elem` ["CI", "Build", "Test", "Run", "Main"]
      in [ Finding
                  { findingSeverity = Info
                  , findingCategory = Naming
                  , findingRuleId = "COMP-001"
                  , findingMessage =
                      "Reusable workflow '" <> wfName wf
                      <> "' has a very short or generic name. "
                      <> "Descriptive names help callers understand the workflow's purpose."
                  , findingFile = wfFileName wf
                  , findingLocation = Nothing
                  , findingRemediation = Just
                      "Use a descriptive name like 'Build and Test Node.js' instead of just 'CI'."
                  , findingAutoFixable = False
                  , findingEffort = Nothing
                  , findingLinks = []
                  }
              | hasCall && (hasShortName || hasGenericName)
              ]
  }

-- | Rule: detect steps in composite-like workflows missing explicit shell.
-- When a reusable workflow has run steps without explicit shell,
-- the shell depends on the runner OS, which is a portability risk.
compositeShellRule :: PolicyRule
compositeShellRule = PolicyRule
  { ruleId = "COMP-002"
  , ruleName = "Shell Not Specified"
  , ruleDescription = "Run steps in reusable workflows should specify shell explicitly"
  , ruleSeverity = Info
  , ruleCategory = Structure
  , ruleTags = [TagStyle]
  , ruleCheck = \wf ->
      let hasCall = any isWorkflowCall (wfTriggers wf)
          -- Count run steps without explicit shell in their 'with' map
          runStepsNoShell = [ (jobId j, s)
                            | j <- wfJobs wf
                            , s <- jobSteps j
                            , hasRun s
                            , not (hasShell s)
                            ]
      in if hasCall && not (null runStepsNoShell)
         then map (\(jid, _) ->
           Finding
             { findingSeverity = Info
             , findingCategory = Structure
             , findingRuleId = "COMP-002"
             , findingMessage =
                 "Job '" <> jid
                 <> "' in reusable workflow has run steps without explicit shell. "
                 <> "Shell defaults vary by runner OS."
             , findingFile = wfFileName wf
             , findingLocation = Nothing
             , findingRemediation = Just $
                 "Add 'shell: bash' (or pwsh) to run steps, or set "
                 <> "'defaults: { run: { shell: bash } }' at workflow level."
             , findingAutoFixable = False
             , findingEffort = Nothing
             , findingLinks = []
             }
           ) (take 3 runStepsNoShell)  -- Cap at 3 findings per workflow
         else []
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

isWorkflowCall :: WorkflowTrigger -> Bool
isWorkflowCall (TriggerEvents evts) =
  any (\e -> triggerName e == "workflow_call") evts
isWorkflowCall _ = False

hasRun :: Step -> Bool
hasRun s = case stepRun s of
  Just _ -> True
  Nothing -> False

hasShell :: Step -> Bool
hasShell s = case stepShell s of
  Just _  -> True
  Nothing -> Map.member "shell" (stepWith s)
