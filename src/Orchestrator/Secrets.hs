-- | Secret scope analysis for GitHub Actions workflows.
--
-- Maps which secrets are accessible where, detects over-scoped secrets,
-- and provides a policy rule for flagging secrets referenced across too many jobs.
module Orchestrator.Secrets
  ( -- * Types
    SecretRef (..)
  , SecretScope (..)
    -- * Analysis
  , analyzeSecrets
  , buildSecretScopes
    -- * Policy
  , secretScopeRule
    -- * Rendering
  , renderSecretReport
  ) where

import Data.List (nub, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

-- | A single reference to a secret found in a workflow.
data SecretRef = SecretRef
  { srSecretName   :: !Text     -- ^ Name of the secret (e.g. "GITHUB_TOKEN")
  , srReferencedIn :: !FilePath -- ^ Workflow file path
  , srJob          :: !Text     -- ^ Job ID where the reference occurs
  , srStep         :: !(Maybe Text) -- ^ Step ID or name, if identifiable
  , srContext      :: !Text     -- ^ Context: "run", "env", or "with"
  } deriving stock (Eq, Show)

-- | Aggregated scope of a single secret across workflows.
data SecretScope = SecretScope
  { ssSecretName :: !Text    -- ^ Name of the secret
  , ssWorkflows  :: ![Text]  -- ^ Workflow file names where it appears
  , ssJobs       :: ![Text]  -- ^ Job IDs where it appears
  , ssSteps      :: ![Text]  -- ^ Step IDs/names where it appears
  } deriving stock (Eq, Show)

-- | Find all secrets.* references in a workflow.
analyzeSecrets :: Workflow -> [SecretRef]
analyzeSecrets wf =
  let fp = wfFileName wf
  in concatMap (analyzeJob fp) (wfJobs wf)

-- | Policy rule: flag secrets referenced in more than 3 jobs (over-scoped).
secretScopeRule :: PolicyRule
secretScopeRule = PolicyRule
  { ruleId          = "SEC-003"
  , ruleName        = "Over-Scoped Secret"
  , ruleDescription = "Flag secrets referenced in more than 3 jobs"
  , ruleSeverity    = Warning
  , ruleCategory    = Security
  , ruleCheck       = \wf ->
      let refs   = analyzeSecrets wf
          scopes = buildSecretScopes refs
      in concatMap (\ss ->
           if length (ssJobs ss) > 3
           then [ Finding
                    { findingSeverity    = Warning
                    , findingCategory    = Security
                    , findingRuleId      = "SEC-003"
                    , findingMessage     =
                        "Secret '" <> ssSecretName ss
                        <> "' is referenced in " <> T.pack (show (length (ssJobs ss)))
                        <> " jobs. Consider reducing its scope."
                    , findingFile        = wfFileName wf
                    , findingLocation    = Nothing
                    , findingRemediation = Just
                        "Use job-level environment variables or separate secrets \
                        \with narrower scope to limit blast radius."
                    , findingAutoFixable = False
                    , findingEffort      = Nothing
                    , findingLinks       = []
                    }
                ]
           else []
         ) scopes
  }

-- | Aggregate secret references by secret name into scopes.
buildSecretScopes :: [SecretRef] -> [SecretScope]
buildSecretScopes refs =
  let grouped = Map.toAscList $ foldl (\m r ->
        Map.insertWith (++) (srSecretName r) [r] m) Map.empty refs
  in map (\(name, rs) -> SecretScope
        { ssSecretName = name
        , ssWorkflows  = nub $ sort $ map srReferencedIn' rs
        , ssJobs       = nub $ sort $ map srJob rs
        , ssSteps      = nub $ sort $ concatMap (maybe [] (:[]) . srStep) rs
        }) grouped
  where
    srReferencedIn' r = T.pack (srReferencedIn r)

-- | Render a secret scope report as human-readable text.
renderSecretReport :: [SecretScope] -> Text
renderSecretReport [] = "No secrets found.\n"
renderSecretReport scopes =
  let header = "Secret Scope Report\n" <> T.replicate 40 "=" <> "\n\n"
      entries = map renderScope scopes
  in header <> T.intercalate "\n" entries

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

-- | Analyze a single job for secret references.
analyzeJob :: FilePath -> Job -> [SecretRef]
analyzeJob fp j =
  concatMap (analyzeStep fp (jobId j)) (jobSteps j)
  ++ analyzeEnvMap fp (jobId j) Nothing (jobEnv j)

-- | Analyze a single step for secret references.
analyzeStep :: FilePath -> Text -> Step -> [SecretRef]
analyzeStep fp jid s =
  let label     = case (stepId s, stepName s) of
                    (Just sid, _) -> Just sid
                    (_, Just nm)  -> Just nm
                    _             -> Nothing
      runRefs   = case stepRun s of
        Just cmd -> map (\n -> SecretRef n fp jid label "run") (extractSecretNames cmd)
        Nothing  -> []
      envRefs   = analyzeEnvMap fp jid label (stepEnv s)
      withRefs  = concatMap (\val ->
        map (\n -> SecretRef n fp jid label "with") (extractSecretNames val)
        ) (Map.elems (stepWith s))
  in runRefs ++ envRefs ++ withRefs

-- | Analyze an environment variable map for secret references.
analyzeEnvMap :: FilePath -> Text -> Maybe Text -> EnvMap -> [SecretRef]
analyzeEnvMap fp jid label env =
  concatMap (\val ->
    map (\n -> SecretRef n fp jid label "env") (extractSecretNames val)
  ) (Map.elems env)

-- | Extract secret names from text containing secrets.NAME patterns.
extractSecretNames :: Text -> [Text]
extractSecretNames = go []
  where
    go acc t
      | T.null t = nub acc
      | "secrets." `T.isInfixOf` t =
          let after = T.drop 8 (snd (T.breakOn "secrets." t))
              name  = T.takeWhile (\c -> c /= ' ' && c /= '}'
                                      && c /= ')' && c /= ','
                                      && c /= '"' && c /= '\''
                                      && c /= '\n') after
              rest  = T.drop (T.length name) after
          in if T.null name
             then go acc rest
             else go (name : acc) rest
      | otherwise = acc

-- | Render a single secret scope entry.
renderScope :: SecretScope -> Text
renderScope ss = T.unlines
  [ "Secret: " <> ssSecretName ss
  , "  Workflows: " <> T.intercalate ", " (ssWorkflows ss)
  , "  Jobs:      " <> T.intercalate ", " (ssJobs ss)
  , "  Steps:     " <> if null (ssSteps ss) then "(none)" else T.intercalate ", " (ssSteps ss)
  ]
