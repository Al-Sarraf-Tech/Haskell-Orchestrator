-- | Markdown output rendering for findings and scan results.
--
-- Produces GitHub-flavored markdown suitable for PR comments,
-- issue bodies, and documentation.
module Orchestrator.Render.Markdown
  ( renderMarkdownFindings,
    renderMarkdownSummary,
    renderMarkdownPlan,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Policy (groupByCategory)
import Orchestrator.Types

-- | Render findings as a markdown table.
renderMarkdownFindings :: [Finding] -> Text
renderMarkdownFindings [] = "_No findings._\n"
renderMarkdownFindings fs =
  T.unlines $
    [ "| Severity | Rule | Category | Message | File |",
      "|----------|------|----------|---------|------|"
    ]
      ++ map renderRow fs

renderRow :: Finding -> Text
renderRow f =
  T.concat
    [ "| ",
      severityEmoji (findingSeverity f),
      " ",
      T.pack (show (findingSeverity f)),
      " | `",
      findingRuleId f,
      "` ",
      " | ",
      T.pack (show (findingCategory f)),
      " | ",
      escapeMarkdown (T.take 120 (findingMessage f)),
      " | `",
      T.pack (findingFile f),
      "` |"
    ]

-- | Render a summary with counts as markdown.
renderMarkdownSummary :: [Finding] -> Text
renderMarkdownSummary [] = "_No findings to summarize._\n"
renderMarkdownSummary fs =
  let grouped = groupByCategory fs
      total = length fs
      errs = length $ filter (\f -> findingSeverity f >= Error) fs
      warns = length $ filter (\f -> findingSeverity f == Warning) fs
      infos = total - errs - warns
   in T.unlines $
        [ "## Scan Summary",
          "",
          "| Metric | Count |",
          "|--------|-------|",
          "| Total findings | **" <> showT total <> "** |",
          "| Errors/Critical | " <> showT errs <> " |",
          "| Warnings | " <> showT warns <> " |",
          "| Info | " <> showT infos <> " |",
          "",
          "### By Category",
          "",
          "| Category | Count |",
          "|----------|-------|"
        ]
          ++ Map.foldlWithKey'
            ( \acc cat items ->
                acc ++ ["| " <> showT cat <> " | " <> showT (length items) <> " |"]
            )
            []
            grouped

-- | Render a remediation plan as markdown.
renderMarkdownPlan :: Plan -> Text
renderMarkdownPlan plan =
  T.unlines $
    [ "## Remediation Plan",
      "",
      "> " <> planSummary plan,
      ""
    ]
      ++ concatMap renderStep (planSteps plan)

renderStep :: RemediationStep -> [Text]
renderStep s =
  [ "### Step " <> showT (remStepOrder s),
    "",
    "**File:** `" <> T.pack (remStepFile s) <> "`",
    "",
    remStepDescription s,
    ""
  ]
    ++ case remStepDiff s of
      Nothing -> []
      Just d -> ["```diff", d, "```", ""]

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

severityEmoji :: Severity -> Text
severityEmoji Critical = ":red_circle:"
severityEmoji Error = ":x:"
severityEmoji Warning = ":warning:"
severityEmoji Info = ":information_source:"

escapeMarkdown :: Text -> Text
escapeMarkdown = T.replace "|" "\\|" . T.replace "\n" " "

showT :: (Show a) => a -> Text
showT = T.pack . show
