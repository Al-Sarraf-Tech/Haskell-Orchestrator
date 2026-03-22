-- | Workflow simulation / dry-run engine.
--
-- Predicts what a workflow will do without running it: expands matrix
-- combinations, evaluates if-conditions against mock contexts, traces
-- the execution DAG, and estimates duration and cost.
--
-- No other GitHub Actions tool can do this.
module Orchestrator.Simulate
  ( -- * Re-exports from Types
    module Orchestrator.Simulate.Types
    -- * Simulation
  , simulateWorkflow
    -- * Rendering
  , renderSimulation
  ) where

import Data.List (foldl')
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Simulate.Conditions (evaluateCondition)
import Orchestrator.Simulate.Matrix (expandMatrix)
import Orchestrator.Simulate.Types

-- | Simulate a workflow execution against a mock context.
simulateWorkflow :: SimContext -> Workflow -> SimulationResult
simulateWorkflow ctx wf =
  let triggered = workflowTriggered ctx (wfTriggers wf)
      expandedJobs = if triggered
        then concatMap (expandJob ctx) (wfJobs wf)
        else map (skipJob "Workflow not triggered for this event") (wfJobs wf)
      resolvedJobs = resolveDependencies expandedJobs
      running = length [() | j <- resolvedJobs, isRunning (sjStatus j)]
      skipped = length [() | j <- resolvedJobs, isSkipped (sjStatus j)]
      estDuration = estimateCriticalPath resolvedJobs
      cost = estimateCost resolvedJobs
  in SimulationResult
       { simWorkflow = wfName wf
       , simFile = wfFileName wf
       , simContext = ctx
       , simJobs = resolvedJobs
       , simTotalJobs = length resolvedJobs
       , simRunningJobs = running
       , simSkippedJobs = skipped
       , simEstDuration = estDuration
       , simCost = cost
       }

workflowTriggered :: SimContext -> [WorkflowTrigger] -> Bool
workflowTriggered ctx triggers = any (triggerMatches ctx) triggers

triggerMatches :: SimContext -> WorkflowTrigger -> Bool
triggerMatches ctx (TriggerEvents evts) =
  any (\e -> triggerName e == ctxEventName ctx
        && branchMatches (ctxBranch ctx) (triggerBranches e)) evts
triggerMatches _ (TriggerCron _) = True
triggerMatches ctx TriggerDispatch = ctxEventName ctx == "workflow_dispatch"

branchMatches :: Text -> [Text] -> Bool
branchMatches _ [] = True
branchMatches branch filters = any (matchBranch branch) filters
  where
    matchBranch b pat
      | "**" `T.isInfixOf` pat = True
      | "*" `T.isSuffixOf` pat = T.init pat `T.isPrefixOf` b
      | otherwise = b == pat

expandJob :: SimContext -> Job -> [SimulatedJob]
expandJob ctx j =
  let runner = renderRunner (jobRunsOn j)
      jobCond = case jobIf j of
        Nothing -> WillRun
        Just cond -> evaluateCondition ctx cond
      matrixCombinations = expandMatrix j
      steps = map (simulateStep ctx) (jobSteps j)
      estMins = estimateJobDuration j
  in if null matrixCombinations
     then [ SimulatedJob
              { sjJobId = jobId j, sjName = jobName j, sjRunner = runner
              , sjStatus = jobCond, sjSteps = steps, sjMatrixKey = Nothing
              , sjNeeds = jobNeeds j, sjEstMins = estMins } ]
     else map (\(key, _vals) ->
            SimulatedJob
              { sjJobId = jobId j <> " [" <> key <> "]"
              , sjName = fmap (<> " (" <> key <> ")") (jobName j)
              , sjRunner = runner, sjStatus = jobCond, sjSteps = steps
              , sjMatrixKey = Just key, sjNeeds = jobNeeds j
              , sjEstMins = estMins }
          ) matrixCombinations

simulateStep :: SimContext -> Step -> SimulatedStep
simulateStep ctx s =
  let status = case stepIf s of
        Nothing -> WillRun
        Just cond -> evaluateCondition ctx cond
      name = case stepName s of
        Just n  -> n
        Nothing -> case stepUses s of
          Just u  -> "Action: " <> u
          Nothing -> case stepRun s of
            Just r  -> "Run: " <> T.take 50 r
            Nothing -> "(unnamed step)"
  in SimulatedStep
       { ssName = name, ssAction = stepUses s
       , ssCommand = fmap (T.take 80) (stepRun s), ssStatus = status }

skipJob :: Text -> Job -> SimulatedJob
skipJob reason j = SimulatedJob
  { sjJobId = jobId j, sjName = jobName j
  , sjRunner = renderRunner (jobRunsOn j), sjStatus = WillSkip reason
  , sjSteps = [], sjMatrixKey = Nothing
  , sjNeeds = jobNeeds j, sjEstMins = 0 }

resolveDependencies :: [SimulatedJob] -> [SimulatedJob]
resolveDependencies jobs =
  let statusMap = Map.fromList [(sjJobId j, sjStatus j) | j <- jobs]
      resolve j =
        let blockers = [ n | n <- sjNeeds j
                       , case Map.findWithDefault WillRun n statusMap of
                           WillSkip _ -> True; Blocked _ -> True; _ -> False ]
        in if null blockers
           then j
           else j { sjStatus = Blocked $ "Blocked by: " <> T.intercalate ", " blockers }
  in map resolve jobs

estimateJobDuration :: Job -> Int
estimateJobDuration j =
  let stepCount = length (jobSteps j)
      hasDocker = any (\s -> maybe False ("docker://" `T.isPrefixOf`) (stepUses s)) (jobSteps j)
      baseMins = case jobTimeoutMin j of
        Just t  -> min t (stepCount * 2 + 1)
        Nothing -> stepCount * 2 + 1
  in if hasDocker then baseMins + 3 else baseMins

estimateCriticalPath :: [SimulatedJob] -> Int
estimateCriticalPath jobs =
  let running = filter (isRunning . sjStatus) jobs
  in if null running then 0 else maximum (map sjEstMins running)

estimateCost :: [SimulatedJob] -> CostEstimate
estimateCost jobs =
  let running = filter (isRunning . sjStatus) jobs
      (linux, macos, windows) = foldl' classify (0, 0, 0) running
  in CostEstimate linux macos windows
       (fromIntegral linux * 0.008 + fromIntegral macos * 0.08 + fromIntegral windows * 0.016)
  where
    classify (l, m, w) j
      | "macos" `T.isInfixOf` sjRunner j = (l, m + sjEstMins j, w)
      | "windows" `T.isInfixOf` sjRunner j = (l, m, w + sjEstMins j)
      | otherwise = (l + sjEstMins j, m, w)

-- | Render simulation results as human-readable text.
renderSimulation :: SimulationResult -> Text
renderSimulation sim = T.unlines $
  [ "Workflow Simulation"
  , T.replicate 60 "═"
  , "Workflow:  " <> simWorkflow sim
  , "File:      " <> T.pack (simFile sim)
  , "Event:     " <> ctxEventName (simContext sim)
  , "Branch:    " <> ctxBranch (simContext sim)
  , ""
  , "Prediction:"
  , "  Total jobs:    " <> showT (simTotalJobs sim)
  , "  Will run:      " <> showT (simRunningJobs sim)
  , "  Will skip:     " <> showT (simSkippedJobs sim)
  , "  Est. duration: ~" <> showT (simEstDuration sim) <> " minutes"
  , "  Est. cost:     $" <> T.pack (show (ceCostUSD (simCost sim)))
  , ""
  , T.replicate 60 "─"
  , "Job Execution Trace:"
  , ""
  ] ++ concatMap renderJob (simJobs sim) ++
  [ T.replicate 60 "═" ]
  where
    showT :: Show a => a -> Text
    showT = T.pack . show
    renderJob j =
      [ statusIcon (sjStatus j) <> " " <> sjJobId j
          <> maybe "" (\n -> " — " <> n) (sjName j)
      , "    Runner: " <> sjRunner j
      , "    Status: " <> renderStatus (sjStatus j)
      ] ++ if isRunning (sjStatus j)
           then map (\s -> "    " <> statusIcon (ssStatus s) <> " " <> ssName s)
                    (sjSteps j) ++ [""]
           else [""]
    statusIcon WillRun = "●"
    statusIcon (WillSkip _) = "○"
    statusIcon (Conditional _) = "◐"
    statusIcon (Blocked _) = "✕"
    renderStatus WillRun = "WILL RUN"
    renderStatus (WillSkip r) = "SKIP: " <> r
    renderStatus (Conditional c) = "CONDITIONAL: " <> c
    renderStatus (Blocked r) = "BLOCKED: " <> r
