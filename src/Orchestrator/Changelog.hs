-- | Generate human-readable changelogs from workflow file diffs.
--
-- Compares two parsed workflows and produces structured changelog entries
-- describing what changed between them.
module Orchestrator.Changelog
  ( -- * Types
    ChangeEntry (..),
    ChangeType (..),

    -- * Diffing
    diffWorkflows,

    -- * Rendering
    renderChangelog,
  )
where

import Data.List (nub, sort, (\\))
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model

-- | Type of change detected between two workflows.
data ChangeType
  = Added
  | Removed
  | Modified
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)

-- | A single changelog entry describing one change.
data ChangeEntry = ChangeEntry
  { -- | What kind of change
    ceChangeType :: !ChangeType,
    -- | Human-readable description
    ceDescription :: !Text,
    -- | Workflow file path
    ceFile :: !FilePath
  }
  deriving stock (Eq, Show)

-- | Compare two parsed workflows and produce changelog entries.
--
-- Compares: name, triggers, jobs (additions/removals), steps within
-- matching jobs, permissions, runner specs, and timeout changes.
diffWorkflows :: Workflow -> Workflow -> [ChangeEntry]
diffWorkflows old new =
  let fp = wfFileName new
   in concat
        [ diffName fp old new,
          diffTriggers fp old new,
          diffPermissions fp "Workflow" (wfPermissions old) (wfPermissions new),
          diffJobs fp old new
        ]

-- | Render a list of changelog entries as human-readable text.
renderChangelog :: [ChangeEntry] -> Text
renderChangelog [] = "No changes detected.\n"
renderChangelog entries =
  let header = "Changelog\n" <> T.replicate 40 "-" <> "\n\n"
      grouped =
        [ ("Added", filter (\e -> ceChangeType e == Added) entries),
          ("Removed", filter (\e -> ceChangeType e == Removed) entries),
          ("Modified", filter (\e -> ceChangeType e == Modified) entries)
        ]
      renderGroup (label, es)
        | null es = ""
        | otherwise =
            "### "
              <> label
              <> "\n"
              <> T.unlines (map (\e -> "- " <> ceDescription e) es)
              <> "\n"
   in header <> T.concat (map renderGroup grouped)

------------------------------------------------------------------------
-- Diff helpers
------------------------------------------------------------------------

-- | Diff workflow name.
diffName :: FilePath -> Workflow -> Workflow -> [ChangeEntry]
diffName fp old new
  | wfName old /= wfName new =
      [ ChangeEntry
          Modified
          ("Workflow name changed from '" <> wfName old <> "' to '" <> wfName new <> "'")
          fp
      ]
  | otherwise = []

-- | Diff triggers.
diffTriggers :: FilePath -> Workflow -> Workflow -> [ChangeEntry]
diffTriggers fp old new =
  let oldTrigNames = sort $ nub $ concatMap triggerNames (wfTriggers old)
      newTrigNames = sort $ nub $ concatMap triggerNames (wfTriggers new)
      added = newTrigNames \\ oldTrigNames
      removed = oldTrigNames \\ newTrigNames
   in map (\t -> ChangeEntry Added ("Trigger added: " <> t) fp) added
        ++ map (\t -> ChangeEntry Removed ("Trigger removed: " <> t) fp) removed

-- | Extract trigger event names.
triggerNames :: WorkflowTrigger -> [Text]
triggerNames (TriggerEvents evts) = map triggerName evts
triggerNames (TriggerCron cron) = ["schedule(" <> cron <> ")"]
triggerNames TriggerDispatch = ["workflow_dispatch"]

-- | Diff permissions at workflow or job level.
diffPermissions :: FilePath -> Text -> Maybe Permissions -> Maybe Permissions -> [ChangeEntry]
diffPermissions fp ctx oldP newP
  | oldP == newP = []
  | otherwise = case (oldP, newP) of
      (Nothing, Just _) ->
        [ChangeEntry Added (ctx <> " permissions block added") fp]
      (Just _, Nothing) ->
        [ChangeEntry Removed (ctx <> " permissions block removed") fp]
      (Just _, Just _) ->
        [ChangeEntry Modified (ctx <> " permissions changed") fp]
      _ -> []

-- | Diff jobs: additions, removals, and per-job changes.
diffJobs :: FilePath -> Workflow -> Workflow -> [ChangeEntry]
diffJobs fp old new =
  let oldIds = map jobId (wfJobs old)
      newIds = map jobId (wfJobs new)
      added = newIds \\ oldIds
      removed = oldIds \\ newIds
      common = filter (`elem` oldIds) newIds
      oldMap = Map.fromList [(jobId j, j) | j <- wfJobs old]
      newMap = Map.fromList [(jobId j, j) | j <- wfJobs new]
      addEntries = map (\jid -> ChangeEntry Added ("Job added: " <> jid) fp) added
      remEntries = map (\jid -> ChangeEntry Removed ("Job removed: " <> jid) fp) removed
      modEntries =
        concatMap
          ( \jid ->
              case (Map.lookup jid oldMap, Map.lookup jid newMap) of
                (Just oj, Just nj) -> diffJob fp jid oj nj
                _ -> []
          )
          common
   in addEntries ++ remEntries ++ modEntries

-- | Diff two versions of the same job.
diffJob :: FilePath -> Text -> Job -> Job -> [ChangeEntry]
diffJob fp jid old new =
  concat
    [ diffRunner fp jid (jobRunsOn old) (jobRunsOn new),
      diffTimeout fp jid (jobTimeoutMin old) (jobTimeoutMin new),
      diffPermissions fp ("Job '" <> jid <> "'") (jobPermissions old) (jobPermissions new),
      diffSteps fp jid (jobSteps old) (jobSteps new)
    ]

-- | Diff runner spec for a job.
diffRunner :: FilePath -> Text -> RunnerSpec -> RunnerSpec -> [ChangeEntry]
diffRunner fp jid old new
  | old == new = []
  | otherwise =
      [ ChangeEntry
          Modified
          ( "Job '"
              <> jid
              <> "' runner changed from '"
              <> showRunner old
              <> "' to '"
              <> showRunner new
              <> "'"
          )
          fp
      ]

-- | Diff timeout-minutes for a job.
diffTimeout :: FilePath -> Text -> Maybe Int -> Maybe Int -> [ChangeEntry]
diffTimeout fp jid old new
  | old == new = []
  | otherwise = case (old, new) of
      (Nothing, Just n) ->
        [ ChangeEntry
            Added
            ("Job '" <> jid <> "' timeout-minutes set to " <> T.pack (show n))
            fp
        ]
      (Just _, Nothing) ->
        [ ChangeEntry
            Removed
            ("Job '" <> jid <> "' timeout-minutes removed")
            fp
        ]
      (Just o, Just n) ->
        [ ChangeEntry
            Modified
            ( "Job '"
                <> jid
                <> "' timeout-minutes changed from "
                <> T.pack (show o)
                <> " to "
                <> T.pack (show n)
            )
            fp
        ]
      _ -> []

-- | Diff steps within a job by comparing step counts and names/IDs.
diffSteps :: FilePath -> Text -> [Step] -> [Step] -> [ChangeEntry]
diffSteps fp jid oldSteps newSteps =
  let oldLabels = map stepLabel oldSteps
      newLabels = map stepLabel newSteps
      added = newLabels \\ oldLabels
      removed = oldLabels \\ newLabels
   in map
        ( \l ->
            ChangeEntry
              Added
              ("Job '" <> jid <> "': step added: " <> l)
              fp
        )
        added
        ++ map
          ( \l ->
              ChangeEntry
                Removed
                ("Job '" <> jid <> "': step removed: " <> l)
                fp
          )
          removed

-- | Get a label for a step (prefer id, then name, then uses, then "(unnamed)").
stepLabel :: Step -> Text
stepLabel s = case stepId s of
  Just sid -> sid
  Nothing -> case stepName s of
    Just nm -> nm
    Nothing -> fromMaybe "(unnamed)" (stepUses s)

-- | Show a runner spec as text.
showRunner :: RunnerSpec -> Text
showRunner (StandardRunner t) = t
showRunner (MatrixRunner t) = t
showRunner (CustomLabel t) = t
