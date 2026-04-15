module Test.Baseline (tests) where

import Data.Set qualified as Set
import Data.Text qualified as T
import Orchestrator.Baseline
import Orchestrator.Types
import System.Directory (removeFile)
import System.IO (hClose, openTempFile)
import System.IO.Error (catchIOError, isDoesNotExistError)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkFinding :: T.Text -> FilePath -> T.Text -> Finding
mkFinding rid fp msg =
  Finding
    { findingSeverity = Error,
      findingCategory = Structure,
      findingRuleId = rid,
      findingMessage = msg,
      findingFile = fp,
      findingLocation = Nothing,
      findingRemediation = Nothing,
      findingAutoFixable = False,
      findingEffort = Nothing,
      findingLinks = []
    }

sampleFindings :: [Finding]
sampleFindings =
  [ mkFinding "RULE-001" "test.yml" "Missing permissions",
    mkFinding "RULE-002" "test.yml" "No timeout set"
  ]

-- | Compute a fingerprint matching the Baseline module logic
fingerprint :: Finding -> T.Text
fingerprint f = findingRuleId f <> ":" <> T.pack (findingFile f) <> ":" <> T.take 64 (findingMessage f)

-- | Run an IO action with a fresh temp file, clean up after
withTempFile :: (FilePath -> IO a) -> IO a
withTempFile action = do
  (fp, h) <- openTempFile "/tmp" "orchestrator-baseline-.json"
  hClose h
  result <- action fp
  catchIOError (removeFile fp) (\e -> if isDoesNotExistError e then pure () else ioError e)
  pure result

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "Baseline"
    [ testCompareEmpty,
      testCompareAllNew,
      testCompareAllKnown,
      testCompareMixed,
      testBaselineFields,
      testBaselinePath,
      testSaveAndLoad,
      testLoadMissing
    ]

-- | No baseline findings → all current findings are new
testCompareEmpty :: TestTree
testCompareEmpty = testCase "compareWithBaseline/empty-baseline-all-new" $ do
  let baseline = Baseline Set.empty 0 "1.0.0"
      new = compareWithBaseline baseline sampleFindings
  length new @?= length sampleFindings

-- | All current findings in baseline → none returned as new
testCompareAllKnown :: TestTree
testCompareAllKnown = testCase "compareWithBaseline/all-known-none-new" $ do
  let fps = Set.fromList (map fingerprint sampleFindings)
      b = Baseline fps (length sampleFindings) "1.0.0"
      new = compareWithBaseline b sampleFindings
  new @?= []

-- | No current findings → result is empty
testCompareAllNew :: TestTree
testCompareAllNew = testCase "compareWithBaseline/no-current-findings" $ do
  let baseline = Baseline Set.empty 0 "1.0.0"
      new = compareWithBaseline baseline []
  new @?= []

-- | Mixed: one known, one new
testCompareMixed :: TestTree
testCompareMixed = testCase "compareWithBaseline/mixed-returns-only-new" $ do
  let f1 = mkFinding "RULE-001" "test.yml" "Missing permissions"
      f2 = mkFinding "RULE-002" "test.yml" "No timeout set"
      b = Baseline (Set.singleton (fingerprint f1)) 1 "1.0.0"
      new = compareWithBaseline b [f1, f2]
  length new @?= 1
  findingRuleId (head new) @?= "RULE-002"

-- | Baseline fields are stored correctly
testBaselineFields :: TestTree
testBaselineFields = testCase "Baseline/fields-stored-correctly" $ do
  let fps = Set.fromList ["fp1", "fp2"]
      b = Baseline fps 2 "1.2.3"
  baselineCount b @?= 2
  baselineVersion b @?= "1.2.3"
  Set.size (baselineFingerprints b) @?= 2

-- | baselinePath appends correct suffix
testBaselinePath :: TestTree
testBaselinePath = testCase "baselinePath/suffix" $ do
  baselinePath "/repo" @?= "/repo/.orchestrator-baseline.json"

-- | Save then load baseline round-trips correctly
testSaveAndLoad :: TestTree
testSaveAndLoad = testCase "saveBaseline/loadBaseline/roundtrip" $
  withTempFile $ \fp -> do
    saveBaseline fp sampleFindings
    result <- loadBaseline fp
    case result of
      Left err -> fail $ "Load failed: " <> T.unpack err
      Right b -> do
        baselineCount b @?= length sampleFindings
        assertBool "fingerprints non-empty" (not (Set.null (baselineFingerprints b)))

-- | Load missing file returns Left
testLoadMissing :: TestTree
testLoadMissing = testCase "loadBaseline/missing-file-returns-Left" $ do
  result <- loadBaseline "/tmp/orchestrator-nonexistent-xyz-baseline.json"
  case result of
    Left _ -> pure ()
    Right _ -> fail "Expected Left for missing file"
