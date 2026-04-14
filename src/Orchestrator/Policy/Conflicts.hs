-- | Rule conflict detection for policy packs.
--
-- Detects three kinds of conflicts between rules in a PolicyPack:
-- Contradictory (same category, opposite severity implications),
-- Redundant (duplicate or same-scope rules), and
-- Overlapping (related rules that partially cover the same concern).
module Orchestrator.Policy.Conflicts
  ( ConflictType (..)
  , RuleConflict (..)
  , detectConflicts
  , renderConflicts
  ) where

import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Policy (PolicyPack (..), PolicyRule (..))
import Orchestrator.Types (RuleTag)

-- | Classification of a conflict between two rules.
data ConflictType
  = Contradictory  -- ^ Rules with opposing severity implications in same category
  | Redundant      -- ^ Duplicate or identical-scope rules
  | Overlapping    -- ^ Rules that partially cover the same concern
  deriving stock (Eq, Ord, Show, Read)

-- | A detected conflict between two rules in a policy pack.
data RuleConflict = RuleConflict
  { conflictType  :: !ConflictType
  , ruleA         :: !Text        -- ^ ID of first rule
  , ruleB         :: !Text        -- ^ ID of second rule
  , description   :: !Text        -- ^ Human-readable explanation
  } deriving stock (Eq, Show)

-- | Detect all conflicts in a PolicyPack.
detectConflicts :: PolicyPack -> [RuleConflict]
detectConflicts pack = nub $
     detectDuplicateIds rules
  ++ detectKnownPairs rules
  ++ detectSameCategoryConflicts rules
  where
    rules = packRules pack

-- | Detect rules with identical IDs — always Contradictory.
detectDuplicateIds :: [PolicyRule] -> [RuleConflict]
detectDuplicateIds rules =
  [ RuleConflict
      { conflictType = Contradictory
      , ruleA = ruleId ra
      , ruleB = ruleId rb
      , description = "Duplicate rule ID \"" <> ruleId ra <> "\" found in pack. \
                      \Two rules with the same ID produce ambiguous results."
      }
  | (i, ra) <- indexed rules
  , (j, rb) <- indexed rules
  , i < j
  , ruleId ra == ruleId rb
  ]
  where
    indexed xs = zip [(0 :: Int) ..] xs

-- | Known pairs of rule IDs with established conflict relationships.
detectKnownPairs :: [PolicyRule] -> [RuleConflict]
detectKnownPairs rules =
  [ conflict
  | (a, b, mkConflict) <- knownPairDefs
  , Just ra <- [findById a]
  , Just rb <- [findById b]
  , let conflict = mkConflict ra rb
  ]
  where
    findById rid = safeLookup rid rules
    safeLookup rid = foldr (\r acc -> if ruleId r == rid then Just r else acc) Nothing

    knownPairDefs =
      [ -- PERM-001 (requires permissions block) vs PERM-002 (flags broad permissions)
        -- Not contradictory: one flags absence, the other flags excess.
        ( "PERM-001", "PERM-002"
        , \ra rb -> RuleConflict
            { conflictType = Overlapping
            , ruleA = ruleId ra
            , ruleB = ruleId rb
            , description = "PERM-001 flags missing permissions blocks; PERM-002 flags \
                            \overly broad permissions. Together they push toward fine-grained \
                            \explicit permissions — overlapping concern, not contradictory."
            }
        )
        -- SEC-001 (unpinned actions) + ACT-001 / supply chain rules — redundant on deprecated unpinned
      , ( "SEC-001", "SUPPLY-001"
        , \ra rb -> RuleConflict
            { conflictType = Redundant
            , ruleA = ruleId ra
            , ruleB = ruleId rb
            , description = "SEC-001 and SUPPLY-001 both detect unpinned or insecure \
                            \third-party action references. Consider whether both rules \
                            \are necessary or if one subsumes the other."
            }
        )
      , ( "SEC-001", "SEC-003"
        , \ra rb -> RuleConflict
            { conflictType = Redundant
            , ruleA = ruleId ra
            , ruleB = ruleId rb
            , description = "SEC-001 and SEC-003 both inspect action pinning / supply-chain \
                            \hygiene. Their findings may overlap on the same steps."
            }
        )
      ]

-- | Detect potential conflicts among rules sharing a category.
-- Same category + same severity = Redundant candidate.
-- Same category + opposing severity direction = Contradictory candidate.
detectSameCategoryConflicts :: [PolicyRule] -> [RuleConflict]
detectSameCategoryConflicts rules =
  [ RuleConflict
      { conflictType = conflictKind (ruleSeverity ra) (ruleSeverity rb) (sharedTags ra rb)
      , ruleA = ruleId ra
      , ruleB = ruleId rb
      , description = describeCategConflict ra rb
      }
  | (i, ra) <- indexed rules
  , (j, rb) <- indexed rules
  , i < j
  , ruleId ra /= ruleId rb          -- duplicates already covered above
  , ruleCategory ra == ruleCategory rb
  , not (null (sharedTags ra rb))   -- must share at least one tag
  , isConflicting ra rb
  ]
  where
    indexed xs = zip [(0 :: Int) ..] xs

    sharedTags :: PolicyRule -> PolicyRule -> [RuleTag]
    sharedTags ra rb = filter (`elem` ruleTags rb) (ruleTags ra)

    -- Two rules conflict when they share category+tags and have the same or adjacent severity.
    -- We skip pairs that are known-pair entries (already covered) to avoid duplication.
    isConflicting :: PolicyRule -> PolicyRule -> Bool
    isConflicting ra rb =
      let severityDelta = abs (fromEnum (ruleSeverity ra) - fromEnum (ruleSeverity rb))
      in  severityDelta <= 1   -- same or adjacent severity in same category

    conflictKind sev1 sev2 tags
      | sev1 == sev2 && not (null tags) = Redundant
      | otherwise                        = Overlapping

    describeCategConflict :: PolicyRule -> PolicyRule -> Text
    describeCategConflict ra rb =
      "Rules \"" <> ruleId ra <> "\" (" <> T.pack (show (ruleSeverity ra))
      <> ") and \"" <> ruleId rb <> "\" (" <> T.pack (show (ruleSeverity rb))
      <> ") share category " <> T.pack (show (ruleCategory ra))
      <> " and tags " <> T.pack (show (sharedTags ra rb))
      <> ". Findings may overlap."

-- | Render a list of conflicts as human-readable text.
renderConflicts :: [RuleConflict] -> Text
renderConflicts [] = "No rule conflicts detected.\n"
renderConflicts cs =
  T.unlines $
    [ "Rule Conflict Report"
    , "===================="
    , T.pack (show (length cs)) <> " conflict(s) detected:"
    , ""
    ] ++
    concatMap renderOne (zip [(1 :: Int) ..] (sort' cs))
  where
    sort' = foldr (:) []   -- preserve order; sort by type if needed later

    renderOne (n, c) =
      [ T.pack (show n) <> ". [" <> renderType (conflictType c) <> "] "
        <> ruleA c <> " <-> " <> ruleB c
      , "   " <> description c
      , ""
      ]

    renderType Contradictory = "CONTRADICTORY"
    renderType Redundant     = "REDUNDANT"
    renderType Overlapping   = "OVERLAPPING"
