module CPlugin.Commands.SkillAdd (run) where

import CPlugin.Commands.Common (failAs, loadCurrent, persistSync, reportCompletion, resolveLocalSource, validateAs)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Plugin (loadStandaloneSkill)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.InstalledSkill (InstalledSkill (..), makeInstalledSkill)
import CPlugin.Types.Lock (Lock (..), makeLockWithSkills)
import CPlugin.Types.Path (absoluteText)
import CPlugin.Types.Skill (resolvedSkillName)
import Control.Exception (IOException, catch)
import Control.Monad (unless, when)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

run :: RuntimePaths -> Bool -> FilePath -> Bool -> IO ()
run paths global raw force = do
    let invalid = "totto2727/c-plugin.SkillAddError.InvalidInput"
    (lockPath, current) <- loadCurrent paths global
    (source, root) <- resolveLocalSource invalid lockPath raw
    resolved <- loadStandaloneSkill root `catch` \e -> failAs invalid (show (e :: IOException))
    skill <- validateAs invalid (makeInstalledSkill (resolvedSkillName resolved) source)
    case Map.lookup (installedSkillName skill) (standaloneSkills current) of
        Just old -> unless (installedSkillSource old == source) (failAs invalid "standalone skill name already registered from a different source")
        Nothing -> pure ()
    when
        (any (\old -> installedSkillSource old == source && installedSkillName old /= installedSkillName skill) (Map.elems (standaloneSkills current)))
        (failAs invalid "standalone skill source already registered with a different name")
    candidate <- validateAs invalid (makeLockWithSkills (Set.toAscList (targets current)) (Map.elems (plugins current)) (Map.elems (Map.insert (installedSkillName skill) skill (standaloneSkills current))))
    if candidate == current
        then putStrLn ("No skill changes for " ++ lockPath)
        else do
            result <- persistSync lockPath candidate force
            reportCompletion result
            putStrLn ("Added skill " ++ absoluteText root ++ " to " ++ lockPath ++ ": " ++ renderSyncResult result)
