-- | Tag-based filtering for policy rules.
--
-- Provides parsing of rule tags and filtering rules by tag membership.
module Orchestrator.Tags
  ( parseRuleTag,
    filterByTags,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types (RuleTag (..))

-- | Parse a text string into a 'RuleTag'. Case insensitive.
parseRuleTag :: Text -> Maybe RuleTag
parseRuleTag t = case T.toLower t of
  "security" -> Just TagSecurity
  "performance" -> Just TagPerformance
  "cost" -> Just TagCost
  "style" -> Just TagStyle
  "structure" -> Just TagStructure
  _ -> Nothing

-- | Filter rules to those matching any of the given tags.
-- An empty tag list returns all rules (no filtering).
filterByTags :: [RuleTag] -> [PolicyRule] -> [PolicyRule]
filterByTags [] rules = rules
filterByTags tags rules = filter (any (`elem` tags) . ruleTags) rules
