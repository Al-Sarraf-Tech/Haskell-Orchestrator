-- | Normalize GitHub Actions YAML formatting.
--
-- Provides a simple line-based formatter for GitHub Actions workflow YAML
-- files.  Normalizes key order, indentation, and produces a diff view
-- between original and formatted output.
module Orchestrator.Formatter
  ( -- * Types
    FormatConfig (..),
    QuoteStyle (..),

    -- * Defaults
    defaultFormatConfig,

    -- * Formatting
    formatWorkflowYAML,

    -- * Diff
    renderFormatDiff,
  )
where

import Data.Char (isSpace)
import Data.List (sortBy)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as T

-- | Quote style preference for YAML string values.
data QuoteStyle
  = SingleQuote
  | DoubleQuote
  | NoQuote
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)

-- | Configuration for the YAML formatter.
data FormatConfig = FormatConfig
  { -- | Number of spaces per indent level
    fcIndentWidth :: !Int,
    -- | Whether to sort top-level keys
    fcSortKeys :: !Bool,
    -- | Preferred quote style for values
    fcQuoteStyle :: !QuoteStyle
  }
  deriving stock (Eq, Show)

-- | Default format configuration: 2-space indent, sorted keys, no quoting.
defaultFormatConfig :: FormatConfig
defaultFormatConfig =
  FormatConfig
    { fcIndentWidth = 2,
      fcSortKeys = True,
      fcQuoteStyle = NoQuote
    }

-- | Normalize a GitHub Actions workflow YAML string.
--
-- This is a simple line-based formatter that:
--
--   1. Normalizes indentation to the configured width
--   2. Sorts top-level keys in canonical order (name, on, permissions,
--      concurrency, env, jobs) when sorting is enabled
--   3. Preserves comment lines and blank lines
formatWorkflowYAML :: FormatConfig -> Text -> Text
formatWorkflowYAML cfg input =
  let rawLines = T.lines input
      blocks = splitTopLevelBlocks rawLines
      sorted =
        if fcSortKeys cfg
          then sortBlocks blocks
          else blocks
      normalized = concatMap (normalizeBlock cfg) sorted
   in T.unlines normalized

-- | Show a unified-style diff between original and formatted text.
renderFormatDiff :: Text -> Text -> Text
renderFormatDiff original formatted
  | original == formatted = "No formatting changes needed.\n"
  | otherwise =
      let oldLines = zip [1 :: Int ..] (T.lines original)
          newLines = T.lines formatted
          diffs = computeLineDiffs oldLines newLines
       in if null diffs
            then "No formatting changes needed.\n"
            else T.unlines diffs

------------------------------------------------------------------------
-- Top-level block splitting
------------------------------------------------------------------------

-- | A top-level block: a key line followed by its indented children.
data TopBlock = TopBlock
  { -- | The top-level key name (e.g. "name", "on", "jobs")
    tbKey :: !Text,
    -- | All lines in this block including the key line
    tbLines :: ![Text]
  }
  deriving stock (Eq, Show)

-- | Split YAML lines into top-level blocks.
-- A top-level block starts with a non-indented, non-comment, non-blank line
-- that contains a colon.
splitTopLevelBlocks :: [Text] -> [TopBlock]
splitTopLevelBlocks [] = []
splitTopLevelBlocks ls = go ls []
  where
    go [] acc = reverse acc
    go (x : xs) acc
      | isTopLevelKey x =
          let (children, rest) = span isChildLine xs
              key = T.strip (T.takeWhile (/= ':') x)
           in go rest (TopBlock key (x : children) : acc)
      | otherwise =
          -- Comment or blank line before any block; attach to a pseudo-block
          case acc of
            (b : bs) -> go xs (b {tbLines = tbLines b ++ [x]} : bs)
            [] -> go xs (TopBlock "" [x] : acc)

    isTopLevelKey line =
      not (T.null line)
        && maybe False ((not . isSpace) . fst) (T.uncons line)
        && not ("#" `T.isPrefixOf` T.stripStart line)
        && ":" `T.isInfixOf` line

    isChildLine line =
      T.null line
        || maybe False (isSpace . fst) (T.uncons line)

-- | Sort top-level blocks in canonical GitHub Actions order.
sortBlocks :: [TopBlock] -> [TopBlock]
sortBlocks = sortBy (comparing blockOrder)
  where
    blockOrder :: TopBlock -> Int
    blockOrder b = case T.toLower (tbKey b) of
      "" -> -1 -- preamble / leading comments
      "name" -> 0
      "on" -> 1
      "permissions" -> 2
      "concurrency" -> 3
      "env" -> 4
      "jobs" -> 5
      _ -> 6 -- unknown keys go last

------------------------------------------------------------------------
-- Indentation normalization
------------------------------------------------------------------------

-- | Normalize indentation within a block.
normalizeBlock :: FormatConfig -> TopBlock -> [Text]
normalizeBlock cfg block = map (normalizeIndent cfg) (tbLines block)

-- | Normalize a single line's indentation to the configured width.
normalizeIndent :: FormatConfig -> Text -> Text
normalizeIndent cfg line
  | T.null line = line
  | T.all isSpace line = "" -- blank lines become empty
  | otherwise =
      let (spaces, content) = T.span isSpace line
          currentIndent = T.length spaces
          -- Determine indent level by finding how many "units" of indent.
          -- We try to detect the original indent width (2, 4, etc.)
          -- and remap to the configured width.
          origWidth = detectIndentWidth spaces
          level =
            if origWidth > 0
              then currentIndent `div` origWidth
              else 0
          newIndent = T.replicate (level * fcIndentWidth cfg) " "
       in newIndent <> content

-- | Detect the likely indent width from a span of spaces.
detectIndentWidth :: Text -> Int
detectIndentWidth spaces =
  let len = T.length spaces
   in if len == 0
        then 0
        else
          if len `mod` 4 == 0
            then 4
            else
              if even len
                then 2
                else len -- odd indentation, preserve as-is

------------------------------------------------------------------------
-- Simple line diff
------------------------------------------------------------------------

-- | Compute line-level diffs between numbered old lines and new lines.
computeLineDiffs :: [(Int, Text)] -> [Text] -> [Text]
computeLineDiffs old new =
  let oldTexts = map snd old
      maxLen = max (length oldTexts) (length new)
      padOld = oldTexts ++ replicate (maxLen - length oldTexts) ""
      padNew = new ++ replicate (maxLen - length new) ""
      numbered = zip3 [1 :: Int ..] padOld padNew
   in concatMap
        ( \(n, o, nn) ->
            if o == nn
              then []
              else
                [ " L" <> T.pack (show n) <> ":",
                  "- " <> o,
                  "+ " <> nn
                ]
        )
        numbered
