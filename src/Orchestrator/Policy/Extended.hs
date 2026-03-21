-- | Extended policy pack combining all community rules.
--
-- This module assembles the full community policy pack by combining
-- the standard rules from Orchestrator.Policy with all additional
-- rule modules (Graph, Reuse, Matrix, Environment, Composite, Duplicate).
module Orchestrator.Policy.Extended
  ( -- * Extended packs
    extendedPolicyPack
  , allCommunityRules
  ) where

import Orchestrator.Graph (graphCycleRule, graphOrphanRule)
import Orchestrator.Policy (PolicyPack (..), PolicyRule (..), defaultPolicyPack)
import Orchestrator.Rules.Composite (compositeDescriptionRule, compositeShellRule)
import Orchestrator.Rules.Duplicate (duplicateJobRule)
import Orchestrator.Rules.Environment (envApprovalGateRule, envMissingUrlRule)
import Orchestrator.Rules.Matrix (matrixExplosionRule, matrixFailFastRule)
import Orchestrator.Rules.Reuse (reuseInputValidationRule, reuseUnusedOutputRule)

-- | All additional community rules (beyond the standard pack).
additionalRules :: [PolicyRule]
additionalRules =
  [ graphCycleRule
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
  ]

-- | All community rules: standard + extended.
allCommunityRules :: [PolicyRule]
allCommunityRules = packRules defaultPolicyPack ++ additionalRules

-- | The extended policy pack with all 21 community rules.
extendedPolicyPack :: PolicyPack
extendedPolicyPack = PolicyPack
  { packName = "extended"
  , packRules = allCommunityRules
  }
