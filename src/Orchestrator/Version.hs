-- | Single source of truth for version and edition strings.
module Orchestrator.Version
  ( orchestratorVersion,
    orchestratorEdition,
    userAgentString,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

orchestratorVersion :: Text
orchestratorVersion = "4.0.0"

orchestratorEdition :: Text
orchestratorEdition = "Community"

userAgentString :: String
userAgentString = "haskell-orchestrator/" <> T.unpack orchestratorVersion
