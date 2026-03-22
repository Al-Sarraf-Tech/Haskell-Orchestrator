-- | SARIF (Static Analysis Results Interchange Format) output.
--
-- Produces SARIF v2.1.0 JSON output compatible with GitHub Code Scanning,
-- VS Code SARIF Viewer, and other SARIF-consuming tools.
module Orchestrator.Render.Sarif
  ( renderSarif
  , renderSarifJSON
  ) where

import Data.Aeson (Value, object, (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Orchestrator.Types

-- | SARIF schema version.
sarifVersion :: Text
sarifVersion = "2.1.0"

-- | SARIF schema URI.
sarifSchema :: Text
sarifSchema = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json"

-- | Render findings as a complete SARIF JSON document.
renderSarif :: Text -> Text -> [Finding] -> Value
renderSarif toolName toolVersion findings =
  object
    [ "$schema" .= sarifSchema
    , "version" .= sarifVersion
    , "runs"    .= [ renderRun toolName toolVersion findings ]
    ]

-- | Render findings as SARIF JSON text.
renderSarifJSON :: Text -> Text -> [Finding] -> Text
renderSarifJSON toolName toolVersion findings =
  TE.decodeUtf8 $ LBS.toStrict $ Aeson.encode $
    renderSarif toolName toolVersion findings

-- | Render a single SARIF run object.
renderRun :: Text -> Text -> [Finding] -> Value
renderRun toolName toolVersion findings =
  object
    [ "tool"    .= renderTool toolName toolVersion
    , "results" .= map renderResult findings
    , "rules"   .= renderRuleDescriptors findings
    ]
  where
    renderRuleDescriptors :: [Finding] -> [Value]
    renderRuleDescriptors fs =
      let ruleIds = dedup $ map findingRuleId fs
      in map (\rid ->
           let matching = filter (\f -> findingRuleId f == rid) fs
               desc = case matching of
                 (f:_) -> findingMessage f
                 []    -> ""
           in object
                [ "id" .= rid
                , "shortDescription" .= object [ "text" .= rid ]
                , "fullDescription"  .= object [ "text" .= desc ]
                , "defaultConfiguration" .= object
                    [ "level" .= sarifLevel (case matching of
                        (f:_) -> findingSeverity f
                        []    -> Info)
                    ]
                ]
         ) ruleIds

-- | Render a single SARIF result.
renderResult :: Finding -> Value
renderResult f =
  object
    [ "ruleId"   .= findingRuleId f
    , "level"    .= sarifLevel (findingSeverity f)
    , "message"  .= object [ "text" .= findingMessage f ]
    , "locations" .= [ renderLocation f ]
    , "fixes"    .= renderFixes f
    ]

-- | Render a SARIF location.
renderLocation :: Finding -> Value
renderLocation f =
  object
    [ "physicalLocation" .= object
        [ "artifactLocation" .= object
            [ "uri" .= T.pack (findingFile f)
            ]
        , "region" .= object
            [ "startLine" .= (1 :: Int)
            , "startColumn" .= (1 :: Int)
            ]
        ]
    ]

-- | Render SARIF fixes from remediation suggestions.
renderFixes :: Finding -> [Value]
renderFixes f = case findingRemediation f of
  Nothing -> []
  Just rem' ->
    [ object
        [ "description" .= object [ "text" .= rem' ]
        ]
    ]

-- | Render SARIF tool descriptor.
renderTool :: Text -> Text -> Value
renderTool name version =
  object
    [ "driver" .= object
        [ "name"            .= name
        , "version"         .= version
        , "semanticVersion" .= version
        , "informationUri"  .= ("https://github.com/jalsarraf0/Haskell-Orchestrator" :: Text)
        ]
    ]

-- | Map Orchestrator severity to SARIF level.
sarifLevel :: Severity -> Text
sarifLevel Critical = "error"
sarifLevel Error    = "error"
sarifLevel Warning  = "warning"
sarifLevel Info     = "note"

-- | Deduplicate a list while preserving order.
dedup :: Eq a => [a] -> [a]
dedup = go []
  where
    go _ [] = []
    go seen (x:xs)
      | x `elem` seen = go seen xs
      | otherwise      = x : go (x : seen) xs
