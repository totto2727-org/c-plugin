module CPlugin.Commands.Update (run, runWithGit, refreshLockWithGit) where

import CPlugin.Commands.Common (failAs, persistSync, reportCompletion, validateAs)
import CPlugin.Paths (RuntimePaths, discoverLocks)
import CPlugin.Plugin (loadPlugin, loadStandaloneSkill)
import CPlugin.Reconcile (renderSyncResult, syncLoadedLock)
import CPlugin.Source.GitHub (GitRunner, fetchGitHubWith, runGit)
import CPlugin.StateStore (readLock)
import CPlugin.Types.GitHub (GitHubOrigin (..), githubSource)
import CPlugin.Types.InstalledSkill (InstalledSkill (..), makeInstalledSkillWithOrigin)
import CPlugin.Types.Lock (Lock (..), makeLockWithSkills)
import CPlugin.Types.Plugin (Plugin (..), makePluginWithOrigin)
import CPlugin.Types.PluginManifest (manifestName)
import CPlugin.Types.Skill (resolvedSkillName)
import Control.Exception (IOException, catch)
import Control.Monad (forM_, unless)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.FilePath (takeDirectory)

run :: RuntimePaths -> Bool -> Bool -> IO ()
run = runWithGit runGit

runWithGit :: GitRunner -> RuntimePaths -> Bool -> Bool -> IO ()
runWithGit git paths global recursive = do
    lockPaths <- discoverLocks paths global recursive
    forM_ lockPaths $ \lockPath -> do
        current <- readLock lockPath
        candidate <- refreshLockWithGit git lockPath current
        result <-
            if candidate == current
                then syncLoadedLock lockPath current False
                else persistSync lockPath candidate False
        reportCompletion result
        putStrLn ("Updated " ++ lockPath ++ ": " ++ renderSyncResult result)

-- Finish all fetches and validate the complete per-lock candidate before any
-- desired-state or link mutation. Independent recursive locks stay isolated.
refreshLockWithGit :: GitRunner -> FilePath -> Lock -> IO Lock
refreshLockWithGit git lockPath current =
    refresh `catch` \e -> failAs invalid (show (e :: IOException))
  where
    invalid = "totto2727/c-plugin.UpdateError.InvalidInput"
    base = takeDirectory lockPath
    refresh = do
        refreshedPlugins <- mapM refreshPlugin (Map.elems (plugins current))
        refreshedSkills <- mapM refreshSkill (Map.elems (standaloneSkills current))
        validateAs invalid (makeLockWithSkills (Set.toAscList (targets current)) refreshedPlugins refreshedSkills)
    fetch origin = fetchGitHubWith git base (githubOriginRepository origin) (githubOriginRef origin) (githubOriginSubpath origin)
    refreshPlugin plugin = case pluginOrigin plugin of
        Nothing -> pure plugin
        Just previous -> do
            (origin, root) <- fetch previous
            (manifest, available, _) <- loadPlugin root
            unless (manifestName manifest == pluginName plugin) (failAs invalid "updated plugin name differs from installed identity")
            let selected = enabledSkills plugin
                choices = Set.fromList (map resolvedSkillName available)
            unless (selected `Set.isSubsetOf` choices) (failAs invalid "updated plugin no longer provides every enabled skill")
            validateAs invalid (makePluginWithOrigin (pluginName plugin) (githubSource origin) (Set.toAscList selected) (Just origin))
    refreshSkill skill = case installedSkillOrigin skill of
        Nothing -> pure skill
        Just previous -> do
            (origin, root) <- fetch previous
            available <- loadStandaloneSkill root
            unless (resolvedSkillName available == installedSkillName skill) (failAs invalid "updated standalone skill name differs from installed identity")
            validateAs invalid (makeInstalledSkillWithOrigin (installedSkillName skill) (githubSource origin) (Just origin))
