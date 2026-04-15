-- | Inline suppression via @# orchestrator:disable@ comments.
--
-- Parses suppression directives from workflow file content and filters
-- findings accordingly.  This module does not modify any files.
module Orchestrator.Suppress
  ( parseSuppressedRules,
    applySuppression,
  )
where

import Data.List (foldl')
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Types (Finding (..))

-- | Parse @# orchestrator:disable RULE-ID@ directives from raw file content.
--
-- The directive keyword is matched case-insensitively, but the rule ID
-- is preserved in its original case.  Extra whitespace around the
-- directive and rule ID is tolerated.
parseSuppressedRules :: Text -> Set Text
parseSuppressedRules = foldl' collectDirectives Set.empty . T.lines
  where
    collectDirectives :: Set Text -> Text -> Set Text
    collectDirectives acc line =
      let stripped = T.strip line
       in case T.stripPrefix "#" stripped of
            Nothing -> acc
            Just rest ->
              let body = T.strip rest
                  lower = T.toLower body
               in case T.stripPrefix "orchestrator:disable" lower of
                    Nothing -> acc
                    Just _afterDirective ->
                      -- Use the original text to preserve rule ID case.
                      -- The directive is 20 chars ("orchestrator:disable").
                      let original = T.drop 20 body
                          ruleId' = T.strip original
                       in if T.null ruleId'
                            then acc
                            else Set.insert ruleId' acc

-- | Filter findings by removing those whose rule ID is in the suppressed set.
-- An empty suppression set returns all findings unchanged.
applySuppression :: Set Text -> [Finding] -> [Finding]
applySuppression suppressed
  | Set.null suppressed = id
  | otherwise = filter (\f -> not (Set.member (findingRuleId f) suppressed))
