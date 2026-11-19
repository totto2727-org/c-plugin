module CPlugin.Commands.PluginSkillDisable (run) where

import qualified CPlugin.Commands.PluginSkills as PluginSkills
import CPlugin.Interaction (Interaction)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Types.Selection (SelectionRequest)

run :: Interaction -> RuntimePaths -> Bool -> Maybe String -> SelectionRequest String -> IO ()
run = PluginSkills.run PluginSkills.DisableSkills
