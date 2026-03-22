-- | GitHub Actions if-condition evaluator.
--
-- Partially evaluates if: expressions against a mock GitHub context.
-- Handles common patterns like github.event_name, github.ref,
-- success(), failure(), always(), and boolean operators.
module Orchestrator.Simulate.Conditions
  ( evaluateCondition
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Simulate.Types (SimContext (..), JobStatus (..))

-- | Evaluate an if-condition string against a simulation context.
-- Returns WillRun, WillSkip, or Conditional depending on what
-- can be statically determined.
evaluateCondition :: SimContext -> Text -> JobStatus
evaluateCondition ctx cond =
  let stripped = T.strip cond
      -- Remove surrounding ${{ }} if present
      expr = if "${{" `T.isPrefixOf` stripped
             then T.strip $ T.dropEnd 2 $ T.drop 3 stripped
             else stripped
  in evalExpr ctx expr

-- | Evaluate a single expression.
evalExpr :: SimContext -> Text -> JobStatus
evalExpr ctx expr
  -- Built-in functions
  | "always()" `T.isInfixOf` expr = WillRun
  | "success()" `T.isInfixOf` expr = WillRun  -- Assume prior jobs succeed
  | "failure()" `T.isInfixOf` expr = WillSkip "failure() — assumes no failures"
  | "cancelled()" `T.isInfixOf` expr = WillSkip "cancelled() — assumes not cancelled"

  -- Event name checks
  | "github.event_name ==" `T.isInfixOf` expr ||
    "github.event_name==" `T.isInfixOf` expr =
      let expected = extractStringLiteral expr
      in if expected == ctxEventName ctx
         then WillRun
         else WillSkip $ "event_name is '" <> ctxEventName ctx
                <> "', not '" <> expected <> "'"

  | "github.event_name !=" `T.isInfixOf` expr ||
    "github.event_name!=" `T.isInfixOf` expr =
      let expected = extractStringLiteral expr
      in if expected /= ctxEventName ctx
         then WillRun
         else WillSkip $ "event_name is '" <> ctxEventName ctx <> "'"

  -- Ref checks
  | "github.ref ==" `T.isInfixOf` expr ||
    "github.ref==" `T.isInfixOf` expr =
      let expected = extractStringLiteral expr
      in if expected == ctxRef ctx
         then WillRun
         else WillSkip $ "ref is '" <> ctxRef ctx <> "', not '" <> expected <> "'"

  -- Branch checks via contains/startsWith
  | "contains(" `T.isPrefixOf` T.strip expr = Conditional expr
  | "startsWith(" `T.isPrefixOf` T.strip expr = Conditional expr

  -- Boolean negation
  | "!" `T.isPrefixOf` T.strip expr =
      case evalExpr ctx (T.drop 1 (T.strip expr)) of
        WillRun -> WillSkip "negated condition"
        WillSkip _ -> WillRun
        other -> other

  -- Variable references we can resolve
  | "github.ref" `T.isInfixOf` expr = Conditional $ "depends on ref (current: " <> ctxRef ctx <> ")"
  | "github.actor" `T.isInfixOf` expr = Conditional $ "depends on actor (current: " <> ctxActor ctx <> ")"
  | "secrets." `T.isInfixOf` expr = Conditional "depends on secret value"
  | "vars." `T.isInfixOf` expr = Conditional "depends on variable value"
  | "needs." `T.isInfixOf` expr = Conditional "depends on prior job output"
  | "inputs." `T.isInfixOf` expr = Conditional "depends on workflow input"
  | "env." `T.isInfixOf` expr = Conditional "depends on environment variable"
  | "steps." `T.isInfixOf` expr = Conditional "depends on prior step output"
  | "matrix." `T.isInfixOf` expr = Conditional "depends on matrix value"

  -- True/false literals
  | T.toLower (T.strip expr) == "true" = WillRun
  | T.toLower (T.strip expr) == "false" = WillSkip "condition is false"

  -- Can't determine statically
  | otherwise = Conditional expr

-- | Extract a string literal from an expression like "github.event_name == 'push'".
extractStringLiteral :: Text -> Text
extractStringLiteral expr =
  let -- Try single quotes first
      afterQuote = T.drop 1 $ snd $ T.breakOn "'" expr
      singleQuoted = T.takeWhile (/= '\'') afterQuote
      -- Try double quotes
      afterDQuote = T.drop 1 $ snd $ T.breakOn "\"" expr
      doubleQuoted = T.takeWhile (/= '"') afterDQuote
  in if not (T.null singleQuoted) then singleQuoted
     else if not (T.null doubleQuoted) then doubleQuoted
     else T.strip $ T.drop 2 $ snd $ T.breakOn "==" expr  -- Fallback
