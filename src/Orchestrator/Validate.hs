-- | Structural validation for parsed workflows.
--
-- Checks for structural issues that go beyond policy (e.g., empty jobs,
-- unreferenced needs, duplicate IDs).
module Orchestrator.Validate
  ( validateWorkflow
  , validateWorkflows
  , ValidationResult (..)
  ) where

import Data.List (group, sort)
import Data.Text (Text)
import Orchestrator.Model
import Orchestrator.Types

-- | Result of structural validation.
data ValidationResult = ValidationResult
  { vrWorkflow :: !Text
  , vrFindings :: ![Finding]
  , vrValid    :: !Bool
  } deriving stock (Show)

-- | Validate a single workflow for structural issues.
validateWorkflow :: Workflow -> ValidationResult
validateWorkflow wf =
  let findings = concat
        [ checkEmptyJobs wf
        , checkDuplicateJobIds wf
        , checkDanglingNeeds wf
        , checkEmptySteps wf
        , checkMissingTriggers wf
        ]
      hasErrors = any (\f -> findingSeverity f >= Error) findings
  in ValidationResult
       { vrWorkflow = wfName wf
       , vrFindings = findings
       , vrValid = not hasErrors
       }

-- | Validate multiple workflows.
validateWorkflows :: [Workflow] -> [ValidationResult]
validateWorkflows = map validateWorkflow

mkValFinding :: Severity -> Text -> Text -> FilePath -> Finding
mkValFinding sev rid msg fp = Finding
  { findingSeverity = sev
  , findingCategory = Structure
  , findingRuleId = rid
  , findingMessage = msg
  , findingFile = fp
  , findingLocation = Nothing
  , findingRemediation = Nothing
  }

checkEmptyJobs :: Workflow -> [Finding]
checkEmptyJobs wf
  | null (wfJobs wf) =
      [ mkValFinding Error "VAL-001" "Workflow has no jobs defined." (wfFileName wf) ]
  | otherwise = []

checkDuplicateJobIds :: Workflow -> [Finding]
checkDuplicateJobIds wf =
  let ids = map jobId (wfJobs wf)
      dupes = [head g | g <- group (sort ids), length g > 1]
  in map (\d -> mkValFinding Error "VAL-002"
            ("Duplicate job ID: " <> d) (wfFileName wf)) dupes

checkDanglingNeeds :: Workflow -> [Finding]
checkDanglingNeeds wf =
  let ids = map jobId (wfJobs wf)
      allNeeds = concatMap (\j -> [(jobId j, n) | n <- jobNeeds j]) (wfJobs wf)
      dangling = filter (\(_, n) -> n `notElem` ids) allNeeds
  in map (\(jid, n) -> mkValFinding Error "VAL-003"
            ("Job '" <> jid <> "' needs '" <> n <> "' which does not exist.")
            (wfFileName wf)) dangling

checkEmptySteps :: Workflow -> [Finding]
checkEmptySteps wf =
  concatMap (\j ->
    if null (jobSteps j)
    then [ mkValFinding Warning "VAL-004"
             ("Job '" <> jobId j <> "' has no steps.") (wfFileName wf) ]
    else concatMap (\s ->
      case (stepUses s, stepRun s) of
        (Nothing, Nothing) ->
          [ mkValFinding Warning "VAL-005"
              ("Step in job '" <> jobId j <> "' has neither 'uses' nor 'run'.")
              (wfFileName wf) ]
        _ -> []
      ) (jobSteps j)
  ) (wfJobs wf)

checkMissingTriggers :: Workflow -> [Finding]
checkMissingTriggers wf
  | null (wfTriggers wf) =
      [ mkValFinding Error "VAL-006"
          ("Workflow '" <> wfName wf <> "' has no triggers defined.") (wfFileName wf) ]
  | otherwise = []
