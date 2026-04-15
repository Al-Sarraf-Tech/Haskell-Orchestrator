{-# OPTIONS_GHC -fno-warn-orphans #-}

module Test.Properties (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing, mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as T
import Orchestrator.Actions.Pin (analyzePinning)
import Orchestrator.Baseline (Baseline (..), compareWithBaseline)
import Orchestrator.Complexity (computeComplexity, csScore)
import Orchestrator.Diff
import Orchestrator.Gate (gateFindings)
import Orchestrator.Graph (buildJobGraph, graphNodes, topologicalSort)
import Orchestrator.Model
import Orchestrator.Policy
import Orchestrator.Render
import Orchestrator.Render.Markdown (renderMarkdownFindings)
import Orchestrator.Render.Sarif (renderSarifJSON)
import Orchestrator.Suppress (applySuppression)
import Orchestrator.Tags (filterByTags)
import Orchestrator.Types
import Orchestrator.Validate
import System.Exit (ExitCode (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck (Arbitrary (..), arbitraryBoundedEnum, choose, elements, forAll, listOf, oneof, resize, testProperty, withMaxSuccess)

------------------------------------------------------------------------
-- Arbitrary instances
------------------------------------------------------------------------

instance Arbitrary Severity where
  arbitrary = elements [Info, Warning, Error, Critical]

instance Arbitrary FindingCategory where
  arbitrary = elements [Permissions, Runners, Triggers, Naming, Concurrency, Security, Structure, Duplication, Drift, Performance, Cost, SupplyChain]

instance Arbitrary PermissionLevel where
  arbitrary = elements [PermNone, PermRead, PermWrite]

instance Arbitrary Permissions where
  arbitrary =
    oneof
      [ PermissionsAll <$> arbitrary,
        PermissionsMap . Map.fromList <$> listOf ((,) <$> arbPermKey <*> arbitrary)
      ]
    where
      arbPermKey = elements ["contents", "packages", "actions", "issues", "pull-requests", "statuses"]

instance Arbitrary RunnerSpec where
  arbitrary =
    oneof
      [ StandardRunner <$> elements ["ubuntu-latest", "macos-latest", "windows-latest"],
        MatrixRunner <$> elements ["${{ matrix.os }}", "${{ matrix.runner }}"],
        CustomLabel <$> elements ["self-hosted", "gpu-runner", "arm64"]
      ]

instance Arbitrary Step where
  arbitrary = do
    sid <- oneof [pure Nothing, Just <$> arbId]
    sname <- oneof [pure Nothing, Just <$> arbName]
    suses <- oneof [pure Nothing, Just <$> arbAction]
    srun <- if isNothing suses then Just <$> arbCommand else pure Nothing
    sif <- oneof [pure Nothing, Just <$> elements ["github.event_name == 'push'", "always()"]]
    sshell <- oneof [pure Nothing, Just <$> elements ["bash", "pwsh", "sh"]]
    pure $ Step sid sname suses srun Map.empty Map.empty sif sshell
    where
      arbId = elements ["checkout", "build", "test", "deploy", "lint", "setup"]
      arbName = elements ["Checkout", "Build", "Test", "Deploy", "Lint", "Setup"]
      arbAction =
        elements
          [ "actions/checkout@v4",
            "actions/setup-node@v4",
            "actions/cache@v4",
            "actions/upload-artifact@v4",
            "third-party/action@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
            "docker://alpine:3.18"
          ]
      arbCommand = elements ["echo test", "make build", "npm test", "cargo test"]

instance Arbitrary Job where
  arbitrary = do
    jid <- arbJobId
    jname <- oneof [pure Nothing, Just <$> arbName]
    runner <- arbitrary
    steps <- listOf1 arbitrary
    perms <- oneof [pure Nothing, Just <$> arbitrary]
    needs <- listOf arbJobId
    conc <- oneof [pure Nothing, Just <$> arbConc]
    jif <- oneof [pure Nothing, Just <$> elements ["github.ref == 'refs/heads/main'", "always()"]]
    timeout <- oneof [pure Nothing, Just <$> choose (5, 120)]
    env <- oneof [pure Nothing, Just <$> elements ["production", "staging", "development"]]
    envUrl <- arbitrary
    ff <- oneof [pure Nothing, Just <$> arbitrary]
    Job jid jname runner steps perms needs conc Map.empty jif timeout env envUrl ff <$> arbitrary
    where
      arbJobId = elements ["build", "test", "deploy", "lint", "check", "publish", "release"]
      arbName = elements ["Build", "Test", "Deploy", "Lint", "Check", "Publish"]
      arbConc = ConcurrencyConfig <$> elements ["ci-${{ github.ref }}", "deploy"] <*> arbitrary
      listOf1 g = do
        x <- g
        xs <- listOf g
        pure (x : xs)

instance Arbitrary TriggerEvent where
  arbitrary =
    TriggerEvent
      <$> elements ["push", "pull_request", "workflow_dispatch", "schedule", "release"]
      <*> listOf (elements ["main", "develop", "release/*"])
      <*> listOf (elements ["src/**", "lib/**"])
      <*> listOf (elements ["v*", "release-*"])

instance Arbitrary WorkflowTrigger where
  arbitrary =
    oneof
      [ TriggerEvents <$> listOf1 arbitrary,
        TriggerCron <$> elements ["0 0 * * *", "0 6 * * MON"],
        pure TriggerDispatch
      ]
    where
      listOf1 g = do
        x <- g
        xs <- listOf g
        pure (x : xs)

instance Arbitrary ConcurrencyConfig where
  arbitrary =
    ConcurrencyConfig
      <$> elements ["ci-${{ github.ref }}", "deploy-prod", "release"]
      <*> arbitrary

instance Arbitrary Workflow where
  arbitrary = do
    name <- elements ["CI", "Deploy", "Release", "Test", "Build", "Security"]
    fname <- elements ["ci.yml", "deploy.yml", "release.yml", "test.yml", "build.yml"]
    triggers <- listOf1 arbitrary
    jobs <- listOf1 arbitrary
    perms <- oneof [pure Nothing, Just <$> arbitrary]
    conc <- oneof [pure Nothing, Just <$> arbitrary]
    pure $ Workflow name fname triggers jobs perms conc Map.empty
    where
      listOf1 g = do
        x <- g
        xs <- listOf g
        pure (x : xs)

instance Arbitrary Finding where
  arbitrary =
    Finding
      <$> arbitrary
      <*> arbitrary
      <*> elements ["PERM-001", "PERM-002", "SEC-001", "SEC-002", "RUN-001", "RES-001", "NAME-001", "TRIG-001"]
      <*> elements ["test finding", "another finding", "policy violation"]
      <*> elements ["ci.yml", "deploy.yml", "build.yml"]
      <*> oneof [pure Nothing, Just <$> elements ["job:build", "step:3"]]
      <*> oneof [pure Nothing, Just <$> elements ["Fix the issue", "Add permissions block"]]
      <*> arbitrary
      <*> oneof [pure Nothing, Just <$> arbitrary]
      <*> pure []

instance Arbitrary Effort where
  arbitrary = elements [LowEffort, MediumEffort, HighEffort]

instance Arbitrary RuleTag where
  arbitrary = arbitraryBoundedEnum

------------------------------------------------------------------------
-- Properties
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "Properties"
    [ testProperty "Severity ordering is total: Info < Warning < Error < Critical" $
        \(s1 :: Severity) (s2 :: Severity) ->
          (s1 <= s2) || (s2 <= s1),
      testProperty "Severity Enum roundtrips" $
        \(s :: Severity) ->
          toEnum (fromEnum s) == s,
      testProperty "FindingCategory Enum roundtrips" $
        \(c :: FindingCategory) ->
          toEnum (fromEnum c) == c,
      testProperty "Policy evaluation is deterministic" $
        \(wf :: Workflow) ->
          let f1 = evaluatePolicies defaultPolicyPack wf
              f2 = evaluatePolicies defaultPolicyPack wf
           in f1 == f2,
      testProperty "Policy evaluation finding count is non-negative" $
        \(wf :: Workflow) ->
          evaluatePolicies defaultPolicyPack wf `seq` True,
      testProperty "Validation result is deterministic" $
        \(wf :: Workflow) ->
          let v1 = validateWorkflow wf
              v2 = validateWorkflow wf
           in vrValid v1 == vrValid v2 && vrFindings v1 == vrFindings v2,
      testProperty "Filter by severity preserves or reduces count" $
        \(sev :: Severity) (findings :: [Finding]) ->
          length (filterBySeverity sev findings) <= length findings,
      testProperty "Filter by severity only keeps >= threshold" $
        \(sev :: Severity) (findings :: [Finding]) ->
          all (\f -> findingSeverity f >= sev) (filterBySeverity sev findings),
      testProperty "Group by category keys are subset of input categories" $
        \(findings :: [Finding]) ->
          let grouped = groupByCategory findings
              inputCats = map findingCategory findings
           in all (`elem` inputCats) (Map.keys grouped),
      testProperty "Plan from empty findings has zero steps" $
        \(target :: ScanTarget) ->
          null (planSteps (generatePlan target [])),
      testProperty "Render findings produces non-empty text for non-empty findings" $
        \(findings :: [Finding]) ->
          null findings || not (T.null (renderFindings findings)),
      testProperty "Render summary produces non-empty text for non-empty findings" $
        \(findings :: [Finding]) ->
          null findings || not (T.null (renderSummary findings)),
      testProperty "FindingCategory values satisfy minBound <= x <= maxBound" $
        \(c :: FindingCategory) ->
          c >= minBound && c <= maxBound,
      testProperty "RuleTag values satisfy minBound <= x <= maxBound" $
        \(t :: RuleTag) ->
          t >= minBound && t <= maxBound,
      testProperty "Suppression idempotence: applying twice equals once" $
        \(findings :: [Finding]) ->
          let suppressed = Set.fromList (map findingRuleId findings)
              once = applySuppression suppressed findings
              twice = applySuppression suppressed once
           in once == twice,
      testProperty "Gating with Info threshold fails on any non-empty findings" $
        \(findings :: [Finding]) ->
          null findings || gateFindings Info findings == ExitFailure 1,
      testProperty "Empty suppression returns all findings" $
        \(findings :: [Finding]) ->
          length (applySuppression Set.empty findings) == length findings,
      testProperty "Tag filtering with empty tags returns all rules" $
        let rules = packRules defaultPolicyPack
         in length (filterByTags [] rules) == length rules,
      -- Graph properties (resize 5: Workflow Arbitrary is expensive at large sizes)
      testProperty "topologicalSort result is subset of graph nodes" $
        withMaxSuccess 50 $
          forAll (resize 5 arbitrary) $
            \(wf :: Workflow) ->
              let wf' = wf {wfJobs = map (\j -> j {jobNeeds = []}) (wfJobs wf)}
                  g = buildJobGraph wf'
                  topo = topologicalSort g
               in all (`Set.member` graphNodes g) topo,
      testProperty "buildJobGraph includes all jobs from workflow" $
        withMaxSuccess 50 $
          forAll (resize 5 arbitrary) $
            \(wf :: Workflow) ->
              let g = buildJobGraph wf
                  jobIds = map jobId (wfJobs wf)
               in all (\jid -> Set.member jid (graphNodes g)) jobIds,
      -- Complexity properties
      testProperty "computeComplexity score is non-negative" $
        withMaxSuccess 50 $
          forAll (resize 5 arbitrary) $
            \(wf :: Workflow) ->
              csScore (computeComplexity wf) >= 0,
      -- Render properties
      testProperty "renderMarkdownFindings non-empty for non-empty findings" $
        \(findings :: [Finding]) ->
          null findings || not (T.null (renderMarkdownFindings findings)),
      testProperty "renderSarifJSON output contains version 2.1.0" $
        \(findings :: [Finding]) ->
          T.isInfixOf "2.1.0" (renderSarifJSON "orchestrator" "1.0.0" findings),
      -- Pin properties (resize 5: Workflow Arbitrary is expensive at large sizes)
      testProperty "analyzePinning length <= steps with uses" $
        withMaxSuccess 50 $
          forAll (resize 5 arbitrary) $
            \(wf :: Workflow) ->
              let pins = analyzePinning wf
                  allSteps = concatMap jobSteps (wfJobs wf)
                  usesCount = length (mapMaybe stepUses allSteps)
               in length pins <= usesCount,
      -- Baseline properties
      testProperty "compareWithBaseline empty baseline returns all findings" $
        \(findings :: [Finding]) ->
          let emptyBaseline =
                Baseline
                  { baselineFingerprints = Set.empty,
                    baselineCount = 0,
                    baselineVersion = "test"
                  }
           in length (compareWithBaseline emptyBaseline findings) == length findings
    ]

instance Arbitrary ScanTarget where
  arbitrary =
    oneof
      [ LocalPath <$> elements ["/tmp/repo", "/home/user/project", "./"],
        GitHubRepo <$> elements ["owner", "org"] <*> elements ["repo", "project"],
        GitHubOrg <$> elements ["my-org", "company"]
      ]
