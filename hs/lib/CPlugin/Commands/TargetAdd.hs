module CPlugin.Commands.TargetAdd (run) where

import CPlugin.Commands.Common (loadCurrent, persistSync, reportCompletion, validateAs)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.Lock (Lock (..))
import CPlugin.Types.Path (relativePath, relativeText)
import qualified Data.Set as Set

run :: RuntimePaths -> Bool -> FilePath -> IO ()
run paths global raw = do
    target <- validateAs "totto2727/c-plugin.TargetAddError.InvalidInput" (relativePath raw)
    (lockPath, current) <- loadCurrent paths global
    if Set.member target (targets current)
        then putStrLn ("Target " ++ relativeText target ++ " already registered in " ++ lockPath)
        else do
            let candidate = current{targets = Set.insert target (targets current)}
            result <- persistSync lockPath candidate False
            reportCompletion result
            putStrLn ("Added target " ++ relativeText target ++ " to " ++ lockPath ++ ": " ++ renderSyncResult result)
