module Test.Config (tests) where

import Orchestrator.Config
import Orchestrator.Types (OrchestratorError (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "Config"
    [ testCase "Default config is valid" $ do
        case validateConfig defaultConfig of
          Right _ -> pure ()
          Left err -> error $ "Default config invalid: " ++ show err,
      testCase "Invalid max_depth rejected" $ do
        let cfg = defaultConfig {cfgScan = (cfgScan defaultConfig) {scMaxDepth = 0}}
        case validateConfig cfg of
          Left (ConfigError _) -> pure ()
          _ -> error "Should reject max_depth < 1",
      testCase "Excessive max_depth rejected" $ do
        let cfg = defaultConfig {cfgScan = (cfgScan defaultConfig) {scMaxDepth = 200}}
        case validateConfig cfg of
          Left (ConfigError _) -> pure ()
          _ -> error "Should reject max_depth > 100",
      testCase "Invalid jobs rejected" $ do
        let cfg = defaultConfig {cfgResources = (cfgResources defaultConfig) {rcJobs = Just 0}}
        case validateConfig cfg of
          Left (ConfigError _) -> pure ()
          _ -> error "Should reject jobs < 1",
      testCase "Excessive jobs rejected" $ do
        let cfg = defaultConfig {cfgResources = (cfgResources defaultConfig) {rcJobs = Just 100}}
        case validateConfig cfg of
          Left (ConfigError _) -> pure ()
          _ -> error "Should reject jobs > 64",
      testCase "Default parallelism is Safe" $ do
        rcProfile (cfgResources defaultConfig) @?= Safe
    ]
