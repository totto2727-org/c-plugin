module CPlugin.Commands (Command (..), runCommand, runCommandWith, runCommandWithGit) where

import qualified CPlugin.Commands.Init as Init
import qualified CPlugin.Commands.List as List
import qualified CPlugin.Commands.PluginAdd as PluginAdd
import qualified CPlugin.Commands.PluginAddGitHub as PluginAddGitHub
import qualified CPlugin.Commands.PluginList as PluginList
import qualified CPlugin.Commands.PluginRemove as PluginRemove
import qualified CPlugin.Commands.PluginSkillDisable as PluginSkillDisable
import qualified CPlugin.Commands.PluginSkillEnable as PluginSkillEnable
import qualified CPlugin.Commands.SkillAdd as SkillAdd
import qualified CPlugin.Commands.SkillAddGitHub as SkillAddGitHub
import qualified CPlugin.Commands.SkillList as SkillList
import qualified CPlugin.Commands.SkillRemove as SkillRemove
import qualified CPlugin.Commands.Sync as Sync
import qualified CPlugin.Commands.TargetAdd as TargetAdd
import qualified CPlugin.Commands.TargetRemove as TargetRemove
import qualified CPlugin.Commands.Update as Update
import CPlugin.Interaction (Interaction (..))
import CPlugin.Paths (runtimePaths)
import CPlugin.Source.GitHub (GitRunner, runGit)
import CPlugin.Types.Selection (SelectionRequest)

-- All raw strings belong to this CLI adapter. Validated domain values cross
-- into lock policy, plugin discovery, and reconciliation exactly once.
data Command
    = Init Bool
    | Sync Bool Bool
    | Update Bool Bool
    | List Bool
    | PluginList Bool
    | SkillList Bool
    | PluginAdd Bool FilePath (SelectionRequest String) Bool
    | SkillAdd Bool FilePath Bool
    | PluginAddGitHub Bool String (Maybe String) (Maybe FilePath) (SelectionRequest String) Bool
    | SkillAddGitHub Bool String (Maybe String) (Maybe FilePath) Bool
    | PluginRemove Bool [String]
    | PluginSkillEnable Bool (Maybe String) (SelectionRequest String)
    | PluginSkillDisable Bool (Maybe String) (SelectionRequest String)
    | SkillRemove Bool [String]
    | TargetAdd Bool FilePath
    | TargetRemove Bool [FilePath]
    deriving (Eq, Show)

runCommand :: Command -> IO ()
runCommand = runCommandWith NonInteractive

runCommandWith :: Interaction -> Command -> IO ()
runCommandWith = runCommandWithGit runGit

runCommandWithGit :: GitRunner -> Interaction -> Command -> IO ()
runCommandWithGit git interaction command = do
    paths <- runtimePaths
    case command of
        Init global -> Init.run paths global
        Sync global recursive -> Sync.run paths global recursive
        Update global recursive -> Update.runWithGit git paths global recursive
        List global -> List.run paths global
        PluginList global -> PluginList.run paths global
        SkillList global -> SkillList.run paths global
        PluginAdd global raw selected force -> PluginAdd.run interaction paths global raw selected force
        SkillAdd global raw force -> SkillAdd.run paths global raw force
        PluginAddGitHub global raw requested subpath selected force -> PluginAddGitHub.runWithGit git interaction paths global raw requested subpath selected force
        SkillAddGitHub global raw requested subpath force -> SkillAddGitHub.runWithGit git paths global raw requested subpath force
        PluginRemove global values -> PluginRemove.run interaction paths global values
        PluginSkillEnable global name selected -> PluginSkillEnable.run interaction paths global name selected
        PluginSkillDisable global name selected -> PluginSkillDisable.run interaction paths global name selected
        SkillRemove global values -> SkillRemove.run interaction paths global values
        TargetAdd global raw -> TargetAdd.run paths global raw
        TargetRemove global values -> TargetRemove.run interaction paths global values
