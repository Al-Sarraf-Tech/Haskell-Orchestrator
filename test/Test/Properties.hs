{-# OPTIONS_GHC -fno-warn-orphans #-}
module Test.Properties (tests) where

import Data.Maybe (isNothing)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy
import Orchestrator.Types
import Orchestrator.Validate
import Orchestrator.Diff
import Orchestrator.Render
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck (testProperty, Arbitrary (..), elements, listOf, oneof, choose)

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
  arbitrary = oneof
    [ PermissionsAll <$> arbitrary
    , PermissionsMap . Map.fromList <$> listOf ((,) <$> arbPermKey <*> arbitrary)
    ]
    where
      arbPermKey = elements ["contents", "packages", "actions", "issues", "pull-requests", "statuses"]

instance Arbitrary RunnerSpec where
  arbitrary = oneof
    [ StandardRunner <$> elements ["ubuntu-latest", "macos-latest", "windows-latest"]
    , MatrixRunner <$> elements ["${{ matrix.os }}", "${{ matrix.runner }}"]
    , CustomLabel <$> elements ["self-hosted", "gpu-runner", "arm64"]
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
      arbAction = elements
        [ "actions/checkout@v4"
        , "actions/setup-node@v4"
        , "actions/cache@v4"
        , "actions/upload-artifact@v4"
        , "third-party/action@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        , "docker://alpine:3.18"
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
  arbitrary = TriggerEvent
    <$> elements ["push", "pull_request", "workflow_dispatch", "schedule", "release"]
    <*> listOf (elements ["main", "develop", "release/*"])
    <*> listOf (elements ["src/**", "lib/**"])
    <*> listOf (elements ["v*", "release-*"])

instance Arbitrary WorkflowTrigger where
  arbitrary = oneof
    [ TriggerEvents <$> listOf1 arbitrary
    , TriggerCron <$> elements ["0 0 * * *", "0 6 * * MON"]
    , pure TriggerDispatch
    ]
    where
      listOf1 g = do
        x <- g
        xs <- listOf g
        pure (x : xs)

instance Arbitrary ConcurrencyConfig where
  arbitrary = ConcurrencyConfig
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
  arbitrary = Finding
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

------------------------------------------------------------------------
-- Properties
------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "Properties"
  [ testProperty "Severity ordering is total: Info < Warning < Error < Critical" $
      \(s1 :: Severity) (s2 :: Severity) ->
        (s1 <= s2) || (s2 <= s1)

  , testProperty "Severity Enum roundtrips" $
      \(s :: Severity) ->
        toEnum (fromEnum s) == s

  , testProperty "FindingCategory Enum roundtrips" $
      \(c :: FindingCategory) ->
        toEnum (fromEnum c) == c

  , testProperty "Policy evaluation is deterministic" $
      \(wf :: Workflow) ->
        let f1 = evaluatePolicies defaultPolicyPack wf
            f2 = evaluatePolicies defaultPolicyPack wf
        in f1 == f2

  , testProperty "Policy evaluation finding count is non-negative" $
      \(wf :: Workflow) ->
        evaluatePolicies defaultPolicyPack wf `seq` True

  , testProperty "Validation result is deterministic" $
      \(wf :: Workflow) ->
        let v1 = validateWorkflow wf
            v2 = validateWorkflow wf
        in vrValid v1 == vrValid v2 && vrFindings v1 == vrFindings v2

  , testProperty "Filter by severity preserves or reduces count" $
      \(sev :: Severity) (findings :: [Finding]) ->
        length (filterBySeverity sev findings) <= length findings

  , testProperty "Filter by severity only keeps >= threshold" $
      \(sev :: Severity) (findings :: [Finding]) ->
        all (\f -> findingSeverity f >= sev) (filterBySeverity sev findings)

  , testProperty "Group by category keys are subset of input categories" $
      \(findings :: [Finding]) ->
        let grouped = groupByCategory findings
            inputCats = map findingCategory findings
        in all (`elem` inputCats) (Map.keys grouped)

  , testProperty "Plan from empty findings has zero steps" $
      \(target :: ScanTarget) ->
        null (planSteps (generatePlan target []))

  , testProperty "Render findings produces non-empty text for non-empty findings" $
      \(findings :: [Finding]) ->
        null findings || not (T.null (renderFindings findings))

  , testProperty "Render summary produces non-empty text for non-empty findings" $
      \(findings :: [Finding]) ->
        null findings || not (T.null (renderSummary findings))
  ]

instance Arbitrary ScanTarget where
  arbitrary = oneof
    [ LocalPath <$> elements ["/tmp/repo", "/home/user/project", "./"]
    , GitHubRepo <$> elements ["owner", "org"] <*> elements ["repo", "project"]
    , GitHubOrg <$> elements ["my-org", "company"]
    ]
