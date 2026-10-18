module CPlugin.Commands.SkillAdd (run, runResolved) where

import CPlugin.Commands.Common (failAs, loadCurrent, persistSync, reportCompletion, resolveLocalSource, validateAs)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Plugin (loadStandaloneSkill)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.GitHub (GitHubOrigin)
import CPlugin.Types.InstalledSkill (InstalledSkill (..), makeInstalledSkillWithOrigin, sameInstalledSkillSource)
import CPlugin.Types.Lock (Lock (..), makeLockWithSkills)
import CPlugin.Types.Ownership (OwnershipSource (..))
import CPlugin.Types.Path (AbsolutePath, RelativePath, absoluteText)
import CPlugin.Types.Skill (resolvedSkillName)
import Control.Exception (IOException, catch)
import Control.Monad (unless, when)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

run :: RuntimePaths -> Bool -> FilePath -> Bool -> IO ()
run paths global raw force = do
    (lockPath, current) <- loadCurrent paths global
    (source, root) <- resolveLocalSource invalid lockPath raw
    runResolved lockPath current source root Nothing force

invalid :: String
invalid = "totto2727/c-plugin.SkillAddError.InvalidInput"

runResolved :: FilePath -> Lock -> RelativePath -> AbsolutePath -> Maybe GitHubOrigin -> Bool -> IO ()
runResolved lockPath current source root origin force = do
    resolved <- loadStandaloneSkill root `catch` \e -> failAs invalid (show (e :: IOException))
    skill <- validateAs invalid (makeInstalledSkillWithOrigin (resolvedSkillName resolved) source origin)
    case Map.lookup (installedSkillName skill) (standaloneSkills current) of
        Just old -> unless (sameInstalledSkillSource old skill) (failAs invalid "standalone skill name already registered from a different source")
        Nothing -> pure ()
    when
        (any (\old -> sameInstalledSkillSource old skill && installedSkillName old /= installedSkillName skill) (Map.elems (standaloneSkills current)))
        (failAs invalid "standalone skill source already registered with a different name")
    candidate <- validateAs invalid (makeLockWithSkills (Set.toAscList (targets current)) (Map.elems (plugins current)) (Map.elems (Map.insert (installedSkillName skill) skill (standaloneSkills current))))
    if candidate == current
        then putStrLn ("No skill changes for " ++ lockPath)
        else do
            let forcedSources =
                    if force
                        then Set.singleton (StandaloneSource (installedSkillSource skill) (installedSkillName skill))
                        else Set.empty
            result <- persistSync lockPath candidate forcedSources
            reportCompletion result
            putStrLn ("Added skill " ++ absoluteText root ++ " to " ++ lockPath ++ ": " ++ renderSyncResult result)
