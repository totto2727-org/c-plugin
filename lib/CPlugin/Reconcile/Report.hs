{-# LANGUAGE LambdaCase #-}

module CPlugin.Reconcile.Report (renderSyncResult, printWarnings) where

import CPlugin.Types.Name (nameText)
import CPlugin.Types.Sync
import Control.Monad (forM_)
import qualified Data.Map.Strict as Map

renderSyncResult :: SyncResult -> String
renderSyncResult result =
    status
        ++ " ("
        ++ show (length (syncNotices result))
        ++ " notices, "
        ++ show (Map.size (unavailablePlugins result))
        ++ " unavailable plugins"
        ++ skillStatus
        ++ ")"
  where
    status = if null (syncNotices result) && Map.null (unavailablePlugins result) && Map.null (unavailableSkills result) then "complete" else "partial"
    skillStatus
        | Map.null (unavailableSkills result) = ""
        | otherwise = ", " ++ show (Map.size (unavailableSkills result)) ++ " unavailable skills"

printWarnings :: SyncResult -> IO ()
printWarnings result = do
    forM_ (syncNotices result) $ \case
        PluginWarning _ reason -> putStrLn ("Warning: " ++ reason)
        OperationFailed path reason -> putStrLn ("Warning: " ++ path ++ ": " ++ reason)
        CheckpointFailed path reason -> putStrLn ("Warning: checkpoint failed for " ++ path ++ ": " ++ reason)
        PreviousCorrupt reason -> putStrLn ("Warning: corrupt ownership state: " ++ reason)
        _ -> pure ()
    forM_ (Map.toAscList (unavailablePlugins result)) $ \(name, reason) ->
        putStrLn ("Warning: unavailable plugin " ++ nameText name ++ ": " ++ reason)
    forM_ (Map.toAscList (unavailableSkills result)) $ \(name, reason) ->
        putStrLn ("Warning: unavailable skill " ++ nameText name ++ ": " ++ reason)
