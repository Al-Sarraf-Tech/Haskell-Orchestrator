-- | Types for the workflow simulation engine.
module Orchestrator.Simulate.Types
  ( SimContext (..),
    JobStatus (..),
    CostEstimate (..),
    SimulatedStep (..),
    SimulatedJob (..),
    SimulationResult (..),
    defaultContext,
    isRunning,
    isSkipped,
    renderRunner,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Orchestrator.Model (RunnerSpec (..))

-- | Mock GitHub context for simulation.
data SimContext = SimContext
  { ctxEventName :: !Text,
    ctxRef :: !Text,
    ctxBranch :: !Text,
    ctxActor :: !Text,
    ctxRepository :: !Text,
    ctxVars :: !(Map Text Text)
  }
  deriving stock (Eq, Show)

-- | Default simulation context (push to main).
defaultContext :: SimContext
defaultContext =
  SimContext
    { ctxEventName = "push",
      ctxRef = "refs/heads/main",
      ctxBranch = "main",
      ctxActor = "developer",
      ctxRepository = "owner/repo",
      ctxVars = Map.empty
    }

-- | Predicted status of a simulated job.
data JobStatus
  = WillRun
  | WillSkip !Text
  | Conditional !Text
  | Blocked !Text
  deriving stock (Eq, Show)

-- | Cost estimate for a workflow run.
data CostEstimate = CostEstimate
  { ceMinutesLinux :: !Int,
    ceMinutesMacOS :: !Int,
    ceMinutesWindows :: !Int,
    ceCostUSD :: !Double
  }
  deriving stock (Eq, Show)

-- | A simulated step within a job.
data SimulatedStep = SimulatedStep
  { ssName :: !Text,
    ssAction :: !(Maybe Text),
    ssCommand :: !(Maybe Text),
    ssStatus :: !JobStatus
  }
  deriving stock (Eq, Show)

-- | A simulated job (may appear multiple times if matrix-expanded).
data SimulatedJob = SimulatedJob
  { sjJobId :: !Text,
    sjName :: !(Maybe Text),
    sjRunner :: !Text,
    sjStatus :: !JobStatus,
    sjSteps :: ![SimulatedStep],
    sjMatrixKey :: !(Maybe Text),
    sjNeeds :: ![Text],
    sjEstMins :: !Int
  }
  deriving stock (Eq, Show)

-- | Complete simulation result for a workflow.
data SimulationResult = SimulationResult
  { simWorkflow :: !Text,
    simFile :: !FilePath,
    simContext :: !SimContext,
    simJobs :: ![SimulatedJob],
    simTotalJobs :: !Int,
    simRunningJobs :: !Int,
    simSkippedJobs :: !Int,
    simEstDuration :: !Int,
    simCost :: !CostEstimate
  }
  deriving stock (Eq, Show)

isRunning :: JobStatus -> Bool
isRunning WillRun = True
isRunning _ = False

isSkipped :: JobStatus -> Bool
isSkipped (WillSkip _) = True
isSkipped (Blocked _) = True
isSkipped _ = False

renderRunner :: RunnerSpec -> Text
renderRunner (StandardRunner t) = t
renderRunner (MatrixRunner t) = t
renderRunner (CustomLabel t) = t
