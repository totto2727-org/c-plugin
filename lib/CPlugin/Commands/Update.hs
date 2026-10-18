module CPlugin.Commands.Update (runWithGit, refreshLockWithGit) where

import CPlugin.Commands.Batch (runPreparedLocks)
import CPlugin.Commands.Common (failAs, reportCompletion, validateAs)
import CPlugin.Internal.Concurrent (concurrentlyIO, mapConcurrentlyIO)
import CPlugin.Paths (RuntimePaths, discoverLocks)
import CPlugin.Plugin (loadPlugin, loadStandaloneSkill)
import CPlugin.Reconcile (planSyncWithGit, renderSyncResult, syncPlannedLock)
import CPlugin.Source.GitHub (GitRunner, fetchGitHubSourcesWith)
import CPlugin.StateStore (readLock, writeLock)
import CPlugin.Types.GitHub (githubSource)
import CPlugin.Types.InstalledSkill (InstalledSkill (..), makeInstalledSkillWithOrigin)
import CPlugin.Types.Lock (Lock (..), makeLockWithSkills)
import CPlugin.Types.Plugin (Plugin (..), makePluginWithOrigin)
import CPlugin.Types.PluginManifest (manifestName)
import CPlugin.Types.Skill (resolvedSkillName)
import Control.Exception (IOException, catch)
import Control.Monad (unless, when)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set
import System.FilePath (takeDirectory)

runWithGit :: GitRunner -> RuntimePaths -> Bool -> Bool -> IO ()
runWithGit git paths global recursive = do
    lockPaths <- discoverLocks paths global recursive
    runPreparedLocks lockPaths prepare apply $ \lockPath result -> do
        reportCompletion result
        putStrLn ("Updated " ++ lockPath ++ ": " ++ renderSyncResult result)
  where
    apply lockPath (current, candidate, plan) = do
        when (candidate /= current) (writeLock lockPath candidate)
        syncPlannedLock plan False
    prepare lockPath = do
        current <- readLock lockPath
        candidate <- refreshLockWithGit git lockPath current
        plan <- planSyncWithGit git lockPath candidate
        pure (current, candidate, plan)

-- Finish all fetches and validate the complete per-lock candidate before any
-- desired-state or link mutation. Independent recursive locks stay isolated.
refreshLockWithGit :: GitRunner -> FilePath -> Lock -> IO Lock
refreshLockWithGit git lockPath current =
    refresh `catch` \e -> failAs invalid (show (e :: IOException))
  where
    invalid = "totto2727/c-plugin.UpdateError.InvalidInput"
    base = takeDirectory lockPath
    refresh = do
        let origins = mapMaybe pluginOrigin (Map.elems (plugins current)) ++ mapMaybe installedSkillOrigin (Map.elems (standaloneSkills current))
        fetched <- fetchGitHubSourcesWith git base origins
        let snapshots = Map.fromList (zip origins fetched)
            fetch origin = maybe (failAs invalid "refreshed source is missing") pure (Map.lookup origin snapshots)
        (refreshedPlugins, refreshedSkills) <-
            concurrentlyIO
                (mapConcurrentlyIO (refreshPlugin fetch) (Map.elems (plugins current)))
                (mapConcurrentlyIO (refreshSkill fetch) (Map.elems (standaloneSkills current)))
        validateAs invalid (makeLockWithSkills (Set.toAscList (targets current)) refreshedPlugins refreshedSkills)
    refreshPlugin fetch plugin = case pluginOrigin plugin of
        Nothing -> pure plugin
        Just previous -> do
            (origin, root) <- fetch previous
            (manifest, available, _) <- loadPlugin root
            unless (manifestName manifest == pluginName plugin) (failAs invalid "updated plugin name differs from installed identity")
            let selected = enabledSkills plugin
                choices = Set.fromList (map resolvedSkillName available)
            unless (selected `Set.isSubsetOf` choices) (failAs invalid "updated plugin no longer provides every enabled skill")
            validateAs invalid (makePluginWithOrigin (pluginName plugin) (githubSource origin) (Set.toAscList selected) (Just origin))
    refreshSkill fetch skill = case installedSkillOrigin skill of
        Nothing -> pure skill
        Just previous -> do
            (origin, root) <- fetch previous
            available <- loadStandaloneSkill root
            unless (resolvedSkillName available == installedSkillName skill) (failAs invalid "updated standalone skill name differs from installed identity")
            validateAs invalid (makeInstalledSkillWithOrigin (installedSkillName skill) (githubSource origin) (Just origin))
