-- | Upgrade path rendering.
--
-- Shows users what additional findings and capabilities they'd get
-- with Business or Enterprise editions. Free marketing inside the
-- free tool, but genuinely useful for evaluating upgrade decisions.
module Orchestrator.Render.Upgrade
  ( renderUpgradePath,
    UpgradeInfo (..),
    estimateUpgradeImpact,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Types

-- | Information about what an upgrade would provide.
data UpgradeInfo = UpgradeInfo
  { uiEdition :: !Text,
    uiAdditionalRules :: !Int,
    uiNewCapabilities :: ![Text],
    uiEstimatedFindings :: !Int
  }
  deriving stock (Show)

-- | Estimate what upgrade to Business/Enterprise would add.
estimateUpgradeImpact :: [Finding] -> (UpgradeInfo, UpgradeInfo)
estimateUpgradeImpact findings =
  let currentCount = length findings
      -- Business: typically adds ~20-30% more findings from team rules
      bizEstimate = max 1 (currentCount * 25 `div` 100)
      -- Enterprise: governance policies apply org-wide
      entEstimate = max 2 (currentCount * 15 `div` 100)
   in ( UpgradeInfo
          { uiEdition = "Business",
            uiAdditionalRules = 4,
            uiNewCapabilities =
              [ "Multi-repo batch scanning (up to 32 parallel workers)",
                "HTML and CSV report generation",
                "Prioritized remediation with effort estimates",
                "Summary statistics across repositories",
                "Team naming convention enforcement",
                "Trend tracking over time",
                "PR comment integration",
                "CODEOWNERS-aware finding routing",
                "Diff-aware scanning for CI",
                "Curated policy bundles"
              ],
            uiEstimatedFindings = bizEstimate
          },
        UpgradeInfo
          { uiEdition = "Enterprise",
            uiAdditionalRules = 5,
            uiNewCapabilities =
              [ "Organisation-wide governance enforcement",
                "Immutable audit trail (JSONL/JSON/CSV export)",
                "SOC 2 Type II compliance mapping",
                "HIPAA Security Rule compliance mapping",
                "ISO 27001 / NIST CSF / FedRAMP compliance",
                "Per-repository risk scoring (0-100)",
                "Policy inheritance (org → team → repo)",
                "GitHub App integration (webhook-driven)",
                "Role-based access control",
                "Evidence vault for auditors",
                "Webhook notifications (Slack, PagerDuty)"
              ],
            uiEstimatedFindings = entEstimate
          }
      )

-- | Render the upgrade path as user-friendly text.
renderUpgradePath :: [Finding] -> Text
renderUpgradePath findings =
  let (biz, ent) = estimateUpgradeImpact findings
   in T.unlines $
        [ "Upgrade Path",
          T.replicate 60 "─",
          "",
          "Current: Community Edition",
          "  " <> T.pack (show (length findings)) <> " finding(s) detected",
          "",
          "━━━ Business Edition ━━━",
          "  +" <> T.pack (show (uiAdditionalRules biz)) <> " additional policy rules",
          "  ~"
            <> T.pack (show (uiEstimatedFindings biz))
            <> " additional findings estimated",
          "",
          "  New capabilities:"
        ]
          ++ map ("    • " <>) (uiNewCapabilities biz)
          ++ [ "",
               "━━━ Enterprise Edition ━━━",
               "  +"
                 <> T.pack (show (uiAdditionalRules ent))
                 <> " governance policies",
               "  Full organisational compliance coverage",
               "",
               "  New capabilities:"
             ]
          ++ map ("    • " <>) (uiNewCapabilities ent)
          ++ [ "",
               T.replicate 60 "─",
               "Learn more: https://github.com/jalsarraf0/Haskell-Orchestrator"
             ]
