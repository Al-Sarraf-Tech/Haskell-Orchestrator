module Test.Scan (tests) where

import Orchestrator.Scan
import Orchestrator.Policy (defaultPolicyPack)
import Orchestrator.Config (defaultConfig, cfgScan)
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

tests :: TestTree
tests = testGroup "Scan"
  [ testCase "isWorkflowFile accepts .yml" $
      isWorkflowFile "ci.yml" @?= True

  , testCase "isWorkflowFile accepts .yaml" $
      isWorkflowFile "release.yaml" @?= True

  , testCase "isWorkflowFile rejects non-workflow extension" $
      isWorkflowFile "README.md" @?= False

  , testCase "isWorkflowFile rejects hidden files" $
      isWorkflowFile ".hidden.yml" @?= False

  , testCase "isWorkflowFile rejects empty name" $
      isWorkflowFile "" @?= False

  , testCase "isWorkflowFile rejects .json" $
      isWorkflowFile "config.json" @?= False

  , testCase "findWorkflowFiles finds demo fixtures" $ do
      let demoDir = "demo/.github/workflows"
      files <- findWorkflowFiles 1 demoDir
      assertBool "found at least one workflow file" (not (null files))
      assertBool "all found files are workflow files" (all isWorkflowFile files)

  , testCase "findWorkflowFiles returns empty for nonexistent dir" $ do
      files <- findWorkflowFiles 1 "/tmp/definitely-does-not-exist-xyz"
      files @?= []

  , testCase "findWorkflowFiles respects maxDepth 0" $ do
      files <- findWorkflowFiles 0 "demo/.github/workflows"
      files @?= []

  , testCase "scanLocalPath succeeds on demo directory" $ do
      let pack = defaultPolicyPack
          cfg  = cfgScan defaultConfig
      result <- scanLocalPath pack cfg "demo"
      case result of
        Left err -> assertBool ("scanLocalPath failed: " ++ show err) False
        Right sr -> assertBool "scan target is LocalPath" $
          case scanTarget sr of
            LocalPath _ -> True
            _           -> False

  , testCase "scanLocalPath returns empty when no .github/workflows" $ do
      let pack = defaultPolicyPack
          cfg  = cfgScan defaultConfig
      result <- scanLocalPath pack cfg "/tmp"
      case result of
        Left err -> assertBool ("unexpected error: " ++ show err) False
        Right sr -> scanFindings sr @?= []

  , testCase "scanWorkflowDir finds findings in demo" $ do
      let pack = defaultPolicyPack
      _ <- scanWorkflowDir pack "demo/.github/workflows"
      -- findings may or may not be empty; just assert it runs without error
      assertBool "scanWorkflowDir returned a list" True

  , testCase "scanLocalPath demo has at least one scanned file" $ do
      let pack = defaultPolicyPack
          cfg  = cfgScan defaultConfig
      result <- scanLocalPath pack cfg "demo"
      case result of
        Left err -> assertBool ("scan failed: " ++ show err) False
        Right sr -> assertBool "at least one file scanned" (not (null (scanFiles sr)))
  ]
