module CPlugin.Reconcile (syncLoadedLock, renderSyncResult, printWarnings) where

import CPlugin.Reconcile.Mutation (desiredStep, staleStep)
import CPlugin.Reconcile.Plan (SyncPlan (..), planSync)
import CPlugin.Reconcile.Report (printWarnings, renderSyncResult)
import CPlugin.Reconcile.Session (Session, checkpoint, newSession, readNotices, readState, runSession)
import CPlugin.Types.Lock (Lock)
import CPlugin.Types.Ownership
import CPlugin.Types.Sync (SyncResult (..))
import Control.Monad (forM_, unless, when)
import qualified Data.Map.Strict as Map

syncLoadedLock :: FilePath -> Lock -> Bool -> IO SyncResult
syncLoadedLock lockPath lock force = do
    plan <- planSync lockPath lock
    (session, previous) <- newSession plan
    completion <- runSession $ do
        mapM_ (desiredStep session force) (Map.elems (planDesired plan))
        finishOwnership session plan previous
    notices <- readNotices session
    pure (SyncResult notices (planUnavailable plan) completion)

finishOwnership :: Session -> SyncPlan -> PreviousOwnership -> IO ()
finishOwnership session plan (Trusted _) = do
    current <- readState session
    forM_ (Map.elems current) $ \old ->
        unless
            ( Map.member (entryLink old) (planDesired plan)
                || Map.member (sourcePlugin (entrySource old)) (planUnavailable plan)
            )
            (staleStep session old)
finishOwnership session _ _ = do
    current <- readState session
    when (Map.null current) (checkpoint session current)
