module Test.GitHub (tests) where

import Orchestrator.GitHub
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))

tests :: TestTree
tests = testGroup "GitHub"
  [ testCase "defaultGitHubConfig with no token sets ghcToken to Nothing" $ do
      let cfg = defaultGitHubConfig Nothing
      ghcToken cfg @?= Nothing

  , testCase "defaultGitHubConfig with token stores token" $ do
      let cfg = defaultGitHubConfig (Just "tok_abc123")
      ghcToken cfg @?= Just "tok_abc123"

  , testCase "defaultGitHubConfig uses api.github.com as base URL" $ do
      let cfg = defaultGitHubConfig Nothing
      ghcApiUrl cfg @?= "https://api.github.com"

  , testCase "defaultGitHubConfig timeout is positive" $ do
      let cfg = defaultGitHubConfig Nothing
      assertBool "timeout > 0" (ghcTimeout cfg > 0)

  , testCase "defaultGitHubConfig maxWait is positive" $ do
      let cfg = defaultGitHubConfig Nothing
      assertBool "maxWait > 0" (ghcMaxWait cfg > 0)

  , testCase "defaultGitHubConfig does not include archived by default" $ do
      let cfg = defaultGitHubConfig Nothing
      ghcIncludeArchived cfg @?= False

  , testCase "defaultGitHubConfig does not include forks by default" $ do
      let cfg = defaultGitHubConfig Nothing
      ghcIncludeForks cfg @?= False

  , testCase "GitHubError Show instance works for HttpError" $ do
      let e = GitHubHttpError 500 "Internal Server Error"
      assertBool "show produces non-empty string" (not (null (show e)))

  , testCase "GitHubError Show instance works for RateLimited" $ do
      let e = GitHubRateLimited 60
      assertBool "show produces non-empty string" (not (null (show e)))

  , testCase "GitHubError Eq: same errors are equal" $ do
      let e1 = GitHubNotFound "/repos/owner/repo"
          e2 = GitHubNotFound "/repos/owner/repo"
      e1 @?= e2

  , testCase "GitHubError Eq: different errors are not equal" $ do
      let e1 = GitHubNotFound "a"
          e2 = GitHubNotFound "b"
      assertBool "different paths differ" (e1 /= e2)

  , testCase "GitHubConfig Eq: two defaults are equal" $ do
      let c1 = defaultGitHubConfig Nothing
          c2 = defaultGitHubConfig Nothing
      c1 @?= c2

  , testCase "GitHubConfig Show produces non-empty string" $ do
      let cfg = defaultGitHubConfig (Just "token")
      assertBool "show non-empty" (not (null (show cfg)))
  ]
