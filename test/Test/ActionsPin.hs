module Test.ActionsPin (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Orchestrator.Actions.Pin
import Orchestrator.Model
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkWf :: [Job] -> Workflow
mkWf jobs =
  Workflow
    "Test"
    "test.yml"
    [TriggerEvents [TriggerEvent "push" ["main"] [] []]]
    jobs
    Nothing
    Nothing
    Map.empty

mkJob :: T.Text -> [Step] -> Job
mkJob jid steps =
  Job
    jid
    (Just jid)
    (StandardRunner "ubuntu-latest")
    steps
    Nothing
    []
    Nothing
    Map.empty
    Nothing
    (Just 30)
    Nothing
    False
    Nothing
    False

mkUsesStep :: T.Text -> Step
mkUsesStep uses =
  Step Nothing (Just "Action") (Just uses) Nothing Map.empty Map.empty Nothing Nothing

mkRunStep :: T.Text -> Step
mkRunStep cmd =
  Step Nothing (Just "Run") Nothing (Just cmd) Map.empty Map.empty Nothing Nothing

-- | A real 40-char hex SHA
pinnedSHA :: T.Text
pinnedSHA = "a6347daa26fa9f3c7b1234567890abcdef123456"

pinnedRef :: T.Text
pinnedRef = "actions/checkout@" <> pinnedSHA

------------------------------------------------------------------------
-- Tests
------------------------------------------------------------------------

tests :: TestTree
tests =
  testGroup
    "ActionsPin"
    [ testGroup
        "analyzePinning"
        [ testCase "empty workflow produces no pin actions" $ do
            let wf = mkWf []
                pins = analyzePinning wf
            pins @?= [],
          testCase "run-only steps produce no pin actions" $ do
            let wf = mkWf [mkJob "build" [mkRunStep "cabal build"]]
                pins = analyzePinning wf
            pins @?= [],
          testCase "tag-versioned action has CanPin status" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep "actions/checkout@v4"]]
                pins = analyzePinning wf
            length pins @?= 1
            pinStatus (head pins) @?= CanPin,
          testCase "SHA-pinned action has AlreadyPinned status" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep pinnedRef]]
                pins = analyzePinning wf
            length pins @?= 1
            pinStatus (head pins) @?= AlreadyPinned,
          testCase "local action has LocalAction status" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep "./.github/actions/my-action"]]
                pins = analyzePinning wf
            length pins @?= 1
            pinStatus (head pins) @?= LocalAction,
          testCase "docker action has DockerAction status" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep "docker://alpine:3.18"]]
                pins = analyzePinning wf
            length pins @?= 1
            pinStatus (head pins) @?= DockerAction,
          testCase "SHA-pinned action stores SHA in pinPinnedSHA" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep pinnedRef]]
                pins = analyzePinning wf
            pinPinnedSHA (head pins) @?= Just pinnedSHA,
          testCase "tag-versioned action has Nothing for pinPinnedSHA" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep "actions/checkout@v4"]]
                pins = analyzePinning wf
            pinPinnedSHA (head pins) @?= Nothing,
          testCase "local action has Nothing for pinPinnedSHA" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep "./.github/actions/my-action"]]
                pins = analyzePinning wf
            pinPinnedSHA (head pins) @?= Nothing,
          testCase "docker action has Nothing for pinPinnedSHA" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep "docker://alpine:3.18"]]
                pins = analyzePinning wf
            pinPinnedSHA (head pins) @?= Nothing,
          testCase "multiple actions across jobs are all analysed" $ do
            let step1 = mkUsesStep "actions/checkout@v4"
                step2 = mkUsesStep pinnedRef
                step3 = mkUsesStep "./.github/actions/my-action"
                wf =
                  mkWf
                    [ mkJob "build" [step1, step2],
                      mkJob "test" [step3]
                    ]
                pins = analyzePinning wf
            length pins @?= 3,
          testCase "tag version stored in pinCurrentVersion" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep "actions/checkout@v4"]]
                pins = analyzePinning wf
            pinCurrentVersion (head pins) @?= "v4",
          testCase "CanPin action ref stored correctly" $ do
            let wf = mkWf [mkJob "build" [mkUsesStep "actions/checkout@v4"]]
                pins = analyzePinning wf
            pinActionRef (head pins) @?= "actions/checkout"
        ],
      testGroup
        "PinStatus ordering"
        [ testCase "AlreadyPinned < CanPin" $
            assertBool
              "AlreadyPinned should be less than CanPin"
              (AlreadyPinned < CanPin),
          testCase "CanPin < LocalAction" $
            assertBool
              "CanPin should be less than LocalAction"
              (CanPin < LocalAction),
          testCase "LocalAction < DockerAction" $
            assertBool
              "LocalAction should be less than DockerAction"
              (LocalAction < DockerAction)
        ]
    ]
