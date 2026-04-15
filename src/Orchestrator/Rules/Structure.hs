-- | Rules for workflow structural analysis.
--
-- Detects structural issues in workflow definitions: unreferenced reusable
-- workflows and circular workflow calls.
module Orchestrator.Rules.Structure
  ( structUnreferencedReusableRule,
    structCircularCallRule,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | STRUCT-001: Unreferenced Reusable Workflow
--
-- Flags workflows that declare a workflow_call trigger (making them
-- reusable).  In single-file scan mode we cannot know whether other
-- workflows call this one, so the finding is informational: the operator
-- should verify that the workflow is actually referenced by a caller.
structUnreferencedReusableRule :: PolicyRule
structUnreferencedReusableRule =
  PolicyRule
    { ruleId = "STRUCT-001",
      ruleName = "Unreferenced Reusable Workflow",
      ruleDescription =
        "Reusable workflows (workflow_call) should be verified as referenced by callers",
      ruleSeverity = Info,
      ruleCategory = Structure,
      ruleTags = [TagStructure],
      ruleCheck = \wf ->
        [ mkFinding'
            Info
            Structure
            "STRUCT-001"
            ( "Workflow '"
                <> wfName wf
                <> "' declares a workflow_call trigger (reusable workflow). "
                <> "Verify that at least one caller workflow references it."
            )
            (wfFileName wf)
            Nothing
            ( Just
                "Search your repository for 'uses:' references to this workflow file. \
                \If no callers exist, consider whether this workflow is still needed."
            )
        | hasWorkflowCall (wfTriggers wf)
        ]
    }

-- | STRUCT-002: Circular Workflow Call
--
-- Detects a workflow that calls itself via a reusable workflow reference.
-- A step whose 'uses' field resolves to the same file as the containing
-- workflow creates an infinite loop at runtime.
structCircularCallRule :: PolicyRule
structCircularCallRule =
  PolicyRule
    { ruleId = "STRUCT-002",
      ruleName = "Circular Workflow Call",
      ruleDescription =
        "Detect workflows that call themselves via a reusable workflow step",
      ruleSeverity = Error,
      ruleCategory = Structure,
      ruleTags = [TagStructure],
      ruleCheck = \wf ->
        let selfRefs =
              [ s
              | j <- wfJobs wf,
                s <- jobSteps j,
                isSelfReference (wfFileName wf) s
              ]
         in map
              ( \s ->
                  mkFinding'
                    Error
                    Structure
                    "STRUCT-002"
                    ( "Workflow '"
                        <> wfName wf
                        <> "' contains a step that calls itself via '"
                        <> fromMaybe "" (stepUses s)
                        <> "'. This creates a circular call and will fail at runtime."
                    )
                    (wfFileName wf)
                    (stepName s)
                    ( Just
                        "Remove the self-referencing 'uses:' step or replace it \
                        \with the intended external workflow path."
                    )
              )
              selfRefs
    }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- | True if any trigger is a workflow_call event.
hasWorkflowCall :: [WorkflowTrigger] -> Bool
hasWorkflowCall = any isWorkflowCallTrigger
  where
    isWorkflowCallTrigger (TriggerEvents evts) =
      any (\e -> triggerName e == "workflow_call") evts
    isWorkflowCallTrigger _ = False

-- | True if the step's 'uses' field points to the same file as the
-- workflow itself.  Paths are normalised by stripping a leading "./".
isSelfReference :: FilePath -> Step -> Bool
isSelfReference wfFile step = case stepUses step of
  Nothing -> False
  Just uses
    | isWorkflowFile uses ->
        normalise (T.unpack uses) == normalise wfFile
    | otherwise -> False
  where
    isWorkflowFile t = ".yml" `T.isSuffixOf` t || ".yaml" `T.isSuffixOf` t
    normalise p = case p of
      '.' : '/' : rest -> rest
      other -> other
