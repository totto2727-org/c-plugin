module CPlugin.Commands.Sync (run) where

import CPlugin.Commands.Common (reportCompletion)
import CPlugin.Paths (RuntimePaths, discoverLocks)
import CPlugin.Reconcile (renderSyncResult, syncLoadedLock)
import CPlugin.StateStore (readLock)
import Control.Monad (forM_)

run :: RuntimePaths -> Bool -> Bool -> IO ()
run paths global recursive = do
    lockPaths <- discoverLocks paths global recursive
    forM_ lockPaths $ \lockPath -> do
        lock <- readLock lockPath
        result <- syncLoadedLock lockPath lock False
        reportCompletion result
        putStrLn ("Synced " ++ lockPath ++ ": " ++ renderSyncResult result)
