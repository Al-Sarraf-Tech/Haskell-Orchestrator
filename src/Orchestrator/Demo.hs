-- | Demo mode with synthetic fixtures.
--
-- Provides a self-contained demonstration of Orchestrator's capabilities
-- using entirely synthetic workflow data.  No external repositories are
-- accessed.
module Orchestrator.Demo
  ( runDemo
  , demoWorkflows
  , goodWorkflow
  , problematicWorkflow
  , insecureWorkflow
  ) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Orchestrator.Diff (generatePlan, renderPlanText)
import Orchestrator.Model
import Orchestrator.Policy (defaultPolicyPack, evaluatePolicies)
import Orchestrator.Render (renderFindings, renderSummary)
import Orchestrator.Types
import Orchestrator.Validate (validateWorkflow, ValidationResult (..))

-- | Run the full demo, printing results to stdout.
runDemo :: IO ()
runDemo = do
  TIO.putStrLn "Haskell Orchestrator — Demo Mode"
  TIO.putStrLn (T.replicate 60 "═")
  TIO.putStrLn ""
  TIO.putStrLn "Using synthetic workflow fixtures (no external repos accessed)."
  TIO.putStrLn ""

  mapM_ demoOneWorkflow demoWorkflows

  TIO.putStrLn (T.replicate 60 "═")
  TIO.putStrLn "Demo complete."

demoOneWorkflow :: Workflow -> IO ()
demoOneWorkflow wf = do
  TIO.putStrLn $ "Analyzing: " <> wfName wf
  TIO.putStrLn $ "  File: " <> T.pack (wfFileName wf)
  TIO.putStrLn ""

  -- Structural validation
  let vr = validateWorkflow wf
  TIO.putStrLn "  Structural validation:"
  if null (getVRFindings vr)
    then TIO.putStrLn "    No structural issues."
    else TIO.putStr $ T.unlines $ map (\f -> "    " <> findingMessage f) (getVRFindings vr)

  -- Policy evaluation
  let findings = evaluatePolicies defaultPolicyPack wf
  TIO.putStrLn ""
  TIO.putStrLn "  Policy findings:"
  if null findings
    then TIO.putStrLn "    All policies passed."
    else do
      TIO.putStr $ renderFindings findings
      TIO.putStrLn ""
      TIO.putStr $ renderSummary findings

  -- Remediation plan
  let plan = generatePlan (LocalPath (wfFileName wf)) findings
  TIO.putStrLn ""
  TIO.putStr $ renderPlanText plan
  TIO.putStrLn ""

getVRFindings :: ValidationResult -> [Finding]
getVRFindings (ValidationResult _ fs _) = fs

-- | All demo workflows.
demoWorkflows :: [Workflow]
demoWorkflows = [goodWorkflow, problematicWorkflow, insecureWorkflow]

-- | A well-configured workflow that should produce minimal findings.
goodWorkflow :: Workflow
goodWorkflow = Workflow
  { wfName = "CI"
  , wfFileName = "demo/.github/workflows/ci.yml"
  , wfTriggers =
      [ TriggerEvents
          [ TriggerEvent "push" ["main"] [] []
          , TriggerEvent "pull_request" ["main"] [] []
          ]
      ]
  , wfJobs =
      [ Job
          { jobId = "build-and-test"
          , jobName = Just "Build and Test"
          , jobRunsOn = StandardRunner "ubuntu-latest"
          , jobSteps =
              [ Step (Just "checkout") (Just "Checkout")
                  (Just "actions/checkout@v4") Nothing Map.empty Map.empty Nothing
              , Step Nothing (Just "Build")
                  Nothing (Just "make build") Map.empty Map.empty Nothing
              , Step Nothing (Just "Test")
                  Nothing (Just "make test") Map.empty Map.empty Nothing
              ]
          , jobPermissions = Just (PermissionsMap (Map.fromList [("contents", PermRead)]))
          , jobNeeds = []
          , jobConcurrency = Nothing
          , jobEnv = Map.empty
          , jobIf = Nothing
          , jobTimeoutMin = Just 30
          , jobFailFast = Nothing
          , jobMatrixIncludeOnly = False
          }
      ]
  , wfPermissions = Just (PermissionsMap (Map.fromList [("contents", PermRead)]))
  , wfConcurrency = Just (ConcurrencyConfig "ci-${{ github.ref }}" True)
  , wfEnv = Map.empty
  }

-- | A workflow with common problems (missing permissions, no timeout, etc.).
problematicWorkflow :: Workflow
problematicWorkflow = Workflow
  { wfName = "Deploy"
  , wfFileName = "demo/.github/workflows/deploy.yml"
  , wfTriggers =
      [ TriggerEvents
          [ TriggerEvent "push" ["**"] [] []
          , TriggerEvent "pull_request" [] [] []
          ]
      ]
  , wfJobs =
      [ Job
          { jobId = "deployProd"
          , jobName = Just "Deploy to Production"
          , jobRunsOn = StandardRunner "ubuntu-latest"
          , jobSteps =
              [ Step Nothing (Just "Checkout")
                  (Just "actions/checkout@v4") Nothing Map.empty Map.empty Nothing
              , Step Nothing (Just "Deploy")
                  (Just "third-party/deploy-action@v2") Nothing Map.empty Map.empty Nothing
              ]
          , jobPermissions = Nothing
          , jobNeeds = []
          , jobConcurrency = Nothing
          , jobEnv = Map.empty
          , jobIf = Nothing
          , jobTimeoutMin = Nothing
          , jobFailFast = Nothing
          , jobMatrixIncludeOnly = False
          }
      ]
  , wfPermissions = Nothing
  , wfConcurrency = Nothing
  , wfEnv = Map.empty
  }

-- | A workflow with security issues.
insecureWorkflow :: Workflow
insecureWorkflow = Workflow
  { wfName = "Release"
  , wfFileName = "demo/.github/workflows/release.yml"
  , wfTriggers =
      [ TriggerEvents [TriggerEvent "push" ["main"] ["v*"] []] ]
  , wfJobs =
      [ Job
          { jobId = "release"
          , jobName = Just "Create Release"
          , jobRunsOn = StandardRunner "ubuntu-latest"
          , jobSteps =
              [ Step Nothing (Just "Checkout")
                  (Just "actions/checkout@v4") Nothing Map.empty Map.empty Nothing
              , Step Nothing (Just "Publish")
                  Nothing
                  (Just "echo \"Publishing with token: ${{ secrets.DEPLOY_TOKEN }}\"")
                  Map.empty Map.empty Nothing
              ]
          , jobPermissions = Just (PermissionsAll PermWrite)
          , jobNeeds = []
          , jobConcurrency = Nothing
          , jobEnv = Map.empty
          , jobIf = Nothing
          , jobTimeoutMin = Nothing
          , jobFailFast = Nothing
          , jobMatrixIncludeOnly = False
          }
      ]
  , wfPermissions = Just (PermissionsAll PermWrite)
  , wfConcurrency = Nothing
  , wfEnv = Map.empty
  }
