module Main (main) where

import Test.Tasty (defaultMain, testGroup)
import Test.ActionsCatalog qualified
import Test.ActionsPin qualified
import Test.Errors qualified
import Test.Interactive qualified
import Test.Baseline qualified
import Test.Changelog qualified
import Test.Complexity qualified
import Test.CompositeRule qualified
import Test.Config qualified
import Test.Cost qualified
import Test.Demo qualified
import Test.Diff qualified
import Test.DriftRule qualified
import Test.DuplicateRule qualified
import Test.EdgeCases qualified
import Test.EnvironmentRule qualified
import Test.Fix qualified
import Test.Formatter qualified
import Test.Gate qualified
import Test.GitHub qualified
import Test.Golden qualified
import Test.Graph qualified
import Test.Hardening qualified
import Test.Hook qualified
import Test.Integration qualified
import Test.LSP qualified
import Test.MatrixRule qualified
import Test.Model qualified
import Test.Parser qualified
import Test.Performance qualified
import Test.PermissionsMinimum qualified
import Test.Policy qualified
import Test.PolicyConflicts qualified
import Test.PolicyValidate qualified
import Test.Properties qualified
import Test.RenderMarkdown qualified
import Test.RenderSarif qualified
import Test.RenderUpgrade qualified
import Test.ReuseRule qualified
import Test.Scan qualified
import Test.Secrets qualified
import Test.Simulate qualified
import Test.StructureRule qualified
import Test.Suppress qualified
import Test.SupplyChain qualified
import Test.Tags qualified
import Test.UI qualified
import Test.Validate qualified
import Test.Version qualified

main :: IO ()
main = defaultMain $ testGroup "Orchestrator"
  [ Test.ActionsCatalog.tests
  , Test.ActionsPin.tests
  , Test.Errors.tests
  , Test.Interactive.tests
  , Test.Baseline.tests
  , Test.Changelog.tests
  , Test.Complexity.tests
  , Test.CompositeRule.tests
  , Test.Config.tests
  , Test.Cost.tests
  , Test.Demo.tests
  , Test.Diff.tests
  , Test.DriftRule.tests
  , Test.DuplicateRule.tests
  , Test.EdgeCases.tests
  , Test.EnvironmentRule.tests
  , Test.Fix.tests
  , Test.Formatter.tests
  , Test.Gate.tests
  , Test.GitHub.tests
  , Test.Golden.tests
  , Test.Graph.tests
  , Test.Hardening.tests
  , Test.Hook.tests
  , Test.Integration.tests
  , Test.LSP.tests
  , Test.MatrixRule.tests
  , Test.Model.tests
  , Test.Parser.tests
  , Test.Performance.tests
  , Test.PermissionsMinimum.tests
  , Test.Policy.tests
  , Test.PolicyConflicts.tests
  , Test.PolicyValidate.tests
  , Test.Properties.tests
  , Test.RenderMarkdown.tests
  , Test.RenderSarif.tests
  , Test.RenderUpgrade.tests
  , Test.ReuseRule.tests
  , Test.Scan.tests
  , Test.Secrets.tests
  , Test.Simulate.tests
  , Test.StructureRule.tests
  , Test.Suppress.tests
  , Test.SupplyChain.tests
  , Test.Tags.tests
  , Test.UI.tests
  , Test.Validate.tests
  , Test.Version.tests
  ]
