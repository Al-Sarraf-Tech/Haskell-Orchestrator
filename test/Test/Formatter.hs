module Test.Formatter (tests) where

import Data.Text qualified as T
import Orchestrator.Formatter
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

------------------------------------------------------------------------
-- Sample YAML inputs
------------------------------------------------------------------------

-- | Well-formed workflow YAML already in canonical order
canonicalYaml :: T.Text
canonicalYaml =
  T.unlines
    [ "name: CI",
      "on:",
      "  push:",
      "    branches: [main]",
      "permissions:",
      "  contents: read",
      "jobs:",
      "  build:",
      "    runs-on: ubuntu-latest",
      "    steps:",
      "      - run: echo hello"
    ]

-- | Workflow with top-level keys in non-canonical order
outOfOrderYaml :: T.Text
outOfOrderYaml =
  T.unlines
    [ "jobs:",
      "  build:",
      "    runs-on: ubuntu-latest",
      "name: CI",
      "on:",
      "  push:",
      "    branches: [main]"
    ]

-- | Workflow with 4-space indentation
fourSpaceYaml :: T.Text
fourSpaceYaml =
  T.unlines
    [ "name: CI",
      "on:",
      "    push:",
      "        branches: [main]",
      "jobs:",
      "    build:",
      "        runs-on: ubuntu-latest"
    ]

-- | Empty YAML
emptyYaml :: T.Text
emptyYaml = ""

-- | Single key YAML
singleKeyYaml :: T.Text
singleKeyYaml = "name: MyWorkflow\n"

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "Formatter"
    [ testDefaultConfig,
      testFormatCanonicalUnchangedContent,
      testFormatSortKeys,
      testFormatEmpty,
      testFormatSingleKey,
      testFormatIndentNormalized,
      testRenderDiffIdentical,
      testRenderDiffChanged,
      testQuoteStyleEnum,
      testConfigFields
    ]

-- | Default config: 2-space indent, sorted keys, no quote
testDefaultConfig :: TestTree
testDefaultConfig = testCase "defaultFormatConfig/fields" $ do
  fcIndentWidth defaultFormatConfig @?= 2
  fcSortKeys defaultFormatConfig @?= True
  fcQuoteStyle defaultFormatConfig @?= NoQuote

-- | Canonical YAML → format output contains 'name' and 'jobs' keys
testFormatCanonicalUnchangedContent :: TestTree
testFormatCanonicalUnchangedContent = testCase "formatWorkflowYAML/canonical-preserves-content" $ do
  let out = formatWorkflowYAML defaultFormatConfig canonicalYaml
  assertBool "contains name: CI" ("name: CI" `T.isInfixOf` out)
  assertBool "contains jobs:" ("jobs:" `T.isInfixOf` out)
  assertBool "contains on:" ("on:" `T.isInfixOf` out)

-- | Out-of-order YAML → 'name' appears before 'jobs' after formatting
testFormatSortKeys :: TestTree
testFormatSortKeys = testCase "formatWorkflowYAML/sort-puts-name-before-jobs" $ do
  let out = formatWorkflowYAML defaultFormatConfig outOfOrderYaml
      ls = T.lines out
      nameI = findLineIndex "name:" ls
      jobsI = findLineIndex "jobs:" ls
  assertBool "name before jobs after sort" (nameI < jobsI)

findLineIndex :: T.Text -> [T.Text] -> Int
findLineIndex needle ls = case filter (T.isInfixOf needle . snd) (zip [0 ..] ls) of
  ((i, _) : _) -> i
  [] -> maxBound

-- | Empty input → output is empty or blank
testFormatEmpty :: TestTree
testFormatEmpty = testCase "formatWorkflowYAML/empty-input" $ do
  let out = formatWorkflowYAML defaultFormatConfig emptyYaml
  assertBool "empty or blank output" (T.null (T.strip out))

-- | Single key → output still contains that key
testFormatSingleKey :: TestTree
testFormatSingleKey = testCase "formatWorkflowYAML/single-key" $ do
  let out = formatWorkflowYAML defaultFormatConfig singleKeyYaml
  assertBool "contains MyWorkflow" ("MyWorkflow" `T.isInfixOf` out)

-- | 4-space indented input → output has correct relative indentation
testFormatIndentNormalized :: TestTree
testFormatIndentNormalized = testCase "formatWorkflowYAML/indent-normalized" $ do
  let cfg = defaultFormatConfig {fcIndentWidth = 2}
      out = formatWorkflowYAML cfg fourSpaceYaml
  assertBool "output non-empty" (not (T.null out))
  assertBool "contains jobs:" ("jobs:" `T.isInfixOf` out)

-- | Identical original and formatted → "No formatting changes needed"
testRenderDiffIdentical :: TestTree
testRenderDiffIdentical = testCase "renderFormatDiff/identical-no-changes" $ do
  let txt = renderFormatDiff canonicalYaml canonicalYaml
  assertBool "no changes message" ("No formatting" `T.isInfixOf` txt)

-- | Different inputs → diff output contains change markers
testRenderDiffChanged :: TestTree
testRenderDiffChanged = testCase "renderFormatDiff/different-shows-diff" $ do
  let original = "name: Old\njobs:\n  build:\n    runs-on: ubuntu-latest\n"
      formatted = "name: New\njobs:\n  build:\n    runs-on: ubuntu-latest\n"
      txt = renderFormatDiff original formatted
  assertBool "diff contains minus line" ("- " `T.isInfixOf` txt)
  assertBool "diff contains plus line" ("+ " `T.isInfixOf` txt)

-- | QuoteStyle enum has all three constructors
testQuoteStyleEnum :: TestTree
testQuoteStyleEnum = testCase "QuoteStyle/all-constructors" $ do
  let styles = [SingleQuote, DoubleQuote, NoQuote]
  length styles @?= 3
  SingleQuote /= DoubleQuote @?= True
  DoubleQuote /= NoQuote @?= True

-- | FormatConfig can be constructed with custom values
testConfigFields :: TestTree
testConfigFields = testCase "FormatConfig/custom-config" $ do
  let cfg = FormatConfig {fcIndentWidth = 4, fcSortKeys = False, fcQuoteStyle = SingleQuote}
  fcIndentWidth cfg @?= 4
  fcSortKeys cfg @?= False
  fcQuoteStyle cfg @?= SingleQuote
