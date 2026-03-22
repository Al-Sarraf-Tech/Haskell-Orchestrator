-- | Typed domain model for GitHub Actions workflows.
--
-- This module defines the Haskell representation of GitHub Actions workflow
-- YAML files.  The model is designed to capture the semantically meaningful
-- parts of a workflow for validation and policy checking.
module Orchestrator.Model
  ( Workflow (..)
  , WorkflowTrigger (..)
  , TriggerEvent (..)
  , Job (..)
  , Step (..)
  , Permissions (..)
  , PermissionLevel (..)
  , ConcurrencyConfig (..)
  , RunnerSpec (..)
  , EnvMap
  ) where

import Data.Map.Strict (Map)
import Data.Text (Text)

-- | Environment variable map.
type EnvMap = Map Text Text

-- | Permission level for a single scope.
data PermissionLevel
  = PermNone
  | PermRead
  | PermWrite
  deriving stock (Eq, Ord, Show, Read)

-- | Workflow-level or job-level permissions block.
data Permissions
  = PermissionsAll !PermissionLevel
  | PermissionsMap !(Map Text PermissionLevel)
  deriving stock (Eq, Show)

-- | Concurrency configuration.
data ConcurrencyConfig = ConcurrencyConfig
  { concGroup            :: !Text
  , concCancelInProgress :: !Bool
  } deriving stock (Eq, Show)

-- | Runner specification.
data RunnerSpec
  = StandardRunner !Text        -- e.g. "ubuntu-latest"
  | MatrixRunner !Text          -- e.g. "${{ matrix.os }}"
  | CustomLabel !Text           -- arbitrary label
  deriving stock (Eq, Show)

-- | A trigger event (e.g. push, pull_request).
data TriggerEvent = TriggerEvent
  { triggerName     :: !Text
  , triggerBranches :: ![Text]
  , triggerPaths    :: ![Text]
  , triggerTags     :: ![Text]
  } deriving stock (Eq, Show)

-- | Workflow trigger configuration.
data WorkflowTrigger
  = TriggerEvents ![TriggerEvent]
  | TriggerCron !Text
  | TriggerDispatch
  deriving stock (Eq, Show)

-- | A single step in a job.
data Step = Step
  { stepId    :: !(Maybe Text)
  , stepName  :: !(Maybe Text)
  , stepUses  :: !(Maybe Text)
  , stepRun   :: !(Maybe Text)
  , stepWith  :: !EnvMap
  , stepEnv   :: !EnvMap
  , stepIf    :: !(Maybe Text)
  } deriving stock (Eq, Show)

-- | A job within a workflow.
data Job = Job
  { jobId           :: !Text
  , jobName         :: !(Maybe Text)
  , jobRunsOn       :: !RunnerSpec
  , jobSteps        :: ![Step]
  , jobPermissions  :: !(Maybe Permissions)
  , jobNeeds        :: ![Text]
  , jobConcurrency  :: !(Maybe ConcurrencyConfig)
  , jobEnv          :: !EnvMap
  , jobIf           :: !(Maybe Text)
  , jobTimeoutMin   :: !(Maybe Int)
  , jobFailFast     :: !(Maybe Bool)
  , jobMatrixIncludeOnly :: !Bool
  } deriving stock (Eq, Show)

-- | A complete GitHub Actions workflow.
data Workflow = Workflow
  { wfName         :: !Text
  , wfFileName     :: !FilePath
  , wfTriggers     :: ![WorkflowTrigger]
  , wfJobs         :: ![Job]
  , wfPermissions  :: !(Maybe Permissions)
  , wfConcurrency  :: !(Maybe ConcurrencyConfig)
  , wfEnv          :: !EnvMap
  } deriving stock (Eq, Show)
