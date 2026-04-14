module Main (main) where

import Test.Tasty.Bench (bench, bgroup, defaultMain, whnf)
import Orchestrator.Parser (parseWorkflowBS)
import Orchestrator.Policy (evaluatePolicies, defaultPolicyPack)
import Orchestrator.Policy.Extended (extendedPolicyPack)
import Orchestrator.Demo (goodWorkflow, problematicWorkflow)
import Orchestrator.Validate (validateWorkflow)
import Orchestrator.Diff (generatePlan)
import Orchestrator.Graph (buildJobGraph)
import Orchestrator.Types (ScanTarget (..))
import Data.ByteString.Char8 qualified as BS

main :: IO ()
main = defaultMain
  [ bgroup "parse"
      [ bench "small workflow" $ whnf (parseWorkflowBS "bench.yml") smallYAML
      , bench "large workflow" $ whnf (parseWorkflowBS "bench.yml") largeYAML
      ]
  , bgroup "policy"
      [ bench "standard pack / good" $ whnf (evaluatePolicies defaultPolicyPack) goodWorkflow
      , bench "extended pack / problematic" $ whnf (evaluatePolicies extendedPolicyPack) problematicWorkflow
      ]
  , bgroup "validate"
      [ bench "good workflow" $ whnf validateWorkflow goodWorkflow
      , bench "problematic workflow" $ whnf validateWorkflow problematicWorkflow
      ]
  , bgroup "graph"
      [ bench "build graph" $ whnf buildJobGraph goodWorkflow
      ]
  , bgroup "plan"
      [ bench "generate plan" $ whnf (generatePlan (LocalPath "bench")) findings
      ]
  ]
  where
    smallYAML = BS.pack $ unlines
      ["name: CI", "on: push", "jobs:", "  build:", "    runs-on: ubuntu-latest"
      , "    steps:", "      - uses: actions/checkout@v4"]
    largeYAML = BS.pack $ unlines $ concat
      [ ["name: Large", "on: push", "jobs:"]
      , concatMap (\i -> ["  job" <> show i <> ":", "    runs-on: ubuntu-latest"
        , "    steps:", "      - uses: actions/checkout@v4"
        , "      - run: echo step " <> show i]) [1..20 :: Int]
      ]
    findings = evaluatePolicies extendedPolicyPack problematicWorkflow
