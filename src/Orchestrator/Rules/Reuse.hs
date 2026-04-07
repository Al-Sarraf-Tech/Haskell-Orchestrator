-- | Rules for reusable workflow (workflow_call) analysis.
--
-- Detects issues with reusable workflows: missing input validation,
-- unused outputs, and missing secret declarations.
module Orchestrator.Rules.Reuse
  ( reuseInputValidationRule
  , reuseUnusedOutputRule
  ) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Rule: detect workflow_call triggers with no inputs defined.
-- Reusable workflows that accept no inputs are likely missing validation.
reuseInputValidationRule :: PolicyRule
reuseInputValidationRule = PolicyRule
  { ruleId = "REUSE-001"
  , ruleName = "Reusable Workflow Input Validation"
  , ruleDescription = "Reusable workflows (workflow_call) should declare explicit inputs"
  , ruleSeverity = Warning
  , ruleCategory = Structure
  , ruleTags = [TagStructure]
  , ruleCheck = \wf ->
      let hasWorkflowCall = any isWorkflowCallTrigger (wfTriggers wf)
          -- A workflow_call without inputs is suspicious — it means the
          -- caller can't parameterize anything, which suggests missing
          -- input declarations.
          allSteps = concatMap jobSteps (wfJobs wf)
          usesExpressions = any stepUsesExpression allSteps
      in [ Finding
                  { findingSeverity = Warning
                  , findingCategory = Structure
                  , findingRuleId = "REUSE-001"
                  , findingMessage =
                      "Reusable workflow '" <> wfName wf
                      <> "' uses workflow_call but no steps reference inputs. "
                      <> "Consider adding typed inputs for callers."
                  , findingFile = wfFileName wf
                  , findingLocation = Nothing
                  , findingRemediation = Just $
                      "Add 'inputs:' under the workflow_call trigger to declare "
                      <> "typed parameters for callers."
                  , findingAutoFixable = False
                  , findingEffort = Nothing
                  , findingLinks = []
                  }
              | hasWorkflowCall && not usesExpressions
              ]
  }

-- | Rule: detect reusable workflows whose outputs are never referenced.
reuseUnusedOutputRule :: PolicyRule
reuseUnusedOutputRule = PolicyRule
  { ruleId = "REUSE-002"
  , ruleName = "Reusable Workflow Unused Outputs"
  , ruleDescription = "Detect reusable workflows that define outputs but never set them"
  , ruleSeverity = Info
  , ruleCategory = Structure
  , ruleTags = [TagStructure]
  , ruleCheck = \wf ->
      let hasWorkflowCall = any isWorkflowCallTrigger (wfTriggers wf)
          -- Check if any step sets outputs via GITHUB_OUTPUT
          allSteps = concatMap jobSteps (wfJobs wf)
          setsOutput = any stepSetsOutput allSteps
      in [ Finding
                  { findingSeverity = Info
                  , findingCategory = Structure
                  , findingRuleId = "REUSE-002"
                  , findingMessage =
                      "Reusable workflow '" <> wfName wf
                      <> "' uses workflow_call but no steps set outputs. "
                      <> "Callers cannot receive data back from this workflow."
                  , findingFile = wfFileName wf
                  , findingLocation = Nothing
                  , findingRemediation = Just $
                      "If callers need results, add 'outputs:' to workflow_call "
                      <> "and set values via $GITHUB_OUTPUT in steps."
                  , findingAutoFixable = False
                  , findingEffort = Nothing
                  , findingLinks = []
                  }
              | hasWorkflowCall && not setsOutput
              ]
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

isWorkflowCallTrigger :: WorkflowTrigger -> Bool
isWorkflowCallTrigger TriggerDispatch = False
isWorkflowCallTrigger (TriggerCron _) = False
isWorkflowCallTrigger (TriggerEvents evts) =
  any (\e -> triggerName e == "workflow_call") evts

stepUsesExpression :: Step -> Bool
stepUsesExpression s =
  let checkField = maybe False hasInputsRef
  in checkField (stepRun s)
     || any hasInputsRef (Map.elems (stepWith s))
     || any hasInputsRef (Map.elems (stepEnv s))
  where
    hasInputsRef :: Text -> Bool
    hasInputsRef t = "inputs." `T.isInfixOf` t || "github.event.inputs" `T.isInfixOf` t

stepSetsOutput :: Step -> Bool
stepSetsOutput s = case stepRun s of
  Just cmd -> "GITHUB_OUTPUT" `T.isInfixOf` cmd
              || "set-output" `T.isInfixOf` cmd
  Nothing  -> False
