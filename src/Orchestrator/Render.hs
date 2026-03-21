-- | Output rendering for findings, plans, and scan results.
--
-- Supports plain text and JSON output formats.
module Orchestrator.Render
  ( renderFindings
  , renderFindingsJSON
  , renderScanResult
  , renderSummary
  , OutputFormat (..)
  ) where

import Data.Aeson (object, (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Orchestrator.Policy (groupByCategory)
import Orchestrator.Types

-- | Output format selection.
data OutputFormat = TextOutput | JSONOutput
  deriving stock (Eq, Show)

-- | Render findings as plain text.
renderFindings :: [Finding] -> Text
renderFindings [] = "No findings."
renderFindings fs =
  T.unlines $ concatMap renderOneFinding fs

renderOneFinding :: Finding -> [Text]
renderOneFinding f =
  [ severityTag (findingSeverity f) <> " [" <> findingRuleId f <> "] "
    <> findingMessage f
  , "  File: " <> T.pack (findingFile f)
  ] ++ maybe [] (\r -> ["  Fix: " <> r]) (findingRemediation f)
    ++ [""]

severityTag :: Severity -> Text
severityTag Info     = "[INFO]    "
severityTag Warning  = "[WARNING] "
severityTag Error    = "[ERROR]   "
severityTag Critical = "[CRITICAL]"

-- | Render findings as JSON text.
renderFindingsJSON :: [Finding] -> Text
renderFindingsJSON fs =
  TE.decodeUtf8 $ LBS.toStrict $ Aeson.encode $ map findingToJSON fs

findingToJSON :: Finding -> Aeson.Value
findingToJSON f = object
  [ "severity"      .= show (findingSeverity f)
  , "category"      .= show (findingCategory f)
  , "rule_id"       .= findingRuleId f
  , "message"       .= findingMessage f
  , "file"          .= T.pack (findingFile f)
  , "remediation"   .= findingRemediation f
  , "auto_fixable"  .= findingAutoFixable f
  , "effort"        .= fmap show (findingEffort f)
  , "links"         .= findingLinks f
  ]

-- | Render a complete scan result.
renderScanResult :: OutputFormat -> ScanResult -> Text
renderScanResult JSONOutput sr =
  TE.decodeUtf8 $ LBS.toStrict $ Aeson.encode $ object
    [ "target"   .= renderTargetJSON (scanTarget sr)
    , "files"    .= map T.pack (scanFiles sr)
    , "findings" .= map findingToJSON (scanFindings sr)
    ]
renderScanResult TextOutput sr =
  T.unlines
    [ "Scan Results"
    , T.replicate 60 "─"
    , "Files scanned: " <> T.pack (show (length (scanFiles sr)))
    , "Findings:      " <> T.pack (show (length (scanFindings sr)))
    , T.replicate 60 "─"
    , ""
    , renderFindings (scanFindings sr)
    ]

renderTargetJSON :: ScanTarget -> Aeson.Value
renderTargetJSON (LocalPath p) = object ["type" .= ("local" :: Text), "path" .= T.pack p]
renderTargetJSON (GitHubRepo o r) = object ["type" .= ("github" :: Text), "owner" .= o, "repo" .= r]
renderTargetJSON (GitHubOrg o) = object ["type" .= ("github_org" :: Text), "org" .= o]

-- | Render a summary of findings by category.
renderSummary :: [Finding] -> Text
renderSummary [] = "No findings to summarize."
renderSummary fs =
  let grouped = groupByCategory fs
      total = length fs
      errs = length $ filter (\f -> findingSeverity f >= Error) fs
      warns = length $ filter (\f -> findingSeverity f == Warning) fs
  in T.unlines $
       [ "Summary"
       , T.replicate 40 "─"
       , "Total findings: " <> T.pack (show total)
       , "  Errors:   " <> T.pack (show errs)
       , "  Warnings: " <> T.pack (show warns)
       , "  Info:     " <> T.pack (show (total - errs - warns))
       , ""
       , "By category:"
       ] ++ Map.foldlWithKey' (\acc cat items ->
              acc ++ ["  " <> T.pack (show cat) <> ": " <> T.pack (show (length items))]
            ) [] grouped
