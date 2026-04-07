-- | Action version intelligence — tracks action health and resolves versions.
--
-- Catalogs all actions used in a workflow, classifies their health status
-- (pinned, deprecated, outdated), and provides a policy rule for flagging
-- unhealthy actions.
module Orchestrator.Actions.Catalog
  ( -- * Types
    ActionInfo (..)
  , ActionHealth (..)
    -- * Analysis
  , catalogActions
  , checkActionHealth
    -- * Rendering
  , renderActionReport
    -- * Policy rule
  , actionHealthRule
    -- * Internals (for testing)
  , deprecatedActions
  ) where

import Data.Char (isHexDigit)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Information about a single action reference found in a workflow.
data ActionInfo = ActionInfo
  { actionOwner       :: !Text
  , actionName        :: !Text
  , actionCurrentRef  :: !Text
  , actionIsPinned    :: !Bool
  , actionIsFirstParty :: !Bool
  , actionIsDeprecated :: !Bool
  } deriving stock (Eq, Show)

-- | Health status of an action.
data ActionHealth
  = Healthy
  | Outdated
  | Deprecated
  | Unpinned
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)

-- | Known deprecated actions and their recommended replacements.
deprecatedActions :: Map Text Text
deprecatedActions = Map.fromList
  [ ("actions/create-release",   "softprops/action-gh-release")
  , ("actions-rs/toolchain",     "dtolnay/rust-toolchain")
  , ("actions/setup-node@v1",    "actions/setup-node@v4")
  , ("actions/setup-node@v2",    "actions/setup-node@v4")
  ]

-- | Extract all actions used in a workflow as 'ActionInfo' values.
catalogActions :: Workflow -> [ActionInfo]
catalogActions wf =
  [ parseActionRef uses
  | j <- wfJobs wf
  , s <- jobSteps j
  , Just uses <- [stepUses s]
  , not ("./" `T.isPrefixOf` uses)
  , not ("docker://" `T.isPrefixOf` uses)
  ]

-- | Parse an action reference string into an 'ActionInfo'.
parseActionRef :: Text -> ActionInfo
parseActionRef ref =
  let (fullName, afterAt) = T.breakOn "@" ref
      version = if T.null afterAt then "" else T.drop 1 afterAt
      (owner, nameWithSlash) = T.breakOn "/" fullName
      name = if T.null nameWithSlash then owner else T.drop 1 nameWithSlash
      -- For sub-actions like "github/codeql-action/analyze", keep the full path
      pinned = isSHAPinned version
      firstParty' = isFirstPartyAction owner
      deprecated = isDeprecatedAction fullName ref
  in ActionInfo
       { actionOwner        = owner
       , actionName         = name
       , actionCurrentRef   = version
       , actionIsPinned     = pinned
       , actionIsFirstParty = firstParty'
       , actionIsDeprecated = deprecated
       }

-- | Check whether a version string is a 40-char hex SHA.
isSHAPinned :: Text -> Bool
isSHAPinned v = T.length v == 40 && T.all isHexDigit v

-- | Check whether an action owner is a GitHub first-party org.
isFirstPartyAction :: Text -> Bool
isFirstPartyAction owner = owner == "actions" || owner == "github"

-- | Check whether an action is in the deprecated list.
isDeprecatedAction :: Text -> Text -> Bool
isDeprecatedAction fullName fullRef =
  Map.member fullName deprecatedActions
  || Map.member fullRef deprecatedActions

-- | Determine the health status of an action.
checkActionHealth :: ActionInfo -> ActionHealth
checkActionHealth ai
  | actionIsDeprecated ai = Deprecated
  | not (actionIsPinned ai) = Unpinned
  | otherwise = Healthy

-- | Render a formatted report of all actions in a workflow.
renderActionReport :: [ActionInfo] -> Text
renderActionReport [] = "No external actions found.\n"
renderActionReport actions =
  let header = "Action Health Report\n" <> T.replicate 50 "─" <> "\n"
      rows   = map renderActionRow actions
  in header <> T.unlines rows

renderActionRow :: ActionInfo -> Text
renderActionRow ai =
  let health   = checkActionHealth ai
      status   = renderHealth health
      ref      = actionOwner ai <> "/" <> actionName ai <> "@" <> actionCurrentRef ai
      party    = if actionIsFirstParty ai then " [1P]" else ""
  in status <> " " <> ref <> party

renderHealth :: ActionHealth -> Text
renderHealth Healthy    = "[OK]        "
renderHealth Outdated   = "[OUTDATED]  "
renderHealth Deprecated = "[DEPRECATED]"
renderHealth Unpinned   = "[UNPINNED]  "

------------------------------------------------------------------------
-- Policy rule
------------------------------------------------------------------------

-- | Policy rule ACT-001: reports unhealthy actions (deprecated, unpinned).
actionHealthRule :: PolicyRule
actionHealthRule = PolicyRule
  { ruleId          = "ACT-001"
  , ruleName        = "Action Health"
  , ruleDescription = "Detect deprecated, unpinned, or unhealthy action references"
  , ruleSeverity    = Warning
  , ruleCategory    = Security
  , ruleTags        = [TagSecurity]
  , ruleCheck       = \wf ->
      let actions   = catalogActions wf
          unhealthy = filter (\ai -> checkActionHealth ai /= Healthy) actions
      in map (actionToFinding (wfFileName wf)) unhealthy
  }

actionToFinding :: FilePath -> ActionInfo -> Finding
actionToFinding fp ai =
  let health  = checkActionHealth ai
      ref     = actionOwner ai <> "/" <> actionName ai <> "@" <> actionCurrentRef ai
      (msg, rem') = case health of
        Deprecated ->
          let replacement = Map.findWithDefault "a maintained alternative" fullName deprecatedActions
              fullName    = actionOwner ai <> "/" <> actionName ai
          in ( "Action '" <> ref <> "' is deprecated."
             , Just $ "Replace with '" <> replacement <> "'."
             )
        Unpinned ->
          ( "Action '" <> ref <> "' is not pinned to a commit SHA. "
            <> "Tag references can be mutated, posing a supply-chain risk."
          , Just "Pin to a full 40-character commit SHA."
          )
        Outdated ->
          ( "Action '" <> ref <> "' may be outdated."
          , Just "Check for a newer version."
          )
        Healthy ->
          ( "Action '" <> ref <> "' is healthy."
          , Nothing
          )
      sev = case health of
        Deprecated -> Warning
        Unpinned   -> Warning
        Outdated   -> Info
        Healthy    -> Info
  in Finding
       { findingSeverity    = sev
       , findingCategory    = Security
       , findingRuleId      = "ACT-001"
       , findingMessage     = msg
       , findingFile        = fp
       , findingLocation    = Nothing
       , findingRemediation = rem'
       , findingAutoFixable = False
       , findingEffort      = Nothing
       , findingLinks       = []
       }
