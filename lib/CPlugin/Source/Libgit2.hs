{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- This is an internal argv protocol adapter, not a general Git implementation.
module CPlugin.Source.Libgit2 (runLibgit2, runLibgit2LocalForTesting) where

import CPlugin.Internal.Concurrent (withIO)
import CPlugin.Types.GitHub (githubCommit, githubRef, githubRepositoryInput, repositoryURL)
import Control.Concurrent (forkIOWithUnmask)
import Control.Concurrent.MVar (modifyMVar_, newEmptyMVar, newMVar, putMVar, readMVar, withMVar)
import Control.Exception (SomeException, catch, mask, onException, throwIO, try)
import Control.Monad (unless, when)
import Data.List (isPrefixOf)
import Foreign (Ptr, alloca, nullPtr, peek, withArray)
import Foreign.C (CInt (..), CSize (..), CString, peekCString, withCString)
import qualified GHC.Foreign as GHC
import GHC.IO.Encoding (getLocaleEncoding)
import System.FilePath (isAbsolute)

-- Network operations accept only the canonical, already validated GitHub URL.
runLibgit2 :: Bool -> FilePath -> [String] -> IO String
runLibgit2 = run False

-- Explicit fixture-only seam. It accepts absolute local paths, never file URLs,
-- relative paths, or arbitrary network endpoints. Local transport transfers the
-- full fixture history because it cannot negotiate shallow fetches. Production
-- must use runLibgit2, whose HTTPS fetch always requests depth one.
runLibgit2LocalForTesting :: Bool -> FilePath -> [String] -> IO String
runLibgit2LocalForTesting = run True

data Call

foreign import ccall unsafe "cplugin_git_new" newCall :: CInt -> CInt -> CString -> CSize -> Ptr CString -> IO (Ptr Call)
foreign import ccall unsafe "cplugin_git_cancel" cancelCall :: Ptr Call -> IO ()
foreign import ccall safe "cplugin_git_run" runCall :: Ptr Call -> IO CInt
foreign import ccall unsafe "cplugin_git_output" outputCall :: Ptr Call -> Ptr CSize -> IO CString
foreign import ccall unsafe "cplugin_git_error" errorCall :: Ptr Call -> IO CString
foreign import ccall unsafe "cplugin_git_free" freeCall :: Ptr Call -> IO ()

run :: Bool -> Bool -> FilePath -> [String] -> IO String
run localTest network directory arguments = do
    when (any (elem '\0') (directory : arguments)) (failure "NUL in libgit2 input")
    (operation, values) <- protocol localTest network arguments
    mask $ \restore -> do
        call <- withCString directory $ \root -> withStrings values $ \strings ->
            withArray strings $ \array -> newCall operation (if localTest then 1 else 0) root (fromIntegral (length strings)) array
        when (call == nullPtr) (failure "could not allocate libgit2 operation")
        -- Serialize cancellation against destruction, not against the blocking call.
        live <- newMVar (Just call)
        done <- newEmptyMVar
        let dispose = modifyMVar_ live $ \pointer -> do
                maybe (pure ()) freeCall pointer
                pure Nothing
            cancel = withMVar live (maybe (pure ()) cancelCall)
            work = withIO $ do
                result <- runCall call
                if result < 0
                    then errorCall call >>= peekCString >>= failure
                    else alloca $ \size -> do
                        bytes <- outputCall call size
                        lengthBytes <- peek size
                        encoding <- getLocaleEncoding
                        GHC.peekCStringLen encoding (bytes, fromIntegral lengthBytes)
        _ <-
            forkIOWithUnmask
                ( \unmask -> do
                    result <- try (unmask work) :: IO (Either SomeException String)
                    dispose
                    putMVar done result
                )
                `onException` dispose
        -- Defer repeated interruption until the scoped worker has stopped. This
        -- remains an interruptible wait, not uninterruptibleMask around C IO.
        -- DNS/TLS may still delay cooperative cancellation between callbacks.
        let cancelAndJoin = (cancel >> readMVar done >> pure ()) `catch` \(_ :: SomeException) -> cancelAndJoin
        result <- restore (readMVar done) `onException` cancelAndJoin
        either throwIO pure result
  where
    failure message = ioError (userError ("libgit2 operation failed: " ++ message))

withStrings :: [String] -> ([CString] -> IO a) -> IO a
withStrings [] action = action []
withStrings (value : rest) action = withCString value $ \string -> withStrings rest (action . (string :))

protocol :: Bool -> Bool -> [String] -> IO (CInt, [String])
protocol localTest network arguments = case arguments of
    ["init", "--template=", "--", tree] -> offline 0 [tree]
    ["remote", "add", "origin", url] -> validURL url >> offline 1 [url]
    ["ls-remote", "--get-url", "--", url] -> online 2 [url] url
    ["fetch", "--no-tags", "--no-recurse-submodules", "--depth=1", "--", url, ref] -> do
        either failure (const (pure ())) (githubRef ref)
        online 3 [url, ref] url
    ["rev-parse", "--verify", revision] | revision `elem` ["FETCH_HEAD^{commit}", "HEAD^{commit}"] -> offline 4 [revision]
    ["-c", "advice.detachedHead=false", "checkout", "--detach", commit, "--"] -> do
        either failure (const (pure ())) (githubCommit commit)
        offline 5 [commit]
    ["fsck", "--full", "--no-reflogs"] -> offline 6 []
    ["config", "--local", "--get", "remote.origin.url"] -> offline 7 []
    ["ls-tree", "-r", "-z", revision] | revision `elem` ["FETCH_HEAD", "HEAD"] -> offline 8 [revision]
    ["cat-file", "blob", oid] -> do
        either failure (const (pure ())) (githubCommit oid)
        offline 9 [oid]
    "hash-object" : "--no-filters" : "--" : paths -> offline 10 paths
    ["-c", "core.fileMode=true", "status", "--porcelain", "--untracked-files=all", "--ignored"] -> offline 11 []
    _ -> failure "unsupported internal operation"
  where
    failure = ioError . userError . ("libgit2: " ++)
    offline operation values = do
        when network (failure "offline operation marked as network")
        pure (operation, values)
    online operation values url = do
        unless network (failure "network operation denied in offline mode")
        validURL url
        pure (operation, values)
    validURL url
        | localTest && isAbsolute url && not ("//" `isPrefixOf` url) = pure ()
        | otherwise = case githubRepositoryInput url of
            Right repository | repositoryURL repository == url -> pure ()
            _ -> failure "expected canonical HTTPS GitHub URL"
