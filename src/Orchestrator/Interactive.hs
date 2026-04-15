-- | Interactive rule picker for terminal-based rule selection.
--
-- Uses only standard terminal I/O — no external TUI libraries required.
module Orchestrator.Interactive
  ( interactiveRulePicker,
    interactiveRuleFilter,
    renderRuleMenu,
  )
where

import Data.Char (isDigit, toLower)
import Data.List (intercalate, nub, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Orchestrator.Policy (PolicyPack (..), PolicyRule (..))
import Orchestrator.Types (RuleTag (..), Severity (..))
import System.IO (hFlush, stdout)

-- | Display a numbered rule menu and let the user select a subset.
-- Returns a 'PolicyPack' containing only the selected rules.
interactiveRulePicker :: PolicyPack -> IO PolicyPack
interactiveRulePicker pack = do
  TIO.putStrLn (renderRuleMenu pack)
  TIO.putStr "Select rules (comma-separated numbers, 'all', or 'q' to quit): "
  hFlush stdout
  input <- getLine
  let trimmed = map (\c -> if c == ' ' then ' ' else c) input
  case map (map toLower) (words trimmed) of
    ["q"] -> pure pack {packRules = []}
    ["all"] -> do
      let n = length (packRules pack)
      TIO.putStrLn $ "Selected " <> T.pack (show n) <> " rules."
      pure pack
    _ -> do
      let indices = parseIndices trimmed
          rules = packRules pack
          selected =
            [ r
            | i <- indices,
              i >= 1,
              i <= length rules,
              let r = rules !! (i - 1)
            ]
          unique = nubRules selected
      TIO.putStrLn $ "Selected " <> T.pack (show (length unique)) <> " rules."
      pure pack {packRules = unique}

-- | Interactive filter by tag or severity.
-- Prompts user, then returns a filtered 'PolicyPack'.
interactiveRuleFilter :: PolicyPack -> IO PolicyPack
interactiveRuleFilter pack = do
  TIO.putStr "Filter by: (t)ag, (s)everity, (a)ll: "
  hFlush stdout
  choice <- getLine
  case map toLower (strip choice) of
    "t" -> filterByTagInteractive pack
    "s" -> filterBySeverityInteractive pack
    "a" -> pure pack
    _ -> do
      TIO.putStrLn "Unrecognised choice. Returning all rules."
      pure pack

-- | Pure renderer: produces the numbered menu text for a policy pack.
renderRuleMenu :: PolicyPack -> Text
renderRuleMenu pack =
  let rules = packRules pack
      header = "Available rules:"
      rows = zipWith renderRow [1 :: Int ..] rules
   in T.unlines (header : rows)

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

renderRow :: Int -> PolicyRule -> Text
renderRow i r =
  let idx = padLeft 4 (T.pack (show i) <> ".")
      rid = "[" <> ruleId r <> "]"
      nm = T.take 32 (ruleName r)
      sev = T.pack (showSev (ruleSeverity r))
      tags = T.intercalate "," (map showTag (ruleTags r))
      meta = "(" <> sev <> if T.null tags then ")" else ", " <> tags <> ")"
   in idx <> " " <> padRight 12 rid <> " " <> padRight 34 nm <> " " <> meta

filterByTagInteractive :: PolicyPack -> IO PolicyPack
filterByTagInteractive pack = do
  let allTags = sort . nub . concatMap ruleTags $ packRules pack
  TIO.putStrLn "Available tags:"
  mapM_
    ( \(i, t) ->
        TIO.putStrLn $ "  " <> T.pack (show (i :: Int)) <> ". " <> showTag t
    )
    (zip [1 ..] allTags)
  TIO.putStr "Enter tag number: "
  hFlush stdout
  input <- getLine
  case parseIndex (strip input) of
    Just i
      | i >= 1,
        i <= length allTags -> do
          let tag = allTags !! (i - 1)
              filtered = filter (elem tag . ruleTags) (packRules pack)
          TIO.putStrLn $ "Filtered to " <> T.pack (show (length filtered)) <> " rules."
          pure pack {packRules = filtered}
    _ -> do
      TIO.putStrLn "Invalid selection. Returning all rules."
      pure pack

filterBySeverityInteractive :: PolicyPack -> IO PolicyPack
filterBySeverityInteractive pack = do
  TIO.putStrLn "Severity levels (minimum):"
  TIO.putStrLn "  1. Info"
  TIO.putStrLn "  2. Warning"
  TIO.putStrLn "  3. Error"
  TIO.putStrLn "  4. Critical"
  TIO.putStr "Enter severity number: "
  hFlush stdout
  input <- getLine
  let sev = case strip input of
        "1" -> Just Info
        "2" -> Just Warning
        "3" -> Just Error
        "4" -> Just Critical
        _ -> Nothing
  case sev of
    Nothing -> do
      TIO.putStrLn "Invalid selection. Returning all rules."
      pure pack
    Just minSev -> do
      let filtered = filter (\r -> ruleSeverity r >= minSev) (packRules pack)
      TIO.putStrLn $ "Filtered to " <> T.pack (show (length filtered)) <> " rules."
      pure pack {packRules = filtered}

-- | Parse a comma-separated list of integers from user input.
parseIndices :: String -> [Int]
parseIndices s =
  [ n
  | part <- splitOn ',' s,
    let t = strip part,
    not (null t),
    all isDigit t,
    let n = read t :: Int
  ]

parseIndex :: String -> Maybe Int
parseIndex s
  | not (null s) && all isDigit s = Just (read s :: Int)
  | otherwise = Nothing

splitOn :: Char -> String -> [String]
splitOn _ [] = [""]
splitOn c (x : xs)
  | x == c = "" : rest
  | otherwise = (x : head rest) : tail rest
  where
    rest = splitOn c xs

strip :: String -> String
strip = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')

-- | Deduplicate rules, preserving order.
nubRules :: [PolicyRule] -> [PolicyRule]
nubRules = go []
  where
    go _ [] = []
    go seen (r : rs)
      | ruleId r `elem` seen = go seen rs
      | otherwise = r : go (ruleId r : seen) rs

padLeft :: Int -> Text -> Text
padLeft n t = T.replicate (max 0 (n - T.length t)) " " <> t

padRight :: Int -> Text -> Text
padRight n t = T.take n (t <> T.replicate n " ")

showSev :: Severity -> String
showSev Info = "Info"
showSev Warning = "Warning"
showSev Error = "Error"
showSev Critical = "Critical"

showTag :: RuleTag -> Text
showTag TagSecurity = "security"
showTag TagPerformance = "performance"
showTag TagCost = "cost"
showTag TagStyle = "style"
showTag TagStructure = "structure"

-- Suppress unused-import warning — intercalate used via show in renderRow
_useIntercalate :: [String] -> String
_useIntercalate = intercalate ","
