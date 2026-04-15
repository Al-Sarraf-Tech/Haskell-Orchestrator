-- | Auto-pin actions to SHA — analyze which action references can be pinned.
--
-- Examines all action references in a workflow and classifies their
-- pinning status: already pinned, can be pinned, local actions, or
-- Docker actions.
module Orchestrator.Actions.Pin
  ( -- * Types
    PinAction (..),
    PinStatus (..),

    -- * Analysis
    analyzePinning,

    -- * Rendering
    renderPinReport,
  )
where

import Data.Char (isHexDigit)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model

-- | Pinning status of an action reference.
data PinStatus
  = AlreadyPinned
  | CanPin
  | LocalAction
  | DockerAction
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded)

-- | Analysis result for a single action reference.
data PinAction = PinAction
  { pinActionRef :: !Text,
    pinCurrentVersion :: !Text,
    pinPinnedSHA :: !(Maybe Text),
    pinStatus :: !PinStatus
  }
  deriving stock (Eq, Show)

-- | Analyze all action references in a workflow for pinning status.
analyzePinning :: Workflow -> [PinAction]
analyzePinning wf =
  [ classifyAction uses
  | j <- wfJobs wf,
    s <- jobSteps j,
    Just uses <- [stepUses s]
  ]

-- | Classify a single action reference.
classifyAction :: Text -> PinAction
classifyAction ref
  -- Local composite actions (e.g. "./.github/actions/my-action")
  | "./" `T.isPrefixOf` ref =
      PinAction
        { pinActionRef = ref,
          pinCurrentVersion = "",
          pinPinnedSHA = Nothing,
          pinStatus = LocalAction
        }
  -- Docker container actions (e.g. "docker://alpine:3.18")
  | "docker://" `T.isPrefixOf` ref =
      PinAction
        { pinActionRef = ref,
          pinCurrentVersion = "",
          pinPinnedSHA = Nothing,
          pinStatus = DockerAction
        }
  -- Regular action references with @version
  | otherwise =
      let (actionName, afterAt) = T.breakOn "@" ref
          version = if T.null afterAt then "" else T.drop 1 afterAt
       in if isSHAPinned version
            then
              PinAction
                { pinActionRef = actionName,
                  pinCurrentVersion = version,
                  pinPinnedSHA = Just version,
                  pinStatus = AlreadyPinned
                }
            else
              PinAction
                { pinActionRef = actionName,
                  pinCurrentVersion = version,
                  pinPinnedSHA = Nothing,
                  pinStatus = CanPin
                }

-- | Check whether a version string is a 40-char hex SHA.
isSHAPinned :: Text -> Bool
isSHAPinned v = T.length v == 40 && T.all isHexDigit v

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

-- | Render a formatted report of pinning status for all actions.
renderPinReport :: [PinAction] -> Text
renderPinReport [] = "No action references found.\n"
renderPinReport pins =
  let header = "Action Pinning Report\n" <> T.replicate 50 "─" <> "\n"
      canPin = filter (\p -> pinStatus p == CanPin) pins
      pinned = filter (\p -> pinStatus p == AlreadyPinned) pins
      local = filter (\p -> pinStatus p == LocalAction) pins
      docker = filter (\p -> pinStatus p == DockerAction) pins
      summary =
        "Summary: "
          <> showCount (length pinned) "pinned"
          <> ", "
          <> showCount (length canPin) "to pin"
          <> ", "
          <> showCount (length local) "local"
          <> ", "
          <> showCount (length docker) "docker"
          <> "\n\n"
      details = T.unlines (map renderPinRow pins)
   in header <> summary <> details

renderPinRow :: PinAction -> Text
renderPinRow pa =
  let tag = renderPinStatus (pinStatus pa)
      ref = pinActionRef pa
      ver =
        if T.null (pinCurrentVersion pa)
          then ""
          else "@" <> pinCurrentVersion pa
   in tag <> " " <> ref <> ver

renderPinStatus :: PinStatus -> Text
renderPinStatus AlreadyPinned = "[PINNED] "
renderPinStatus CanPin = "[TO PIN] "
renderPinStatus LocalAction = "[LOCAL]  "
renderPinStatus DockerAction = "[DOCKER] "

showCount :: Int -> Text -> Text
showCount n label = T.pack (show n) <> " " <> label
