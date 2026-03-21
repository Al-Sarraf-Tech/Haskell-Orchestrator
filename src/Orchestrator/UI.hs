-- | Embedded web dashboard types and HTML rendering.
--
-- Provides core types and self-contained HTML generation for a scan
-- results dashboard.  The generated HTML includes all CSS inline with
-- no external dependencies, suitable for serving from any HTTP server
-- or opening directly in a browser.
module Orchestrator.UI
  ( -- * Types
    DashboardData (..)
    -- * Rendering
  , renderDashboardHTML
  , renderAPIJSON
  ) where

import Data.Aeson (object, (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE

import Orchestrator.Render (renderFindingsJSON)
import Orchestrator.Types
  ( Finding (..)
  , ScanResult (..)
  , Severity (..)
  )

-- | Data required to render the dashboard.
data DashboardData = DashboardData
  { ddFindings   :: ![Finding]
  , ddScanResult :: !(Maybe ScanResult)
  , ddRuleCount  :: !Int
  , ddVersion    :: !Text
  , ddEdition    :: !Text
  } deriving stock (Show)

-- | Render the dashboard as a complete, self-contained HTML page.
--
-- The output uses a dark-mode design with CSS Grid layout, severity-coded
-- summary cards, a findings table, and a status bar.  All styles are inline;
-- no external resources are required.
renderDashboardHTML :: DashboardData -> Text
renderDashboardHTML dd = T.concat
  [ htmlHead
  , htmlBody dd
  ]

-- | Render the dashboard data as a JSON object.
renderAPIJSON :: DashboardData -> Text
renderAPIJSON dd =
  TE.decodeUtf8 $ LBS.toStrict $ Aeson.encode $ object
    [ "version"    .= ddVersion dd
    , "edition"    .= ddEdition dd
    , "ruleCount"  .= ddRuleCount dd
    , "totalFindings" .= length (ddFindings dd)
    , "findings"   .= Aeson.toJSON (renderFindingsJSON (ddFindings dd))
    , "summary"    .= object
        [ "errors"   .= countBySev Error (ddFindings dd)
        , "critical" .= countBySev Critical (ddFindings dd)
        , "warnings" .= countBySev Warning (ddFindings dd)
        , "info"     .= countBySev Info (ddFindings dd)
        ]
    , "filesScanned" .= maybe (0 :: Int) (length . scanFiles) (ddScanResult dd)
    ]

-- Severity counting -------------------------------------------------------

countBySev :: Severity -> [Finding] -> Int
countBySev sev = length . filter (\f -> findingSeverity f == sev)

-- HTML generation ----------------------------------------------------------

htmlHead :: Text
htmlHead = T.unlines
  [ "<!DOCTYPE html>"
  , "<html lang=\"en\">"
  , "<head>"
  , "<meta charset=\"utf-8\">"
  , "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
  , "<title>Orchestrator Dashboard</title>"
  , "<style>"
  , cssStyles
  , "</style>"
  , "</head>"
  ]

htmlBody :: DashboardData -> Text
htmlBody dd = T.unlines
  [ "<body>"
  , "<div class=\"layout\">"
  , renderSidebar dd
  , "<main class=\"main\">"
  , renderHeader
  , renderSummaryCards dd
  , renderFindingsTable dd
  , "</main>"
  , "</div>"
  , renderStatusBar dd
  , "</body>"
  , "</html>"
  ]

renderHeader :: Text
renderHeader = T.unlines
  [ "<div class=\"header\">"
  , "  <h1>Scan Results</h1>"
  , "  <p class=\"subtitle\">GitHub Actions workflow policy analysis</p>"
  , "</div>"
  ]

renderSidebar :: DashboardData -> Text
renderSidebar dd = T.unlines
  [ "<nav class=\"sidebar\">"
  , "  <div class=\"sidebar-brand\">Orchestrator</div>"
  , "  <ul class=\"sidebar-nav\">"
  , "    <li class=\"nav-item active\">Overview</li>"
  , "    <li class=\"nav-item\">Findings (" <> showT (length (ddFindings dd)) <> ")</li>"
  , "    <li class=\"nav-item\">Rules (" <> showT (ddRuleCount dd) <> ")</li>"
  , "    <li class=\"nav-item\">Settings</li>"
  , "  </ul>"
  , "  <div class=\"sidebar-footer\">"
  , "    <span class=\"edition-badge\">" <> ddEdition dd <> "</span>"
  , "  </div>"
  , "</nav>"
  ]

renderSummaryCards :: DashboardData -> Text
renderSummaryCards dd =
  let fs       = ddFindings dd
      errors   = countBySev Error fs + countBySev Critical fs
      warnings = countBySev Warning fs
      infos    = countBySev Info fs
      total    = length fs
      files    = maybe 0 (length . scanFiles) (ddScanResult dd)
  in T.unlines
    [ "<div class=\"cards\">"
    , renderCard "Total" (showT total) "card-total"
    , renderCard "Errors" (showT errors) "card-error"
    , renderCard "Warnings" (showT warnings) "card-warning"
    , renderCard "Info" (showT infos) "card-info"
    , renderCard "Files" (showT files) "card-files"
    , "</div>"
    ]

renderCard :: Text -> Text -> Text -> Text
renderCard label value cls = T.unlines
  [ "<div class=\"card " <> cls <> "\">"
  , "  <div class=\"card-value\">" <> value <> "</div>"
  , "  <div class=\"card-label\">" <> label <> "</div>"
  , "</div>"
  ]

renderFindingsTable :: DashboardData -> Text
renderFindingsTable dd =
  let fs = ddFindings dd
  in T.unlines $
    [ "<div class=\"table-container\">"
    , "<table class=\"findings-table\">"
    , "<thead>"
    , "<tr>"
    , "  <th>Severity</th>"
    , "  <th>Rule</th>"
    , "  <th>Message</th>"
    , "  <th>File</th>"
    , "  <th>Fix</th>"
    , "</tr>"
    , "</thead>"
    , "<tbody>"
    ] ++ map renderFindingRow fs ++
    [ "</tbody>"
    , "</table>"
    , if null fs
        then "<div class=\"empty-state\">No findings — all checks passed.</div>"
        else ""
    , "</div>"
    ]

renderFindingRow :: Finding -> Text
renderFindingRow f = T.unlines
  [ "<tr>"
  , "  <td>" <> severityBadge (findingSeverity f) <> "</td>"
  , "  <td class=\"rule-id\">" <> escapeHtml (findingRuleId f) <> "</td>"
  , "  <td>" <> escapeHtml (findingMessage f) <> "</td>"
  , "  <td class=\"file-path\">" <> escapeHtml (T.pack (findingFile f)) <> "</td>"
  , "  <td>" <> maybe "—" escapeHtml (findingRemediation f) <> "</td>"
  , "</tr>"
  ]

severityBadge :: Severity -> Text
severityBadge Critical = "<span class=\"badge badge-critical\">Critical</span>"
severityBadge Error    = "<span class=\"badge badge-error\">Error</span>"
severityBadge Warning  = "<span class=\"badge badge-warning\">Warning</span>"
severityBadge Info     = "<span class=\"badge badge-info\">Info</span>"

renderStatusBar :: DashboardData -> Text
renderStatusBar dd = T.unlines
  [ "<footer class=\"status-bar\">"
  , "  <span>Orchestrator v" <> ddVersion dd <> "</span>"
  , "  <span>" <> ddEdition dd <> " Edition</span>"
  , "  <span>" <> showT (length (ddFindings dd)) <> " findings</span>"
  , "</footer>"
  ]

-- CSS ---------------------------------------------------------------------

cssStyles :: Text
cssStyles = T.unlines
  [ "*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }"
  , ""
  , ":root {"
  , "  --bg-primary: #0a0a0f;"
  , "  --bg-secondary: #111118;"
  , "  --bg-elevated: #18181f;"
  , "  --bg-surface: #1e1e28;"
  , "  --border: #2a2a35;"
  , "  --border-subtle: #222230;"
  , "  --text-primary: #e4e4e7;"
  , "  --text-secondary: #a1a1aa;"
  , "  --text-muted: #71717a;"
  , "  --accent: #6366f1;"
  , "  --error: #ef4444;"
  , "  --error-bg: rgba(239, 68, 68, 0.08);"
  , "  --warning: #f59e0b;"
  , "  --warning-bg: rgba(245, 158, 11, 0.08);"
  , "  --info: #3b82f6;"
  , "  --info-bg: rgba(59, 130, 246, 0.08);"
  , "  --critical: #dc2626;"
  , "  --critical-bg: rgba(220, 38, 38, 0.08);"
  , "  --radius: 8px;"
  , "  --shadow: 0 1px 3px rgba(0,0,0,0.3), 0 1px 2px rgba(0,0,0,0.2);"
  , "}"
  , ""
  , "body {"
  , "  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Inter',"
  , "    'Roboto', 'Helvetica Neue', Arial, sans-serif;"
  , "  background: var(--bg-primary);"
  , "  color: var(--text-primary);"
  , "  line-height: 1.5;"
  , "  font-size: 14px;"
  , "  min-height: 100vh;"
  , "}"
  , ""
  , ".layout {"
  , "  display: grid;"
  , "  grid-template-columns: 220px 1fr;"
  , "  min-height: calc(100vh - 36px);"
  , "}"
  , ""
  , ".sidebar {"
  , "  background: var(--bg-secondary);"
  , "  border-right: 1px solid var(--border-subtle);"
  , "  padding: 24px 0;"
  , "  display: flex;"
  , "  flex-direction: column;"
  , "}"
  , ""
  , ".sidebar-brand {"
  , "  font-size: 16px;"
  , "  font-weight: 600;"
  , "  padding: 0 20px 20px;"
  , "  border-bottom: 1px solid var(--border-subtle);"
  , "  letter-spacing: -0.02em;"
  , "  color: var(--text-primary);"
  , "}"
  , ""
  , ".sidebar-nav {"
  , "  list-style: none;"
  , "  padding: 12px 0;"
  , "  flex: 1;"
  , "}"
  , ""
  , ".nav-item {"
  , "  padding: 8px 20px;"
  , "  color: var(--text-secondary);"
  , "  font-size: 13px;"
  , "  cursor: pointer;"
  , "  transition: background 0.15s, color 0.15s;"
  , "  border-radius: 0;"
  , "}"
  , ""
  , ".nav-item:hover { background: var(--bg-elevated); color: var(--text-primary); }"
  , ".nav-item.active {"
  , "  background: var(--bg-elevated);"
  , "  color: var(--text-primary);"
  , "  border-left: 2px solid var(--accent);"
  , "  padding-left: 18px;"
  , "}"
  , ""
  , ".sidebar-footer {"
  , "  padding: 16px 20px;"
  , "  border-top: 1px solid var(--border-subtle);"
  , "}"
  , ""
  , ".edition-badge {"
  , "  font-size: 11px;"
  , "  padding: 3px 8px;"
  , "  background: var(--bg-elevated);"
  , "  border: 1px solid var(--border);"
  , "  border-radius: 4px;"
  , "  color: var(--text-muted);"
  , "  text-transform: uppercase;"
  , "  letter-spacing: 0.05em;"
  , "}"
  , ""
  , ".main {"
  , "  padding: 32px 40px;"
  , "  overflow-y: auto;"
  , "}"
  , ""
  , ".header { margin-bottom: 32px; }"
  , ".header h1 {"
  , "  font-size: 22px;"
  , "  font-weight: 600;"
  , "  letter-spacing: -0.03em;"
  , "  color: var(--text-primary);"
  , "}"
  , ".subtitle {"
  , "  color: var(--text-muted);"
  , "  font-size: 13px;"
  , "  margin-top: 4px;"
  , "}"
  , ""
  , ".cards {"
  , "  display: grid;"
  , "  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));"
  , "  gap: 16px;"
  , "  margin-bottom: 32px;"
  , "}"
  , ""
  , ".card {"
  , "  background: var(--bg-elevated);"
  , "  border: 1px solid var(--border);"
  , "  border-radius: var(--radius);"
  , "  padding: 20px;"
  , "  box-shadow: var(--shadow);"
  , "}"
  , ""
  , ".card-value {"
  , "  font-size: 28px;"
  , "  font-weight: 700;"
  , "  letter-spacing: -0.04em;"
  , "  line-height: 1;"
  , "  margin-bottom: 6px;"
  , "}"
  , ""
  , ".card-label {"
  , "  font-size: 12px;"
  , "  color: var(--text-muted);"
  , "  text-transform: uppercase;"
  , "  letter-spacing: 0.06em;"
  , "}"
  , ""
  , ".card-error { border-left: 3px solid var(--error); }"
  , ".card-error .card-value { color: var(--error); }"
  , ".card-warning { border-left: 3px solid var(--warning); }"
  , ".card-warning .card-value { color: var(--warning); }"
  , ".card-info { border-left: 3px solid var(--info); }"
  , ".card-info .card-value { color: var(--info); }"
  , ".card-total { border-left: 3px solid var(--accent); }"
  , ".card-total .card-value { color: var(--accent); }"
  , ".card-files { border-left: 3px solid var(--text-muted); }"
  , ""
  , ".table-container {"
  , "  background: var(--bg-elevated);"
  , "  border: 1px solid var(--border);"
  , "  border-radius: var(--radius);"
  , "  overflow: hidden;"
  , "}"
  , ""
  , ".findings-table {"
  , "  width: 100%;"
  , "  border-collapse: collapse;"
  , "}"
  , ""
  , ".findings-table th {"
  , "  text-align: left;"
  , "  padding: 12px 16px;"
  , "  font-size: 11px;"
  , "  font-weight: 600;"
  , "  text-transform: uppercase;"
  , "  letter-spacing: 0.06em;"
  , "  color: var(--text-muted);"
  , "  background: var(--bg-surface);"
  , "  border-bottom: 1px solid var(--border);"
  , "  cursor: pointer;"
  , "  user-select: none;"
  , "}"
  , ""
  , ".findings-table th:hover { color: var(--text-secondary); }"
  , ""
  , ".findings-table td {"
  , "  padding: 10px 16px;"
  , "  border-bottom: 1px solid var(--border-subtle);"
  , "  font-size: 13px;"
  , "  color: var(--text-secondary);"
  , "  vertical-align: top;"
  , "}"
  , ""
  , ".findings-table tr:last-child td { border-bottom: none; }"
  , ".findings-table tr:hover td { background: rgba(255,255,255,0.02); }"
  , ""
  , ".rule-id {"
  , "  font-family: 'SF Mono', 'Cascadia Code', 'Fira Code', monospace;"
  , "  font-size: 12px;"
  , "  color: var(--text-muted);"
  , "  white-space: nowrap;"
  , "}"
  , ""
  , ".file-path {"
  , "  font-family: 'SF Mono', 'Cascadia Code', 'Fira Code', monospace;"
  , "  font-size: 12px;"
  , "  color: var(--text-muted);"
  , "  max-width: 200px;"
  , "  overflow: hidden;"
  , "  text-overflow: ellipsis;"
  , "  white-space: nowrap;"
  , "}"
  , ""
  , ".badge {"
  , "  display: inline-block;"
  , "  padding: 2px 8px;"
  , "  border-radius: 4px;"
  , "  font-size: 11px;"
  , "  font-weight: 600;"
  , "  letter-spacing: 0.02em;"
  , "  white-space: nowrap;"
  , "}"
  , ""
  , ".badge-critical { background: var(--critical-bg); color: var(--critical); border: 1px solid rgba(220,38,38,0.2); }"
  , ".badge-error { background: var(--error-bg); color: var(--error); border: 1px solid rgba(239,68,68,0.2); }"
  , ".badge-warning { background: var(--warning-bg); color: var(--warning); border: 1px solid rgba(245,158,11,0.2); }"
  , ".badge-info { background: var(--info-bg); color: var(--info); border: 1px solid rgba(59,130,246,0.2); }"
  , ""
  , ".empty-state {"
  , "  padding: 48px;"
  , "  text-align: center;"
  , "  color: var(--text-muted);"
  , "  font-size: 14px;"
  , "}"
  , ""
  , ".status-bar {"
  , "  display: flex;"
  , "  justify-content: space-between;"
  , "  align-items: center;"
  , "  padding: 8px 24px;"
  , "  background: var(--bg-secondary);"
  , "  border-top: 1px solid var(--border-subtle);"
  , "  font-size: 11px;"
  , "  color: var(--text-muted);"
  , "  height: 36px;"
  , "}"
  , ""
  , "@media (max-width: 768px) {"
  , "  .layout { grid-template-columns: 1fr; }"
  , "  .sidebar { display: none; }"
  , "  .main { padding: 20px 16px; }"
  , "  .cards { grid-template-columns: repeat(2, 1fr); }"
  , "  .findings-table { font-size: 12px; }"
  , "}"
  ]

-- Utility helpers ---------------------------------------------------------

showT :: Show a => a -> Text
showT = T.pack . show

escapeHtml :: Text -> Text
escapeHtml = T.replace "&" "&amp;"
           . T.replace "<" "&lt;"
           . T.replace ">" "&gt;"
           . T.replace "\"" "&quot;"
