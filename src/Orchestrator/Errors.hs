-- | Pretty-printed error messages with context and fix suggestions.
module Orchestrator.Errors
  ( formatError,
    suggestFix,
    ErrorContext (..),
  )
where

import Data.Char (isDigit)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Types (OrchestratorError (..))

-- | Rich context for an error, suitable for terminal display.
data ErrorContext = ErrorContext
  { errFile :: !(Maybe FilePath),
    errLine :: !(Maybe Int),
    errMessage :: !Text,
    errSuggestion :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

-- | Format an 'OrchestratorError' as a human-readable multi-line block.
--
-- Example output:
-- @
-- Error: Failed to parse workflow
--   File: .github/workflows/ci.yml
--   Line: 15
--
--   The 'on' key is required but missing.
--
--   Suggestion: Add a trigger configuration:
--     on:
--       push:
--         branches: [main]
-- @
formatError :: OrchestratorError -> Text
formatError err =
  let ctx = toErrorContext err
   in renderContext ctx

-- | Return a fix suggestion for known error patterns, Nothing otherwise.
suggestFix :: OrchestratorError -> Maybe Text
suggestFix err = errSuggestion (toErrorContext err)

------------------------------------------------------------------------
-- Internal
------------------------------------------------------------------------

-- | Convert an 'OrchestratorError' to a structured 'ErrorContext'.
toErrorContext :: OrchestratorError -> ErrorContext
toErrorContext (ParseError fp msg) =
  ErrorContext
    { errFile = Just fp,
      errLine = extractLine msg,
      errMessage = stripLinePrefix msg,
      errSuggestion = suggestForParseError msg
    }
toErrorContext (ConfigError msg) =
  ErrorContext
    { errFile = Nothing,
      errLine = Nothing,
      errMessage = msg,
      errSuggestion = suggestForConfigError msg
    }
toErrorContext (ScanError msg) =
  ErrorContext
    { errFile = Nothing,
      errLine = Nothing,
      errMessage = msg,
      errSuggestion = suggestForScanError msg
    }
toErrorContext (ValidationError msg) =
  ErrorContext
    { errFile = Nothing,
      errLine = Nothing,
      errMessage = msg,
      errSuggestion = suggestForValidationError msg
    }
toErrorContext (IOError' msg) =
  ErrorContext
    { errFile = Nothing,
      errLine = Nothing,
      errMessage = msg,
      errSuggestion = suggestForIOError msg
    }

renderContext :: ErrorContext -> Text
renderContext ctx =
  T.unlines $
    filter (not . T.null) $
      [ "Error: " <> headline ctx,
        maybe "" (\f -> "  File: " <> T.pack f) (errFile ctx),
        maybe "" (\l -> "  Line: " <> T.pack (show l)) (errLine ctx),
        "",
        "  " <> errMessage ctx
      ]
        ++ case errSuggestion ctx of
          Nothing -> []
          Just sug -> ["", "  Suggestion: " <> sug]

headline :: ErrorContext -> Text
headline ctx
  | Just _ <- errFile ctx = "Failed to parse workflow"
  | "missing" `T.isInfixOf` T.toLower (errMessage ctx) = "Missing required field"
  | "permission" `T.isInfixOf` T.toLower (errMessage ctx) = "Permission error"
  | "directory" `T.isInfixOf` T.toLower (errMessage ctx) = "Directory not found"
  | "file" `T.isInfixOf` T.toLower (errMessage ctx) = "File not found"
  | otherwise = "Operation failed"

-- | Try to extract a line number from YAML parse error messages.
-- Handles patterns like "line 15:" or "at line 15".
extractLine :: Text -> Maybe Int
extractLine msg =
  let ws = T.words msg
      pairs = zip ws (tail ws)
      found =
        [ n
        | ("line", numT) <- pairs,
          let cleaned = T.dropWhile (not . isDigitChar) numT,
          let digits = T.takeWhile isDigitChar cleaned,
          not (T.null digits),
          let n = read (T.unpack digits) :: Int
        ]
   in case found of
        (n : _) -> Just n
        [] -> Nothing

isDigitChar :: Char -> Bool
isDigitChar = isDigit

-- | Remove leading "line N:" prefix from messages if present.
stripLinePrefix :: Text -> Text
stripLinePrefix msg
  | "line " `T.isPrefixOf` T.toLower msg =
      T.strip . T.dropWhile (/= ':') . T.drop 1 . T.dropWhile (/= ':') $ msg
  | otherwise = msg

------------------------------------------------------------------------
-- Pattern-based suggestions
------------------------------------------------------------------------

suggestForParseError :: Text -> Maybe Text
suggestForParseError msg
  | "on" `T.isInfixOf` msg || "trigger" `T.isInfixOf` T.toLower msg =
      Just $
        T.unlines
          [ "Add a trigger configuration:",
            "  on:",
            "    push:",
            "      branches: [main]"
          ]
  | "jobs" `T.isInfixOf` msg =
      Just $
        T.unlines
          [ "Add at least one job:",
            "  jobs:",
            "    build:",
            "      runs-on: ubuntu-latest",
            "      steps: []"
          ]
  | "indent" `T.isInfixOf` T.toLower msg || "mapping" `T.isInfixOf` T.toLower msg =
      Just "Check indentation — YAML uses 2-space indentation, not tabs."
  | "unexpected" `T.isInfixOf` T.toLower msg =
      Just "Review the YAML syntax around the indicated line."
  | otherwise = Nothing

suggestForConfigError :: Text -> Maybe Text
suggestForConfigError msg
  | "pack" `T.isInfixOf` T.toLower msg =
      Just "Set 'policy.pack' to 'standard' or 'extended' in .orchestrator.yml"
  | "severity" `T.isInfixOf` T.toLower msg =
      Just "Valid severity values: info, warning, error, critical"
  | "format" `T.isInfixOf` T.toLower msg =
      Just "Valid output formats: text, json, sarif, markdown"
  | otherwise = Nothing

suggestForScanError :: Text -> Maybe Text
suggestForScanError msg
  | "no workflow" `T.isInfixOf` T.toLower msg || "not found" `T.isInfixOf` T.toLower msg =
      Just "Ensure the repository contains a .github/workflows/ directory with .yml files."
  | "permission" `T.isInfixOf` T.toLower msg =
      Just "Check read permissions on the workflow directory."
  | otherwise = Nothing

suggestForValidationError :: Text -> Maybe Text
suggestForValidationError msg
  | "name" `T.isInfixOf` T.toLower msg =
      Just "Add a descriptive 'name:' field to the workflow or job."
  | "runs-on" `T.isInfixOf` T.toLower msg =
      Just "Specify a runner: runs-on: ubuntu-latest"
  | otherwise = Nothing

suggestForIOError :: Text -> Maybe Text
suggestForIOError msg
  | "no such file" `T.isInfixOf` T.toLower msg =
      Just "Verify the path exists and is readable."
  | "permission" `T.isInfixOf` T.toLower msg =
      Just "Check file permissions."
  | otherwise = Nothing
