-- | Exit code gating for CI integration.
--
-- Determines the process exit code based on findings and a configurable
-- severity threshold, enabling @--fail-on@ behaviour in CI pipelines.
module Orchestrator.Gate
  ( gateFindings
  , parseFailOn
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Types (Finding (..), Severity (..))
import System.Exit (ExitCode (..))

-- | Return 'ExitFailure' 1 if any finding meets or exceeds the threshold.
gateFindings :: Severity -> [Finding] -> ExitCode
gateFindings threshold findings
  | any (\f -> findingSeverity f >= threshold) findings = ExitFailure 1
  | otherwise = ExitSuccess

-- | Parse a severity threshold string.  Case insensitive.
parseFailOn :: Text -> Maybe Severity
parseFailOn t = case T.toLower t of
  "info"     -> Just Info
  "warning"  -> Just Warning
  "error"    -> Just Error
  "critical" -> Just Critical
  _          -> Nothing
