-- | Rules for environment and deployment configuration analysis.
--
-- Detects missing approval gates and URL declarations on environment blocks.
module Orchestrator.Rules.Environment
  ( envApprovalGateRule
  , envMissingUrlRule
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Rule: detect deployment workflows without environment protection.
-- Workflows that appear to deploy (by name pattern) should use
-- GitHub Environments with required reviewers for approval gates.
envApprovalGateRule :: PolicyRule
envApprovalGateRule = PolicyRule
  { ruleId = "ENV-001"
  , ruleName = "Missing Environment Approval Gate"
  , ruleDescription = "Deployment workflows should use environment protection rules"
  , ruleSeverity = Warning
  , ruleCategory = Security
  , ruleCheck = \wf ->
      let isDeployLike = isDeploymentWorkflow wf
          hasEnvRef = any jobReferencesEnvironment (wfJobs wf)
      in if isDeployLike && not hasEnvRef
         then [ Finding
                  { findingSeverity = Warning
                  , findingCategory = Security
                  , findingRuleId = "ENV-001"
                  , findingMessage =
                      "Workflow '" <> wfName wf
                      <> "' appears to be a deployment workflow but does not reference "
                      <> "a GitHub Environment. Without environments, there are no "
                      <> "approval gates, wait timers, or deployment branch restrictions."
                  , findingFile = wfFileName wf
                  , findingLocation = Nothing
                  , findingRemediation = Just $
                      "Add 'environment: <name>' to deployment jobs to enable "
                      <> "protection rules and approval workflows."
                  , findingAutoFixable = False
                  , findingEffort = Nothing
                  , findingLinks = []
                  }
              ]
         else []
  }

-- | Rule: detect environment references without URL declarations.
-- Environment URLs provide links to the deployed artifact in the
-- GitHub UI, improving deployment visibility.
envMissingUrlRule :: PolicyRule
envMissingUrlRule = PolicyRule
  { ruleId = "ENV-002"
  , ruleName = "Environment Missing URL"
  , ruleDescription = "Environment deployments should set environment_url for visibility"
  , ruleSeverity = Info
  , ruleCategory = Structure
  , ruleCheck = \wf ->
      concatMap (\j ->
        let refsEnv = jobReferencesEnvironment j
            hasUrl = jobEnvironmentUrl j || any stepSetsEnvironmentUrl (jobSteps j)
        in if refsEnv && not hasUrl
           then [ Finding
                    { findingSeverity = Info
                    , findingCategory = Structure
                    , findingRuleId = "ENV-002"
                    , findingMessage =
                        "Job '" <> jobId j
                        <> "' uses an environment but no step sets environment_url. "
                        <> "Setting a URL improves deployment visibility in the GitHub UI."
                    , findingFile = wfFileName wf
                    , findingLocation = Nothing
                    , findingRemediation = Just $
                        "Add an 'environment: { name: ..., url: ... }' block or "
                        <> "set 'environment_url' output in a deployment step."
                    , findingAutoFixable = False
                    , findingEffort = Nothing
                    , findingLinks = []
                    }
                ]
           else []
      ) (wfJobs wf)
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- | Check if a workflow looks like a deployment workflow by name/file.
isDeploymentWorkflow :: Workflow -> Bool
isDeploymentWorkflow wf =
  let indicators = ["deploy", "release", "staging", "production", "publish", "ship"]
      name = T.toLower (wfName wf)
      file = T.toLower (T.pack (wfFileName wf))
  in any (\i -> i `T.isInfixOf` name || i `T.isInfixOf` file) indicators

-- | Check if a job references a GitHub Environment.
-- Checks the job-level 'environment:' field first, then falls back to
-- heuristic text search in 'if' conditions and step configs.
jobReferencesEnvironment :: Job -> Bool
jobReferencesEnvironment j =
  case jobEnvironment j of
    Just _  -> True
    Nothing ->
      let ifRef = maybe False ("environment" `T.isInfixOf`) (jobIf j)
          stepRefs = any (\s ->
            maybe False ("environment" `T.isInfixOf`) (stepRun s)
            || maybe False ("environment" `T.isInfixOf`) (stepIf s)
            ) (jobSteps j)
      in ifRef || stepRefs

-- | Check if a step sets environment_url.
stepSetsEnvironmentUrl :: Step -> Bool
stepSetsEnvironmentUrl s =
  maybe False ("environment_url" `T.isInfixOf`) (stepRun s)
