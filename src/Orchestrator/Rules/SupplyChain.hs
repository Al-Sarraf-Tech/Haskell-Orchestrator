-- | Supply chain security rules for GitHub Actions workflows.
--
-- Detects privilege escalation, artifact poisoning, OIDC scope issues,
-- abandoned actions, and typosquat risks.
module Orchestrator.Rules.SupplyChain
  ( sec003Rule
  , sec004Rule
  , sec005Rule
  , supply001Rule
  , supply002Rule
  ) where

import Data.List (minimumBy)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Map.Strict qualified as Map
import Orchestrator.Model
import Orchestrator.Policy (PolicyRule (..))
import Orchestrator.Types

------------------------------------------------------------------------
-- SEC-003: Workflow Run Privilege Escalation
------------------------------------------------------------------------

-- | Detect pull_request_target combined with explicit checkout of the PR
-- head ref.  Default checkout (no 'ref' input) is NOT flagged.
sec003Rule :: PolicyRule
sec003Rule = PolicyRule
  { ruleId = "SEC-003"
  , ruleName = "Workflow Run Privilege Escalation"
  , ruleDescription =
      "pull_request_target with explicit head-ref checkout grants write \
      \permissions to untrusted code"
  , ruleSeverity = Error
  , ruleCategory = Security
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      let hasPRT = any (triggerHasName "pull_request_target") (wfTriggers wf)
          headRefSteps =
            [ s
            | j <- wfJobs wf
            , s <- jobSteps j
            , isCheckoutWithHeadRef s
            ]
      in [ mkFinding' Error Security "SEC-003"
              "Workflow uses pull_request_target with an explicit PR head-ref \
              \checkout. This grants write-token access to untrusted fork code \
              \and is a critical supply-chain attack vector."
              (wfFileName wf)
              Nothing
              (Just "Remove the explicit 'ref' input from actions/checkout, \
                    \or use pull_request instead of pull_request_target.")
         | hasPRT && not (null headRefSteps)
         ]
  }

isCheckoutWithHeadRef :: Step -> Bool
isCheckoutWithHeadRef s =
  case stepUses s of
    Just uses | "actions/checkout" `T.isPrefixOf` uses ->
      let ref = Map.findWithDefault "" "ref" (stepWith s)
      in  "pull_request.head" `T.isInfixOf` ref
          || "github.head_ref" `T.isInfixOf` ref
    _ -> False

------------------------------------------------------------------------
-- SEC-004: Artifact Poisoning
------------------------------------------------------------------------

-- | Detect a download-artifact step followed by a run step in the same job.
sec004Rule :: PolicyRule
sec004Rule = PolicyRule
  { ruleId = "SEC-004"
  , ruleName = "Artifact Poisoning"
  , ruleDescription =
      "Downloading an artifact then executing it in the same job allows \
      \poisoned artifacts to run with workflow permissions"
  , ruleSeverity = Warning
  , ruleCategory = Security
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      let isWorkflowRun = any (triggerHasName "workflow_run") (wfTriggers wf)
          jobFindings = concatMap (checkArtifactPoisoning (wfFileName wf) isWorkflowRun) (wfJobs wf)
      in jobFindings
  }

checkArtifactPoisoning :: FilePath -> Bool -> Job -> [Finding]
checkArtifactPoisoning fp isWfRun job =
  let steps = jobSteps job
      pairs  = zip [0 :: Int ..] steps
      downloadIndices =
        [ i | (i, s) <- pairs, isDownloadArtifactStep s ]
      runIndices =
        [ i | (i, s) <- pairs, hasRunStep s ]
      hasRunAfterDownload =
        any (\di -> any (> di) runIndices) downloadIndices
      severity = if isWfRun then Error else Warning
      note = if isWfRun
               then " (workflow_run trigger increases severity: artifacts may \
                    \come from fork workflows)"
               else ""
  in [ mkFinding' severity Security "SEC-004"
          ("Job '" <> jobId job <> "' downloads an artifact and then executes \
           \a run step. Poisoned artifacts could execute arbitrary code with \
           \workflow permissions." <> note)
          fp
          Nothing
          (Just "Verify artifact integrity (e.g. cosign/sigstore) before \
                \executing. Consider separating download and execution into \
                \isolated jobs with minimal permissions.")
     | hasRunAfterDownload
     ]

isDownloadArtifactStep :: Step -> Bool
isDownloadArtifactStep s = case stepUses s of
  Just uses -> "download-artifact" `T.isInfixOf` uses
  Nothing   -> False

hasRunStep :: Step -> Bool
hasRunStep s = case stepRun s of
  Just _ -> True
  Nothing -> False

------------------------------------------------------------------------
-- SEC-005: OIDC Token Scope
------------------------------------------------------------------------

-- | Detect id-token: write without any deployment step.
sec005Rule :: PolicyRule
sec005Rule = PolicyRule
  { ruleId = "SEC-005"
  , ruleName = "OIDC Token Scope"
  , ruleDescription =
      "id-token: write is granted but no deployment action is present. \
      \Unused OIDC scope violates least-privilege."
  , ruleSeverity = Warning
  , ruleCategory = Security
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      let hasIdTokenWrite = workflowHasIdTokenWrite wf
          hasDeployStep   = any (any isDeployStep . jobSteps) (wfJobs wf)
      in [ mkFinding' Warning Security "SEC-005"
              "Workflow grants id-token: write but contains no recognized \
              \deployment step (AWS, Azure, GCP, Vault). \
              \Remove the permission if OIDC federation is not needed."
              (wfFileName wf)
              Nothing
              (Just "Remove 'id-token: write' or add an OIDC-consuming \
                    \deployment step.")
         | hasIdTokenWrite && not hasDeployStep
         ]
  }

workflowHasIdTokenWrite :: Workflow -> Bool
workflowHasIdTokenWrite wf =
  permissionsHaveIdTokenWrite (wfPermissions wf)
  || any (permissionsHaveIdTokenWrite . jobPermissions) (wfJobs wf)

permissionsHaveIdTokenWrite :: Maybe Permissions -> Bool
permissionsHaveIdTokenWrite Nothing = False
permissionsHaveIdTokenWrite (Just (PermissionsAll PermWrite)) = True
permissionsHaveIdTokenWrite (Just (PermissionsAll _)) = False
permissionsHaveIdTokenWrite (Just (PermissionsMap m)) =
  Map.findWithDefault PermNone "id-token" m == PermWrite

deploymentActions :: [Text]
deploymentActions =
  [ "aws-actions/configure-aws-credentials"
  , "azure/login"
  , "google-github-actions/auth"
  , "hashicorp/vault-action"
  ]

isDeployStep :: Step -> Bool
isDeployStep s = case stepUses s of
  Just uses -> any (`T.isPrefixOf` uses) deploymentActions
  Nothing   -> False

------------------------------------------------------------------------
-- SUPPLY-001: Abandoned Action
------------------------------------------------------------------------

-- | Detect actions from a known-abandoned list.
-- The list starts empty and will be populated over time.
supply001Rule :: PolicyRule
supply001Rule = PolicyRule
  { ruleId = "SUPPLY-001"
  , ruleName = "Abandoned Action"
  , ruleDescription =
      "Action repository is on the abandoned-action watchlist. \
      \Unmaintained actions may have unpatched vulnerabilities."
  , ruleSeverity = Warning
  , ruleCategory = SupplyChain
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      concatMap (concatMap (checkAbandoned (wfFileName wf)) . jobSteps) (wfJobs wf)
  }

-- | Known-abandoned action owner/repo slugs (without @ref).
abandonedActions :: [Text]
abandonedActions = []

checkAbandoned :: FilePath -> Step -> [Finding]
checkAbandoned fp s = case stepUses s of
  Just uses
    | isFirstPartyAction uses -> []
    | otherwise ->
        let slug = ownerRepo uses
        in [ mkFinding' Warning SupplyChain "SUPPLY-001"
                ("Action '" <> slug <> "' is on the abandoned-action watchlist. \
                 \The repository may no longer receive security updates.")
                fp
                Nothing
                (Just "Replace with an actively maintained alternative.")
           | slug `elem` abandonedActions
           ]
  Nothing -> []

------------------------------------------------------------------------
-- SUPPLY-002: Typosquat Risk
------------------------------------------------------------------------

-- | Detect action names within edit-distance 2 of popular actions.
supply002Rule :: PolicyRule
supply002Rule = PolicyRule
  { ruleId = "SUPPLY-002"
  , ruleName = "Typosquat Risk"
  , ruleDescription =
      "Action name is suspiciously similar to a popular action. \
      \May be a typosquatting attempt."
  , ruleSeverity = Info
  , ruleCategory = SupplyChain
  , ruleTags = [TagSecurity]
  , ruleCheck = \wf ->
      concatMap (concatMap (checkTyposquat (wfFileName wf)) . jobSteps) (wfJobs wf)
  }

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
  , "docker/build-push-action"
  , "docker/login-action"
  , "aws-actions/configure-aws-credentials"
  , "softprops/action-gh-release"
  ]

checkTyposquat :: FilePath -> Step -> [Finding]
checkTyposquat fp s = case stepUses s of
  Just uses
    | isFirstPartyAction uses -> []
    | "./" `T.isPrefixOf` uses -> []
    | otherwise ->
        let slug = ownerRepo uses
            closest = minimumBy (comparing (levenshtein slug)) popularActions
            dist    = levenshtein slug closest
        in [ mkFinding' Info SupplyChain "SUPPLY-002"
                ("Action '" <> slug <> "' is edit-distance " <> T.pack (show dist)
                 <> " from popular action '" <> closest
                 <> "'. Possible typosquat.")
                fp
                Nothing
                (Just $ "Verify '" <> slug <> "' is intentional and not a \
                        \typo of '" <> closest <> "'.")
           | dist > 0 && dist <= 2
           ]
  Nothing -> []

------------------------------------------------------------------------
-- Shared helpers
------------------------------------------------------------------------

triggerHasName :: Text -> WorkflowTrigger -> Bool
triggerHasName name (TriggerEvents evts) =
  any (\e -> triggerName e == name) evts
triggerHasName _ _ = False

isFirstPartyAction :: Text -> Bool
isFirstPartyAction t =
  "actions/" `T.isPrefixOf` t
  || "github/" `T.isPrefixOf` t
  || "./" `T.isPrefixOf` t

-- | Extract "owner/repo" from "owner/repo@ref".
ownerRepo :: Text -> Text
ownerRepo t = fst (T.breakOn "@" t)

-- | Standard Levenshtein edit distance on Text.
-- Uses the classic DP two-row approach.
levenshtein :: Text -> Text -> Int
levenshtein s t = last $ foldl step firstRow tChars
  where
    sChars   = T.unpack s
    tChars   = T.unpack t
    firstRow = [0 .. length sChars]
    step prevRow c = scanl (advance prevRow c) (head prevRow + 1) (zip [0..] sChars)
    advance prevRow c acc (j, sc) =
      let ins  = acc + 1
          del  = (prevRow !! (j + 1)) + 1
          sub  = (prevRow !! j) + if c == sc then 0 else 1
      in minimum [ins, del, sub]
