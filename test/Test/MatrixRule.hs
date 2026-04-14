module Test.MatrixRule (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Rules.Matrix
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [Job] -> Workflow
mkWf jobs = Workflow "Test" "test.yml"
  [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
  jobs Nothing Nothing Map.empty

mkJob :: T.Text -> [Step] -> Job
mkJob jid steps =
  Job jid (Just jid) (StandardRunner "ubuntu-latest")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkMatrixJob :: T.Text -> [Step] -> Job
mkMatrixJob jid steps =
  Job jid (Just jid) (MatrixRunner "${{ matrix.os }}")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkMatrixJobFF :: T.Text -> Bool -> [Step] -> Job
mkMatrixJobFF jid ff steps =
  Job jid (Just jid) (MatrixRunner "${{ matrix.os }}")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False (Just ff) False

-- | Job with include-only matrix flag set
mkMatrixJobIncludeOnly :: T.Text -> [Step] -> Job
mkMatrixJobIncludeOnly jid steps =
  Job jid (Just jid) (MatrixRunner "${{ matrix.os }}")
    steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing True

mkRunStep :: T.Text -> Step
mkRunStep cmd =
  Step Nothing (Just "Run") Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

-- | Step referencing multiple matrix dimensions (triggers explosion rule)
multiDimStep :: Step
multiDimStep = mkRunStep
  "echo ${{ matrix.os }} ${{ matrix.node-version }} ${{ matrix.arch }}"

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "MatrixRule"
  [ testGroup "MAT-001 Matrix Explosion Risk"
      [ testCase "rule has correct ID" $
          ruleId matrixExplosionRule @?= "MAT-001"

      , testCase "rule severity is Warning" $
          ruleSeverity matrixExplosionRule @?= Warning

      , testCase "detects matrix job with 3+ dimensions" $ do
          let wf = mkWf [mkMatrixJob "build" [multiDimStep]]
              findings = ruleCheck matrixExplosionRule wf
          assertBool "Should find MAT-001 for 3+ dimensions" (not (null findings))
          findingRuleId (head findings) @?= "MAT-001"
          findingSeverity (head findings) @?= Warning

      , testCase "no finding for standard runner without matrix refs" $ do
          let wf = mkWf [mkJob "build" [mkRunStep "cabal build"]]
              findings = ruleCheck matrixExplosionRule wf
          assertBool "Standard runner without matrix refs should not trigger MAT-001"
            (null findings)

      , testCase "no finding for include-only matrix job" $ do
          let wf = mkWf [mkMatrixJobIncludeOnly "build" [multiDimStep]]
              findings = ruleCheck matrixExplosionRule wf
          assertBool "Include-only matrix should not trigger MAT-001" (null findings)

      , testCase "no finding for matrix job with fewer than 3 dimensions" $ do
          let step = mkRunStep "echo ${{ matrix.os }} ${{ matrix.node-version }}"
              wf = mkWf [mkMatrixJob "build" [step]]
              findings = ruleCheck matrixExplosionRule wf
          assertBool "Fewer than 3 matrix dims should not trigger MAT-001" (null findings)

      , testCase "no finding for empty workflow" $ do
          let wf = mkWf []
              findings = ruleCheck matrixExplosionRule wf
          assertBool "Empty workflow should not trigger MAT-001" (null findings)

      , testCase "finding message mentions job ID" $ do
          let wf = mkWf [mkMatrixJob "cross-build" [multiDimStep]]
              findings = ruleCheck matrixExplosionRule wf
          assertBool "Finding message should mention job ID"
            ("cross-build" `T.isInfixOf` findingMessage (head findings))
      ]

  , testGroup "MAT-002 Matrix Missing Fail-Fast"
      [ testCase "rule has correct ID" $
          ruleId matrixFailFastRule @?= "MAT-002"

      , testCase "rule severity is Info" $
          ruleSeverity matrixFailFastRule @?= Info

      , testCase "detects matrix job without fail-fast" $ do
          let wf = mkWf [mkMatrixJob "build" [mkRunStep "cabal test"]]
              findings = ruleCheck matrixFailFastRule wf
          assertBool "Should find MAT-002 for matrix job without fail-fast"
            (not (null findings))
          findingRuleId (head findings) @?= "MAT-002"

      , testCase "no finding when fail-fast is explicitly set" $ do
          let wf = mkWf [mkMatrixJobFF "build" True [mkRunStep "cabal test"]]
              findings = ruleCheck matrixFailFastRule wf
          assertBool "Explicit fail-fast should not trigger MAT-002" (null findings)

      , testCase "no finding when fail-fast is explicitly false" $ do
          let wf = mkWf [mkMatrixJobFF "build" False [mkRunStep "cabal test"]]
              findings = ruleCheck matrixFailFastRule wf
          assertBool "Explicit fail-fast false should not trigger MAT-002" (null findings)

      , testCase "no finding for standard runner without matrix refs" $ do
          let wf = mkWf [mkJob "build" [mkRunStep "cabal build"]]
              findings = ruleCheck matrixFailFastRule wf
          assertBool "Standard runner without matrix should not trigger MAT-002"
            (null findings)

      , testCase "no finding for empty workflow" $ do
          let wf = mkWf []
              findings = ruleCheck matrixFailFastRule wf
          assertBool "Empty workflow should not trigger MAT-002" (null findings)

      , testCase "finding message mentions job ID" $ do
          let wf = mkWf [mkMatrixJob "matrix-build" [mkRunStep "make"]]
              findings = ruleCheck matrixFailFastRule wf
          assertBool "Finding message should mention job ID"
            ("matrix-build" `T.isInfixOf` findingMessage (head findings))
      ]
  ]
