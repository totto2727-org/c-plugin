module CPlugin.Reconcile.Mutation (desiredStep, staleStep) where

import CPlugin.Paths
import CPlugin.Reconcile.Session
import CPlugin.Types.Ownership
import CPlugin.Types.Path (absoluteText)
import CPlugin.Types.Sync
import Control.Exception (IOException, catch, throwIO)
import Control.Monad (unless, when)
import qualified Data.Map.Strict as Map
import System.IO.Error (isDoesNotExistError)
import System.Posix.Files (createSymbolicLink, removeLink)

desiredStep :: Session -> Bool -> OwnershipEntry -> IO ()
desiredStep session force entry = safely session (absoluteText (entryLink entry)) $ do
    ensureManagedRoot (sessionBase session) (managedRoot entry)
    contained <- containedEntry (sessionBase session) entry
    unless contained (ioError (userError "link parent escapes managed root"))
    kind <- pathKind (absoluteText (entryLink entry))
    state <- readState session
    let owned = Map.lookup (entryLink entry) state
    case (owned, kind) of
        _
            | force && kind `elem` [Just RegularFile, Just SymbolicLink] ->
                forceReplace session entry owned kind
        (_, Nothing) -> do
            when (Map.member (entryLink entry) state) (forget session (entryLink entry))
            create session entry
        (Nothing, Just _) -> notice session (UnmanagedPreserved (entryLink entry))
        (Just old, Just _) -> reconcileOwned session old entry

forceReplace :: Session -> OwnershipEntry -> Maybe OwnershipEntry -> Maybe PathKind -> IO ()
forceReplace session entry owned kind = do
    case owned of
        Just _ -> forget session (entryLink entry)
        Nothing -> pure ()
    -- Force replaces only this direct contained file or symlink.
    stillContained <- containedEntry (sessionBase session) entry
    currentKind <- pathKind (absoluteText (entryLink entry))
    unless (stillContained && currentKind == kind) (ioError (userError "force eligibility changed"))
    removeLink (absoluteText (entryLink entry))
    durableMutationRoot session (absoluteText (managedRoot entry))
    readState session >>= checkpoint session
    create session entry

reconcileOwned :: Session -> OwnershipEntry -> OwnershipEntry -> IO ()
reconcileOwned session old entry = do
    matches <- missingIsFalse (matchingEntry (sessionBase session) old)
    if matches
        then updateMatching session old entry
        else preserveReplaced session entry

updateMatching :: Session -> OwnershipEntry -> OwnershipEntry -> IO ()
updateMatching session old entry
    | old == entry = pure ()
    | symlinkTarget old == symlinkTarget entry && resolvedTarget old == resolvedTarget entry = record session entry
    | otherwise = do
        removed <- removeOwned session old
        if removed
            then forget session (entryLink old) >> create session entry
            else preserveReplaced session old

preserveReplaced :: Session -> OwnershipEntry -> IO ()
preserveReplaced session entry = do
    notice session (ReplacedPreserved (entryLink entry))
    forget session (entryLink entry)

staleStep :: Session -> OwnershipEntry -> IO ()
staleStep session old = safely session (absoluteText (entryLink old)) $ do
    rootKind <- pathKind (absoluteText (managedRoot old))
    case rootKind of
        Nothing -> forget session (entryLink old)
        Just _ -> cleanStalePath session old

cleanStalePath :: Session -> OwnershipEntry -> IO ()
cleanStalePath session old = do
    contained <- containedEntry (sessionBase session) old
    unless contained (ioError (userError "recorded managed root is not physically contained"))
    kind <- pathKind (absoluteText (entryLink old))
    case kind of
        Nothing -> forget session (entryLink old)
        Just SymbolicLink -> do
            removed <- missingIsFalse (removeOwned session old)
            unless removed (notice session (ReplacedPreserved (entryLink old)))
            forget session (entryLink old)
        Just _ -> preserveReplaced session old

removeOwned :: Session -> OwnershipEntry -> IO Bool
removeOwned session entry = do
    matches <- matchingEntry (sessionBase session) entry
    if matches then removeRechecked session entry else pure False

removeRechecked :: Session -> OwnershipEntry -> IO Bool
removeRechecked session entry = do
    -- Recheck literal identity and containment immediately before unlink.
    rechecked <- matchingEntry (sessionBase session) entry
    if not rechecked
        then pure False
        else do
            removeLink (absoluteText (entryLink entry))
            durableMutationRoot session (absoluteText (managedRoot entry))
            pure True

create :: Session -> OwnershipEntry -> IO ()
create session entry = do
    createSymbolicLink (symlinkTarget entry) (absoluteText (entryLink entry))
    -- The catch starts after creation, so a failed create never rolls back an
    -- existing path. Rollback always rethrows the terminal signal.
    finishCreation session entry `catch` \HardStop -> do
        rollbackCreated session entry
        throwIO HardStop

finishCreation :: Session -> OwnershipEntry -> IO ()
finishCreation session entry = do
    durableMutationRoot session (absoluteText (managedRoot entry))
    verified <-
        matchingEntry (sessionBase session) entry `catch` \e ->
            stopWithNotice session (OperationFailed (absoluteText (entryLink entry)) (show (e :: IOException)))
    unless verified (stopWithNotice session (OperationFailed (absoluteText (entryLink entry)) "created link could not be verified"))
    record session entry

rollbackCreated :: Session -> OwnershipEntry -> IO ()
rollbackCreated session entry = safely session (absoluteText (entryLink entry)) $ do
    -- Only roll back the exact matching link freshly created by this mutation.
    matches <- matchingEntry (sessionBase session) entry
    when matches $ do
        removeLink (absoluteText (entryLink entry))
        durableMutationRoot session (absoluteText (managedRoot entry))

missingIsFalse :: IO Bool -> IO Bool
missingIsFalse action =
    action `catch` \e ->
        if isDoesNotExistError e then pure False else ioError (e :: IOException)
