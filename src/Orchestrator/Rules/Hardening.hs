-- | Hardening rules for GitHub Actions security best practices.
--
-- Detects common misconfigurations that weaken workflow security:
-- missing persist-credentials flag, unshelled run steps, and the
-- dangerous pull_request_target + checkout combination.
module Orchestrator.Rules.Hardening
  ( hard001PersistCredentials,
    hard002DefaultShellUnset,
    hard003PullRequestTargetRisk,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | HARD-001: Detect actions/checkout steps without persist-credentials: false.
--
-- By default, actions/checkout persists the GitHub token in the local git
-- config. Any subsequent step that spawns a subprocess can read it.
-- Setting persist-credentials: false eliminates that residual exposure.
hard001PersistCredentials :: PolicyRule
hard001PersistCredentials =
  PolicyRule
    { ruleId = "HARD-001",
      ruleName = "Missing persist-credentials: false",
      ruleDescription =
        "actions/checkout steps should set persist-credentials: false \
        \to avoid leaving the GitHub token in the local git config",
      ruleSeverity = Warning,
      ruleCategory = Security,
      ruleTags = [TagSecurity],
      ruleCheck = \wf ->
        concatMap (concatMap (checkStep (wfFileName wf)) . jobSteps) (wfJobs wf)
    }
  where
    checkStep fp step =
      case stepUses step of
        Just uses
          | "actions/checkout" `T.isPrefixOf` uses,
            Map.lookup "persist-credentials" (stepWith step) /= Just "false" ->
              [ mkFinding'
                  Warning
                  Security
                  "HARD-001"
                  "Step uses actions/checkout without 'persist-credentials: false'. \
                  \The GitHub token is written into the local git config and is \
                  \readable by any subsequent process."
                  fp
                  (stepName step >>= \n -> Just ("Step: " <> n))
                  (Just "Add 'with: { persist-credentials: false }' to the checkout step.")
              ]
        _ -> []

-- | HARD-002: Detect run steps that do not specify an explicit shell.
--
-- When shell is omitted, GitHub Actions selects a default based on the
-- runner OS. This makes workflow behaviour OS-dependent and harder to
-- audit. One finding is emitted per workflow, summarising the count.
hard002DefaultShellUnset :: PolicyRule
hard002DefaultShellUnset =
  PolicyRule
    { ruleId = "HARD-002",
      ruleName = "Default Shell Unset",
      ruleDescription =
        "Run steps should declare an explicit shell to avoid OS-dependent \
        \behaviour and improve auditability",
      ruleSeverity = Info,
      ruleCategory = Security,
      ruleTags = [TagSecurity, TagStyle],
      ruleCheck = \wf ->
        let unshelledCount =
              length
                [ s
                | j <- wfJobs wf,
                  s <- jobSteps j,
                  Just _ <- [stepRun s], -- is a run step
                  Nothing <- [stepShell s] -- no explicit shell
                ]
         in [ mkFinding'
                Info
                Security
                "HARD-002"
                ( "Workflow contains "
                    <> T.pack (show unshelledCount)
                    <> " run step(s) without an explicit shell declaration. \
                       \Add 'shell: bash' (or another explicit shell) to each run step."
                )
                (wfFileName wf)
                Nothing
                (Just "Add 'shell: bash' to every run step.")
            | unshelledCount > 0
            ]
    }

-- | HARD-003: Detect pull_request_target workflows that contain checkout steps.
--
-- pull_request_target runs with write permissions and access to secrets in the
-- base repository context.  Checking out the PR head ref in this context can
-- allow untrusted code to exfiltrate secrets.  Unlike SEC-003 (which looks
-- only for head-ref checkouts), this rule flags ANY checkout under
-- pull_request_target because even a base-branch checkout widens the attack
-- surface through the elevated token.
hard003PullRequestTargetRisk :: PolicyRule
hard003PullRequestTargetRisk =
  PolicyRule
    { ruleId = "HARD-003",
      ruleName = "Pull Request Target Risk",
      ruleDescription =
        "Workflows triggered by pull_request_target that also use actions/checkout \
        \run untrusted code with elevated privileges",
      ruleSeverity = Error,
      ruleCategory = Security,
      ruleTags = [TagSecurity],
      ruleCheck = \wf ->
        let hasPRT = any isPRTargetTrigger (wfTriggers wf)
            hasCheckout =
              any
                ( any
                    ( \s -> case stepUses s of
                        Just uses -> "actions/checkout" `T.isPrefixOf` uses
                        Nothing -> False
                    )
                    . jobSteps
                )
                (wfJobs wf)
         in [ mkFinding'
                Error
                Security
                "HARD-003"
                "Workflow uses pull_request_target trigger and contains an \
                \actions/checkout step. This combination can allow untrusted \
                \pull-request code to execute with write permissions and access \
                \to repository secrets."
                (wfFileName wf)
                Nothing
                ( Just
                    "Separate the privileged workflow (pull_request_target) from \
                    \the checkout workflow (pull_request). Use workflow_run to pass \
                    \artifacts between them without exposing elevated credentials."
                )
            | hasPRT && hasCheckout
            ]
    }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

isPRTargetTrigger :: WorkflowTrigger -> Bool
isPRTargetTrigger (TriggerEvents evts) =
  any (\e -> triggerName e == "pull_request_target") evts
isPRTargetTrigger _ = False
