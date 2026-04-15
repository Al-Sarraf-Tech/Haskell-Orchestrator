-- | Rules for intra-repo workflow drift detection.
--
-- Detects the same GitHub Action used at different versions
-- within a single workflow file.
module Orchestrator.Rules.Drift
  ( driftVersionRule,
    collectActionVersions,
    parseActionRef,
  )
where

import Data.List (nub, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | Rule DRIFT-001: Detect the same action used at different versions
-- within a single workflow.
driftVersionRule :: PolicyRule
driftVersionRule =
  PolicyRule
    { ruleId = "DRIFT-001",
      ruleName = "Intra-Repo Inconsistency",
      ruleDescription =
        "Detect the same action referenced at different versions within a workflow",
      ruleSeverity = Info,
      ruleCategory = Drift,
      ruleTags = [TagStyle, TagStructure],
      ruleCheck = \wf ->
        let versions = collectActionVersions wf
            drifted = Map.filter (\vs -> length (nub vs) >= 2) versions
         in Map.foldrWithKey
              ( \action vs acc ->
                  let distinct = sort (nub vs)
                      msg =
                        "Action '"
                          <> action
                          <> "' is used at multiple versions: "
                          <> T.intercalate ", " distinct
                          <> ". Pin all uses to the same version."
                      finding =
                        mkFinding'
                          Info
                          Drift
                          "DRIFT-001"
                          msg
                          (wfFileName wf)
                          Nothing
                          ( Just $
                              "Unify all references to '"
                                <> action
                                <> "' on a single pinned version."
                          )
                   in finding : acc
              )
              []
              drifted
    }

-- | Collect a map from \"owner/repo\" to all version strings seen
-- across every step in every job of the workflow.
collectActionVersions :: Workflow -> Map Text [Text]
collectActionVersions wf =
  foldr
    (\(action, ver) m -> Map.insertWith (++) action [ver] m)
    Map.empty
    refs
  where
    allSteps = concatMap jobSteps (wfJobs wf)
    usesRefs = mapMaybe stepUses allSteps
    refs = concatMap parseActionRef usesRefs

-- | Parse an action reference string into a list of (owner\/repo, version)
-- pairs.  Returns an empty list for local actions (@.\/@ prefix) or
-- references that contain no @\@@ separator.
parseActionRef :: Text -> [(Text, Text)]
parseActionRef ref
  | "./" `T.isPrefixOf` ref = []
  | "@" `T.isInfixOf` ref =
      let (action, rest) = T.breakOn "@" ref
          ver = T.drop 1 rest -- drop the '@'
       in [(action, ver) | not (T.null action || T.null ver)]
  | otherwise = []
