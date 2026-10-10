module CPlugin.Commands.AddLocal (run) where

import CPlugin.Commands.Common (failAs, loadCurrent, persistSync, reportCompletion, validateAs)
import CPlugin.Paths (RuntimePaths, absoluteIO)
import CPlugin.Plugin (loadPlugin)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.Lock (Lock (..), makeLock)
import CPlugin.Types.Name (itemName)
import CPlugin.Types.Path (absoluteText, relativePath, relativeText)
import CPlugin.Types.Plugin (makePlugin, pluginSource)
import CPlugin.Types.PluginManifest (manifestName)
import CPlugin.Types.Skill (resolvedSkillName)
import Control.Exception (IOException, catch)
import Control.Monad (unless, when)
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.FilePath (takeDirectory, (</>))

run :: RuntimePaths -> Bool -> FilePath -> [String] -> Bool -> IO ()
run paths global raw selected force = do
    let invalid = "totto2727/c-plugin.AddLocalError.InvalidInput"
    unless ("./" `isPrefixOf` raw) (failAs invalid "--local must begin with ./")
    source <- validateAs invalid (relativePath raw)
    (lockPath, current) <- loadCurrent paths global
    when (any ((== source) . pluginSource) (Map.elems (plugins current))) (failAs invalid "plugin source already added")
    root <- absoluteIO (takeDirectory lockPath </> relativeText source)
    (manifest, skills, _) <- loadPlugin root `catch` \e -> failAs invalid (show (e :: IOException))
    selections <- mapM (validateAs invalid . itemName) selected
    enabled <- if null selected then pure (map resolvedSkillName skills) else pure selections
    unless (all (\s -> any ((== s) . resolvedSkillName) skills) enabled) (failAs invalid "unknown or invalid plugin skill")
    plugin <- validateAs invalid (makePlugin (manifestName manifest) source enabled)
    candidate <- validateAs invalid (makeLock (Set.toAscList (targets current)) (Map.elems (plugins current) ++ [plugin]))
    result <- persistSync lockPath candidate force
    reportCompletion result
    putStrLn ("Added " ++ absoluteText root ++ " to " ++ lockPath ++ ": " ++ renderSyncResult result)
