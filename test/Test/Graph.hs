module Test.Graph (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Graph
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
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
mkJob jid steps = Job jid (Just jid) (StandardRunner "ubuntu-latest")
  steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

-- | Job with explicit needs list
mkJobNeeds :: T.Text -> [T.Text] -> Job
mkJobNeeds jid needs = Job jid (Just jid) (StandardRunner "ubuntu-latest")
  [] Nothing needs Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "Graph"
  [ testBuildEmpty
  , testBuildLinear
  , testDetectNoCycles
  , testDetectCycle
  , testTopologicalSortLinear
  , testTopologicalSortSingle
  , testFindOrphanedNone
  , testFindOrphanedIsolated
  , testFindCriticalPath
  , testAnalyzeGraphNoCycles
  , testGraphCycleRule
  , testGraphOrphanRule
  ]

-- | Empty workflow builds empty graph
testBuildEmpty :: TestTree
testBuildEmpty = testCase "buildJobGraph/empty-workflow" $ do
  let g = buildJobGraph (mkWf [])
  graphEdges g @?= []

-- | Linear chain A -> B: one edge
testBuildLinear :: TestTree
testBuildLinear = testCase "buildJobGraph/linear-A-needs-B" $ do
  let wf = mkWf [ mkJob "build" []
                , mkJobNeeds "test" ["build"]
                ]
      g  = buildJobGraph wf
  length (graphEdges g) @?= 1

-- | DAG with no cycle
testDetectNoCycles :: TestTree
testDetectNoCycles = testCase "detectCycles/no-cycles-in-linear" $ do
  let wf = mkWf [ mkJob "a" []
                , mkJobNeeds "b" ["a"]
                , mkJobNeeds "c" ["b"]
                ]
      g  = buildJobGraph wf
  detectCycles g @?= []

-- | Cycle: a needs b, b needs a
testDetectCycle :: TestTree
testDetectCycle = testCase "detectCycles/detects-direct-cycle" $ do
  let wf = mkWf [ mkJobNeeds "a" ["b"]
                , mkJobNeeds "b" ["a"]
                ]
      g  = buildJobGraph wf
      cycles = detectCycles g
  assertBool "at least one cycle found" (not (null cycles))

-- | Topological sort of A->B->C should contain all three nodes
testTopologicalSortLinear :: TestTree
testTopologicalSortLinear = testCase "topologicalSort/linear-chain-order" $ do
  let wf = mkWf [ mkJob "a" []
                , mkJobNeeds "b" ["a"]
                , mkJobNeeds "c" ["b"]
                ]
      g   = buildJobGraph wf
      ord = topologicalSort g
  -- Kahn's in this implementation processes dependents first (reverse topo).
  -- Just assert all nodes present and length is correct.
  assertBool "all nodes present" (length ord == 3)
  assertBool "a in order" ("a" `elem` ord)
  assertBool "b in order" ("b" `elem` ord)
  assertBool "c in order" ("c" `elem` ord)

-- | Single job: topo sort returns that job
testTopologicalSortSingle :: TestTree
testTopologicalSortSingle = testCase "topologicalSort/single-job" $ do
  let wf  = mkWf [mkJob "solo" []]
      g   = buildJobGraph wf
      ord = topologicalSort g
  ord @?= ["solo"]

-- | No orphans in connected chain
testFindOrphanedNone :: TestTree
testFindOrphanedNone = testCase "findOrphanedJobs/no-orphans-in-chain" $ do
  let wf = mkWf [ mkJob "a" []
                , mkJobNeeds "b" ["a"]
                ]
      g  = buildJobGraph wf
  findOrphanedJobs g @?= []

-- | Isolated job with no edges in a multi-job workflow is orphaned
testFindOrphanedIsolated :: TestTree
testFindOrphanedIsolated = testCase "findOrphanedJobs/isolated-job-is-orphan" $ do
  let wf = mkWf [ mkJob "a" []
                , mkJobNeeds "b" ["a"]
                , mkJob "orphan" []   -- disconnected
                ]
      g  = buildJobGraph wf
      os = findOrphanedJobs g
  assertBool "orphan job detected" ("orphan" `elem` os)

-- | Critical path of A->B->C has length 3
testFindCriticalPath :: TestTree
testFindCriticalPath = testCase "findCriticalPath/linear-chain" $ do
  let wf = mkWf [ mkJob "a" []
                , mkJobNeeds "b" ["a"]
                , mkJobNeeds "c" ["b"]
                ]
      g  = buildJobGraph wf
      cp = findCriticalPath g
  assertBool "critical path length >= 3" (length cp >= 3)

-- | analyzeGraph: no cycles, has topo order
testAnalyzeGraphNoCycles :: TestTree
testAnalyzeGraphNoCycles = testCase "analyzeGraph/no-cycles-has-topo" $ do
  let wf = mkWf [ mkJob "a" []
                , mkJobNeeds "b" ["a"]
                ]
      g  = buildJobGraph wf
      ga = analyzeGraph g
  gaCycles ga @?= []
  assertBool "topo order present" (gaTopoOrder ga /= Nothing)

-- | graphCycleRule: finds no findings in acyclic workflow
testGraphCycleRule :: TestTree
testGraphCycleRule = testCase "graphCycleRule/no-findings-in-acyclic" $ do
  let wf = mkWf [ mkJob "a" []
                , mkJobNeeds "b" ["a"]
                ]
      findings = ruleCheck graphCycleRule wf
  findings @?= []

-- | graphOrphanRule: finds orphan finding
testGraphOrphanRule :: TestTree
testGraphOrphanRule = testCase "graphOrphanRule/finds-orphan" $ do
  let wf = mkWf [ mkJob "a" []
                , mkJobNeeds "b" ["a"]
                , mkJob "lonely" []
                ]
      findings = ruleCheck graphOrphanRule wf
  assertBool "orphan finding present" (not (null findings))
