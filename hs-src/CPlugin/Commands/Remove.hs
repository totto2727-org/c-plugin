module CPlugin.Commands.Remove (run) where

import CPlugin.Commands.Common (failAs, loadCurrent, persistSync, reportCompletion, validateAs)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Reconcile (renderSyncResult)
import CPlugin.Types.Lock (Lock (..))
import CPlugin.Types.Name (ItemName, itemName, nameText, pluginNameValue)
import CPlugin.Types.Path (relativePath, relativeText)
import CPlugin.Types.Plugin (Plugin (..))
import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.FilePath (splitDirectories)

run :: RuntimePaths -> Bool -> [String] -> [String] -> IO ()
run paths global pluginValues skillValues = do
    let invalid = "totto2727/c-plugin.RemoveError.InvalidInput"
    selectedPlugins <- mapM (validateAs invalid . pluginNameValue) pluginValues
    selectedSkills <- mapM (parseSkillSelector invalid) skillValues
    (lockPath, current) <- loadCurrent paths global
    let validPlugin name = Map.member name (plugins current)
        validSkill (name, skill) = maybe False (Set.member skill . enabledSkills) (Map.lookup name (plugins current))
        unchanged =
            null selectedPlugins && null selectedSkills
                || not (all validPlugin selectedPlugins && all validSkill selectedSkills)
    if unchanged
        then putStrLn ("No skill changes for " ++ lockPath)
        else do
            let rebuild plugin
                    | pluginName plugin `elem` selectedPlugins = Nothing
                    | otherwise =
                        let removed = Set.fromList [skill | (name, skill) <- selectedSkills, name == pluginName plugin]
                            remaining = enabledSkills plugin Set.\\ removed
                         in if Set.null remaining && not (Set.null removed) then Nothing else Just plugin{enabledSkills = remaining}
                candidate = current{plugins = Map.mapMaybe rebuild (plugins current)}
            result <- persistSync lockPath candidate False
            reportCompletion result
            let names = intercalate ", " (map nameText selectedPlugins)
                skills = intercalate ", " [nameText name ++ "/" ++ nameText skill | (name, skill) <- selectedSkills]
                action
                    | null selectedPlugins = "Removed skills " ++ skills
                    | null selectedSkills = "Removed plugins " ++ names
                    | otherwise = "Removed plugins " ++ names ++ " and skills " ++ skills
            putStrLn (action ++ " from " ++ lockPath ++ ": " ++ renderSyncResult result)

parseSkillSelector :: String -> String -> IO (ItemName, ItemName)
parseSkillSelector invalid value = do
    path <- validateAs invalid (relativePath value)
    case splitDirectories (relativeText path) of
        [plugin, skill] -> (,) <$> validateAs invalid (pluginNameValue plugin) <*> validateAs invalid (itemName skill)
        _ -> failAs invalid "skill selection must be plugin/skill"
