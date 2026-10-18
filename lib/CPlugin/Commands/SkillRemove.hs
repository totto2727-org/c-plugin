module CPlugin.Commands.SkillRemove (run) where

import qualified CPlugin.Commands.Remove as Remove
import CPlugin.Interaction (Interaction)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Types.Selection (RemovalScope (..))

run :: Interaction -> RuntimePaths -> Bool -> [String] -> IO ()
run = Remove.run SkillRemoval
