module CPlugin.Commands.Common (loadCurrent, resolveLocalSource, persistSync, reportCompletion, validateAs, failAs) where

import CPlugin.Paths (RuntimePaths, absoluteIO, discoverLocks, strictRealPath, validateManagedRoot, within)
import CPlugin.Reconcile (printWarnings, syncLoadedLockWithForce)
import CPlugin.StateStore (readLock, writeLock)
import CPlugin.Types.Lock (Lock (..))
import CPlugin.Types.Ownership (OwnershipSource)
import CPlugin.Types.Path (AbsolutePath, RelativePath, absoluteText, relativePath, relativeText)
import CPlugin.Types.Sync (SyncCompletion (..), SyncResult (..))
import Control.Monad (unless, when)
import Data.List (isPrefixOf)
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

resolveLocalSource :: String -> FilePath -> FilePath -> IO (RelativePath, AbsolutePath)
resolveLocalSource invalid lockPath raw = do
    unless ("./" `isPrefixOf` raw) (failAs invalid "local source must begin with ./")
    source <- validateAs invalid (relativePath raw)
    let base = takeDirectory lockPath
    root <- absoluteIO (base </> relativeText source)
    physicalBase <- strictRealPath base
    physicalRoot <- strictRealPath (absoluteText root)
    unless (within physicalBase physicalRoot) (failAs invalid "local source resolves outside lock root")
    pure (source, root)

persistSync :: FilePath -> Lock -> Set.Set OwnershipSource -> IO SyncResult
persistSync lockPath candidate forcedSources = do
    let base = takeDirectory lockPath
    roots <-
        mapM
            (absoluteIO . (base </>))
            (".agents" : ".agents/skills" : map relativeText (Set.toAscList (targets candidate)))
    mapM_ (validateManagedRoot base) roots
    writeLock lockPath candidate
    syncLoadedLockWithForce lockPath candidate forcedSources

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
