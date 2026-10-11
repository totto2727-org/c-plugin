module CPlugin.Commands.PluginAdd (run, runResolved) where

import CPlugin.Commands.Common (failAs, loadCurrent, persistSync, reportCompletion, resolveLocalSource, validateAs)
import CPlugin.Interaction (Interaction, select)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Plugin (loadPlugin)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.GitHub (GitHubOrigin)
import CPlugin.Types.Lock (Lock (..), makeLockWithSkills)
import CPlugin.Types.Name (ItemName, itemName, nameText)
import CPlugin.Types.Path (AbsolutePath, RelativePath, absoluteText)
import CPlugin.Types.Plugin (Plugin (..), makePluginWithOrigin, samePluginSource)
import CPlugin.Types.PluginManifest (manifestName)
import CPlugin.Types.Selection (Selection (..), SelectionRequest (..), traverseSelectionRequest)
import CPlugin.Types.Skill (resolvedSkillName)
import Control.Exception (IOException, catch)
import Control.Monad (unless, when)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

run :: Interaction -> RuntimePaths -> Bool -> FilePath -> SelectionRequest String -> Bool -> IO ()
run interaction paths global raw request force = do
    (lockPath, current) <- loadCurrent paths global
    (source, root) <- resolveLocalSource invalid lockPath raw
    runResolved interaction lockPath current source root Nothing request force

runResolved :: Interaction -> FilePath -> Lock -> RelativePath -> AbsolutePath -> Maybe GitHubOrigin -> SelectionRequest String -> Bool -> IO ()
runResolved interaction lockPath current source root origin request force = do
    (manifest, skills, _) <- loadPlugin root `catch` \e -> failAs invalid (show (e :: IOException))
    identity <- validateAs invalid (makePluginWithOrigin (manifestName manifest) source [] origin)
    requested <- traverseSelectionRequest (validateAs invalid . itemName) request
    let name = manifestName manifest
        choices = map resolvedSkillName skills
        previous = case Map.lookup name (plugins current) of
            Just plugin | samePluginSource plugin identity -> enabledSkills plugin
            _ -> Set.empty
    selection <- select interaction "Choose the replacement enabled skill set. Markers show current state. Blank/q keeps unchanged, none disables all. Use --all / --none / --skill for explicit selection." (skillLabel previous) choices requested
    case selection of
        Cancelled -> putStrLn "Cancelled; no changes."
        Selected selected -> do
            unless (selected `Set.isSubsetOf` Set.fromList choices) (failAs invalid "unknown or invalid plugin skill")
            plugin <- validateAs invalid (makePluginWithOrigin name source (Set.toAscList selected) origin)
            updatePlugin lockPath current root plugin force

invalid :: String
invalid = "totto2727/c-plugin.PluginAddError.InvalidInput"

skillLabel :: Set.Set ItemName -> ItemName -> String
skillLabel previous skill = nameText skill ++ if Set.member skill previous then " [enabled]" else " [disabled]"

updatePlugin :: FilePath -> Lock -> AbsolutePath -> Plugin -> Bool -> IO ()
updatePlugin lockPath current root plugin force = do
    let existing = Map.lookup (pluginName plugin) (plugins current)
    case existing of
        Just old -> unless (samePluginSource old plugin) (failAs invalid "plugin name already registered from a different source")
        Nothing -> pure ()
    when
        (any (\old -> samePluginSource old plugin && pluginName old /= pluginName plugin) (Map.elems (plugins current)))
        (failAs invalid "plugin source already registered with a different name")
    candidate <- validateAs invalid (makeLockWithSkills (Set.toAscList (targets current)) (Map.elems (Map.insert (pluginName plugin) plugin (plugins current))) (Map.elems (standaloneSkills current)))
    if candidate == current
        then putStrLn ("No skill changes for " ++ lockPath)
        else do
            result <- persistSync lockPath candidate force
            reportCompletion result
            putStrLn ("Added " ++ absoluteText root ++ " to " ++ lockPath ++ ": " ++ renderSyncResult result)
