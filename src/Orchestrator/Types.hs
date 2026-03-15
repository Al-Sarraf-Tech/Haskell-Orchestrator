-- | Core types shared across all Orchestrator modules.
module Orchestrator.Types
  ( Severity (..)
  , Finding (..)
  , FindingCategory (..)
  , ScanTarget (..)
  , ScanResult (..)
  , RemediationStep (..)
  , Plan (..)
  , OrchestratorError (..)
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)

-- | Severity of a policy finding.
data Severity
  = Info
  | Warning
  | Error
  | Critical
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)

-- | Category of a finding for grouping and filtering.
data FindingCategory
  = Permissions
  | Runners
  | Triggers
  | Naming
  | Concurrency
  | Security
  | Structure
  | Duplication
  | Drift
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)

-- | A single finding from policy validation.
data Finding = Finding
  { findingSeverity    :: !Severity
  , findingCategory    :: !FindingCategory
  , findingRuleId      :: !Text
  , findingMessage     :: !Text
  , findingFile        :: !FilePath
  , findingLocation    :: !(Maybe Text)
  , findingRemediation :: !(Maybe Text)
  } deriving stock (Eq, Show)

-- | What to scan.
data ScanTarget
  = LocalPath !FilePath
  | GitHubRepo !Text !Text   -- owner, repo
  | GitHubOrg !Text           -- organization
  deriving stock (Eq, Show)

-- | Result of scanning a target.
data ScanResult = ScanResult
  { scanTarget   :: !ScanTarget
  , scanFindings :: ![Finding]
  , scanFiles    :: ![FilePath]
  , scanTime     :: !(Maybe UTCTime)
  } deriving stock (Show)

-- | A single remediation step.
data RemediationStep = RemediationStep
  { remStepOrder       :: !Int
  , remStepDescription :: !Text
  , remStepFile        :: !FilePath
  , remStepDiff        :: !(Maybe Text)
  } deriving stock (Eq, Show)

-- | A complete remediation plan.
data Plan = Plan
  { planTarget  :: !ScanTarget
  , planSteps   :: ![RemediationStep]
  , planSummary :: !Text
  } deriving stock (Show)

-- | Errors that can occur during orchestrator operations.
data OrchestratorError
  = ParseError !FilePath !Text
  | ConfigError !Text
  | ScanError !Text
  | ValidationError !Text
  | IOError' !Text
  deriving stock (Eq, Show)
