module Main (main) where

import Test.Tasty (defaultMain, testGroup)
import Test.Model qualified
import Test.Parser qualified
import Test.Policy qualified
import Test.Validate qualified
import Test.Diff qualified
import Test.Demo qualified
import Test.Config qualified
import Test.Golden qualified
import Test.EdgeCases qualified
import Test.Properties qualified
import Test.Integration qualified
import Test.Tags qualified
import Test.Suppress qualified
import Test.Gate qualified

main :: IO ()
main = defaultMain $ testGroup "Orchestrator"
  [ Test.Model.tests
  , Test.Parser.tests
  , Test.Policy.tests
  , Test.Validate.tests
  , Test.Diff.tests
  , Test.Demo.tests
  , Test.Config.tests
  , Test.Golden.tests
  , Test.EdgeCases.tests
  , Test.Properties.tests
  , Test.Integration.tests
  , Test.Tags.tests
  , Test.Suppress.tests
  , Test.Gate.tests
  ]
