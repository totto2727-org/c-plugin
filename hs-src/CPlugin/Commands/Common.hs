module CPlugin.Commands.Common (loadCurrent, persistSync, reportCompletion, validateAs, failAs) where

import CPlugin.Paths (RuntimePaths, absoluteIO, discoverLocks, validateManagedRoot)
import CPlugin.Reconcile (printWarnings, syncLoadedLock)
import CPlugin.StateStore (readLock, writeLock)
import CPlugin.Types.Lock (Lock (..))
import CPlugin.Types.Path (relativeText)
import CPlugin.Types.Sync (SyncCompletion (..), SyncResult (..))
import Control.Monad (when)
import qualified Data.Set as Set
import System.FilePath (takeDirectory, (</>))

loadCurrent :: RuntimePaths -> Bool -> IO (FilePath, Lock)
loadCurrent paths global = do
    discovered <- discoverLocks paths global False
    case discovered of
        [lockPath] -> do
            current <- readLock lockPath
            pure (lockPath, current)
        _ -> failAs "totto2727/c-plugin.LockDiscoveryError" "expected exactly one lock"

persistSync :: FilePath -> Lock -> Bool -> IO SyncResult
persistSync lockPath candidate force = do
    let base = takeDirectory lockPath
    roots <-
        mapM
            (absoluteIO . (base </>))
            (".agents" : ".agents/skills" : map relativeText (Set.toAscList (targets candidate)))
    mapM_ (validateManagedRoot base) roots
    writeLock lockPath candidate
    syncLoadedLock lockPath candidate force

reportCompletion :: SyncResult -> IO ()
reportCompletion result = do
    printWarnings result
    when
        (syncCompletion result == Interrupted)
        (failAs "totto2727/c-plugin.SyncError.CheckpointFailed" "reconciliation stopped at a durability or verification boundary")

validateAs :: String -> Either String a -> IO a
validateAs prefix = either (failAs prefix) pure
failAs :: String -> String -> IO a
failAs prefix reason = ioError (userError (prefix ++ " " ++ reason))
