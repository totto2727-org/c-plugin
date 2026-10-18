module CPlugin.Reconcile (SyncPlan, planSync, planSyncWithGit, syncPlannedLock, syncLoadedLock, syncLoadedLockWithForce, renderSyncResult, printWarnings) where

import CPlugin.Reconcile.Mutation (desiredStep, staleStep)
import CPlugin.Reconcile.Plan (SyncPlan (..), planSync, planSyncWithGit)
import CPlugin.Reconcile.Report (printWarnings, renderSyncResult)
import CPlugin.Reconcile.Session (Session, checkpoint, newSession, readNotices, readState, runSession)
import CPlugin.Types.Lock (Lock)
import CPlugin.Types.Ownership
import CPlugin.Types.Sync (SyncResult (..))
import Control.Monad (forM_, unless, when)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

syncLoadedLock :: FilePath -> Lock -> Bool -> IO SyncResult
syncLoadedLock lockPath lock force = do
    plan <- planSync lockPath lock
    syncPlannedLock plan force

syncLoadedLockWithForce :: FilePath -> Lock -> Set.Set OwnershipSource -> IO SyncResult
syncLoadedLockWithForce lockPath lock forcedSources = do
    plan <- planSync lockPath lock
    -- The whole candidate is reconciled, but add authorizes force only for its
    -- selected source identities, across all managed targets.
    syncPlannedLockWith plan (`Set.member` forcedSources)

-- Planning is read-only and may overlap other repositories and locks. The
-- session owns sequential mutations and their required durable checkpoints.
syncPlannedLock :: SyncPlan -> Bool -> IO SyncResult
syncPlannedLock plan force = syncPlannedLockWith plan (const force)

syncPlannedLockWith :: SyncPlan -> (OwnershipSource -> Bool) -> IO SyncResult
syncPlannedLockWith plan force = do
    (session, previous) <- newSession plan
    completion <- runSession $ do
        forM_ (Map.elems (planDesired plan)) $ \entry ->
            desiredStep session (force (entrySource entry)) entry
        finishOwnership session plan previous
    notices <- readNotices session
    pure (SyncResult notices (planUnavailable plan) (planUnavailableSkills plan) completion)

finishOwnership :: Session -> SyncPlan -> PreviousOwnership -> IO ()
finishOwnership session plan (Trusted _) = do
    current <- readState session
    forM_ (Map.elems current) $ \old ->
        unless
            ( Map.member (entryLink old) (planDesired plan)
                || sourceUnavailable plan (entrySource old)
            )
            (staleStep session old)
finishOwnership session _ _ = do
    current <- readState session
    when (Map.null current) (checkpoint session current)

sourceUnavailable :: SyncPlan -> OwnershipSource -> Bool
sourceUnavailable plan source = case sourcePlugin source of
    Just plugin -> Map.member plugin (planUnavailable plan)
    Nothing -> Map.member (sourceSkill source) (planUnavailableSkills plan)
