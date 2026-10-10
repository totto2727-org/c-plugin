module CPlugin.Commands.TargetRemove (run) where

import CPlugin.Commands.Common (loadCurrent, persistSync, reportCompletion, validateAs)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.Lock (Lock (..))
import CPlugin.Types.Path (relativePath, relativeText)
import Data.List (intercalate)
import qualified Data.Set as Set

run :: RuntimePaths -> Bool -> [FilePath] -> IO ()
run paths global values = do
    selected <- mapM (validateAs "totto2727/c-plugin.TargetRemoveError.InvalidInput" . relativePath) values
    (lockPath, current) <- loadCurrent paths global
    if null selected || not (all (`Set.member` targets current) selected)
        then putStrLn ("No target changes for " ++ lockPath)
        else do
            let candidate = current{targets = targets current Set.\\ Set.fromList selected}
            result <- persistSync lockPath candidate False
            reportCompletion result
            putStrLn ("Removed targets " ++ intercalate ", " (map relativeText selected) ++ " from " ++ lockPath ++ ": " ++ renderSyncResult result)
