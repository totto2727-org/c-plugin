module CPlugin.Commands (Command (..), runCommand) where

import qualified CPlugin.Commands.AddLocal as AddLocal
import qualified CPlugin.Commands.Init as Init
import qualified CPlugin.Commands.Remove as Remove
import qualified CPlugin.Commands.Sync as Sync
import qualified CPlugin.Commands.TargetAdd as TargetAdd
import qualified CPlugin.Commands.TargetRemove as TargetRemove
import CPlugin.Paths (runtimePaths)

-- All raw strings belong to this CLI adapter. Validated domain values cross
-- into lock policy, plugin discovery, and reconciliation exactly once.
data Command
    = Init Bool
    | Sync Bool Bool
    | AddLocal Bool FilePath [String] Bool
    | Remove Bool [String] [String]
    | TargetAdd Bool FilePath
    | TargetRemove Bool [FilePath]
    deriving (Eq, Show)

runCommand :: Command -> IO ()
runCommand command = do
    paths <- runtimePaths
    case command of
        Init global -> Init.run paths global
        Sync global recursive -> Sync.run paths global recursive
        AddLocal global raw selected force -> AddLocal.run paths global raw selected force
        Remove global pluginValues skillValues -> Remove.run paths global pluginValues skillValues
        TargetAdd global raw -> TargetAdd.run paths global raw
        TargetRemove global values -> TargetRemove.run paths global values
