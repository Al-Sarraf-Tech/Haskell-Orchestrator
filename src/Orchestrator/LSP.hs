-- | Language Server Protocol analysis foundation for GitHub Actions YAML.
--
-- Provides the analysis layer that an LSP server would call: converting
-- orchestrator findings into LSP-style diagnostics with line\/column ranges.
-- This module does NOT depend on the @lsp@ package — it defines its own
-- lightweight diagnostic types suitable for integration.
module Orchestrator.LSP
  ( -- * Types
    Diagnostic (..)
  , DiagSeverity (..)
  , Range (..)
    -- * Conversion
  , findingsToDiagnostics
    -- * Analysis
  , analyzeForLSP
    -- * Rendering
  , renderDiagnostics
  ) where

import Data.Text (Text)
import Data.Text qualified as T

import Orchestrator.Parser (parseWorkflowFile)
import Orchestrator.Policy (defaultPolicyPack, evaluatePolicies)
import Orchestrator.Types (Finding (..), Severity (..))

-- | A source range within a file.
data Range = Range
  { rangeStartLine :: !Int
  , rangeStartCol  :: !Int
  , rangeEndLine   :: !Int
  , rangeEndCol    :: !Int
  } deriving stock (Eq, Show)

-- | Diagnostic severity levels matching the LSP specification.
data DiagSeverity
  = DiagError
  | DiagWarning
  | DiagInfo
  | DiagHint
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | A diagnostic message with location, severity, and rule reference.
data Diagnostic = Diagnostic
  { diagRange    :: !Range
  , diagSeverity :: !DiagSeverity
  , diagMessage  :: !Text
  , diagCode     :: !Text
  } deriving stock (Eq, Show)

-- | Convert orchestrator findings to LSP-style diagnostics.
--
-- Maps 'Severity' to 'DiagSeverity' and extracts line information from
-- the finding location field.  When no location is available, defaults
-- to line 1, column 1.
findingsToDiagnostics :: [Finding] -> [Diagnostic]
findingsToDiagnostics = map findingToDiag

-- | Analyze a workflow file and return LSP diagnostics.
--
-- Parses the workflow file at the given path, evaluates the default policy
-- pack, and converts all findings to diagnostics.  Parse errors are
-- returned as a single error diagnostic.
analyzeForLSP :: FilePath -> IO [Diagnostic]
analyzeForLSP fp = do
  result <- parseWorkflowFile fp
  case result of
    Left _ ->
      pure [ Diagnostic
               { diagRange    = Range 1 1 1 1
               , diagSeverity = DiagError
               , diagMessage  = "Failed to parse workflow file"
               , diagCode     = "PARSE-001"
               }
           ]
    Right wf ->
      let findings = evaluatePolicies defaultPolicyPack wf
      in pure $ findingsToDiagnostics findings

-- | Render diagnostics as human-readable text for testing and debugging.
renderDiagnostics :: [Diagnostic] -> Text
renderDiagnostics [] = "No diagnostics."
renderDiagnostics ds = T.unlines $ map renderOne ds
  where
    renderOne :: Diagnostic -> Text
    renderOne d = T.concat
      [ severityLabel (diagSeverity d)
      , " "
      , T.pack (show (rangeStartLine (diagRange d)))
      , ":"
      , T.pack (show (rangeStartCol (diagRange d)))
      , " ["
      , diagCode d
      , "] "
      , diagMessage d
      ]

    severityLabel :: DiagSeverity -> Text
    severityLabel DiagError   = "error"
    severityLabel DiagWarning = "warning"
    severityLabel DiagInfo    = "info"
    severityLabel DiagHint    = "hint"

-- Internal helpers --------------------------------------------------------

findingToDiag :: Finding -> Diagnostic
findingToDiag f = Diagnostic
  { diagRange    = locationToRange (findingLocation f)
  , diagSeverity = severityToDiag (findingSeverity f)
  , diagMessage  = findingMessage f
  , diagCode     = findingRuleId f
  }

severityToDiag :: Severity -> DiagSeverity
severityToDiag Info     = DiagInfo
severityToDiag Warning  = DiagWarning
severityToDiag Error    = DiagError
severityToDiag Critical = DiagError

-- | Parse a location string like "line 5" or "line 5, col 10" into a Range.
-- Falls back to line 1, column 1 when the location is absent or unparseable.
locationToRange :: Maybe Text -> Range
locationToRange Nothing = Range 1 1 1 1
locationToRange (Just loc)
  | "line " `T.isPrefixOf` loc =
      let stripped = T.drop 5 loc
          lineText = T.takeWhile (\c -> c /= ',' && c /= ' ') stripped
      in case reads (T.unpack lineText) :: [(Int, String)] of
           [(n, _)] -> Range n 1 n 1
           _        -> Range 1 1 1 1
  | otherwise = Range 1 1 1 1
