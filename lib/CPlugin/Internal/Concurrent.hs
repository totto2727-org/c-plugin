{-# LANGUAGE LambdaCase #-}

-- Keep worker lifetimes scoped to the requesting operation. Nested traversals
-- never hold a permit while waiting for their children: only leaf blocking
-- effects enter withIO, so nested source and file work cannot deadlock the pool.
module CPlugin.Internal.Concurrent (mapConcurrentlyIO, concurrentlyIO, withIO) where

import Control.Concurrent.Async (concurrently, mapConcurrently)
import Control.Concurrent.MVar (modifyMVar, newMVar)
import Control.Concurrent.QSem (QSem, newQSem, signalQSem, waitQSem)
import Control.Exception (bracket_)
import Data.List (sortOn)
import System.IO.Unsafe (unsafePerformIO)

workerLimit :: Int
workerLimit = 8

-- A process-wide gate prevents nested repository/file traversals from spawning
-- an unbounded number of simultaneous external Git processes or file reads.
{-# NOINLINE ioSlots #-}
ioSlots :: QSem
ioSlots = unsafePerformIO (newQSem workerLimit)

withIO :: IO a -> IO a
withIO = bracket_ (waitQSem ioSlots) (signalQSem ioSlots)

concurrentlyIO :: IO a -> IO b -> IO (a, b)
concurrentlyIO = concurrently

-- The queue has at most eight workers, rather than one blocked thread per item.
-- async cancels and joins all siblings on failure or asynchronous interruption.
-- Results retain input order even when effects finish in a different order.
mapConcurrentlyIO :: (a -> IO b) -> [a] -> IO [b]
mapConcurrentlyIO action inputs = do
    pending <- newMVar (zip [0 :: Int ..] inputs)
    let next = modifyMVar pending $ \case
            [] -> pure ([], Nothing)
            item : rest -> pure (rest, Just item)
        worker = do
            item <- next
            case item of
                Nothing -> pure []
                Just (index, input) -> do
                    result <- action input
                    rest <- worker
                    pure ((index, result) : rest)
    results <- mapConcurrently (const worker) (take workerLimit inputs)
    pure (map snd (sortOn fst (concat results)))
