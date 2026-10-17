module CPlugin.Commands.PluginSkills (SkillAction (..), run) where

import CPlugin.Commands.Common (failAs, loadCurrent, persistSync, reportCompletion, resolveLocalSource, validateAs)
import CPlugin.Interaction (Interaction (..), select)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Plugin (loadPlugin)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Source.GitHub (verifyGitHub)
import CPlugin.Types.GitHub (githubSource)
import CPlugin.Types.Lock (Lock (..), makeLockWithSkills)
import CPlugin.Types.Name (ItemName, itemName, nameText, pluginNameValue)
import CPlugin.Types.Path (AbsolutePath, relativeText)
import CPlugin.Types.Plugin (Plugin (..), makePluginWithOrigin)
import CPlugin.Types.PluginManifest (manifestName)
import CPlugin.Types.Selection (Selection (..), SelectionRequest (..), traverseSelectionRequest, validateSelectionItems)
import CPlugin.Types.Skill (resolvedSkillName)
import Control.Exception (IOException, catch)
import Control.Monad (unless, when)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.FilePath (takeDirectory)
import System.IO (hPutStrLn)

-- This command policy is not persisted. Both actions select from the validated
-- registered source, including for disable: missing sources never fall back to
-- the enabled names in the lock. SelectAll means all available source skills.
data SkillAction = EnableSkills | DisableSkills

run :: SkillAction -> Interaction -> RuntimePaths -> Bool -> Maybe String -> SelectionRequest String -> IO ()
run action interaction paths global rawName request = do
    let invalid = errorPrefix action
    requested <- validateRequest invalid request
    (lockPath, current) <- loadCurrent paths global
    chosen <- choosePlugin invalid interaction current rawName
    case chosen of
        Nothing -> putStrLn "Cancelled; no changes."
        Just plugin -> selectSkills action invalid interaction lockPath current plugin requested

choosePlugin :: String -> Interaction -> Lock -> Maybe String -> IO (Maybe Plugin)
choosePlugin invalid _ current (Just rawName) = do
    name <- validateAs invalid (pluginNameValue rawName)
    Just <$> lookupPlugin invalid current name
choosePlugin invalid NonInteractive _ Nothing =
    failAs invalid "Plugin selection required in non-interactive mode; provide PLUGIN."
choosePlugin invalid interaction@(Interactive _ output) current Nothing = do
    when (Map.null (plugins current)) (failAs invalid "no registered plugins")
    selected <- select interaction "Choose exactly one registered plugin. Blank/q keeps unchanged." nameText (Map.keys (plugins current)) PromptSelection
    case selected of
        Cancelled -> pure Nothing
        Selected names -> case Set.toAscList names of
            [] -> pure Nothing
            [name] -> Just <$> lookupPlugin invalid current name
            _ -> do
                hPutStrLn output "Invalid selection: choose exactly one registered plugin."
                choosePlugin invalid interaction current Nothing

lookupPlugin :: String -> Lock -> ItemName -> IO Plugin
lookupPlugin invalid current name =
    maybe (failAs invalid "unknown registered plugin") pure (Map.lookup name (plugins current))

selectSkills :: SkillAction -> String -> Interaction -> FilePath -> Lock -> Plugin -> SelectionRequest ItemName -> IO ()
selectSkills action invalid interaction lockPath current plugin requested = do
    choices <- availableSkills invalid lockPath plugin
    selection <- select interaction (guidance action) (skillLabel (enabledSkills plugin)) choices requested
    case selection of
        Cancelled -> putStrLn "Cancelled; no changes."
        Selected selected -> do
            unless (selected `Set.isSubsetOf` Set.fromList choices) (failAs invalid "unknown or invalid plugin skill")
            updateSkills action invalid lockPath current plugin selected

validateRequest :: String -> SelectionRequest String -> IO (SelectionRequest ItemName)
validateRequest invalid request = do
    case request of
        SelectNone -> failAs invalid "plugin skill enable/disable does not accept --none; use --skill or --all"
        SelectItems items -> do
            names <- mapM (validateAs invalid . itemName) items
            _ <- validateAs invalid (validateSelectionItems names)
            pure (SelectItems names)
        _ -> traverseSelectionRequest (validateAs invalid . itemName) request

availableSkills :: String -> FilePath -> Plugin -> IO [ItemName]
availableSkills invalid lockPath plugin =
    load `catch` \e -> failAs invalid (show (e :: IOException))
  where
    load = do
        root <- registeredRoot invalid lockPath plugin
        (manifest, skills, _) <- loadPlugin root
        unless (manifestName manifest == pluginName plugin) (failAs invalid "plugin name differs from lock")
        pure (map resolvedSkillName skills)

registeredRoot :: String -> FilePath -> Plugin -> IO AbsolutePath
registeredRoot invalid lockPath plugin = case pluginOrigin plugin of
    Nothing -> snd <$> resolveLocalSource invalid lockPath ("./" ++ relativeText (pluginSource plugin))
    Just origin -> do
        unless (pluginSource plugin == githubSource origin) (failAs invalid "source path differs from GitHub provenance")
        verifyGitHub (takeDirectory lockPath) origin

updateSkills :: SkillAction -> String -> FilePath -> Lock -> Plugin -> Set.Set ItemName -> IO ()
updateSkills action invalid lockPath current plugin selected = do
    let enabled = case action of
            EnableSkills -> Set.union (enabledSkills plugin) selected
            DisableSkills -> Set.difference (enabledSkills plugin) selected
    validateAs invalid (validateNewSkillNames current plugin enabled)
    changed <- validateAs invalid (makePluginWithOrigin (pluginName plugin) (pluginSource plugin) (Set.toAscList enabled) (pluginOrigin plugin))
    candidate <- validateAs invalid (makeLockWithSkills (Set.toAscList (targets current)) (Map.elems (Map.insert (pluginName plugin) changed (plugins current))) (Map.elems (standaloneSkills current)))
    if candidate == current
        then putStrLn ("No skill changes for " ++ lockPath)
        else do
            result <- persistSync lockPath candidate Set.empty
            reportCompletion result
            putStrLn (actionLabel action ++ " skills for " ++ nameText (pluginName plugin) ++ " in " ++ lockPath ++ ": " ++ renderSyncResult result)

-- Existing legacy collisions retain their reconciliation semantics. Only new
-- enabled names can introduce a conflict, so disable and no-ops remain valid.
validateNewSkillNames :: Lock -> Plugin -> Set.Set ItemName -> Either String ()
validateNewSkillNames current plugin enabled = do
    let newlyEnabled = Set.difference enabled (enabledSkills plugin)
        otherEnabled = Set.unions (map enabledSkills (Map.elems (Map.delete (pluginName plugin) (plugins current))))
        conflicts = Set.intersection newlyEnabled otherEnabled
    unless (Set.null conflicts) (Left ("plugin skills already enabled by another registered plugin: " ++ unwords (map nameText (Set.toAscList conflicts))))

skillLabel :: Set.Set ItemName -> ItemName -> String
skillLabel enabled skill = nameText skill ++ if Set.member skill enabled then " [enabled]" else " [disabled]"

guidance :: SkillAction -> String
guidance action = "Choose plugin skills to " ++ actionVerb action ++ ". Markers show current state. Blank/q keeps unchanged. Use --all or --skill for explicit selection."

actionVerb :: SkillAction -> String
actionVerb EnableSkills = "enable"
actionVerb DisableSkills = "disable"

actionLabel :: SkillAction -> String
actionLabel EnableSkills = "Enabled"
actionLabel DisableSkills = "Disabled"

errorPrefix :: SkillAction -> String
errorPrefix EnableSkills = "totto2727/c-plugin.PluginSkillEnableError.InvalidInput"
errorPrefix DisableSkills = "totto2727/c-plugin.PluginSkillDisableError.InvalidInput"
