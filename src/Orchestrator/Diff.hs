-- | Diff and remediation plan generation.
--
-- Compares scan findings against desired state and produces actionable
-- remediation plans with ordered steps.
module Orchestrator.Diff
  ( generatePlan,
    renderPlanText,
    findingsToPlan,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Types

-- | Generate a remediation plan from scan findings.
findingsToPlan :: ScanTarget -> [Finding] -> Plan
findingsToPlan target findings =
  let actionable = filter (\f -> findingSeverity f >= Warning) findings
      steps = zipWith toStep [1 ..] actionable
      summary =
        T.pack $
          show (length steps)
            <> " remediation step(s) from "
            <> show (length findings)
            <> " finding(s)"
   in Plan
        { planTarget = target,
          planSteps = steps,
          planSummary = summary
        }

toStep :: Int -> Finding -> RemediationStep
toStep n f =
  RemediationStep
    { remStepOrder = n,
      remStepDescription =
        findingRuleId f
          <> ": "
          <> findingMessage f
          <> maybe "" ("\n  Fix: " <>) (findingRemediation f),
      remStepFile = findingFile f,
      remStepDiff = Nothing
    }

-- | Generate a plan for a scan target (convenience wrapper).
generatePlan :: ScanTarget -> [Finding] -> Plan
generatePlan = findingsToPlan

-- | Render a plan as human-readable text.
renderPlanText :: Plan -> Text
renderPlanText plan =
  T.unlines $
    [ "Remediation Plan",
      T.replicate 60 "─",
      "Target: " <> renderTarget (planTarget plan),
      "Summary: " <> planSummary plan,
      ""
    ]
      ++ concatMap renderStep (planSteps plan)
      ++ [T.replicate 60 "─"]

renderTarget :: ScanTarget -> Text
renderTarget (LocalPath p) = T.pack p
renderTarget (GitHubRepo owner repo) = owner <> "/" <> repo
renderTarget (GitHubOrg org) = org <> " (organization)"

renderStep :: RemediationStep -> [Text]
renderStep s =
  [ "Step " <> T.pack (show (remStepOrder s)) <> ":",
    "  File: " <> T.pack (remStepFile s),
    "  " <> remStepDescription s,
    ""
  ]
