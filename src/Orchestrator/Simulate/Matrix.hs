-- | Matrix expansion logic.
--
-- Computes all combinations from a GitHub Actions matrix strategy,
-- detects explosion risk, and generates human-readable combination keys.
module Orchestrator.Simulate.Matrix
  ( expandMatrix,
    MatrixCombination,
    estimateMatrixSize,
  )
where

import Data.Map.Strict qualified as Map
import Data.Maybe (maybeToList)
import Data.Text (Text)
import Data.Text qualified as T
import Orchestrator.Model

-- | A single matrix combination: key description + variable values.
type MatrixCombination = (Text, [(Text, Text)])

-- | Extract matrix dimensions from a job and expand all combinations.
--
-- Since the typed model doesn't directly parse strategy.matrix, we
-- infer dimensions from matrix variable references in the job.
expandMatrix :: Job -> [MatrixCombination]
expandMatrix j =
  let dims = extractDimensions j
   in if null dims
        then [] -- No matrix detected
        else cartesian dims

-- | Extract matrix dimensions by analyzing variable references.
-- Returns [(dimension_name, [inferred_values])].
extractDimensions :: Job -> [(Text, [Text])]
extractDimensions j =
  let allRefs = concatMap findMatrixRefs (jobSteps j)
      runnerRef = case jobRunsOn j of
        MatrixRunner t -> findMatrixRefsInText t
        _ -> []
      allDimNames = dedup (allRefs ++ runnerRef)
   in -- Infer plausible values for common dimensions
      map (\dim -> (dim, inferValues dim)) allDimNames

-- | Find matrix.* references in a step.
findMatrixRefs :: Step -> [Text]
findMatrixRefs s =
  let texts =
        concat
          [ maybeToList (stepRun s),
            maybeToList (stepUses s),
            maybeToList (stepName s),
            maybeToList (stepIf s),
            Map.elems (stepWith s),
            Map.elems (stepEnv s)
          ]
   in concatMap findMatrixRefsInText texts

-- | Extract matrix dimension names from text containing ${{ matrix.X }}.
findMatrixRefsInText :: Text -> [Text]
findMatrixRefsInText = go []
  where
    go acc t
      | T.null t = acc
      | "matrix." `T.isInfixOf` t =
          let (_, after) = T.breakOn "matrix." t
              rest = T.drop 7 after -- skip "matrix."
              dim =
                T.takeWhile
                  ( \c ->
                      c /= ' '
                        && c /= '}'
                        && c /= ','
                        && c /= ')'
                        && c /= '"'
                        && c /= '\''
                  )
                  rest
           in if T.null dim
                then go acc (T.drop 7 after)
                else go (dim : acc) (T.drop (T.length dim) rest)
      | otherwise = acc

-- | Infer plausible values for common matrix dimension names.
inferValues :: Text -> [Text]
inferValues dim = case T.toLower dim of
  "os" -> ["ubuntu-latest", "macos-latest", "windows-latest"]
  "node-version" -> ["18", "20", "22"]
  "node" -> ["18", "20", "22"]
  "python-version" -> ["3.10", "3.11", "3.12"]
  "python" -> ["3.10", "3.11", "3.12"]
  "go-version" -> ["1.21", "1.22"]
  "go" -> ["1.21", "1.22"]
  "java-version" -> ["17", "21"]
  "java" -> ["17", "21"]
  "ruby-version" -> ["3.2", "3.3"]
  "ghc" -> ["9.4", "9.6"]
  "ghc-version" -> ["9.4", "9.6"]
  "rust" -> ["stable", "nightly"]
  "toolchain" -> ["stable", "nightly"]
  _ -> ["value-1", "value-2"] -- Unknown dimension

-- | Compute cartesian product of all dimensions.
cartesian :: [(Text, [Text])] -> [MatrixCombination]
cartesian [] = []
cartesian [(dim, vals)] = [(dim <> "=" <> v, [(dim, v)]) | v <- vals]
cartesian ((dim, vals) : rest) =
  let subCombos = cartesian rest
   in [ (dim <> "=" <> v <> ", " <> subKey, (dim, v) : subVals)
      | v <- vals,
        (subKey, subVals) <- subCombos
      ]

-- | Estimate total matrix size without expanding.
estimateMatrixSize :: Job -> Int
estimateMatrixSize j =
  let dims = extractDimensions j
   in if null dims
        then 1
        else product (map (length . snd) dims)

-- | Deduplicate preserving order.
dedup :: (Eq a) => [a] -> [a]
dedup = go []
  where
    go _ [] = []
    go seen (x : xs)
      | x `elem` seen = go seen xs
      | otherwise = x : go (x : seen) xs
