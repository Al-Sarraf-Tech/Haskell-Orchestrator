-- | Workflow dependency graph analysis.
--
-- Builds a DAG of job @needs:@ relationships and detects structural
-- issues: cycles, orphaned jobs, unreachable jobs, and critical path.
module Orchestrator.Graph
  ( -- * Types
    JobGraph (..),
    GraphEdge (..),
    GraphAnalysis (..),

    -- * Construction
    buildJobGraph,

    -- * Analysis
    analyzeGraph,
    detectCycles,
    findOrphanedJobs,
    findCriticalPath,
    topologicalSort,

    -- * Rules
    graphCycleRule,
    graphOrphanRule,
  )
where

import Data.List (foldl')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | A directed edge in the job dependency graph.
data GraphEdge = GraphEdge
  { -- | The job that depends
    edgeFrom :: !Text,
    -- | The job depended upon
    edgeTo :: !Text
  }
  deriving stock (Eq, Ord, Show)

-- | A complete job dependency graph for a workflow.
data JobGraph = JobGraph
  { graphNodes :: !(Set Text),
    graphEdges :: ![GraphEdge],
    -- | job -> jobs it needs
    graphAdjacency :: !(Map Text [Text]),
    -- | job -> jobs that need it
    graphReverse :: !(Map Text [Text])
  }
  deriving stock (Show)

-- | Results of graph analysis.
data GraphAnalysis = GraphAnalysis
  { -- | Detected cycles (each as a path)
    gaCycles :: ![[Text]],
    -- | Jobs with no dependents and no needs
    gaOrphans :: ![Text],
    -- | Longest dependency chain
    gaCriticalPath :: ![Text],
    -- | Topological order (Nothing if cycles)
    gaTopoOrder :: !(Maybe [Text]),
    -- | Maximum dependency depth
    gaMaxDepth :: !Int
  }
  deriving stock (Show)

-- | Build a dependency graph from a workflow's jobs.
buildJobGraph :: Workflow -> JobGraph
buildJobGraph wf =
  let jobs = wfJobs wf
      nodes = Set.fromList (map jobId jobs)
      edges =
        [ GraphEdge (jobId j) n
        | j <- jobs,
          n <- jobNeeds j
        ]
      adj =
        foldl'
          ( \m (GraphEdge from to) ->
              Map.insertWith (++) from [to] m
          )
          (Map.fromList [(jobId j, []) | j <- jobs])
          edges
      rev =
        foldl'
          ( \m (GraphEdge from to) ->
              Map.insertWith (++) to [from] m
          )
          (Map.fromList [(jobId j, []) | j <- jobs])
          edges
   in JobGraph
        { graphNodes = nodes,
          graphEdges = edges,
          graphAdjacency = adj,
          graphReverse = rev
        }

-- | Full graph analysis: cycles, orphans, critical path, topo sort.
analyzeGraph :: JobGraph -> GraphAnalysis
analyzeGraph g =
  let cycles = detectCycles g
      orphans = findOrphanedJobs g
      critical = findCriticalPath g
      topo = if null cycles then Just (topologicalSort g) else Nothing
      maxD = if null critical then 0 else length critical - 1
   in GraphAnalysis
        { gaCycles = cycles,
          gaOrphans = orphans,
          gaCriticalPath = critical,
          gaTopoOrder = topo,
          gaMaxDepth = maxD
        }

-- | Detect cycles using DFS with path tracking.
detectCycles :: JobGraph -> [[Text]]
detectCycles g =
  let nodes = Set.toList (graphNodes g)
      adj = graphAdjacency g
   in dfsAllCycles adj nodes

dfsAllCycles :: Map Text [Text] -> [Text] -> [[Text]]
dfsAllCycles adj nodes =
  let (cycles, _) =
        foldl'
          ( \(found, visited) node ->
              if Set.member node visited
                then (found, visited)
                else
                  let (newCycles, newVisited) = dfs adj node [] Set.empty visited
                   in (found ++ newCycles, newVisited)
          )
          ([], Set.empty)
          nodes
   in cycles

dfs ::
  Map Text [Text] ->
  Text ->
  [Text] ->
  Set Text ->
  Set Text ->
  ([[Text]], Set Text)
dfs adj node path inPath visited
  | Set.member node inPath =
      -- Found a cycle: extract the cycle portion from the path
      let cycle' = dropWhile (/= node) (reverse path) ++ [node]
       in ([cycle'], visited)
  | Set.member node visited = ([], visited)
  | otherwise =
      let neighbors = Map.findWithDefault [] node adj
          path' = node : path
          inPath' = Set.insert node inPath
          visited' = Set.insert node visited
          (cycles, finalVisited) =
            foldl'
              ( \(cs, v) neighbor ->
                  let (newCs, newV) = dfs adj neighbor path' inPath' v
                   in (cs ++ newCs, newV)
              )
              ([], visited')
              neighbors
       in (cycles, finalVisited)

-- | Find orphaned jobs: jobs with no dependents (nothing needs them)
-- and that are not terminal jobs (they also need nothing).
-- A truly orphaned job has no incoming and no outgoing edges and there
-- are other jobs in the workflow.
findOrphanedJobs :: JobGraph -> [Text]
findOrphanedJobs g
  | Set.size (graphNodes g) <= 1 = []
  | otherwise =
      let adj = graphAdjacency g
          rev = graphReverse g
          -- Jobs that nothing depends on AND that depend on nothing
          isolated =
            [ n
            | n <- Set.toList (graphNodes g),
              null (Map.findWithDefault [] n rev),
              null (Map.findWithDefault [] n adj)
            ]
       in isolated

-- | Find the critical path (longest dependency chain) via DFS.
findCriticalPath :: JobGraph -> [Text]
findCriticalPath g =
  let adj = graphAdjacency g
      -- Find root nodes (no incoming edges)
      roots =
        [ n
        | n <- Set.toList (graphNodes g),
          null (Map.findWithDefault [] n (graphReverse g))
        ]
      -- For each root, find longest path
      paths = map (longestPath adj Set.empty) roots
   in case paths of
        [] -> []
        _ -> maximumByLength paths

longestPath :: Map Text [Text] -> Set Text -> Text -> [Text]
longestPath adj visited node
  | Set.member node visited = [node] -- cycle guard
  | otherwise =
      let neighbors = Map.findWithDefault [] node adj
          visited' = Set.insert node visited
          subPaths = map (longestPath adj visited') neighbors
       in case subPaths of
            [] -> [node]
            _ -> node : maximumByLength subPaths

maximumByLength :: [[a]] -> [a]
maximumByLength [] = []
maximumByLength xs = foldl1 (\a b -> if length a >= length b then a else b) xs

-- | Topological sort (Kahn's algorithm). Assumes no cycles.
topologicalSort :: JobGraph -> [Text]
topologicalSort g =
  let adj = graphAdjacency g
      initDeg :: Map Text Int
      initDeg = Map.fromList [(n, 0) | n <- Set.toList (graphNodes g)]
      inDegree =
        foldl'
          ( \m node ->
              let deps = Map.findWithDefault [] node adj
               in foldl' (\m' dep -> Map.insertWith (+) dep (1 :: Int) m') m deps
          )
          initDeg
          (Set.toList (graphNodes g))
      queue = [n | (n, d) <- Map.toList inDegree, d == 0]
   in kahn' adj inDegree queue []

kahn' :: Map Text [Text] -> Map Text Int -> [Text] -> [Text] -> [Text]
kahn' _ _ [] result = reverse result
kahn' adj inDeg (n : rest) result =
  let deps = Map.findWithDefault [] n adj
      (newQueue, newInDeg) =
        foldl'
          ( \(q, deg) dep ->
              let newD = Map.findWithDefault 1 dep deg - 1
                  deg' = Map.insert dep newD deg
               in if newD == 0 then (dep : q, deg') else (q, deg')
          )
          (rest, inDeg)
          deps
   in kahn' adj newInDeg newQueue (n : result)

------------------------------------------------------------------------
-- Policy Rules
------------------------------------------------------------------------

-- | Rule: detect dependency cycles in job graphs.
graphCycleRule :: PolicyRule
graphCycleRule =
  PolicyRule
    { ruleId = "GRAPH-001",
      ruleName = "Dependency Cycle Detection",
      ruleDescription = "Detect circular dependencies in job needs: chains",
      ruleSeverity = Error,
      ruleCategory = Structure,
      ruleTags = [TagStructure],
      ruleCheck = \wf ->
        let g = buildJobGraph wf
            cycles = detectCycles g
         in concatMap
              ( \cyc ->
                  [ Finding
                      { findingSeverity = Error,
                        findingCategory = Structure,
                        findingRuleId = "GRAPH-001",
                        findingMessage =
                          "Dependency cycle detected: "
                            <> T.intercalate " → " cyc,
                        findingFile = wfFileName wf,
                        findingLocation = Nothing,
                        findingRemediation = Just "Remove circular needs: dependencies between jobs.",
                        findingAutoFixable = False,
                        findingEffort = Nothing,
                        findingLinks = []
                      }
                  ]
              )
              cycles
    }

-- | Rule: detect orphaned jobs that are disconnected from the graph.
graphOrphanRule :: PolicyRule
graphOrphanRule =
  PolicyRule
    { ruleId = "GRAPH-002",
      ruleName = "Orphaned Job Detection",
      ruleDescription = "Detect jobs isolated from the dependency graph",
      ruleSeverity = Info,
      ruleCategory = Structure,
      ruleTags = [TagStructure],
      ruleCheck = \wf ->
        let g = buildJobGraph wf
            orphans = findOrphanedJobs g
         in map
              ( \o ->
                  Finding
                    { findingSeverity = Info,
                      findingCategory = Structure,
                      findingRuleId = "GRAPH-002",
                      findingMessage =
                        "Job '"
                          <> o
                          <> "' is isolated: no other job depends on it and it depends on nothing.",
                      findingFile = wfFileName wf,
                      findingLocation = Nothing,
                      findingRemediation = Just "Consider if this job should be connected via needs: or removed.",
                      findingAutoFixable = False,
                      findingEffort = Nothing,
                      findingLinks = []
                    }
              )
              orphans
    }
