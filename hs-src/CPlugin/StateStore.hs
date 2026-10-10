{-# LANGUAGE ScopedTypeVariables #-}

module CPlugin.StateStore (
    readLock,
    readOwnership,
    writeLock,
    writeOwnership,
    createLock,
    encodePretty,
) where

import CPlugin.Types.Lock (Lock)
import CPlugin.Types.Ownership (OwnershipState, PreviousOwnership (..))
import Control.Exception (IOException, bracket, catch, mask, onException)
import Control.Monad (unless, when)
import Data.Aeson (ToJSON, eitherDecodeStrict')
import qualified Data.Aeson.Encode.Pretty as Pretty
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (hClose, hFlush)
import System.IO.Error (isAlreadyExistsError, isDoesNotExistError)
import System.Posix.Files (deviceID, fileID, getFdStatus, getSymbolicLinkStatus, isRegularFile)
import System.Posix.IO (OpenFileFlags (..), OpenMode (ReadOnly, WriteOnly), closeFd, defaultFileFlags, fdToHandle, openFd)
import System.Posix.Unistd (fileSynchronise)

-- Canonical ordering and whitespace do not depend on Aeson's map traversal.
encodePretty :: (ToJSON a) => a -> BS.ByteString
encodePretty =
    BL.toStrict
        . Pretty.encodePretty'
            Pretty.defConfig
                { Pretty.confIndent = Pretty.Spaces 2
                , Pretty.confCompare = compare
                , Pretty.confTrailingNewline = True
                }

readLock :: FilePath -> IO Lock
readLock p = do
    bytes <- BS.readFile p
    either (ioError . userError . ("totto2727/c-plugin.StateStoreError.Decode " ++)) pure (eitherDecodeStrict' bytes)
readOwnership :: FilePath -> IO PreviousOwnership
readOwnership p =
    ( do
        status <- getSymbolicLinkStatus p
        if not (isRegularFile status)
            then pure (Corrupt "ownership state must be a physical regular file")
            else do
                bytes <- BS.readFile p
                pure (either Corrupt Trusted (eitherDecodeStrict' bytes))
    )
        `catch` \e ->
            if isDoesNotExistError e then pure Missing else ioError (e :: IOException)

-- Only the process that acquired the exclusive sibling may clean it up.
-- Compare inode identity so a replaced temporary path is never removed.
writeAtomic :: (ToJSON a) => FilePath -> a -> IO ()
writeAtomic p a = mask $ \restore -> do
    createDirectoryIfMissing True (takeDirectory p)
    let tmp = takeDirectory p </> (takeFileName p ++ ".tmp")
    fd <- openFd tmp WriteOnly (Just 0o600) defaultFileFlags{exclusive = True}
    identity <- getFdStatus fd `onException` closeFd fd
    let cleanup =
            ( do
                live <- getSymbolicLinkStatus tmp
                when ((fileID live, deviceID live) == (fileID identity, deviceID identity)) (removeFile tmp)
            )
                `catch` \(_ :: IOException) -> pure ()
    ( do
            h <- fdToHandle fd `onException` closeFd fd
            restore (BS.hPut h (encodePretty a) >> hFlush h >> fileSynchronise fd) `onException` hClose h
            hClose h
            live <- getSymbolicLinkStatus tmp
            unless
                ((fileID live, deviceID live) == (fileID identity, deviceID identity))
                (ioError (userError "temporary state path was replaced before commit"))
            renameFile tmp p
            syncDirectory (takeDirectory p)
        )
        `onException` cleanup

syncDirectory :: FilePath -> IO ()
syncDirectory p = bracket (openFd p ReadOnly Nothing defaultFileFlags) closeFd fileSynchronise

createLock :: FilePath -> Lock -> IO ()
createLock p lock = do
    createDirectoryIfMissing True (takeDirectory p)
    ( do
            fd <- openFd p WriteOnly (Just 0o600) defaultFileFlags{exclusive = True}
            h <- fdToHandle fd `onException` closeFd fd
            (BS.hPut h (encodePretty lock) >> hFlush h >> fileSynchronise fd) `onException` hClose h
            hClose h
            syncDirectory (takeDirectory p)
        )
        `catch` \e ->
            if isAlreadyExistsError e
                then ioError (userError ("totto2727/c-plugin.StateStoreError.AlreadyExists " ++ p))
                else ioError (e :: IOException)
writeLock :: FilePath -> Lock -> IO ()
writeLock = writeAtomic
writeOwnership :: FilePath -> OwnershipState -> IO ()
writeOwnership = writeAtomic
