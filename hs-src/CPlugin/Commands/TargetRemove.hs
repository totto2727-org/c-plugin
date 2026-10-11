module CPlugin.Commands.TargetRemove (run) where

import CPlugin.Commands.Common (loadCurrent, persistSync, reportCompletion, validateAs)
import CPlugin.Interaction (Interaction, select)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.Lock (Lock (..))
import CPlugin.Types.Path (relativePath, relativeText)
import CPlugin.Types.Selection (Selection (..), SelectionRequest (..))
import Data.List (intercalate)
import qualified Data.Set as Set

run :: Interaction -> RuntimePaths -> Bool -> [FilePath] -> IO ()
run interaction paths global values = do
    explicit <- mapM (validateAs "totto2727/c-plugin.TargetRemoveError.InvalidInput" . relativePath) values
    (lockPath, current) <- loadCurrent paths global
    let request = if null values then PromptSelection else SelectItems explicit
    selection <- select interaction "Choose targets to remove, or use --target for explicit selection." relativeText (Set.toAscList (targets current)) request
    case selection of
        Cancelled -> putStrLn "Cancelled; no changes."
        Selected selected
            | Set.null selected -> putStrLn "No selection; no changes."
            | not (selected `Set.isSubsetOf` targets current) -> putStrLn ("No target changes for " ++ lockPath)
            | otherwise -> do
                let candidate = current{targets = targets current Set.\\ selected}
                result <- persistSync lockPath candidate False
                reportCompletion result
                putStrLn ("Removed targets " ++ intercalate ", " (map relativeText (Set.toAscList selected)) ++ " from " ++ lockPath ++ ": " ++ renderSyncResult result)
