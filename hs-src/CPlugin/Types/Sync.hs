module CPlugin.Types.Sync (Notice (..), SyncResult (..), SyncCompletion (..)) where

import CPlugin.Types.Name (ItemName)
import CPlugin.Types.Path (AbsolutePath)
import qualified Data.Map.Strict as Map

data Notice
    = PreviousMissing
    | PreviousCorrupt String
    | UnmanagedPreserved AbsolutePath
    | ReplacedPreserved AbsolutePath
    | BrokenPreserved AbsolutePath
    | OperationFailed FilePath String
    | CheckpointFailed FilePath String
    | PluginWarning FilePath String
    deriving (Eq, Show)
data SyncCompletion = Finished | Interrupted deriving (Eq, Show)
data SyncResult = SyncResult
    {syncNotices :: [Notice], unavailablePlugins :: Map.Map ItemName String, syncCompletion :: SyncCompletion}
    deriving (Eq, Show)
