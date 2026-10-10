{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE LambdaCase #-}

module CPlugin.Reconcile (syncLoadedLock, renderSyncResult, printWarnings) where

import CPlugin.Codec (readOwnership, writeOwnership)
import CPlugin.Paths
import CPlugin.Plugin (loadPlugin)
import CPlugin.Types
import Control.Exception (Exception, IOException, bracket, catch, throwIO, try)
import Control.Monad (forM, forM_, unless, when)
import Data.IORef
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import qualified Data.Set as Set
import Data.Typeable (Typeable)
import System.FilePath (takeDirectory, (</>))
import qualified System.IO.Error
import System.Posix.Files (createSymbolicLink, removeLink)
import System.Posix.IO (OpenMode (ReadOnly), closeFd, defaultFileFlags, openFd)
import System.Posix.Unistd (fileSynchronise)

-- A failed checkpoint stops further mutation, leaving the last durable state.
data HardStop = HardStop deriving (Show, Typeable)
instance Exception HardStop

syncLoadedLock :: FilePath -> Lock -> Bool -> IO SyncResult
syncLoadedLock lockPath lock force = do
    let base = takeDirectory lockPath
        statePath = base </> ".agents/c-plugin-state.json"
    stateRoot <- absoluteIO (base </> ".agents")
    validateManagedRoot base stateRoot
    roots <-
        Set.fromList
            <$> mapM
                (absoluteIO . (base </>))
                (".agents/skills" : map relativeText (Set.toAscList (targets lock)))
    mapM_ (validateManagedRoot base) roots
    resolutions <- forM (Map.elems (plugins lock)) $ \plugin -> do
        root <- absoluteIO (base </> relativeText (pluginSource plugin))
        result <-
            try
                ( do
                    (manifest, skills, warnings) <- loadPlugin root
                    unless (manifestName manifest == pluginName plugin) (ioError (userError "plugin name differs from lock"))
                    pure (skills, warnings)
                ) ::
                IO (Either IOException ([ResolvedSkill], [String]))
        pure (plugin, root, result)
    let unavailable = Map.fromList [(pluginName p, show e) | (p, _, Left e) <- resolutions]
        warnings = [PluginWarning (absoluteText root) w | (_, root, Right (_, ws)) <- resolutions, w <- ws]
    entries <- fmap concat $ forM resolutions $ \(plugin, _, result) -> case result of
        Left _ -> pure []
        Right (skills, _) -> fmap concat $ forM skills $ \skill ->
            if Set.member (resolvedSkillName skill) (enabledSkills plugin)
                then forM (Set.toAscList roots) $ \root -> do
                    link <- absoluteIO (absoluteText root </> nameText (resolvedSkillName skill))
                    let source = OwnershipSource (pluginSource plugin) (pluginName plugin) (resolvedSkillName skill)
                    either
                        (ioError . userError)
                        pure
                        ( makeEntry
                            link
                            (relativeLinkTarget (absoluteText root) (absoluteText (skillPath skill)))
                            (skillPath skill)
                            root
                            source
                        )
                else pure []
    -- Sorted plugin traversal makes the lexically greatest plugin the collision
    -- winner, independent of filesystem enumeration order.
    let desired = Map.fromList [(entryLink e, e) | e <- entries]
    previous <- readOwnership statePath >>= validatePrevious base
    let initial = case previous of Trusted (OwnershipState es) -> es; _ -> Map.empty
        initialNotices =
            warnings ++ case previous of
                Trusted _ -> []
                Missing -> [PreviousMissing]
                Corrupt reason -> [PreviousCorrupt reason]
    stateRef <- newIORef initial
    noticesRef <- newIORef initialNotices
    let notice n = modifyIORef' noticesRef (++ [n])
        checkpoint next = do
            result <- try (validateManagedRoot base stateRoot >> writeOwnership statePath (OwnershipState next)) :: IO (Either IOException ())
            case result of
                Left e -> notice (CheckpointFailed statePath (show e)) >> throwIO HardStop
                Right () -> writeIORef stateRef next
        durableMutationRoot root =
            syncDirectory root `catch` \e ->
                notice (CheckpointFailed root (show (e :: IOException))) >> throwIO HardStop
        forget link = readIORef stateRef >>= checkpoint . Map.delete link
        record entry = readIORef stateRef >>= checkpoint . Map.insert (entryLink entry) entry
        safely path action = action `catch` \e -> notice (OperationFailed path (show (e :: IOException)))
        removeOwned entry = do
            matches <- matchingEntry base entry
            if matches
                then do
                    -- Recheck literal identity and containment immediately before unlink.
                    rechecked <- matchingEntry base entry
                    if rechecked
                        then do
                            removeLink (absoluteText (entryLink entry))
                            durableMutationRoot (absoluteText (managedRoot entry))
                            pure True
                        else pure False
                else pure False
        create entry = do
            createSymbolicLink (symlinkTarget entry) (absoluteText (entryLink entry))
            ( do
                    durableMutationRoot (absoluteText (managedRoot entry))
                    verified <-
                        matchingEntry base entry `catch` \e -> do
                            notice (OperationFailed (absoluteText (entryLink entry)) (show (e :: IOException)))
                            throwIO HardStop
                    unless verified (notice (OperationFailed (absoluteText (entryLink entry)) "created link could not be verified") >> throwIO HardStop)
                    record entry
                )
                `catch` \HardStop -> do
                    -- A failed ownership checkpoint must not leave an adopted path. Only
                    -- roll back the exact verified link created by this mutation.
                    safely (absoluteText (entryLink entry)) $ do
                        matches <- matchingEntry base entry
                        when matches $ do
                            removeLink (absoluteText (entryLink entry))
                            durableMutationRoot (absoluteText (managedRoot entry))
                    throwIO HardStop
        desiredStep entry = safely (absoluteText (entryLink entry)) $ do
            ensureManagedRoot base (managedRoot entry)
            contained <- containedEntry base entry
            unless contained (ioError (userError "link parent escapes managed root"))
            kind <- pathKind (absoluteText (entryLink entry))
            state <- readIORef stateRef
            let owned = Map.lookup (entryLink entry) state
            if force && kind `elem` [Just RegularFile, Just SymbolicLink]
                then do
                    when (Map.member (entryLink entry) state) (forget (entryLink entry))
                    -- Force replaces only this direct contained file or symlink.
                    stillContained <- containedEntry base entry
                    currentKind <- pathKind (absoluteText (entryLink entry))
                    unless (stillContained && currentKind == kind) (ioError (userError "force eligibility changed"))
                    removeLink (absoluteText (entryLink entry))
                    durableMutationRoot (absoluteText (managedRoot entry))
                    readIORef stateRef >>= checkpoint
                    create entry
                else case (owned, kind) of
                    (_, Nothing) -> do
                        when (Map.member (entryLink entry) state) (forget (entryLink entry))
                        create entry
                    (Nothing, Just _) -> notice (UnmanagedPreserved (entryLink entry))
                    (Just old, Just _) -> do
                        matches <-
                            matchingEntry base old `catch` \e ->
                                if isMissing e then pure False else ioError (e :: IOException)
                        if not matches
                            then do
                                notice (ReplacedPreserved (entryLink entry))
                                forget (entryLink entry)
                            else
                                if old == entry
                                    then pure ()
                                    else
                                        if symlinkTarget old == symlinkTarget entry && resolvedTarget old == resolvedTarget entry
                                            then record entry
                                            else do
                                                removed <- removeOwned old
                                                if removed
                                                    then forget (entryLink old) >> create entry
                                                    else notice (ReplacedPreserved (entryLink old)) >> forget (entryLink old)
        staleStep old = safely (absoluteText (entryLink old)) $ do
            rootKind <- pathKind (absoluteText (managedRoot old))
            if isNothing rootKind
                then forget (entryLink old)
                else do
                    contained <- containedEntry base old
                    unless contained (ioError (userError "recorded managed root is not physically contained"))
                    kind <- pathKind (absoluteText (entryLink old))
                    case kind of
                        Nothing -> forget (entryLink old)
                        Just SymbolicLink -> do
                            removed <-
                                removeOwned old `catch` \e ->
                                    if isMissing e then pure False else ioError (e :: IOException)
                            unless removed (notice (ReplacedPreserved (entryLink old)))
                            forget (entryLink old)
                        Just _ -> notice (ReplacedPreserved (entryLink old)) >> forget (entryLink old)
        mutations = do
            mapM_ desiredStep (Map.elems desired)
            case previous of
                Trusted _ -> do
                    current <- readIORef stateRef
                    forM_ (Map.elems current) $ \old ->
                        unless
                            (Map.member (entryLink old) desired || Map.member (sourcePlugin (entrySource old)) unavailable)
                            (staleStep old)
                _ -> do
                    current <- readIORef stateRef
                    when (Map.null current) (checkpoint current)
    completed <- try mutations :: IO (Either HardStop ())
    notices <- readIORef noticesRef
    pure (SyncResult notices unavailable (either (const Interrupted) (const Finished) completed))
  where
    isMissing :: IOException -> Bool
    isMissing = System.IO.Error.isDoesNotExistError

validatePrevious :: FilePath -> PreviousOwnership -> IO PreviousOwnership
validatePrevious base previous@(Trusted (OwnershipState es)) = do
    result <- try (mapM_ (validateManagedRoot base . managedRoot) (Map.elems es)) :: IO (Either IOException ())
    pure $ case result of
        Left e -> Corrupt ("unsafe recorded managed root: " ++ show e)
        Right () -> previous
validatePrevious _ previous = pure previous

syncDirectory :: FilePath -> IO ()
syncDirectory p = bracket (openFd p ReadOnly Nothing defaultFileFlags) closeFd fileSynchronise

renderSyncResult :: SyncResult -> String
renderSyncResult result =
    status
        ++ " ("
        ++ show (length (syncNotices result))
        ++ " notices, "
        ++ show (Map.size (unavailablePlugins result))
        ++ " unavailable plugins)"
  where
    status = if null (syncNotices result) && Map.null (unavailablePlugins result) then "complete" else "partial"

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
