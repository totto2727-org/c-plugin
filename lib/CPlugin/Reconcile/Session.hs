{-# LANGUAGE DeriveDataTypeable #-}

module CPlugin.Reconcile.Session (
    Session,
    HardStop (..),
    newSession,
    sessionBase,
    readState,
    readNotices,
    notice,
    checkpoint,
    forget,
    record,
    safely,
    durableMutationRoot,
    stopWithNotice,
    runSession,
) where

import CPlugin.Paths (validateManagedRoot)
import CPlugin.Reconcile.Plan (SyncPlan (..))
import CPlugin.StateStore (readOwnership, writeOwnership)
import CPlugin.Types.Ownership
import CPlugin.Types.Path (AbsolutePath)
import CPlugin.Types.Sync
import Control.Exception (Exception, IOException, bracket, catch, throwIO, try)
import Data.IORef
import qualified Data.Map.Strict as Map
import Data.Typeable (Typeable)
import System.Posix.IO (OpenMode (ReadOnly), closeFd, defaultFileFlags, openFd)
import System.Posix.Unistd (fileSynchronise)

-- A failed checkpoint stops further mutation, leaving the last durable state.
data HardStop = HardStop deriving (Show, Typeable)
instance Exception HardStop

data Session = Session
    { sessionBase :: FilePath
    , sessionStatePath :: FilePath
    , sessionStateRoot :: AbsolutePath
    , sessionStateRef :: IORef (Map.Map AbsolutePath OwnershipEntry)
    , sessionNoticesRef :: IORef [Notice]
    }

newSession :: SyncPlan -> IO (Session, PreviousOwnership)
newSession plan = do
    previous <- readOwnership (planStatePath plan) >>= validatePrevious (planBase plan)
    let initial = case previous of Trusted (OwnershipState es) -> es; _ -> Map.empty
        initialNotices = planWarnings plan ++ previousNotices previous
    stateRef <- newIORef initial
    noticesRef <- newIORef initialNotices
    pure (Session (planBase plan) (planStatePath plan) (planStateRoot plan) stateRef noticesRef, previous)

previousNotices :: PreviousOwnership -> [Notice]
previousNotices (Trusted _) = []
previousNotices Missing = [PreviousMissing]
previousNotices (Corrupt reason) = [PreviousCorrupt reason]

validatePrevious :: FilePath -> PreviousOwnership -> IO PreviousOwnership
validatePrevious base previous@(Trusted (OwnershipState es)) = do
    result <- try (mapM_ (validateManagedRoot base . managedRoot) (Map.elems es)) :: IO (Either IOException ())
    pure $ case result of
        Left e -> Corrupt ("unsafe recorded managed root: " ++ show e)
        Right () -> previous
validatePrevious _ previous = pure previous

readState :: Session -> IO (Map.Map AbsolutePath OwnershipEntry)
readState = readIORef . sessionStateRef

readNotices :: Session -> IO [Notice]
readNotices = readIORef . sessionNoticesRef

notice :: Session -> Notice -> IO ()
notice session n = modifyIORef' (sessionNoticesRef session) (++ [n])

stopWithNotice :: Session -> Notice -> IO a
stopWithNotice session n = notice session n >> throwIO HardStop

checkpoint :: Session -> Map.Map AbsolutePath OwnershipEntry -> IO ()
checkpoint session next = do
    result <- try persist :: IO (Either IOException ())
    case result of
        Left e -> stopWithNotice session (CheckpointFailed (sessionStatePath session) (show e))
        Right () -> writeIORef (sessionStateRef session) next
  where
    persist = do
        validateManagedRoot (sessionBase session) (sessionStateRoot session)
        writeOwnership (sessionStatePath session) (OwnershipState next)

forget :: Session -> AbsolutePath -> IO ()
forget session link = readState session >>= checkpoint session . Map.delete link

record :: Session -> OwnershipEntry -> IO ()
record session entry = readState session >>= checkpoint session . Map.insert (entryLink entry) entry

-- Only ordinary IO failures are recoverable. HardStop must escape to runSession.
safely :: Session -> FilePath -> IO () -> IO ()
safely session path action =
    action `catch` \e -> notice session (OperationFailed path (show (e :: IOException)))

durableMutationRoot :: Session -> FilePath -> IO ()
durableMutationRoot session root =
    syncDirectory root `catch` \e ->
        stopWithNotice session (CheckpointFailed root (show (e :: IOException)))

syncDirectory :: FilePath -> IO ()
syncDirectory p = bracket (openFd p ReadOnly Nothing defaultFileFlags) closeFd fileSynchronise

-- Catch the terminal signal only around the entire traversal, never each step.
runSession :: IO () -> IO SyncCompletion
runSession mutations = do
    completed <- try mutations :: IO (Either HardStop ())
    pure (either (const Interrupted) (const Finished) completed)
