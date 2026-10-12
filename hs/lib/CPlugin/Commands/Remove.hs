module CPlugin.Commands.Remove (run) where

import CPlugin.Commands.Common (loadCurrent, persistSync, reportCompletion, validateAs)
import CPlugin.Interaction (Interaction, select)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.Lock (Lock (..))
import CPlugin.Types.Name (nameText, pluginNameValue)
import CPlugin.Types.Plugin (Plugin (..))
import CPlugin.Types.Selection (RemovalChoice (..), RemovalScope (..), Selection (..), SelectionRequest (..), parseRemovalSkill, removalLabel)
import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

run :: RemovalScope -> Interaction -> RuntimePaths -> Bool -> [String] -> IO ()
run scope interaction paths global values = do
    let invalid = "totto2727/c-plugin.RemoveError.InvalidInput"
        parseSelector = case scope of
            PluginRemoval -> fmap RemovePlugin . pluginNameValue
            SkillRemoval -> parseRemovalSkill
    explicit <- mapM (validateAs invalid . parseSelector) values
    (lockPath, current) <- loadCurrent paths global
    let choices = removalChoices scope current
        request = if null values then PromptSelection else SelectItems explicit
        guidance = case scope of
            PluginRemoval -> "Choose installed plugins to remove, or use --plugin for explicit selection."
            SkillRemoval -> "Choose installed skills to remove, or use --skill for explicit selection."
        unchanged = case scope of
            PluginRemoval -> "No plugin changes for "
            SkillRemoval -> "No skill changes for "
    selection <- select interaction guidance removalLabel choices request
    case selection of
        Cancelled -> putStrLn "Cancelled; no changes."
        Selected selected
            | Set.null selected -> putStrLn "No selection; no changes."
            | not (selected `Set.isSubsetOf` Set.fromList choices) -> putStrLn (unchanged ++ lockPath)
            | otherwise -> removeSelected lockPath current selected

removalChoices :: RemovalScope -> Lock -> [RemovalChoice]
removalChoices PluginRemoval current = map (RemovePlugin . pluginName) (Map.elems (plugins current))
removalChoices SkillRemoval current =
    [RemoveSkill (pluginName plugin) skill | plugin <- Map.elems (plugins current), skill <- Set.toAscList (enabledSkills plugin)]
        ++ map RemoveStandalone (Map.keys (standaloneSkills current))

removeSelected :: FilePath -> Lock -> Set.Set RemovalChoice -> IO ()
removeSelected lockPath current selected = do
    let removedStandalone = Set.fromList [name | RemoveStandalone name <- Set.toList selected]
        candidate = current{plugins = Map.mapMaybe (rebuild selected) (plugins current), standaloneSkills = Map.withoutKeys (standaloneSkills current) removedStandalone}
    result <- persistSync lockPath candidate False
    reportCompletion result
    putStrLn (removalAction selected ++ " from " ++ lockPath ++ ": " ++ renderSyncResult result)

removalAction :: Set.Set RemovalChoice -> String
removalAction selected
    | null names = "Removed skills " ++ intercalate ", " skills
    | null skills = "Removed plugins " ++ intercalate ", " names
    | otherwise = "Removed plugins " ++ intercalate ", " names ++ " and skills " ++ intercalate ", " skills
  where
    names = [nameText name | RemovePlugin name <- Set.toAscList selected]
    skills = [nameText name ++ "/" ++ nameText skill | RemoveSkill name skill <- Set.toAscList selected] ++ [nameText name | RemoveStandalone name <- Set.toAscList selected]

rebuild :: Set.Set RemovalChoice -> Plugin -> Maybe Plugin
rebuild selected plugin
    | Set.member (RemovePlugin (pluginName plugin)) selected = Nothing
    | otherwise =
        let removed = Set.fromList [skill | RemoveSkill name skill <- Set.toList selected, name == pluginName plugin]
            remaining = enabledSkills plugin Set.\\ removed
         in Just plugin{enabledSkills = remaining}
