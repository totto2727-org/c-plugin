module CPlugin.Commands (Command (..), runCommand) where

import CPlugin.Codec
import CPlugin.Paths
import CPlugin.Plugin (loadPlugin)
import CPlugin.Reconcile
import CPlugin.Types
import Control.Exception (IOException, catch)
import Control.Monad (forM_, unless, when)
import Data.List (intercalate, isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.FilePath (splitDirectories, takeDirectory, (</>))

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
        Init global -> do
            let root = if global then homePath paths else cwdPath paths
                lockPath = absoluteText root </> "c-plugin-lock.json"
            createLock lockPath emptyLock
            putStrLn ("Created " ++ lockPath)
        Sync global recursive -> do
            lockPaths <- discoverLocks paths global recursive
            forM_ lockPaths $ \lockPath -> do
                lock <- readLock lockPath
                result <- syncLoadedLock lockPath lock False
                reportCompletion result
                putStrLn ("Synced " ++ lockPath ++ ": " ++ renderSyncResult result)
        AddLocal global raw selected force -> do
            let invalid = "totto2727/c-plugin.AddLocalError.InvalidInput"
            unless ("./" `isPrefixOf` raw) (failAs invalid "--local must begin with ./")
            source <- validateAs invalid (relativePath raw)
            (lockPath, current) <- loadCurrent paths global
            when (any ((== source) . pluginSource) (Map.elems (plugins current))) (failAs invalid "plugin source already added")
            root <- absoluteIO (takeDirectory lockPath </> relativeText source)
            (manifest, skills, _) <- loadPlugin root `catch` \e -> failAs invalid (show (e :: IOException))
            selections <- mapM (validateAs invalid . itemName) selected
            enabled <- if null selected then pure (map resolvedSkillName skills) else pure selections
            unless (all (\s -> any ((== s) . resolvedSkillName) skills) enabled) (failAs invalid "unknown or invalid plugin skill")
            plugin <- validateAs invalid (makePlugin (manifestName manifest) source enabled)
            candidate <- validateAs invalid (makeLock (Set.toAscList (targets current)) (Map.elems (plugins current) ++ [plugin]))
            result <- persistSync lockPath candidate force
            reportCompletion result
            putStrLn ("Added " ++ absoluteText root ++ " to " ++ lockPath ++ ": " ++ renderSyncResult result)
        Remove global pluginValues skillValues -> do
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
        TargetAdd global raw -> do
            target <- validateAs "totto2727/c-plugin.TargetAddError.InvalidInput" (relativePath raw)
            (lockPath, current) <- loadCurrent paths global
            if Set.member target (targets current)
                then putStrLn ("Target " ++ relativeText target ++ " already registered in " ++ lockPath)
                else do
                    let candidate = current{targets = Set.insert target (targets current)}
                    result <- persistSync lockPath candidate False
                    reportCompletion result
                    putStrLn ("Added target " ++ relativeText target ++ " to " ++ lockPath ++ ": " ++ renderSyncResult result)
        TargetRemove global values -> do
            selected <- mapM (validateAs "totto2727/c-plugin.TargetRemoveError.InvalidInput" . relativePath) values
            (lockPath, current) <- loadCurrent paths global
            if null selected || not (all (`Set.member` targets current) selected)
                then putStrLn ("No target changes for " ++ lockPath)
                else do
                    let candidate = current{targets = targets current Set.\\ Set.fromList selected}
                    result <- persistSync lockPath candidate False
                    reportCompletion result
                    putStrLn ("Removed targets " ++ intercalate ", " (map relativeText selected) ++ " from " ++ lockPath ++ ": " ++ renderSyncResult result)

loadCurrent :: RuntimePaths -> Bool -> IO (FilePath, Lock)
loadCurrent paths global = do
    discovered <- discoverLocks paths global False
    case discovered of
        [lockPath] -> do
            current <- readLock lockPath
            pure (lockPath, current)
        _ -> failAs "totto2727/c-plugin.LockDiscoveryError" "expected exactly one lock"

persistSync :: FilePath -> Lock -> Bool -> IO SyncResult
persistSync lockPath candidate force = do
    let base = takeDirectory lockPath
    roots <-
        mapM
            (absoluteIO . (base </>))
            (".agents" : ".agents/skills" : map relativeText (Set.toAscList (targets candidate)))
    mapM_ (validateManagedRoot base) roots
    writeLock lockPath candidate
    syncLoadedLock lockPath candidate force

reportCompletion :: SyncResult -> IO ()
reportCompletion result = do
    printWarnings result
    when
        (syncCompletion result == Interrupted)
        (failAs "totto2727/c-plugin.SyncError.CheckpointFailed" "reconciliation stopped at a durability or verification boundary")

parseSkillSelector :: String -> String -> IO (ItemName, ItemName)
parseSkillSelector invalid value = do
    path <- validateAs invalid (relativePath value)
    case splitDirectories (relativeText path) of
        [plugin, skill] -> (,) <$> validateAs invalid (pluginNameValue plugin) <*> validateAs invalid (itemName skill)
        _ -> failAs invalid "skill selection must be plugin/skill"

validateAs :: String -> Either String a -> IO a
validateAs prefix = either (failAs prefix) pure
failAs :: String -> String -> IO a
failAs prefix reason = ioError (userError (prefix ++ " " ++ reason))
