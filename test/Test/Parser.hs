module Test.Parser (tests) where

import Data.ByteString.Char8 qualified as BS
import Orchestrator.Model
import Orchestrator.Parser
import Orchestrator.Types (OrchestratorError (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "Parser"
  [ testCase "Parse minimal workflow" $ do
      let yaml = BS.pack $ unlines
            [ "name: CI"
            , "on: push"
            , "jobs:"
            , "  build:"
            , "    runs-on: ubuntu-latest"
            , "    steps:"
            , "      - uses: actions/checkout@v4"
            ]
      case parseWorkflowBS "test.yml" yaml of
        Left err -> error $ "Parse failed: " ++ show err
        Right wf -> do
          wfName wf @?= "CI"
          length (wfJobs wf) @?= 1

  , testCase "Parse workflow with permissions" $ do
      let yaml = BS.pack $ unlines
            [ "name: Secure CI"
            , "on: push"
            , "permissions:"
            , "  contents: read"
            , "jobs:"
            , "  build:"
            , "    runs-on: ubuntu-latest"
            , "    steps:"
            , "      - run: echo hello"
            ]
      case parseWorkflowBS "test.yml" yaml of
        Left err -> error $ "Parse failed: " ++ show err
        Right wf -> do
          assertBool "Should have permissions" (wfPermissions wf /= Nothing)

  , testCase "Parse workflow with concurrency" $ do
      let yaml = BS.pack $ unlines
            [ "name: PR CI"
            , "on: pull_request"
            , "concurrency:"
            , "  group: ci-${{ github.ref }}"
            , "  cancel-in-progress: true"
            , "jobs:"
            , "  test:"
            , "    runs-on: ubuntu-latest"
            , "    steps:"
            , "      - run: make test"
            ]
      case parseWorkflowBS "test.yml" yaml of
        Left err -> error $ "Parse failed: " ++ show err
        Right wf -> do
          assertBool "Should have concurrency" (wfConcurrency wf /= Nothing)

  , testCase "Reject invalid YAML" $ do
      let yaml = BS.pack "{{invalid yaml"
      case parseWorkflowBS "bad.yml" yaml of
        Left (ParseError _ _) -> pure ()
        _ -> error "Should have failed"

  , testCase "Parse multiple triggers" $ do
      let yaml = BS.pack $ unlines
            [ "name: Multi"
            , "on:"
            , "  push:"
            , "    branches: [main]"
            , "  pull_request:"
            , "    branches: [main]"
            , "jobs:"
            , "  build:"
            , "    runs-on: ubuntu-latest"
            , "    steps:"
            , "      - run: echo test"
            ]
      case parseWorkflowBS "test.yml" yaml of
        Left err -> error $ "Parse failed: " ++ show err
        Right wf -> do
          assertBool "Should have triggers" (not $ null $ wfTriggers wf)

  , testCase "Parse job with timeout" $ do
      let yaml = BS.pack $ unlines
            [ "name: Timeout Test"
            , "on: push"
            , "jobs:"
            , "  build:"
            , "    runs-on: ubuntu-latest"
            , "    timeout-minutes: 30"
            , "    steps:"
            , "      - run: echo test"
            ]
      case parseWorkflowBS "test.yml" yaml of
        Left err -> error $ "Parse failed: " ++ show err
        Right wf -> do
          let job = head (wfJobs wf)
          jobTimeoutMin job @?= Just 30
  ]
