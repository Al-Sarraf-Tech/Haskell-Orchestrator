-- | Extended policy pack combining all 36 community rules.
--
-- This module assembles the full community policy pack by combining
-- the standard rules from Orchestrator.Policy with all additional
-- rule modules (Graph, Reuse, Matrix, Environment, Composite, Duplicate,
-- SupplyChain, Performance, Cost, Hardening, Drift, Structure).
module Orchestrator.Policy.Extended
  ( -- * Extended packs
    extendedPolicyPack
  , allCommunityRules
  ) where

import Orchestrator.Graph (graphCycleRule, graphOrphanRule)
import Orchestrator.Policy (PolicyPack (..), PolicyRule (..), defaultPolicyPack)
import Orchestrator.Rules.Composite (compositeDescriptionRule, compositeShellRule)
import Orchestrator.Rules.Cost (matrixWasteRule, redundantArtifactUploadRule)
import Orchestrator.Rules.Drift (driftVersionRule)
import Orchestrator.Rules.Duplicate (duplicateJobRule)
import Orchestrator.Rules.Environment (envApprovalGateRule, envMissingUrlRule)
import Orchestrator.Rules.Hardening
  ( hard001PersistCredentials
  , hard002DefaultShellUnset
  , hard003PullRequestTargetRisk
  )
import Orchestrator.Rules.Matrix (matrixExplosionRule, matrixFailFastRule)
import Orchestrator.Rules.Performance (missingCacheRule, sequentialParallelizableRule)
import Orchestrator.Rules.Reuse (reuseInputValidationRule, reuseUnusedOutputRule)
import Orchestrator.Rules.Structure (structUnreferencedReusableRule, structCircularCallRule)
import Orchestrator.Rules.SupplyChain
  ( sec003Rule
  , sec004Rule
  , sec005Rule
  , supply001Rule
  , supply002Rule
  )

-- | All additional community rules (beyond the standard pack).
additionalRules :: [PolicyRule]
additionalRules =
  [ -- Graph rules
    graphCycleRule
  , graphOrphanRule
    -- Duplicate detection
  , duplicateJobRule
    -- Reuse rules
  , reuseInputValidationRule
  , reuseUnusedOutputRule
    -- Matrix rules
  , matrixExplosionRule
  , matrixFailFastRule
    -- Environment rules
  , envApprovalGateRule
  , envMissingUrlRule
    -- Composite action rules
  , compositeDescriptionRule
  , compositeShellRule
    -- Supply chain security rules (SEC-003..005, SUPPLY-001..002)
  , sec003Rule
  , sec004Rule
  , sec005Rule
  , supply001Rule
  , supply002Rule
    -- Performance rules (PERF-001..002)
  , missingCacheRule
  , sequentialParallelizableRule
    -- Cost rules (COST-001..002)
  , matrixWasteRule
  , redundantArtifactUploadRule
    -- Hardening rules (HARD-001..003)
  , hard001PersistCredentials
  , hard002DefaultShellUnset
  , hard003PullRequestTargetRisk
    -- Drift rule (DRIFT-001)
  , driftVersionRule
    -- Structure rules (STRUCT-001..002)
  , structUnreferencedReusableRule
  , structCircularCallRule
  ]

-- | All community rules: standard + extended.
allCommunityRules :: [PolicyRule]
allCommunityRules = packRules defaultPolicyPack ++ additionalRules

-- | The extended policy pack with all 36 community rules.
extendedPolicyPack :: PolicyPack
extendedPolicyPack = PolicyPack
  { packName = "extended"
  , packRules = allCommunityRules
  }
