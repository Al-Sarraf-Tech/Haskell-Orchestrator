-- | Compute minimum required permissions a workflow actually needs.
--
-- Analyzes which actions a workflow uses and maps them to the permissions
-- those actions require, producing a side-by-side comparison of declared
-- vs. minimum permissions.
module Orchestrator.Permissions.Minimum
  ( -- * Types
    PermissionAnalysis (..)
    -- * Analysis
  , analyzePermissions
    -- * Rendering
  , renderPermissionAnalysis
    -- * Policy rule
  , permissionsMinimumRule
    -- * Internals (for testing)
  , actionPermissionCatalog
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Result of permission analysis for a workflow.
data PermissionAnalysis = PermissionAnalysis
  { currentPerms :: !(Maybe Permissions)
  , minimumPerms :: !(Map Text PermissionLevel)
  , excessPerms  :: !(Map Text PermissionLevel)
  } deriving stock (Eq, Show)

-- | Built-in catalog mapping action prefixes to their required permissions.
--
-- Each entry maps an action name (without version) to a list of
-- @(scope, level)@ pairs.
actionPermissionCatalog :: Map Text [(Text, PermissionLevel)]
actionPermissionCatalog = Map.fromList
  [ ("actions/checkout",             [("contents", PermRead)])
  , ("actions/upload-artifact",      [("actions", PermWrite)])
  , ("actions/download-artifact",    [("actions", PermRead)])
  , ("actions/create-release",       [("contents", PermWrite)])
  , ("actions/cache",                [("actions", PermRead)])
  , ("actions/deploy-pages",         [("pages", PermWrite), ("id-token", PermWrite)])
  , ("peter-evans/create-pull-request",
      [("pull-requests", PermWrite), ("contents", PermWrite)])
  , ("github/codeql-action",         [("security-events", PermWrite)])
  ]

-- | Analyze a workflow to determine its minimum required permissions.
analyzePermissions :: Workflow -> PermissionAnalysis
analyzePermissions wf =
  let allSteps   = concatMap jobSteps (wfJobs wf)
      usedActions = [ uses | s <- allSteps, Just uses <- [stepUses s] ]
      required   = foldr (mergePerms . lookupRequired) Map.empty usedActions
      declared   = extractDeclared (wfPermissions wf)
      excess     = computeExcess declared required
  in PermissionAnalysis
       { currentPerms = wfPermissions wf
       , minimumPerms = required
       , excessPerms  = excess
       }

-- | Look up the required permissions for a single action reference.
lookupRequired :: Text -> [(Text, PermissionLevel)]
lookupRequired ref =
  let actionName = T.takeWhile (/= '@') ref
      -- Try exact match first, then prefix match for org-level entries
      -- (e.g. "github/codeql-action/analyze" matches "github/codeql-action")
  in case Map.lookup actionName actionPermissionCatalog of
       Just perms -> perms
       Nothing    ->
         let matches = Map.filterWithKey (\k _ -> k `T.isPrefixOf` actionName) actionPermissionCatalog
         in case Map.elems matches of
              (perms : _) -> perms
              []          -> []

-- | Merge a list of @(scope, level)@ pairs into an accumulator map,
-- keeping the highest permission level for each scope.
mergePerms :: [(Text, PermissionLevel)] -> Map Text PermissionLevel -> Map Text PermissionLevel
mergePerms pairs acc = foldl (\m (scope, lvl) -> Map.insertWith max scope lvl m) acc pairs

-- | Extract declared permissions as a flat map.
extractDeclared :: Maybe Permissions -> Map Text PermissionLevel
extractDeclared Nothing = Map.empty
extractDeclared (Just (PermissionsAll lvl)) =
  -- 'write-all' or 'read-all' grants every scope at that level.
  -- We represent this as a special marker; excess computation handles it.
  Map.singleton "*" lvl
extractDeclared (Just (PermissionsMap m)) = m

-- | Compute which declared permissions exceed the minimum requirements.
computeExcess :: Map Text PermissionLevel -> Map Text PermissionLevel -> Map Text PermissionLevel
computeExcess declared required
  -- If 'write-all' is declared, every required scope at a lower level is excess
  | Just lvl <- Map.lookup "*" declared =
      if lvl > maximum (PermNone : Map.elems required)
        then Map.singleton "*" lvl
        else Map.empty
  | otherwise =
      Map.differenceWith excessLevel declared required
  where
    excessLevel :: PermissionLevel -> PermissionLevel -> Maybe PermissionLevel
    excessLevel decl req
      | decl > req = Just decl
      | otherwise  = Nothing

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

-- | Render a human-readable side-by-side permission comparison.
renderPermissionAnalysis :: PermissionAnalysis -> Text
renderPermissionAnalysis pa =
  let header  = "Permission Analysis\n" <> T.replicate 40 "─" <> "\n"
      current = "Declared: " <> renderPerms (currentPerms pa) <> "\n"
      minReq  = "Minimum:  " <> renderPermMap (minimumPerms pa) <> "\n"
      excess' = if Map.null (excessPerms pa)
                then "Excess:   (none)\n"
                else "Excess:   " <> renderPermMap (excessPerms pa) <> "\n"
  in header <> current <> minReq <> excess'

renderPerms :: Maybe Permissions -> Text
renderPerms Nothing = "(not declared)"
renderPerms (Just (PermissionsAll lvl)) = showLevel lvl <> "-all"
renderPerms (Just (PermissionsMap m)) = renderPermMap m

renderPermMap :: Map Text PermissionLevel -> Text
renderPermMap m
  | Map.null m = "(none)"
  | otherwise  = T.intercalate ", " $ map renderEntry (Map.toAscList m)
  where
    renderEntry (scope, lvl) = scope <> ": " <> showLevel lvl

showLevel :: PermissionLevel -> Text
showLevel PermNone  = "none"
showLevel PermRead  = "read"
showLevel PermWrite = "write"

------------------------------------------------------------------------
-- Policy rule
------------------------------------------------------------------------

-- | Policy rule PERM-003: flags when declared permissions exceed the minimum
-- required by the actions used.
permissionsMinimumRule :: PolicyRule
permissionsMinimumRule = PolicyRule
  { ruleId          = "PERM-003"
  , ruleName        = "Excess Permissions"
  , ruleDescription = "Declared permissions exceed the minimum required by actions used"
  , ruleSeverity    = Warning
  , ruleCategory    = Permissions
  , ruleTags        = [TagSecurity]
  , ruleCheck       = \wf ->
      let pa = analyzePermissions wf
      in [ Finding
                  { findingSeverity    = Warning
                  , findingCategory    = Permissions
                  , findingRuleId      = "PERM-003"
                  , findingMessage     =
                      "Workflow declares permissions beyond what its actions require. "
                      <> "Excess: " <> renderPermMap (excessPerms pa) <> "."
                  , findingFile        = wfFileName wf
                  , findingLocation    = Nothing
                  , findingRemediation = Just $
                      "Reduce permissions to the minimum: "
                      <> renderPermMap (minimumPerms pa) <> "."
                  , findingAutoFixable = False
                  , findingEffort      = Nothing
                  , findingLinks       = []
                  }
              | not (Map.null (excessPerms pa))
              ]
  }
