-- | Baseline comparison for incremental adoption.
--
-- Allows saving a snapshot of current findings and comparing future
-- scans against it, showing only NEW findings. This enables teams to
-- adopt the tool gradually without being overwhelmed by existing issues.
module Orchestrator.Baseline
  ( -- * Types
    Baseline (..),

    -- * Operations
    saveBaseline,
    loadBaseline,
    compareWithBaseline,
    baselinePath,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON (..), ToJSON (..), object, (.:), (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LBS
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Types

-- | A saved baseline of known findings.
-- Uses fingerprints (rule_id + file + message_hash) for comparison.
data Baseline = Baseline
  { baselineFingerprints :: !(Set Text),
    baselineCount :: !Int,
    baselineVersion :: !Text
  }
  deriving stock (Eq, Show)

instance ToJSON Baseline where
  toJSON b =
    object
      [ "fingerprints" .= Set.toList (baselineFingerprints b),
        "count" .= baselineCount b,
        "version" .= baselineVersion b
      ]

instance FromJSON Baseline where
  parseJSON = Aeson.withObject "Baseline" $ \o -> do
    fps <- o .: "fingerprints"
    count <- o .: "count"
    version <- o .: "version"
    pure
      Baseline
        { baselineFingerprints = Set.fromList fps,
          baselineCount = count,
          baselineVersion = version
        }

-- | Default baseline file path.
baselinePath :: FilePath -> FilePath
baselinePath root = root ++ "/.orchestrator-baseline.json"

-- | Create a fingerprint for a finding.
findingFingerprint :: Finding -> Text
findingFingerprint f =
  findingRuleId f
    <> ":"
    <> T.pack (findingFile f)
    <> ":"
    <> T.take 64 (findingMessage f)

-- | Save findings as a baseline.
saveBaseline :: FilePath -> [Finding] -> IO ()
saveBaseline path findings = do
  let fps = Set.fromList (map findingFingerprint findings)
      baseline =
        Baseline
          { baselineFingerprints = fps,
            baselineCount = length findings,
            baselineVersion = "1.2.1"
          }
  LBS.writeFile path (Aeson.encode baseline)

-- | Load a previously saved baseline.
loadBaseline :: FilePath -> IO (Either Text Baseline)
loadBaseline path = do
  result <- try (LBS.readFile path) :: IO (Either SomeException LBS.ByteString)
  case result of
    Left err -> pure $ Left $ "Failed to read baseline file: " <> T.pack (show err)
    Right bs -> case Aeson.eitherDecode bs of
      Left err -> pure $ Left $ "Failed to load baseline: " <> T.pack err
      Right b -> pure $ Right b

-- | Compare current findings against a baseline.
-- Returns only findings that are NOT in the baseline (new findings).
compareWithBaseline :: Baseline -> [Finding] -> [Finding]
compareWithBaseline baseline findings =
  let fps = baselineFingerprints baseline
   in filter (\f -> not (Set.member (findingFingerprint f) fps)) findings
