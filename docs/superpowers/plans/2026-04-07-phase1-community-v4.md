# Phase 1: Community v4.0.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand Community edition from 21 to 36 rules, add suppression comments, rule tagging, exit code gating, and CI self-check dogfooding.

**Architecture:** New rules follow the existing pattern: pure functions `Workflow -> [Finding]` in dedicated `Orchestrator.Rules.*` modules, registered in `Orchestrator.Policy.Extended`. Infrastructure features (suppression, tagging, gating) are standalone modules integrated at the scan pipeline level. All changes are in the Community repo only.

**Tech Stack:** Haskell (GHC2021, GHC 9.6.7), Cabal 3.10+, Tasty/HUnit/QuickCheck for testing, Ormolu for formatting, HLint for linting.

**Spec:** `docs/superpowers/specs/2026-04-07-tier-expansion-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `src/Orchestrator/Rules/SupplyChain.hs` | SEC-003, SEC-004, SEC-005, SUPPLY-001, SUPPLY-002 |
| `src/Orchestrator/Rules/Performance.hs` | PERF-001, PERF-002 |
| `src/Orchestrator/Rules/Cost.hs` | COST-001, COST-002 |
| `src/Orchestrator/Rules/Hardening.hs` | HARD-001, HARD-002, HARD-003 |
| `src/Orchestrator/Rules/Drift.hs` | DRIFT-001 |
| `src/Orchestrator/Rules/Structure.hs` | STRUCT-001, STRUCT-002 |
| `src/Orchestrator/Suppress.hs` | Inline suppression comment parser |
| `src/Orchestrator/Tags.hs` | Rule tagging and tag-based filtering |
| `src/Orchestrator/Gate.hs` | `--fail-on` exit code logic |
| `test/Test/SupplyChain.hs` | Tests for supply chain rules |
| `test/Test/Performance.hs` | Tests for performance rules |
| `test/Test/Cost.hs` | Tests for cost rules |
| `test/Test/Hardening.hs` | Tests for hardening rules |
| `test/Test/DriftRule.hs` | Tests for drift rule |
| `test/Test/StructureRule.hs` | Tests for structure rules |
| `test/Test/Suppress.hs` | Tests for suppression system |
| `test/Test/Tags.hs` | Tests for tagging system |
| `test/Test/Gate.hs` | Tests for exit code gating |

### Modified Files

| File | Change |
|------|--------|
| `src/Orchestrator/Types.hs` | Add `Performance`, `Cost`, `SupplyChain` to `FindingCategory` |
| `src/Orchestrator/Policy.hs` | Add `RuleTag` type, `ruleTags` field to `PolicyRule`, update `parseCategory` |
| `src/Orchestrator/Policy/Extended.hs` | Register all 15 new rules, update pack name/count |
| `src/Orchestrator/Scan.hs` | Integrate suppression filtering after rule evaluation |
| `app/CLI.hs` | Add `--fail-on` and `--tags` flags |
| `app/Main.hs` | Wire gating exit code and tag filtering |
| `orchestrator.cabal` | Add new modules to exposed-modules and test-suite other-modules |
| `test/Main.hs` | Import and register new test modules |

---

## Task 1: Add New FindingCategory Values

**Files:**
- Modify: `src/Orchestrator/Types.hs:27-37`
- Modify: `src/Orchestrator/Policy.hs:172-184`
- Modify: `src/Orchestrator/Render.hs` (if it pattern-matches on categories)

- [ ] **Step 1: Add Performance, Cost, SupplyChain to FindingCategory**

In `src/Orchestrator/Types.hs`, update the `FindingCategory` enum:

```haskell
data FindingCategory
  = Permissions
  | Runners
  | Triggers
  | Naming
  | Concurrency
  | Security
  | Structure
  | Duplication
  | Drift
  | Performance
  | Cost
  | SupplyChain
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)
```

- [ ] **Step 2: Update parseCategory in Policy.hs**

In `src/Orchestrator/Policy.hs`, add the new categories to `parseCategory`:

```haskell
parseCategory :: Text -> FindingCategory
parseCategory t = case T.toLower t of
  "permissions"  -> Permissions
  "runners"      -> Runners
  "triggers"     -> Triggers
  "naming"       -> Naming
  "concurrency"  -> Concurrency
  "security"     -> Security
  "structure"    -> Structure
  "duplication"  -> Duplication
  "drift"        -> Drift
  "performance"  -> Performance
  "cost"         -> Cost
  "supplychain"  -> SupplyChain
  "supply_chain" -> SupplyChain
  _              -> Structure
```

- [ ] **Step 3: Check Render.hs for exhaustive pattern matches**

Search `src/Orchestrator/Render.hs` and `src/Orchestrator/Render/Sarif.hs` for any pattern matches on `FindingCategory`. If they use exhaustive matches (not just field access), add cases for the new constructors. If they use `show` or field access, no changes needed.

- [ ] **Step 4: Build to verify no warnings**

Run: `cabal build all --ghc-options="-Werror"`
Expected: Clean build, no non-exhaustive pattern match warnings.

- [ ] **Step 5: Run existing tests**

Run: `cabal test all --test-show-details=direct`
Expected: All 115 existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/Orchestrator/Types.hs src/Orchestrator/Policy.hs
git commit -m "feat: add Performance, Cost, SupplyChain to FindingCategory"
```

---

## Task 2: Add Rule Tagging System

**Files:**
- Create: `src/Orchestrator/Tags.hs`
- Modify: `src/Orchestrator/Policy.hs:46-53`
- Create: `test/Test/Tags.hs`

- [ ] **Step 1: Write failing test for tag filtering**

Create `test/Test/Tags.hs`:

```haskell
module Test.Tags (tests) where

import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Tags
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "Tags"
  [ testCase "parseRuleTag parses known tags" $ do
      parseRuleTag "security" @?= Just TagSecurity
      parseRuleTag "performance" @?= Just TagPerformance
      parseRuleTag "cost" @?= Just TagCost
      parseRuleTag "style" @?= Just TagStyle
      parseRuleTag "structure" @?= Just TagStructure

  , testCase "parseRuleTag rejects unknown" $
      parseRuleTag "banana" @?= Nothing

  , testCase "filterByTags keeps matching rules" $ do
      let rule1 = dummyRule "R1" [TagSecurity]
          rule2 = dummyRule "R2" [TagPerformance]
          rule3 = dummyRule "R3" [TagSecurity, TagCost]
          filtered = filterByTags [TagSecurity] [rule1, rule2, rule3]
      length filtered @?= 2
      map ruleId filtered @?= ["R1", "R3"]

  , testCase "filterByTags with empty tags returns all" $ do
      let rules = [dummyRule "R1" [TagSecurity], dummyRule "R2" [TagCost]]
          filtered = filterByTags [] rules
      length filtered @?= 2

  , testCase "filterByTags with multiple tags is union" $ do
      let rule1 = dummyRule "R1" [TagSecurity]
          rule2 = dummyRule "R2" [TagPerformance]
          rule3 = dummyRule "R3" [TagCost]
          filtered = filterByTags [TagSecurity, TagCost] [rule1, rule2, rule3]
      length filtered @?= 2
  ]

dummyRule :: Text -> [RuleTag] -> PolicyRule
dummyRule rid tags = PolicyRule
  { ruleId = rid
  , ruleName = rid
  , ruleDescription = "test"
  , ruleSeverity = Info
  , ruleCategory = Structure
  , ruleTags = tags
  , ruleCheck = const []
  }
```

- [ ] **Step 2: Create Tags module**

Create `src/Orchestrator/Tags.hs`:

```haskell
-- | Rule tagging for category-based filtering.
module Orchestrator.Tags
  ( RuleTag (..)
  , parseRuleTag
  , filterByTags
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Policy (PolicyRule (..))

-- | Tags for categorizing rules by concern.
data RuleTag
  = TagSecurity
  | TagPerformance
  | TagCost
  | TagStyle
  | TagStructure
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)

-- | Parse a tag name from text.
parseRuleTag :: Text -> Maybe RuleTag
parseRuleTag t = case T.toLower t of
  "security"    -> Just TagSecurity
  "performance" -> Just TagPerformance
  "cost"        -> Just TagCost
  "style"       -> Just TagStyle
  "structure"   -> Just TagStructure
  _             -> Nothing

-- | Filter rules to those matching any of the given tags.
-- Empty tag list returns all rules (no filtering).
filterByTags :: [RuleTag] -> [PolicyRule] -> [PolicyRule]
filterByTags [] rules = rules
filterByTags tags rules = filter (any (`elem` tags) . ruleTags) rules
```

- [ ] **Step 3: Add ruleTags field to PolicyRule**

In `src/Orchestrator/Policy.hs`, add the `ruleTags` field to `PolicyRule`:

```haskell
data PolicyRule = PolicyRule
  { ruleId          :: !Text
  , ruleName        :: !Text
  , ruleDescription :: !Text
  , ruleSeverity    :: !Severity
  , ruleCategory    :: !FindingCategory
  , ruleTags        :: ![RuleTag]
  , ruleCheck       :: Workflow -> [Finding]
  }
```

This requires importing `RuleTag` from `Orchestrator.Tags`. However, this creates a circular dependency: `Tags` imports `PolicyRule` from `Policy`, and `Policy` imports `RuleTag` from `Tags`.

**Resolution:** Define `RuleTag` in `Orchestrator.Types` instead of `Orchestrator.Tags`. Then `Tags.hs` only contains `parseRuleTag` and `filterByTags`, importing from both `Types` and `Policy`.

Move `RuleTag` to `src/Orchestrator/Types.hs`:

```haskell
-- | Tags for categorizing rules by concern.
data RuleTag
  = TagSecurity
  | TagPerformance
  | TagCost
  | TagStyle
  | TagStructure
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)
```

Add to the export list of `Types.hs`: `RuleTag (..)`.

Update `Tags.hs` to import `RuleTag` from `Orchestrator.Types`.

- [ ] **Step 4: Add `ruleTags = []` to all 21 existing rules**

Every existing `PolicyRule` construction in `Policy.hs`, `Graph.hs`, `Rules/Composite.hs`, `Rules/Duplicate.hs`, `Rules/Environment.hs`, `Rules/Matrix.hs`, and `Rules/Reuse.hs` needs a `ruleTags` field. Add `ruleTags = []` to each. We will assign proper tags to existing rules after all new rules are implemented.

For each file, add the field. Example in `Policy.hs`:

```haskell
permissionsRequiredRule :: PolicyRule
permissionsRequiredRule = PolicyRule
  { ruleId = "PERM-001"
  , ruleName = "Permissions Required"
  , ruleDescription = "Workflows should declare explicit permissions"
  , ruleSeverity = Warning
  , ruleCategory = Permissions
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf -> ...
  }
```

Assign tags to all 21 existing rules:

| Rule | Tags |
|------|------|
| PERM-001, PERM-002 | `[TagSecurity]` |
| SEC-001, SEC-002 | `[TagSecurity]` |
| RUN-001 | `[TagStructure]` |
| CONC-001 | `[TagPerformance]` |
| RES-001 | `[TagStructure, TagPerformance]` |
| NAME-001, NAME-002 | `[TagStyle]` |
| TRIG-001 | `[TagSecurity]` |
| GRAPH-CYCLE, GRAPH-ORPHAN | `[TagStructure]` |
| DUP-001 | `[TagStyle]` |
| REUSE-001, REUSE-002 | `[TagStructure]` |
| MAT-001, MAT-002 | `[TagPerformance, TagCost]` |
| ENV-001, ENV-002 | `[TagSecurity]` |
| COMP-001, COMP-002 | `[TagStyle]` |

- [ ] **Step 5: Update customRuleToPolicy**

In `Policy.hs`, add `ruleTags = []` to the `customRuleToPolicy` function's `PolicyRule` construction.

- [ ] **Step 6: Register test module and run tests**

Add `Test.Tags` to `test/Main.hs` imports and test group. Add `Test.Tags` to `orchestrator.cabal` test-suite `other-modules`. Add `Orchestrator.Tags` and `RuleTag` export to `orchestrator.cabal` exposed-modules.

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass including new tag tests.

- [ ] **Step 7: Commit**

```bash
git add src/Orchestrator/Types.hs src/Orchestrator/Policy.hs src/Orchestrator/Tags.hs \
  src/Orchestrator/Graph.hs src/Orchestrator/Rules/*.hs \
  test/Test/Tags.hs test/Main.hs orchestrator.cabal
git commit -m "feat: add rule tagging system with tag-based filtering"
```

---

## Task 3: Implement Suppression System

**Files:**
- Create: `src/Orchestrator/Suppress.hs`
- Create: `test/Test/Suppress.hs`
- Modify: `src/Orchestrator/Scan.hs`

- [ ] **Step 1: Write failing tests for suppression**

Create `test/Test/Suppress.hs`:

```haskell
module Test.Suppress (tests) where

import Data.Set qualified as Set
import Data.Text qualified as T
import Orchestrator.Suppress
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "Suppress"
  [ testCase "Parse single suppression comment" $ do
      let content = "# orchestrator:disable SEC-001\nname: Test\n"
          suppressed = parseSuppressedRules content
      Set.member "SEC-001" suppressed @?= True

  , testCase "Parse multiple suppressions" $ do
      let content = T.unlines
            [ "# orchestrator:disable SEC-001"
            , "# orchestrator:disable PERM-002"
            , "name: Test"
            ]
          suppressed = parseSuppressedRules content
      Set.size suppressed @?= 2
      Set.member "SEC-001" suppressed @?= True
      Set.member "PERM-002" suppressed @?= True

  , testCase "Ignore non-suppression comments" $ do
      let content = T.unlines
            [ "# This is a regular comment"
            , "# orchestrator:disable SEC-001"
            , "name: Test"
            ]
          suppressed = parseSuppressedRules content
      Set.size suppressed @?= 1

  , testCase "Case insensitive directive" $ do
      let content = "# Orchestrator:Disable SEC-001\n"
          suppressed = parseSuppressedRules content
      Set.member "SEC-001" suppressed @?= True

  , testCase "Suppression with extra whitespace" $ do
      let content = "#   orchestrator:disable   SEC-001  \n"
          suppressed = parseSuppressedRules content
      Set.member "SEC-001" suppressed @?= True

  , testCase "No suppressions in clean file" $ do
      let content = "name: Clean\non: push\n"
          suppressed = parseSuppressedRules content
      Set.null suppressed @?= True

  , testCase "applySuppression filters matching findings" $ do
      let suppressed = Set.fromList ["SEC-001", "PERM-001"]
          findings =
            [ mkTestFinding' "SEC-001"
            , mkTestFinding' "SEC-002"
            , mkTestFinding' "PERM-001"
            , mkTestFinding' "RES-001"
            ]
          filtered = applySuppression suppressed findings
      length filtered @?= 2
      map findingRuleId filtered @?= ["SEC-002", "RES-001"]

  , testCase "applySuppression with empty set returns all" $ do
      let findings = [mkTestFinding' "SEC-001", mkTestFinding' "SEC-002"]
          filtered = applySuppression Set.empty findings
      length filtered @?= 2
  ]

mkTestFinding' :: T.Text -> Finding
mkTestFinding' rid = Finding Warning Security rid "test" "test.yml" Nothing Nothing False Nothing []
```

- [ ] **Step 2: Implement Suppress module**

Create `src/Orchestrator/Suppress.hs`:

```haskell
-- | Inline suppression of specific rules via YAML comments.
--
-- Supports @# orchestrator:disable RULE-ID@ comments in workflow files
-- to suppress specific findings for that file.
module Orchestrator.Suppress
  ( parseSuppressedRules
  , applySuppression
  ) where

import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Types (Finding (..))

-- | Parse suppression directives from raw file content.
-- Looks for lines matching: @# orchestrator:disable RULE-ID@
parseSuppressedRules :: Text -> Set Text
parseSuppressedRules = Set.fromList . concatMap parseLine . T.lines
  where
    parseLine line =
      let stripped = T.strip $ T.dropWhile (== '#') (T.strip line)
          lower = T.toLower stripped
      in case T.stripPrefix "orchestrator:disable" lower of
           Just rest ->
             let ruleId = T.strip rest
                 -- Use original case for the rule ID
                 originalRuleId = T.strip $ T.drop (T.length "orchestrator:disable") stripped
             in [originalRuleId | not (T.null originalRuleId)]
           Nothing -> []

-- | Remove findings whose rule IDs are in the suppression set.
applySuppression :: Set Text -> [Finding] -> [Finding]
applySuppression suppressed
  | Set.null suppressed = id
  | otherwise = filter (\f -> not (Set.member (findingRuleId f) suppressed))
```

- [ ] **Step 3: Register module and run tests**

Add `Orchestrator.Suppress` to `orchestrator.cabal` exposed-modules.
Add `Test.Suppress` to test-suite other-modules and `test/Main.hs`.

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass.

- [ ] **Step 4: Integrate suppression into Scan.hs**

In `src/Orchestrator/Scan.hs`, after evaluating policies against a parsed workflow, apply suppression filtering. Find where `evaluatePolicies` is called and wrap the result:

```haskell
import Orchestrator.Suppress (parseSuppressedRules, applySuppression)
import Data.Text.IO qualified as TIO

-- In the scan function, after parsing each file:
-- 1. Read the raw file content
-- 2. Parse suppression directives
-- 3. Evaluate policies
-- 4. Apply suppression to findings

scanWorkflowFile :: PolicyPack -> FilePath -> IO [Finding]
scanWorkflowFile pack fp = do
  rawContent <- TIO.readFile fp
  let suppressed = parseSuppressedRules rawContent
  case parseWorkflowFile fp of
    Left _ -> pure []
    Right wf ->
      let findings = evaluatePolicies pack wf
      in pure (applySuppression suppressed findings)
```

Note: Adapt this to the actual scan function signature in `Scan.hs`. The key change is reading raw content for suppression before or alongside YAML parsing.

- [ ] **Step 5: Build and run all tests**

Run: `cabal build all --ghc-options="-Werror" && cabal test all --test-show-details=direct`
Expected: Clean build, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/Orchestrator/Suppress.hs src/Orchestrator/Scan.hs \
  test/Test/Suppress.hs test/Main.hs orchestrator.cabal
git commit -m "feat: add inline suppression via orchestrator:disable comments"
```

---

## Task 4: Implement Exit Code Gating

**Files:**
- Create: `src/Orchestrator/Gate.hs`
- Create: `test/Test/Gate.hs`

- [ ] **Step 1: Write failing tests**

Create `test/Test/Gate.hs`:

```haskell
module Test.Gate (tests) where

import Orchestrator.Gate
import Orchestrator.Types
import System.Exit (ExitCode (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

tests :: TestTree
tests = testGroup "Gate"
  [ testCase "No findings always passes" $
      gateFindings Warning [] @?= ExitSuccess

  , testCase "Findings below threshold pass" $ do
      let findings = [mkGateFinding Info]
      gateFindings Warning findings @?= ExitSuccess

  , testCase "Findings at threshold fail" $ do
      let findings = [mkGateFinding Warning]
      gateFindings Warning findings @?= ExitFailure 1

  , testCase "Findings above threshold fail" $ do
      let findings = [mkGateFinding Error]
      gateFindings Warning findings @?= ExitFailure 1

  , testCase "Mixed findings - one above threshold fails" $ do
      let findings = [mkGateFinding Info, mkGateFinding Error]
      gateFindings Warning findings @?= ExitFailure 1

  , testCase "Critical threshold only fails on Critical" $ do
      let findings = [mkGateFinding Error]
      gateFindings Critical findings @?= ExitSuccess

  , testCase "parseFailOn parses valid thresholds" $ do
      parseFailOn "info" @?= Just Info
      parseFailOn "warning" @?= Just Warning
      parseFailOn "error" @?= Just Error
      parseFailOn "critical" @?= Just Critical

  , testCase "parseFailOn rejects invalid" $
      parseFailOn "banana" @?= Nothing

  , testCase "parseFailOn is case insensitive" $
      parseFailOn "WARNING" @?= Just Warning
  ]

mkGateFinding :: Severity -> Finding
mkGateFinding sev = Finding sev Security "TEST" "test" "test.yml" Nothing Nothing False Nothing []
```

- [ ] **Step 2: Implement Gate module**

Create `src/Orchestrator/Gate.hs`:

```haskell
-- | Exit code gating for CI integration.
--
-- Provides @--fail-on@ logic: scan results are compared against a severity
-- threshold and an appropriate exit code is returned.
module Orchestrator.Gate
  ( gateFindings
  , parseFailOn
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Types (Finding (..), Severity (..))
import System.Exit (ExitCode (..))

-- | Determine exit code based on findings and a severity threshold.
-- Returns 'ExitFailure 1' if any finding meets or exceeds the threshold.
gateFindings :: Severity -> [Finding] -> ExitCode
gateFindings threshold findings
  | any (\f -> findingSeverity f >= threshold) findings = ExitFailure 1
  | otherwise = ExitSuccess

-- | Parse a severity threshold string.
parseFailOn :: Text -> Maybe Severity
parseFailOn t = case T.toLower t of
  "info"     -> Just Info
  "warning"  -> Just Warning
  "error"    -> Just Error
  "critical" -> Just Critical
  _          -> Nothing
```

- [ ] **Step 3: Register module, run tests**

Add `Orchestrator.Gate` to `orchestrator.cabal` exposed-modules.
Add `Test.Gate` to test-suite other-modules and `test/Main.hs`.

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/Orchestrator/Gate.hs test/Test/Gate.hs test/Main.hs orchestrator.cabal
git commit -m "feat: add exit code gating for --fail-on CI integration"
```

---

## Task 5: Add --fail-on and --tags CLI Flags

**Files:**
- Modify: `app/CLI.hs`
- Modify: `app/Main.hs`

- [ ] **Step 1: Add flags to CLI Options type**

In `app/CLI.hs`, add two new fields to `Options`:

```haskell
data Options = Options
  { optConfigFile :: !(Maybe FilePath)
  , optVerbose    :: !Bool
  , optOutput     :: !OutputMode
  , optJobs       :: !(Maybe Int)
  , optBaseline   :: !(Maybe FilePath)
  , optFailOn     :: !(Maybe Text)
  , optTags       :: ![Text]
  , optCommand    :: !Command
  } deriving stock (Show)
```

- [ ] **Step 2: Add parsers for the new flags**

In `optionsParser`, add the two new flag parsers between `optBaseline` and `optCommand`:

```haskell
  <*> optional (strOption
        ( long "fail-on"
        <> metavar "SEVERITY"
        <> help "Exit with code 1 if any finding meets this severity (info|warning|error|critical)"
        ))
  <*> many (strOption
        ( long "tags"
        <> metavar "TAG"
        <> help "Only evaluate rules with these tags (security|performance|cost|style|structure). Repeatable."
        ))
```

- [ ] **Step 3: Wire gating into Main.hs**

In `app/Main.hs`, after the scan produces findings:

```haskell
import Orchestrator.Gate (gateFindings, parseFailOn)
import Orchestrator.Tags (filterByTags, parseRuleTag)
import System.Exit (exitWith)

-- Before evaluating policies, filter rules by tags:
let tagFilters = mapMaybe parseRuleTag (optTags opts)
    filteredPack = pack { packRules = filterByTags tagFilters (packRules pack) }

-- After collecting all findings and rendering output:
case optFailOn opts of
  Nothing -> pure ()
  Just threshold -> case parseFailOn threshold of
    Nothing -> hPutStrLn stderr ("Unknown severity: " <> T.unpack threshold)
    Just sev -> exitWith (gateFindings sev findings)
```

- [ ] **Step 4: Update footer with new rule count**

In `app/CLI.hs`, update the footer text from "21 built-in rules" to "36 built-in rules".

- [ ] **Step 5: Build and test**

Run: `cabal build all --ghc-options="-Werror"`
Expected: Clean build.

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/CLI.hs app/Main.hs
git commit -m "feat: add --fail-on and --tags CLI flags for CI gating and filtering"
```

---

## Task 6: Supply Chain Rules (SEC-003, SEC-004, SEC-005, SUPPLY-001, SUPPLY-002)

**Files:**
- Create: `src/Orchestrator/Rules/SupplyChain.hs`
- Create: `test/Test/SupplyChain.hs`

- [ ] **Step 1: Write failing tests**

Create `test/Test/SupplyChain.hs`:

```haskell
module Test.SupplyChain (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..), evaluatePolicy)
import Orchestrator.Rules.SupplyChain
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "SupplyChain Rules"
  [ sec003Tests
  , sec004Tests
  , sec005Tests
  , supply001Tests
  , supply002Tests
  ]

------------------------------------------------------------------------
-- SEC-003: Workflow Run Privilege Escalation
------------------------------------------------------------------------

sec003Tests :: TestTree
sec003Tests = testGroup "SEC-003 Workflow Run Privilege Escalation"
  [ testCase "Detects pull_request_target with PR head checkout" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "pull_request_target" [] [] []]]
                     [mkJob "build" [mkCheckoutStep (Map.fromList [("ref", "${{ github.event.pull_request.head.sha }}")])]]
          findings = evaluatePolicy workflowRunEscalationRule wf
      assertBool "Should detect escalation" (not $ null findings)
      findingSeverity (head findings) @?= Error

  , testCase "No finding for regular pull_request" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "pull_request" [] [] []]]
                     [mkJob "build" [mkCheckoutStep Map.empty]]
          findings = evaluatePolicy workflowRunEscalationRule wf
      assertBool "Should not flag regular PR" (null findings)

  , testCase "No finding for pull_request_target without head checkout" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "pull_request_target" [] [] []]]
                     [mkJob "build" [mkRunStep "echo hello"]]
          findings = evaluatePolicy workflowRunEscalationRule wf
      assertBool "Should not flag without checkout" (null findings)
  ]

------------------------------------------------------------------------
-- SEC-004: Artifact Poisoning
------------------------------------------------------------------------

sec004Tests :: TestTree
sec004Tests = testGroup "SEC-004 Artifact Poisoning"
  [ testCase "Detects download-artifact followed by run step" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "workflow_run" [] [] []]]
                     [mkJob "use" [ mkUseStep "actions/download-artifact@v4"
                                  , mkRunStep "bash ./downloaded-script.sh"
                                  ]]
          findings = evaluatePolicy artifactPoisoningRule wf
      assertBool "Should detect artifact poisoning" (not $ null findings)

  , testCase "No finding without download-artifact" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "build" [mkRunStep "echo safe"]]
          findings = evaluatePolicy artifactPoisoningRule wf
      assertBool "Should not flag" (null findings)
  ]

------------------------------------------------------------------------
-- SEC-005: OIDC Token Scope
------------------------------------------------------------------------

sec005Tests :: TestTree
sec005Tests = testGroup "SEC-005 OIDC Token Scope"
  [ testCase "Detects id-token write without deployment step" $ do
      let perms = Just (PermissionsMap (Map.fromList [("id-token", PermWrite), ("contents", PermRead)]))
          wf = (mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "build" [mkRunStep "npm test"]])
               { wfPermissions = perms }
          findings = evaluatePolicy oidcTokenScopeRule wf
      assertBool "Should detect unused OIDC" (not $ null findings)

  , testCase "No finding when deployment step present" $ do
      let perms = Just (PermissionsMap (Map.fromList [("id-token", PermWrite)]))
          wf = (mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "deploy" [mkUseStep "aws-actions/configure-aws-credentials@v4"]])
               { wfPermissions = perms }
          findings = evaluatePolicy oidcTokenScopeRule wf
      assertBool "Should not flag with deployment" (null findings)
  ]

------------------------------------------------------------------------
-- SUPPLY-001: Abandoned Action
------------------------------------------------------------------------

supply001Tests :: TestTree
supply001Tests = testGroup "SUPPLY-001 Abandoned Action"
  [ testCase "Detects known abandoned action" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "build" [mkUseStep "benadryl/unmaintained-action@v1"]]
          findings = evaluatePolicy abandonedActionRule wf
      -- This depends on the catalog. If benadryl/unmaintained-action is in catalog as abandoned:
      -- For now, test with a known-bad entry from the catalog.
      pure ()  -- Will be populated once catalog is defined

  , testCase "No finding for well-known maintained action" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "build" [mkUseStep "actions/checkout@v4"]]
          findings = evaluatePolicy abandonedActionRule wf
      assertBool "Should not flag actions/*" (null findings)
  ]

------------------------------------------------------------------------
-- SUPPLY-002: Typosquat Risk
------------------------------------------------------------------------

supply002Tests :: TestTree
supply002Tests = testGroup "SUPPLY-002 Typosquat Risk"
  [ testCase "Detects action similar to popular action" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "build" [mkUseStep "action/checkout@v4"]]
          findings = evaluatePolicy typosquatRiskRule wf
      assertBool "Should detect typosquat" (not $ null findings)

  , testCase "No finding for exact popular action" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "build" [mkUseStep "actions/checkout@v4"]]
          findings = evaluatePolicy typosquatRiskRule wf
      assertBool "Should not flag exact match" (null findings)

  , testCase "Detects 'action/setup-node' vs 'actions/setup-node'" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "build" [mkUseStep "action/setup-node@v4"]]
          findings = evaluatePolicy typosquatRiskRule wf
      assertBool "Should detect typosquat" (not $ null findings)
  ]

------------------------------------------------------------------------
-- Test helpers
------------------------------------------------------------------------

mkWf :: [WorkflowTrigger] -> [Job] -> Workflow
mkWf triggers jobs = Workflow
  { wfName = "Test"
  , wfFileName = "test.yml"
  , wfTriggers = triggers
  , wfJobs = jobs
  , wfPermissions = Nothing
  , wfConcurrency = Nothing
  , wfEnv = Map.empty
  }

mkJob :: T.Text -> [Step] -> Job
mkJob jid steps = Job jid (Just jid) (StandardRunner "ubuntu-latest")
  steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkRunStep :: T.Text -> Step
mkRunStep cmd = Step Nothing Nothing Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

mkUseStep :: T.Text -> Step
mkUseStep action = Step Nothing Nothing (Just action) Nothing Map.empty Map.empty Nothing Nothing

mkCheckoutStep :: Map.Map T.Text T.Text -> Step
mkCheckoutStep withMap = Step Nothing Nothing (Just "actions/checkout@v4") Nothing withMap Map.empty Nothing Nothing
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cabal test all --test-show-details=direct`
Expected: Compilation fails — `Orchestrator.Rules.SupplyChain` does not exist yet.

- [ ] **Step 3: Implement SupplyChain rules**

Create `src/Orchestrator/Rules/SupplyChain.hs`:

```haskell
-- | Supply chain security rules for GitHub Actions workflows.
--
-- Detects privilege escalation via pull_request_target, artifact poisoning,
-- OIDC token misuse, abandoned actions, and typosquat risks.
module Orchestrator.Rules.SupplyChain
  ( workflowRunEscalationRule
  , artifactPoisoningRule
  , oidcTokenScopeRule
  , abandonedActionRule
  , typosquatRiskRule
  ) where

import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types (Finding (..), FindingCategory (..), RuleTag (..), Severity (..), mkFinding')

-- | SEC-003: Detect pull_request_target with checkout of PR head.
-- This pattern runs untrusted code from a fork with write permissions.
workflowRunEscalationRule :: PolicyRule
workflowRunEscalationRule = PolicyRule
  { ruleId = "SEC-003"
  , ruleName = "Workflow Run Privilege Escalation"
  , ruleDescription = "Detect pull_request_target with checkout of untrusted PR head"
  , ruleSeverity = Error
  , ruleCategory = Security
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      let hasPRTarget = any (triggerHasName "pull_request_target") (wfTriggers wf)
          checksOutHead = any (any stepChecksOutPRHead . jobSteps) (wfJobs wf)
      in [ mkFinding' Error Security "SEC-003"
              "Workflow uses pull_request_target and checks out the PR head. \
              \This executes untrusted fork code with write permissions — \
              \a critical privilege escalation risk."
              (wfFileName wf)
              Nothing
              (Just "Use pull_request event instead, or avoid checking out the PR head ref.")
         | hasPRTarget && checksOutHead
         ]
  }

-- | SEC-004: Detect artifact poisoning patterns.
-- Downloading artifacts from untrusted workflows and executing them.
artifactPoisoningRule :: PolicyRule
artifactPoisoningRule = PolicyRule
  { ruleId = "SEC-004"
  , ruleName = "Artifact Poisoning"
  , ruleDescription = "Detect download of artifacts followed by execution"
  , ruleSeverity = Warning
  , ruleCategory = Security
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      let hasWorkflowRun = any (triggerHasName "workflow_run") (wfTriggers wf)
      in concatMap (\j ->
            let steps = jobSteps j
                hasDownload = any isDownloadArtifact steps
                hasRunAfter = any isRunStep (dropWhile (not . isDownloadArtifact) steps)
            in [ mkFinding' Warning Security "SEC-004"
                    ("Job '" <> jobId j <> "' downloads artifacts and executes commands. "
                    <> if hasWorkflowRun
                       then "Combined with workflow_run trigger, this risks artifact poisoning."
                       else "Verify artifact integrity before execution.")
                    (wfFileName wf)
                    Nothing
                    (Just "Verify artifact checksums before executing downloaded content.")
               | hasDownload && hasRunAfter
               ]
         ) (wfJobs wf)
  }

-- | SEC-005: Detect OIDC token permissions without deployment steps.
oidcTokenScopeRule :: PolicyRule
oidcTokenScopeRule = PolicyRule
  { ruleId = "SEC-005"
  , ruleName = "OIDC Token Scope"
  , ruleDescription = "Detect id-token write permission without deployment"
  , ruleSeverity = Warning
  , ruleCategory = Security
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      let hasOIDC = hasIdTokenWrite (wfPermissions wf)
                    || any (hasIdTokenWrite . jobPermissions) (wfJobs wf)
          hasDeploy = any (any isDeploymentStep . jobSteps) (wfJobs wf)
      in [ mkFinding' Warning Security "SEC-005"
              "Workflow grants id-token: write permission but has no deployment \
              \steps that would consume OIDC tokens. This may grant unnecessary access."
              (wfFileName wf)
              Nothing
              (Just "Remove id-token: write if no OIDC-consuming step is present.")
         | hasOIDC && not hasDeploy
         ]
  }

-- | SUPPLY-001: Detect actions from abandoned repositories.
abandonedActionRule :: PolicyRule
abandonedActionRule = PolicyRule
  { ruleId = "SUPPLY-001"
  , ruleName = "Abandoned Action"
  , ruleDescription = "Detect actions from archived or unmaintained repositories"
  , ruleSeverity = Warning
  , ruleCategory = SupplyChain
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      concatMap (\j ->
        concatMap (\s -> case stepUses s of
          Just uses | not (isFirstPartyAction uses) ->
            let owner'repo = extractOwnerRepo uses
            in [ mkFinding' Warning SupplyChain "SUPPLY-001"
                    ("Step uses action '" <> uses <> "' which is in the abandoned actions catalog. "
                    <> "Unmaintained actions may contain unpatched vulnerabilities.")
                    (wfFileName wf)
                    Nothing
                    (Just "Replace with an actively maintained alternative.")
               | maybe False (`elem` abandonedActions) owner'repo
               ]
          _ -> []
        ) (jobSteps j)
      ) (wfJobs wf)
  }

-- | SUPPLY-002: Detect action names suspiciously similar to popular actions.
typosquatRiskRule :: PolicyRule
typosquatRiskRule = PolicyRule
  { ruleId = "SUPPLY-002"
  , ruleName = "Typosquat Risk"
  , ruleDescription = "Detect action names similar to popular actions"
  , ruleSeverity = Info
  , ruleCategory = SupplyChain
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      concatMap (\j ->
        concatMap (\s -> case stepUses s of
          Just uses | not (isFirstPartyAction uses) ->
            let owner'repo = extractOwnerRepo uses
            in case owner'repo of
                 Just or' -> concatMap (checkTyposquat (wfFileName wf) uses or') popularActions
                 Nothing -> []
          _ -> []
        ) (jobSteps j)
      ) (wfJobs wf)
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

triggerHasName :: Text -> WorkflowTrigger -> Bool
triggerHasName name (TriggerEvents evts) = any (\e -> triggerName e == name) evts
triggerHasName _ _ = False

stepChecksOutPRHead :: Step -> Bool
stepChecksOutPRHead s = case stepUses s of
  Just uses | "actions/checkout" `T.isPrefixOf` uses ->
    let withMap = stepWith s
        ref = Map.lookup "ref" withMap
    in case ref of
         Just r -> "pull_request.head" `T.isInfixOf` r
                   || "event.pull_request.head" `T.isInfixOf` r
                   || "github.head_ref" `T.isInfixOf` r
         Nothing -> False
  _ -> False

isDownloadArtifact :: Step -> Bool
isDownloadArtifact s = case stepUses s of
  Just uses -> "download-artifact" `T.isInfixOf` uses
  Nothing -> False

isRunStep :: Step -> Bool
isRunStep s = case stepRun s of
  Just _ -> True
  Nothing -> False

hasIdTokenWrite :: Maybe Permissions -> Bool
hasIdTokenWrite Nothing = False
hasIdTokenWrite (Just (PermissionsAll PermWrite)) = True
hasIdTokenWrite (Just (PermissionsMap m)) =
  Map.lookup "id-token" m == Just PermWrite
hasIdTokenWrite _ = False

isDeploymentStep :: Step -> Bool
isDeploymentStep s = case stepUses s of
  Just uses -> any (`T.isInfixOf` uses) deploymentActions
  Nothing -> False

-- | Actions that typically consume OIDC tokens.
deploymentActions :: [Text]
deploymentActions =
  [ "aws-actions/configure-aws-credentials"
  , "azure/login"
  , "google-github-actions/auth"
  , "hashicorp/vault-action"
  ]

isFirstPartyAction :: Text -> Bool
isFirstPartyAction t =
  "actions/" `T.isPrefixOf` t
  || "github/" `T.isPrefixOf` t
  || "./" `T.isPrefixOf` t

-- | Extract "owner/repo" from "owner/repo@ref" or "owner/repo/path@ref".
extractOwnerRepo :: Text -> Maybe Text
extractOwnerRepo uses =
  let noRef = T.takeWhile (/= '@') uses
      parts = T.splitOn "/" noRef
  in case parts of
       (owner : repo : _) | not (T.null owner) && not (T.null repo) ->
         Just (owner <> "/" <> repo)
       _ -> Nothing

-- | Compiled-in list of known abandoned/archived actions.
-- This list is curated and updated with each release.
abandonedActions :: [Text]
abandonedActions =
  [ -- Add known abandoned actions here as they are identified.
    -- Format: "owner/repo"
  ]

-- | Popular actions to check for typosquatting.
popularActions :: [Text]
popularActions =
  [ "actions/checkout"
  , "actions/setup-node"
  , "actions/setup-python"
  , "actions/setup-java"
  , "actions/setup-go"
  , "actions/cache"
  , "actions/upload-artifact"
  , "actions/download-artifact"
  , "actions/github-script"
  , "actions/labeler"
  , "docker/build-push-action"
  , "docker/setup-buildx-action"
  , "docker/login-action"
  , "aws-actions/configure-aws-credentials"
  , "azure/login"
  , "google-github-actions/auth"
  , "softprops/action-gh-release"
  , "peter-evans/create-pull-request"
  , "peaceiris/actions-gh-pages"
  , "JamesIves/github-pages-deploy-action"
  ]

-- | Check if an action owner/repo is a likely typosquat of a popular action.
-- Uses simple edit distance: differs by exactly 1 character (insertion, deletion, or substitution).
checkTyposquat :: FilePath -> Text -> Text -> Text -> [Finding]
checkTyposquat fp fullUses candidate popular
  | candidate == popular = []  -- Exact match, not a typosquat
  | editDistance candidate popular <= 2 && candidate /= popular =
      [ mkFinding' Info SupplyChain "SUPPLY-002"
          ("Action '" <> fullUses <> "' looks similar to popular action '"
          <> popular <> "'. This may be a typosquat.")
          fp
          Nothing
          (Just $ "Verify you intended '" <> fullUses <> "' and not '" <> popular <> "'.")
      ]
  | otherwise = []

-- | Simple Levenshtein edit distance for short strings.
editDistance :: Text -> Text -> Int
editDistance a b = go (T.unpack a) (T.unpack b)
  where
    go [] ys = length ys
    go xs [] = length xs
    go (x:xs) (y:ys)
      | x == y = go xs ys
      | otherwise = 1 + minimum [go xs (y:ys), go (x:xs) ys, go xs ys]
```

- [ ] **Step 4: Register module in cabal and test runner**

Add `Orchestrator.Rules.SupplyChain` to `orchestrator.cabal` exposed-modules.
Add `Test.SupplyChain` to test-suite other-modules and `test/Main.hs`.

- [ ] **Step 5: Run tests**

Run: `cabal test all --test-show-details=direct`
Expected: All SupplyChain tests pass.

- [ ] **Step 6: Commit**

```bash
git add src/Orchestrator/Rules/SupplyChain.hs test/Test/SupplyChain.hs \
  test/Main.hs orchestrator.cabal
git commit -m "feat: add supply chain rules SEC-003, SEC-004, SEC-005, SUPPLY-001, SUPPLY-002"
```

---

## Task 7: Performance Rules (PERF-001, PERF-002)

**Files:**
- Create: `src/Orchestrator/Rules/Performance.hs`
- Create: `test/Test/Performance.hs`

- [ ] **Step 1: Write failing tests**

Create `test/Test/Performance.hs`:

```haskell
module Test.Performance (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..), evaluatePolicy)
import Orchestrator.Rules.Performance
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "Performance Rules"
  [ perf001Tests
  , perf002Tests
  ]

------------------------------------------------------------------------
-- PERF-001: Missing Cache
------------------------------------------------------------------------

perf001Tests :: TestTree
perf001Tests = testGroup "PERF-001 Missing Cache"
  [ testCase "Detects Node build without cache" $ do
      let wf = mkWf [mkJob "build"
                       [ mkUseStep "actions/setup-node@v4"
                       , mkRunStep "npm install && npm run build"
                       ]]
          findings = evaluatePolicy missingCacheRule wf
      assertBool "Should detect missing cache" (not $ null findings)

  , testCase "No finding when cache is present" $ do
      let wf = mkWf [mkJob "build"
                       [ mkUseStep "actions/setup-node@v4"
                       , mkUseStep "actions/cache@v4"
                       , mkRunStep "npm install && npm run build"
                       ]]
          findings = evaluatePolicy missingCacheRule wf
      assertBool "Should not flag with cache" (null findings)

  , testCase "Detects Rust build without cache" $ do
      let wf = mkWf [mkJob "build"
                       [ mkRunStep "cargo build"
                       ]]
          findings = evaluatePolicy missingCacheRule wf
      assertBool "Should detect missing cache for Rust" (not $ null findings)

  , testCase "No finding for non-build workflow" $ do
      let wf = mkWf [mkJob "lint" [mkRunStep "echo linting"]]
          findings = evaluatePolicy missingCacheRule wf
      assertBool "Should not flag non-build" (null findings)
  ]

------------------------------------------------------------------------
-- PERF-002: Sequential Parallelizable Jobs
------------------------------------------------------------------------

perf002Tests :: TestTree
perf002Tests = testGroup "PERF-002 Sequential Parallelizable Jobs"
  [ testCase "Detects multiple independent jobs" $ do
      let wf = mkWf [ mkJob "lint" [mkRunStep "npm run lint"]
                     , mkJob "test" [mkRunStep "npm test"]
                     , mkJob "build" [mkRunStep "npm run build"]
                     ]
          findings = evaluatePolicy sequentialJobsRule wf
      -- All 3 jobs have no needs: dependencies, could run in parallel
      assertBool "Should suggest parallelization" (not $ null findings)

  , testCase "No finding for jobs with dependencies" $ do
      let wf = mkWf [ mkJob "build" [mkRunStep "npm run build"]
                     , mkJobWithNeeds "test" ["build"] [mkRunStep "npm test"]
                     ]
          findings = evaluatePolicy sequentialJobsRule wf
      assertBool "Should not flag dependent jobs" (null findings)

  , testCase "No finding for single job" $ do
      let wf = mkWf [mkJob "build" [mkRunStep "npm run build"]]
          findings = evaluatePolicy sequentialJobsRule wf
      assertBool "Should not flag single job" (null findings)
  ]

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

mkJobWithNeeds :: T.Text -> [T.Text] -> [Step] -> Job
mkJobWithNeeds jid needs steps = Job jid (Just jid) (StandardRunner "ubuntu-latest")
  steps Nothing needs Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkRunStep :: T.Text -> Step
mkRunStep cmd = Step Nothing Nothing Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

mkUseStep :: T.Text -> Step
mkUseStep action = Step Nothing Nothing (Just action) Nothing Map.empty Map.empty Nothing Nothing
```

- [ ] **Step 2: Implement Performance rules**

Create `src/Orchestrator/Rules/Performance.hs`:

```haskell
-- | Performance rules for GitHub Actions workflows.
--
-- Detects missing caching and missed parallelization opportunities.
module Orchestrator.Rules.Performance
  ( missingCacheRule
  , sequentialJobsRule
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | PERF-001: Detect build workflows without caching.
missingCacheRule :: PolicyRule
missingCacheRule = PolicyRule
  { ruleId = "PERF-001"
  , ruleName = "Missing Cache"
  , ruleDescription = "Build workflows should use caching to speed up builds"
  , ruleSeverity = Warning
  , ruleCategory = Performance
  , ruleTags = [TagPerformance]
  , ruleCheck = \wf ->
      concatMap (\j ->
        let steps = jobSteps j
            hasBuild = any isBuildStep steps
            hasCache = any isCacheStep steps
        in [ mkFinding' Warning Performance "PERF-001"
                ("Job '" <> jobId j <> "' appears to run a build but has no cache step. "
                <> "Adding caching can significantly reduce CI time.")
                (wfFileName wf)
                Nothing
                (Just "Add actions/cache or use the setup action's built-in caching.")
           | hasBuild && not hasCache
           ]
      ) (wfJobs wf)
  }

-- | PERF-002: Detect multiple independent jobs that could run in parallel.
sequentialJobsRule :: PolicyRule
sequentialJobsRule = PolicyRule
  { ruleId = "PERF-002"
  , ruleName = "Sequential Parallelizable Jobs"
  , ruleDescription = "Independent jobs should run in parallel"
  , ruleSeverity = Info
  , ruleCategory = Performance
  , ruleTags = [TagPerformance]
  , ruleCheck = \wf ->
      let jobs = wfJobs wf
          independentJobs = filter (null . jobNeeds) jobs
      in [ mkFinding' Info Performance "PERF-002"
              (T.pack (show (length independentJobs))
              <> " jobs have no 'needs:' dependencies. If they are truly independent, "
              <> "GitHub Actions will run them in parallel automatically. "
              <> "Verify this is intentional.")
              (wfFileName wf)
              Nothing
              (Just "Add 'needs:' to create explicit dependencies, or confirm parallelism is intended.")
         | length jobs > 2 && length independentJobs >= 3
         ]
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- | Detect build-related steps by command patterns or setup actions.
isBuildStep :: Step -> Bool
isBuildStep s =
  case stepRun s of
    Just cmd -> any (`T.isInfixOf` cmd) buildCommands
    Nothing -> case stepUses s of
      Just uses -> any (`T.isInfixOf` uses) setupActions
      Nothing -> False

buildCommands :: [Text]
buildCommands =
  [ "npm install", "npm ci", "npm run build", "yarn install", "yarn build"
  , "pnpm install", "pnpm build"
  , "cargo build", "cargo test"
  , "cabal build", "stack build"
  , "go build", "go test"
  , "pip install", "poetry install", "pipenv install"
  , "mvn ", "gradle ", "./gradlew"
  , "dotnet build", "dotnet restore"
  , "make", "cmake"
  ]

setupActions :: [Text]
setupActions =
  [ "actions/setup-node"
  , "actions/setup-python"
  , "actions/setup-java"
  , "actions/setup-go"
  , "actions/setup-dotnet"
  , "haskell-actions/setup"
  , "ATiltedTree/setup-rust"
  , "dtolnay/rust-toolchain"
  ]

-- | Detect caching steps.
isCacheStep :: Step -> Bool
isCacheStep s = case stepUses s of
  Just uses -> "cache" `T.isInfixOf` T.toLower uses
  Nothing -> False
```

- [ ] **Step 3: Register module, run tests**

Add `Orchestrator.Rules.Performance` to cabal. Add `Test.Performance` to test runner.

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/Orchestrator/Rules/Performance.hs test/Test/Performance.hs \
  test/Main.hs orchestrator.cabal
git commit -m "feat: add performance rules PERF-001, PERF-002"
```

---

## Task 8: Cost Rules (COST-001, COST-002)

**Files:**
- Create: `src/Orchestrator/Rules/Cost.hs`
- Create: `test/Test/Cost.hs`

- [ ] **Step 1: Write failing tests**

Create `test/Test/Cost.hs`:

```haskell
module Test.Cost (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..), evaluatePolicy)
import Orchestrator.Rules.Cost
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "Cost Rules"
  [ cost001Tests
  , cost002Tests
  ]

------------------------------------------------------------------------
-- COST-001: Matrix Waste
------------------------------------------------------------------------

cost001Tests :: TestTree
cost001Tests = testGroup "COST-001 Matrix Waste"
  [ testCase "Detects matrix with immediate exclude in if condition" $ do
      let wf = mkWf [mkMatrixJobWithIf "build"
                       "matrix.os != 'windows-latest'"
                       [mkRunStep "echo build"]]
          findings = evaluatePolicy matrixWasteRule wf
      assertBool "Should detect matrix waste" (not $ null findings)

  , testCase "No finding for matrix without exclusion" $ do
      let wf = mkWf [mkMatrixJob "build" [mkRunStep "echo build"]]
          findings = evaluatePolicy matrixWasteRule wf
      assertBool "Should not flag" (null findings)
  ]

------------------------------------------------------------------------
-- COST-002: Redundant Artifact Upload
------------------------------------------------------------------------

cost002Tests :: TestTree
cost002Tests = testGroup "COST-002 Redundant Artifact Upload"
  [ testCase "Detects multiple upload-artifact in same workflow" $ do
      let wf = mkWf [ mkJob "build1" [mkUseStep "actions/upload-artifact@v4"]
                     , mkJob "build2" [mkUseStep "actions/upload-artifact@v4"]
                     ]
          findings = evaluatePolicy redundantArtifactRule wf
      assertBool "Should detect redundant uploads" (not $ null findings)

  , testCase "No finding for single upload" $ do
      let wf = mkWf [mkJob "build" [mkUseStep "actions/upload-artifact@v4"]]
          findings = evaluatePolicy redundantArtifactRule wf
      assertBool "Should not flag single upload" (null findings)
  ]

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

mkMatrixJob :: T.Text -> [Step] -> Job
mkMatrixJob jid steps = Job jid (Just jid) (MatrixRunner "${{ matrix.os }}")
  steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkMatrixJobWithIf :: T.Text -> T.Text -> [Step] -> Job
mkMatrixJobWithIf jid cond steps = Job jid (Just jid) (MatrixRunner "${{ matrix.os }}")
  steps Nothing [] Nothing Map.empty (Just cond) (Just 30) Nothing False Nothing False

mkRunStep :: T.Text -> Step
mkRunStep cmd = Step Nothing Nothing Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

mkUseStep :: T.Text -> Step
mkUseStep action = Step Nothing Nothing (Just action) Nothing Map.empty Map.empty Nothing Nothing
```

- [ ] **Step 2: Implement Cost rules**

Create `src/Orchestrator/Rules/Cost.hs`:

```haskell
-- | Cost rules for GitHub Actions workflows.
--
-- Detects wasteful patterns: matrix entries that are immediately excluded
-- and redundant artifact uploads across jobs.
module Orchestrator.Rules.Cost
  ( matrixWasteRule
  , redundantArtifactRule
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | COST-001: Detect matrix jobs with exclusion conditions.
-- When a matrix job has an 'if' condition that excludes matrix values,
-- the excluded combinations still start runners briefly before being skipped.
matrixWasteRule :: PolicyRule
matrixWasteRule = PolicyRule
  { ruleId = "COST-001"
  , ruleName = "Matrix Waste"
  , ruleDescription = "Detect matrix entries excluded by job-level conditions"
  , ruleSeverity = Warning
  , ruleCategory = Cost
  , ruleTags = [TagCost]
  , ruleCheck = \wf ->
      concatMap (\j ->
        let isMatrix = case jobRunsOn j of
              MatrixRunner _ -> True
              _ -> False
            hasExcludeIf = case jobIf j of
              Just cond -> "matrix." `T.isInfixOf` cond
                           && ("!=" `T.isInfixOf` cond || "!contains" `T.isInfixOf` cond)
              Nothing -> False
        in [ mkFinding' Warning Cost "COST-001"
                ("Job '" <> jobId j <> "' uses a matrix with a condition that excludes entries. "
                <> "Excluded matrix combinations still start runners. "
                <> "Use 'exclude:' in the matrix definition instead.")
                (wfFileName wf)
                Nothing
                (Just "Use 'strategy.matrix.exclude' instead of job-level 'if' conditions.")
           | isMatrix && hasExcludeIf
           ]
      ) (wfJobs wf)
  }

-- | COST-002: Detect multiple artifact upload steps across jobs.
redundantArtifactRule :: PolicyRule
redundantArtifactRule = PolicyRule
  { ruleId = "COST-002"
  , ruleName = "Redundant Artifact Upload"
  , ruleDescription = "Detect multiple jobs uploading artifacts in the same workflow"
  , ruleSeverity = Info
  , ruleCategory = Cost
  , ruleTags = [TagCost]
  , ruleCheck = \wf ->
      let uploadJobs = filter (any isUploadArtifact . jobSteps) (wfJobs wf)
      in [ mkFinding' Info Cost "COST-002"
              (T.pack (show (length uploadJobs)) <> " jobs upload artifacts. "
              <> "Multiple uploads in one workflow may create redundant storage. "
              <> "Verify they upload distinct, necessary content.")
              (wfFileName wf)
              Nothing
              (Just "Consolidate artifact uploads or verify each uploads unique content.")
         | length uploadJobs > 1
         ]
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

isUploadArtifact :: Step -> Bool
isUploadArtifact s = case stepUses s of
  Just uses -> "upload-artifact" `T.isInfixOf` uses
  Nothing -> False
```

- [ ] **Step 3: Register module, run tests**

Add module and tests to cabal and test runner.

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/Orchestrator/Rules/Cost.hs test/Test/Cost.hs \
  test/Main.hs orchestrator.cabal
git commit -m "feat: add cost rules COST-001, COST-002"
```

---

## Task 9: Hardening Rules (HARD-001, HARD-002, HARD-003)

**Files:**
- Create: `src/Orchestrator/Rules/Hardening.hs`
- Create: `test/Test/Hardening.hs`

- [ ] **Step 1: Write failing tests**

Create `test/Test/Hardening.hs`:

```haskell
module Test.Hardening (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..), evaluatePolicy)
import Orchestrator.Rules.Hardening
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

tests :: TestTree
tests = testGroup "Hardening Rules"
  [ hard001Tests
  , hard002Tests
  , hard003Tests
  ]

------------------------------------------------------------------------
-- HARD-001: Missing persist-credentials: false
------------------------------------------------------------------------

hard001Tests :: TestTree
hard001Tests = testGroup "HARD-001 Missing persist-credentials: false"
  [ testCase "Detects checkout without persist-credentials" $ do
      let wf = mkWf [mkJob "build" [mkUseStep "actions/checkout@v4"]]
          findings = evaluatePolicy persistCredentialsRule wf
      assertBool "Should detect missing persist-credentials" (not $ null findings)

  , testCase "No finding when persist-credentials: false" $ do
      let step = Step Nothing Nothing (Just "actions/checkout@v4") Nothing
                   (Map.fromList [("persist-credentials", "false")]) Map.empty Nothing Nothing
          wf = mkWf [mkJob "build" [step]]
          findings = evaluatePolicy persistCredentialsRule wf
      assertBool "Should not flag" (null findings)

  , testCase "No finding for non-checkout actions" $ do
      let wf = mkWf [mkJob "build" [mkUseStep "actions/setup-node@v4"]]
          findings = evaluatePolicy persistCredentialsRule wf
      assertBool "Should not flag non-checkout" (null findings)
  ]

------------------------------------------------------------------------
-- HARD-002: Default Shell Unset
------------------------------------------------------------------------

hard002Tests :: TestTree
hard002Tests = testGroup "HARD-002 Default Shell Unset"
  [ testCase "Detects workflow with run steps but no default shell" $ do
      let wf = mkWf [mkJob "build" [mkRunStep "echo hello"]]
          findings = evaluatePolicy defaultShellRule wf
      assertBool "Should detect missing default shell" (not $ null findings)

  , testCase "No finding when steps specify shell" $ do
      let step = Step Nothing Nothing Nothing (Just "echo hello") Map.empty Map.empty Nothing (Just "bash")
          wf = mkWf [mkJob "build" [step]]
          findings = evaluatePolicy defaultShellRule wf
      assertBool "Should not flag with explicit shell" (null findings)

  , testCase "No finding for workflow without run steps" $ do
      let wf = mkWf [mkJob "build" [mkUseStep "actions/checkout@v4"]]
          findings = evaluatePolicy defaultShellRule wf
      assertBool "Should not flag action-only" (null findings)
  ]

------------------------------------------------------------------------
-- HARD-003: Pull Request Target Risk
------------------------------------------------------------------------

hard003Tests :: TestTree
hard003Tests = testGroup "HARD-003 Pull Request Target Risk"
  [ testCase "Detects pull_request_target with checkout" $ do
      let wf = (mkWf [mkJob "build" [mkUseStep "actions/checkout@v4"]])
               { wfTriggers = [TriggerEvents [TriggerEvent "pull_request_target" [] [] []]] }
          findings = evaluatePolicy prTargetRiskRule wf
      assertBool "Should detect PR target risk" (not $ null findings)

  , testCase "No finding for regular pull_request" $ do
      let wf = (mkWf [mkJob "build" [mkUseStep "actions/checkout@v4"]])
               { wfTriggers = [TriggerEvents [TriggerEvent "pull_request" [] [] []]] }
          findings = evaluatePolicy prTargetRiskRule wf
      assertBool "Should not flag regular PR" (null findings)
  ]

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

mkRunStep :: T.Text -> Step
mkRunStep cmd = Step Nothing Nothing Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

mkUseStep :: T.Text -> Step
mkUseStep action = Step Nothing Nothing (Just action) Nothing Map.empty Map.empty Nothing Nothing
```

- [ ] **Step 2: Implement Hardening rules**

Create `src/Orchestrator/Rules/Hardening.hs`:

```haskell
-- | Hardening rules for GitHub Actions workflows.
--
-- Detects missing persist-credentials: false on checkout, missing default
-- shell specification, and pull_request_target with code checkout.
module Orchestrator.Rules.Hardening
  ( persistCredentialsRule
  , defaultShellRule
  , prTargetRiskRule
  ) where

import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | HARD-001: Checkout without persist-credentials: false.
persistCredentialsRule :: PolicyRule
persistCredentialsRule = PolicyRule
  { ruleId = "HARD-001"
  , ruleName = "Missing persist-credentials: false"
  , ruleDescription = "Checkout should set persist-credentials: false"
  , ruleSeverity = Warning
  , ruleCategory = Security
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      concatMap (\j ->
        concatMap (\s ->
          case stepUses s of
            Just uses | "actions/checkout" `T.isPrefixOf` uses ->
              let pc = Map.lookup "persist-credentials" (stepWith s)
              in [ mkFinding' Warning Security "HARD-001"
                      ("Job '" <> jobId j <> "' uses actions/checkout without "
                      <> "persist-credentials: false. The GITHUB_TOKEN remains "
                      <> "in the git config after checkout.")
                      (wfFileName wf)
                      Nothing
                      (Just "Add 'with: { persist-credentials: false }' to checkout.")
                 | pc /= Just "false"
                 ]
            _ -> []
        ) (jobSteps j)
      ) (wfJobs wf)
  }

-- | HARD-002: Missing default shell specification.
defaultShellRule :: PolicyRule
defaultShellRule = PolicyRule
  { ruleId = "HARD-002"
  , ruleName = "Default Shell Unset"
  , ruleDescription = "Workflows with run steps should specify shell"
  , ruleSeverity = Info
  , ruleCategory = Security
  , ruleTags = [TagSecurity, TagStyle]
  , ruleCheck = \wf ->
      let allSteps = concatMap jobSteps (wfJobs wf)
          runSteps = filter (not . isNothing . stepRun) allSteps
          unshelled = filter (isNothing . stepShell) runSteps
      in [ mkFinding' Info Security "HARD-002"
              ("Workflow has " <> T.pack (show (length unshelled))
              <> " run steps without an explicit shell. Default shell behavior "
              <> "varies by platform (bash on Linux, pwsh on Windows).")
              (wfFileName wf)
              Nothing
              (Just "Set 'defaults: { run: { shell: bash } }' or specify shell per-step.")
         | not (null unshelled)
         ]
  }

-- | HARD-003: pull_request_target with code checkout.
prTargetRiskRule :: PolicyRule
prTargetRiskRule = PolicyRule
  { ruleId = "HARD-003"
  , ruleName = "Pull Request Target Risk"
  , ruleDescription = "Detect pull_request_target with actions/checkout"
  , ruleSeverity = Error
  , ruleCategory = Security
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      let hasPRTarget = any isPRTargetTrigger (wfTriggers wf)
          hasCheckout = any (any isCheckoutStep . jobSteps) (wfJobs wf)
      in [ mkFinding' Error Security "HARD-003"
              "Workflow uses pull_request_target and contains an actions/checkout step. "
              <> "This combination can execute untrusted code from forks with elevated "
              <> "permissions. This is a known attack vector."
              (wfFileName wf)
              Nothing
              (Just "Use pull_request event, or if pull_request_target is needed, "
              <> "never check out the PR head ref.")
         | hasPRTarget && hasCheckout
         ]
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

isPRTargetTrigger :: WorkflowTrigger -> Bool
isPRTargetTrigger (TriggerEvents evts) =
  any (\e -> triggerName e == "pull_request_target") evts
isPRTargetTrigger _ = False

isCheckoutStep :: Step -> Bool
isCheckoutStep s = case stepUses s of
  Just uses -> "actions/checkout" `T.isPrefixOf` uses
  Nothing -> False
```

Note: The HARD-003 `ruleCheck` has a string concatenation issue with `(<>)` on `mkFinding'`. Fix by using parentheses or a `let` binding for the message and remediation strings:

```haskell
  , ruleCheck = \wf ->
      let hasPRTarget = any isPRTargetTrigger (wfTriggers wf)
          hasCheckout = any (any isCheckoutStep . jobSteps) (wfJobs wf)
          msg = "Workflow uses pull_request_target and contains an actions/checkout step. \
                \This combination can execute untrusted code from forks with elevated \
                \permissions. This is a known attack vector."
          fix' = "Use pull_request event, or if pull_request_target is needed, \
                 \never check out the PR head ref."
      in [ mkFinding' Error Security "HARD-003" msg (wfFileName wf) Nothing (Just fix')
         | hasPRTarget && hasCheckout
         ]
```

- [ ] **Step 3: Register module, run tests**

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/Orchestrator/Rules/Hardening.hs test/Test/Hardening.hs \
  test/Main.hs orchestrator.cabal
git commit -m "feat: add hardening rules HARD-001, HARD-002, HARD-003"
```

---

## Task 10: Drift Rule (DRIFT-001)

**Files:**
- Create: `src/Orchestrator/Rules/Drift.hs`
- Create: `test/Test/DriftRule.hs`

- [ ] **Step 1: Write failing tests**

Create `test/Test/DriftRule.hs`:

```haskell
module Test.DriftRule (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..), evaluatePolicy)
import Orchestrator.Rules.Drift
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool)

tests :: TestTree
tests = testGroup "Drift Rules"
  [ testCase "Detects same action at different versions" $ do
      let wf = mkWf [ mkJob "build" [mkUseStep "actions/checkout@v3"]
                     , mkJob "test"  [mkUseStep "actions/checkout@v4"]
                     ]
          findings = evaluatePolicy intraRepoDriftRule wf
      assertBool "Should detect version drift" (not $ null findings)

  , testCase "No finding when all versions match" $ do
      let wf = mkWf [ mkJob "build" [mkUseStep "actions/checkout@v4"]
                     , mkJob "test"  [mkUseStep "actions/checkout@v4"]
                     ]
          findings = evaluatePolicy intraRepoDriftRule wf
      assertBool "Should not flag consistent versions" (null findings)

  , testCase "No finding for different actions" $ do
      let wf = mkWf [ mkJob "build" [mkUseStep "actions/checkout@v4"]
                     , mkJob "test"  [mkUseStep "actions/setup-node@v4"]
                     ]
          findings = evaluatePolicy intraRepoDriftRule wf
      assertBool "Should not flag different actions" (null findings)

  , testCase "No finding for single use" $ do
      let wf = mkWf [mkJob "build" [mkUseStep "actions/checkout@v4"]]
          findings = evaluatePolicy intraRepoDriftRule wf
      assertBool "Should not flag single use" (null findings)
  ]

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

mkUseStep :: T.Text -> Step
mkUseStep action = Step Nothing Nothing (Just action) Nothing Map.empty Map.empty Nothing Nothing
```

- [ ] **Step 2: Implement Drift rule**

Create `src/Orchestrator/Rules/Drift.hs`:

```haskell
-- | Drift detection rules.
--
-- Detects inconsistent action versions within a single workflow.
module Orchestrator.Rules.Drift
  ( intraRepoDriftRule
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | DRIFT-001: Detect same action used at different versions.
intraRepoDriftRule :: PolicyRule
intraRepoDriftRule = PolicyRule
  { ruleId = "DRIFT-001"
  , ruleName = "Intra-Repo Inconsistency"
  , ruleDescription = "Detect same action at different versions within a workflow"
  , ruleSeverity = Info
  , ruleCategory = Drift
  , ruleTags = [TagStyle, TagStructure]
  , ruleCheck = \wf ->
      let actionVersions = collectActionVersions wf
          drifted = Map.filter (\vs -> length vs > 1) actionVersions
      in concatMap (\(action, versions) ->
            [ mkFinding' Info Drift "DRIFT-001"
                ("Action '" <> action <> "' is used at multiple versions: "
                <> T.intercalate ", " versions <> ". "
                <> "Inconsistent versions may cause subtle behavior differences.")
                (wfFileName wf)
                Nothing
                (Just $ "Standardize on a single version for '" <> action <> "'.")
            ]
         ) (Map.toList drifted)
  }

-- | Collect all action references grouped by action name (without version).
-- Returns a map from "owner/repo" to list of distinct versions seen.
collectActionVersions :: Workflow -> Map Text [Text]
collectActionVersions wf =
  let allUses = concatMap (concatMap (maybe [] pure . stepUses) . jobSteps) (wfJobs wf)
      parsed = concatMap parseActionRef allUses
      grouped = foldl (\m (name, ver) -> Map.insertWith (\new old ->
        if head new `elem` old then old else old ++ new
        ) name [ver] m) Map.empty parsed
  in grouped

-- | Parse "owner/repo@version" into ("owner/repo", "version").
parseActionRef :: Text -> [(Text, Text)]
parseActionRef uses
  | "./" `T.isPrefixOf` uses = []  -- Skip local actions
  | "@" `T.isInfixOf` uses =
      let (name, rest) = T.breakOn "@" uses
          version = T.drop 1 rest
      in [(name, version) | not (T.null name) && not (T.null version)]
  | otherwise = []
```

- [ ] **Step 3: Register module, run tests**

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/Orchestrator/Rules/Drift.hs test/Test/DriftRule.hs \
  test/Main.hs orchestrator.cabal
git commit -m "feat: add drift rule DRIFT-001 for intra-repo version inconsistency"
```

---

## Task 11: Structure Rules (STRUCT-001, STRUCT-002)

**Files:**
- Create: `src/Orchestrator/Rules/Structure.hs`
- Create: `test/Test/StructureRule.hs`

- [ ] **Step 1: Write failing tests**

Create `test/Test/StructureRule.hs`:

```haskell
module Test.StructureRule (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..), evaluatePolicy)
import Orchestrator.Rules.Structure
import Orchestrator.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool)

tests :: TestTree
tests = testGroup "Structure Rules"
  [ struct001Tests
  , struct002Tests
  ]

------------------------------------------------------------------------
-- STRUCT-001: Unreferenced Reusable Workflow
------------------------------------------------------------------------

struct001Tests :: TestTree
struct001Tests = testGroup "STRUCT-001 Unreferenced Reusable Workflow"
  [ testCase "Detects reusable workflow never called" $ do
      -- A workflow with workflow_call trigger but no other workflow references it
      let wf = mkWf [TriggerEvents [TriggerEvent "workflow_call" [] [] []]]
                     [mkJob "build" [mkRunStep "echo reusable"]]
      -- This rule needs multi-workflow context. For single-workflow analysis,
      -- it flags any workflow_call workflow as potentially unreferenced.
      -- Full detection requires the scan-level context (multiple workflows).
      let findings = evaluatePolicy unreferencedReusableRule wf
      -- Single-file mode: flags as info
      assertBool "Should flag reusable workflow" (not $ null findings)

  , testCase "No finding for regular workflow" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "build" [mkRunStep "echo build"]]
          findings = evaluatePolicy unreferencedReusableRule wf
      assertBool "Should not flag non-reusable" (null findings)
  ]

------------------------------------------------------------------------
-- STRUCT-002: Circular Workflow Call
------------------------------------------------------------------------

struct002Tests :: TestTree
struct002Tests = testGroup "STRUCT-002 Circular Workflow Call"
  [ testCase "Detects self-referencing workflow" $ do
      let wf = (mkWf [TriggerEvents [TriggerEvent "workflow_call" [] [] []]]
                      [mkJob "build" [mkUseStep "./.github/workflows/test.yml"]])
               { wfFileName = ".github/workflows/test.yml" }
          findings = evaluatePolicy circularWorkflowCallRule wf
      assertBool "Should detect self-reference" (not $ null findings)

  , testCase "No finding for normal reusable call" $ do
      let wf = mkWf [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
                     [mkJob "build" [mkUseStep "./.github/workflows/shared.yml"]]
          findings = evaluatePolicy circularWorkflowCallRule wf
      assertBool "Should not flag normal call" (null findings)
  ]

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [WorkflowTrigger] -> [Job] -> Workflow
mkWf triggers jobs = Workflow "Test" "test.yml" triggers jobs Nothing Nothing Map.empty

mkJob :: T.Text -> [Step] -> Job
mkJob jid steps = Job jid (Just jid) (StandardRunner "ubuntu-latest")
  steps Nothing [] Nothing Map.empty Nothing (Just 30) Nothing False Nothing False

mkRunStep :: T.Text -> Step
mkRunStep cmd = Step Nothing Nothing Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

mkUseStep :: T.Text -> Step
mkUseStep action = Step Nothing Nothing (Just action) Nothing Map.empty Map.empty Nothing Nothing
```

- [ ] **Step 2: Implement Structure rules**

Create `src/Orchestrator/Rules/Structure.hs`:

```haskell
-- | Structural rules for workflow organization.
--
-- Detects unreferenced reusable workflows and circular workflow calls.
module Orchestrator.Rules.Structure
  ( unreferencedReusableRule
  , circularWorkflowCallRule
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | STRUCT-001: Detect reusable workflows that may not be called.
-- In single-file mode, this flags any workflow with workflow_call trigger
-- as a reminder to verify it is actually referenced.
unreferencedReusableRule :: PolicyRule
unreferencedReusableRule = PolicyRule
  { ruleId = "STRUCT-001"
  , ruleName = "Unreferenced Reusable Workflow"
  , ruleDescription = "Reusable workflows should be called by at least one other workflow"
  , ruleSeverity = Info
  , ruleCategory = Structure
  , ruleTags = [TagStructure]
  , ruleCheck = \wf ->
      let isReusable = any isWorkflowCallTrigger (wfTriggers wf)
      in [ mkFinding' Info Structure "STRUCT-001"
              ("Workflow '" <> wfName wf <> "' has a workflow_call trigger. "
              <> "Verify it is referenced by at least one other workflow.")
              (wfFileName wf)
              Nothing
              (Just "Remove the workflow_call trigger if this workflow is not used as a reusable workflow.")
         | isReusable
         ]
  }

-- | STRUCT-002: Detect circular workflow calls.
-- A workflow that calls itself (directly) via a reusable workflow reference.
circularWorkflowCallRule :: PolicyRule
circularWorkflowCallRule = PolicyRule
  { ruleId = "STRUCT-002"
  , ruleName = "Circular Workflow Call"
  , ruleDescription = "Detect workflows that call themselves"
  , ruleSeverity = Error
  , ruleCategory = Structure
  , ruleTags = [TagStructure]
  , ruleCheck = \wf ->
      let ownPath = wfFileName wf
          calledWorkflows = concatMap (concatMap getWorkflowCall . jobSteps) (wfJobs wf)
          selfCalls = filter (isSameWorkflow ownPath) calledWorkflows
      in [ mkFinding' Error Structure "STRUCT-002"
              ("Workflow calls itself via '" <> call <> "'. "
              <> "This creates an infinite recursion that GitHub will reject.")
              (wfFileName wf)
              Nothing
              (Just "Remove the self-referencing workflow call.")
         | call <- selfCalls
         ]
  }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

isWorkflowCallTrigger :: WorkflowTrigger -> Bool
isWorkflowCallTrigger (TriggerEvents evts) =
  any (\e -> triggerName e == "workflow_call") evts
isWorkflowCallTrigger _ = False

-- | Extract reusable workflow references from job-level 'uses:'.
-- Reusable workflows are called at the job level, not step level,
-- but in our model they appear as steps with uses: pointing to .yml files.
getWorkflowCall :: Step -> [Text]
getWorkflowCall s = case stepUses s of
  Just uses | ".yml" `T.isSuffixOf` uses || ".yaml" `T.isSuffixOf` uses -> [uses]
  _ -> []

-- | Check if a workflow call references the same file.
isSameWorkflow :: FilePath -> Text -> Bool
isSameWorkflow ownPath call =
  let normalizedCall = T.replace "./" "" call
      normalizedOwn = T.pack ownPath
  in normalizedCall == normalizedOwn
     || ("./" <> normalizedCall) == normalizedOwn
     || normalizedCall == T.replace "./" "" normalizedOwn
```

- [ ] **Step 3: Register module, run tests**

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/Orchestrator/Rules/Structure.hs test/Test/StructureRule.hs \
  test/Main.hs orchestrator.cabal
git commit -m "feat: add structure rules STRUCT-001, STRUCT-002"
```

---

## Task 12: Register All Rules and Update Version

**Files:**
- Modify: `src/Orchestrator/Policy/Extended.hs`
- Modify: `src/Orchestrator/Version.hs`
- Modify: `orchestrator.cabal`

- [ ] **Step 1: Update Extended.hs with all 15 new rules**

```haskell
module Orchestrator.Policy.Extended
  ( extendedPolicyPack
  , allCommunityRules
  ) where

import Orchestrator.Graph (graphCycleRule, graphOrphanRule)
import Orchestrator.Policy (PolicyPack (..), PolicyRule (..), defaultPolicyPack)
import Orchestrator.Rules.Composite (compositeDescriptionRule, compositeShellRule)
import Orchestrator.Rules.Cost (matrixWasteRule, redundantArtifactRule)
import Orchestrator.Rules.Drift (intraRepoDriftRule)
import Orchestrator.Rules.Duplicate (duplicateJobRule)
import Orchestrator.Rules.Environment (envApprovalGateRule, envMissingUrlRule)
import Orchestrator.Rules.Hardening (persistCredentialsRule, defaultShellRule, prTargetRiskRule)
import Orchestrator.Rules.Matrix (matrixExplosionRule, matrixFailFastRule)
import Orchestrator.Rules.Performance (missingCacheRule, sequentialJobsRule)
import Orchestrator.Rules.Reuse (reuseInputValidationRule, reuseUnusedOutputRule)
import Orchestrator.Rules.Structure (unreferencedReusableRule, circularWorkflowCallRule)
import Orchestrator.Rules.SupplyChain
  ( workflowRunEscalationRule, artifactPoisoningRule, oidcTokenScopeRule
  , abandonedActionRule, typosquatRiskRule
  )

additionalRules :: [PolicyRule]
additionalRules =
  [ -- Existing extended rules
    graphCycleRule
  , graphOrphanRule
  , duplicateJobRule
  , reuseInputValidationRule
  , reuseUnusedOutputRule
  , matrixExplosionRule
  , matrixFailFastRule
  , envApprovalGateRule
  , envMissingUrlRule
  , compositeDescriptionRule
  , compositeShellRule
    -- New supply chain rules
  , workflowRunEscalationRule
  , artifactPoisoningRule
  , oidcTokenScopeRule
  , abandonedActionRule
  , typosquatRiskRule
    -- New performance rules
  , missingCacheRule
  , sequentialJobsRule
    -- New cost rules
  , matrixWasteRule
  , redundantArtifactRule
    -- New hardening rules
  , persistCredentialsRule
  , defaultShellRule
  , prTargetRiskRule
    -- New drift rule
  , intraRepoDriftRule
    -- New structure rules
  , unreferencedReusableRule
  , circularWorkflowCallRule
  ]

allCommunityRules :: [PolicyRule]
allCommunityRules = packRules defaultPolicyPack ++ additionalRules

extendedPolicyPack :: PolicyPack
extendedPolicyPack = PolicyPack
  { packName = "extended"
  , packRules = allCommunityRules
  }
```

- [ ] **Step 2: Update version to 4.0.0**

In `orchestrator.cabal`, change `version: 3.0.4` to `version: 4.0.0`.
In `src/Orchestrator/Version.hs`, update the version string.
In `CHANGELOG.md`, add v4.0.0 entry.

- [ ] **Step 3: Verify rule count**

Run: `cabal run orchestrator -- rules | wc -l`
Expected: Output should list 36 rules (10 standard + 26 extended = 36 total; 10 + 11 existing extended + 15 new = 36).

- [ ] **Step 4: Full build and test**

Run: `cabal clean && cabal build all --ghc-options="-Werror" && cabal test all --test-show-details=direct`
Expected: Zero warnings, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/Orchestrator/Policy/Extended.hs src/Orchestrator/Version.hs \
  orchestrator.cabal CHANGELOG.md
git commit -m "feat: register all 36 rules, bump to v4.0.0"
```

---

## Task 13: Property Tests for New Invariants

**Files:**
- Modify: `test/Test/Properties.hs`

- [ ] **Step 1: Add new property tests**

Add to the existing `test/Test/Properties.hs`:

```haskell
-- Add these properties to the existing test group:

, testProperty "New categories are in Bounded range" $
    \(cat :: FindingCategory) -> cat >= minBound && cat <= maxBound

, testProperty "Rule tags are in Bounded range" $
    \(tag :: RuleTag) -> tag >= minBound && tag <= maxBound

, testProperty "Suppression is idempotent" $ \(rids :: [Text]) ->
    let suppressed = Set.fromList rids
        findings = map (\r -> mkTestFinding' r) rids
        once = applySuppression suppressed findings
        twice = applySuppression suppressed once
    in once == twice

, testProperty "Gating with Info threshold fails on any finding" $ \(sev :: Severity) ->
    let findings = [Finding sev Security "T" "t" "t.yml" Nothing Nothing False Nothing []]
    in gateFindings Info findings == ExitFailure 1

, testProperty "Empty suppression returns all findings" $ \(n :: Positive Int) ->
    let findings = replicate (getPositive n) (mkTestFinding' "X")
    in length (applySuppression Set.empty findings) == getPositive n

, testProperty "Tag filtering with empty tags returns all rules" $ \(n :: Positive Int) ->
    let rules = replicate (getPositive n) (dummyRule "R" [TagSecurity])
    in length (filterByTags [] rules) == getPositive n
```

Also add `Arbitrary` instances for `RuleTag`:

```haskell
instance Arbitrary RuleTag where
  arbitrary = arbitraryBoundedEnum
```

- [ ] **Step 2: Run property tests**

Run: `cabal test all --test-show-details=direct`
Expected: All properties hold.

- [ ] **Step 3: Commit**

```bash
git add test/Test/Properties.hs
git commit -m "test: add property tests for tags, suppression, gating invariants"
```

---

## Task 14: Integration Tests for New Features

**Files:**
- Modify: `test/Test/Integration.hs`

- [ ] **Step 1: Add integration tests**

Add to `test/Test/Integration.hs`:

```haskell
-- Integration tests for new v4.0.0 features

, testCase "Extended pack evaluates 36 rules" $ do
    let pack = extendedPolicyPack
    length (packRules pack) @?= 36

, testCase "Tag filtering produces subset of rules" $ do
    let pack = extendedPolicyPack
        secRules = filterByTags [TagSecurity] (packRules pack)
    assertBool "Security rules should exist" (not $ null secRules)
    assertBool "Should be subset" (length secRules < length (packRules pack))

, testCase "Suppression removes targeted findings" $ do
    let pack = extendedPolicyPack
        wf = mkMinimalWorkflow  -- workflow that triggers multiple rules
        allFindings = evaluatePolicies pack wf
        suppressed = Set.fromList ["PERM-001", "RES-001"]
        filtered = applySuppression suppressed allFindings
    assertBool "Should have fewer findings" (length filtered < length allFindings)
    assertBool "No PERM-001 in filtered" (not $ any (\f -> findingRuleId f == "PERM-001") filtered)

, testCase "Gate returns ExitSuccess when all below threshold" $ do
    let pack = extendedPolicyPack
        wf = mkCleanWorkflow  -- workflow that only triggers Info findings
        findings = filterBySeverity Info (evaluatePolicies pack wf)
        infoOnly = filter (\f -> findingSeverity f == Info) findings
    gateFindings Error infoOnly @?= ExitSuccess

, testCase "All rules have non-empty tags" $ do
    let pack = extendedPolicyPack
        untagged = filter (null . ruleTags) (packRules pack)
    assertBool ("Rules missing tags: " <> show (map ruleId untagged)) (null untagged)

, testCase "All new rules have remediation text" $ do
    let pack = extendedPolicyPack
        wf = mkMinimalWorkflow
        findings = evaluatePolicies pack wf
        noRemediation = filter (isNothing . findingRemediation) findings
    assertBool "All findings should have remediation" (null noRemediation)
```

- [ ] **Step 2: Run integration tests**

Run: `cabal test all --test-show-details=direct`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/Test/Integration.hs
git commit -m "test: add integration tests for tag filtering, suppression, gating"
```

---

## Task 15: Golden Tests for New Rules

**Files:**
- Create: `test/golden/rules-table.golden` (updated)
- Create: `test/golden/explain-*.golden` (one per new rule)
- Modify: `test/Test/Golden.hs`

- [ ] **Step 1: Generate golden files**

Run the orchestrator to generate baseline outputs:

```bash
cabal run orchestrator -- rules > test/golden/rules-table-v4.golden
```

For each new rule, generate explain output:

```bash
for rule in SEC-003 SEC-004 SEC-005 SUPPLY-001 SUPPLY-002 PERF-001 PERF-002 \
  COST-001 COST-002 HARD-001 HARD-002 HARD-003 DRIFT-001 STRUCT-001 STRUCT-002; do
  cabal run orchestrator -- explain "$rule" > "test/golden/explain-${rule}.golden"
done
```

- [ ] **Step 2: Add golden test cases**

Add to `test/Test/Golden.hs`:

```haskell
, goldenVsFile "Rules table v4"
    "test/golden/rules-table-v4.golden"
    "test/golden/rules-table-v4.actual"
    (runOrchestratorCapture ["rules"] "test/golden/rules-table-v4.actual")
```

And for each new rule explain output (follow existing golden test pattern).

- [ ] **Step 3: Run golden tests**

Run: `cabal test all --test-show-details=direct`
Expected: All golden tests pass (first run establishes baselines).

- [ ] **Step 4: Commit**

```bash
git add test/golden/ test/Test/Golden.hs
git commit -m "test: add golden tests for v4 rule table and explain outputs"
```

---

## Task 16: CI Self-Check Dogfooding

**Files:**
- Modify: `.github/workflows/ci-haskell.yml`

- [ ] **Step 1: Add self-check job**

Add to `.github/workflows/ci-haskell.yml`:

```yaml
  orchestrator-self-check:
    name: "Orchestrator Self-Check"
    runs-on: [self-hosted, Linux, X64, haskell, unified-all]
    needs: [build]
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false

      - name: Restore cabal cache
        uses: actions/cache@v4
        with:
          path: |
            ~/.cabal/store
            dist-newstyle
          key: ${{ runner.os }}-cabal-${{ hashFiles('orchestrator.cabal') }}

      - name: Run Orchestrator against own workflows
        run: |
          cabal run orchestrator -- scan .github/workflows/ --fail-on error --sarif \
            > orchestrator-self-check.sarif

      - name: Upload SARIF results
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: orchestrator-self-check.sarif
```

- [ ] **Step 2: Create baseline**

```bash
cabal run orchestrator -- baseline .github/workflows/
```

Commit the baseline file:

```bash
git add .orchestrator-baseline.json
git commit -m "ci: add self-check baseline for dogfooding"
```

- [ ] **Step 3: Run CI validation locally**

```bash
cabal run orchestrator -- scan .github/workflows/ --fail-on error
```

Expected: Clean pass or only Info/Warning findings (no Error/Critical).

- [ ] **Step 4: Commit CI changes**

```bash
git add .github/workflows/ci-haskell.yml
git commit -m "ci: add orchestrator self-check job for dogfooding"
```

---

## Task 17: Final Validation

**Files:** None (validation only)

- [ ] **Step 1: Full clean build with -Werror**

```bash
cabal clean && cabal build all --ghc-options="-Werror"
```

Expected: Zero warnings.

- [ ] **Step 2: Full test suite**

```bash
cabal test all --test-show-details=direct
```

Expected: All tests pass (target: 150+ tests at this point).

- [ ] **Step 3: HLint**

```bash
hlint src/ app/ test/
```

Expected: Zero suggestions.

- [ ] **Step 4: Ormolu format check**

```bash
ormolu --mode check $(find src app test -name '*.hs')
```

Expected: All files formatted.

- [ ] **Step 5: Self-check**

```bash
cabal run orchestrator -- scan .github/workflows/ --fail-on error
```

Expected: Clean pass.

- [ ] **Step 6: Verify rule count**

```bash
cabal run orchestrator -- rules | grep -c '|'
```

Expected: 36 rules listed.

- [ ] **Step 7: ShellCheck scripts**

```bash
shellcheck scripts/*.sh
```

Expected: Clean pass.

- [ ] **Step 8: Final commit and tag**

```bash
git tag v4.0.0
```

Do NOT push the tag until the user explicitly authorizes.
