module CPlugin.Commands.Sync (runWithGit) where

import CPlugin.Commands.Batch (runPreparedLocks)
import CPlugin.Commands.Common (reportCompletion)
import CPlugin.Paths (RuntimePaths, discoverLocks)
import CPlugin.Reconcile (planSyncWithGit, renderSyncResult, syncPlannedLock)
import CPlugin.Source.GitHub (GitRunner)
import CPlugin.StateStore (readLock)

runWithGit :: GitRunner -> RuntimePaths -> Bool -> Bool -> IO ()
runWithGit git paths global recursive = do
    lockPaths <- discoverLocks paths global recursive
    runPreparedLocks lockPaths prepare (\_ plan -> syncPlannedLock plan False) $ \lockPath result -> do
        reportCompletion result
        putStrLn ("Synced " ++ lockPath ++ ": " ++ renderSyncResult result)
  where
    prepare lockPath = readLock lockPath >>= planSyncWithGit git lockPath
