module CPlugin.Commands.Batch (runPreparedLocks) where

import CPlugin.Internal.Concurrent (mapConcurrentlyIO)
import CPlugin.Paths (within)
import Control.Exception (throwIO)
import Control.Monad (forM_)
import System.FilePath (takeDirectory)
import System.IO.Error (tryIOError)

-- A lock can only write inside its own root. Sibling roots may commit in
-- parallel, but ancestor/descendant roots can share targets and must not overlap.
-- Reporting stays in discovery order. Join ordinary failures so an independent
-- session in the current wave finishes before the failure is reported, including
-- work queued behind the worker limit. No later wave starts after a failure.
runPreparedLocks :: [FilePath] -> (FilePath -> IO a) -> (FilePath -> a -> IO b) -> (FilePath -> b -> IO ()) -> IO ()
runPreparedLocks paths prepare apply report = runWaves paths
  where
    runWaves [] = pure ()
    runWaves pending = do
        let (ready, remaining) = nextWave [] pending
        prepared <- mapConcurrentlyIO (tryIOError . prepare) ready
        results <- mapConcurrentlyIO execute (zip ready prepared)
        forM_ (zip ready results) $ \(path, result) -> either throwIO (report path) result
        runWaves remaining
    execute (_, Left failure) = pure (Left failure)
    execute (path, Right value) = tryIOError (apply path value)
    nextWave ready [] = (reverse ready, [])
    nextWave ready pending@(path : rest)
        | any (overlaps path) ready = (reverse ready, pending)
        | otherwise = nextWave (path : ready) rest
    overlaps left right =
        let a = takeDirectory left
            b = takeDirectory right
         in within a b || within b a
