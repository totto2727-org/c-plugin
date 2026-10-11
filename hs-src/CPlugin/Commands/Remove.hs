module CPlugin.Commands.Remove (run) where

import CPlugin.Commands.Common (loadCurrent, persistSync, reportCompletion, validateAs)
import CPlugin.Interaction (Interaction, select)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.Lock (Lock (..))
import CPlugin.Types.Name (nameText, pluginNameValue)
import CPlugin.Types.Plugin (Plugin (..))
import CPlugin.Types.Selection (RemovalChoice (..), Selection (..), SelectionRequest (..), parseRemovalSkill, removalLabel)
import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

run :: Interaction -> RuntimePaths -> Bool -> [String] -> [String] -> IO ()
run interaction paths global pluginValues skillValues = do
    let invalid = "totto2727/c-plugin.RemoveError.InvalidInput"
    selectedPlugins <- mapM (validateAs invalid . fmap RemovePlugin . pluginNameValue) pluginValues
    selectedSkills <- mapM (validateAs invalid . parseRemovalSkill) skillValues
    (lockPath, current) <- loadCurrent paths global
    let choices = concatMap pluginChoices (Map.elems (plugins current)) ++ map RemoveStandalone (Map.keys (standaloneSkills current))
        request = if null pluginValues && null skillValues then PromptSelection else SelectItems (selectedPlugins ++ selectedSkills)
    selection <- select interaction "Choose installed plugins or skills to remove, or use --plugin / --skill for explicit selection." removalLabel choices request
    case selection of
        Cancelled -> putStrLn "Cancelled; no changes."
        Selected selected
            | Set.null selected -> putStrLn "No selection; no changes."
            | not (selected `Set.isSubsetOf` Set.fromList choices) -> putStrLn ("No skill changes for " ++ lockPath)
            | otherwise -> removeSelected lockPath current selected

pluginChoices :: Plugin -> [RemovalChoice]
pluginChoices plugin = RemovePlugin (pluginName plugin) : [RemoveSkill (pluginName plugin) skill | skill <- Set.toAscList (enabledSkills plugin)]

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
         in if Set.null remaining && not (Set.null removed) then Nothing else Just plugin{enabledSkills = remaining}
