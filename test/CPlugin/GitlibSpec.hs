{-# LANGUAGE OverloadedStrings #-}

-- Only the fixed HTTPS fetch is mapped to a local repository. All Git operations
-- use the production gitlib adapter and the installed Git executable.
module CPlugin.GitlibSpec (spec) where

import CPlugin.Commands (Command (Sync), runCommand)
import CPlugin.GitHubTestSupport (gitCommand, gitCommit, withGitFixture, writeWideFixture)
import CPlugin.Internal.Concurrent (withIO)
import CPlugin.Paths (nameIO)
import CPlugin.Source.GitHub (GitRunner, fetchGitHubWith, verifyGitHub, verifyGitHubWith)
import CPlugin.Source.Gitlib (runGitlib)
import CPlugin.StateStore (writeLock)
import CPlugin.TestSupport (writeFixture)
import CPlugin.Types.GitHub (GitHubOrigin, githubRepository, githubSource, githubSubpath)
import CPlugin.Types.Lock (Lock (plugins), makeLock)
import CPlugin.Types.Path (AbsolutePath, absoluteText)
import CPlugin.Types.Plugin (makePluginWithOrigin)
import Control.Concurrent (newEmptyMVar, putMVar, readMVar, takeMVar, threadDelay)
import Control.Concurrent.Async (AsyncCancelled, cancel, concurrently, mapConcurrently, wait, waitCatch, withAsync)
import Control.Exception (bracket, fromException)
import Control.Monad (replicateM_, void)
import Data.Bits ((.&.))
import qualified Data.ByteString as BS
import Data.List (isSuffixOf)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Foreign.C.Error (Errno (Errno), eNXIO)
import GHC.IO.Exception (IOException (ioe_errno))
import System.Directory (doesDirectoryExist, doesFileExist, getCurrentDirectory, listDirectory)
import System.Environment (getEnvironment, lookupEnv, setEnv, unsetEnv)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose)
import System.IO.Error (catchIOError)
import System.Posix.Files (createNamedPipe, createSymbolicLink, fileMode, getFileStatus, readSymbolicLink, setFileMode)
import System.Posix.IO (OpenFileFlags (nonBlock), OpenMode (WriteOnly), defaultFileFlags, fdToHandle, openFd)
import System.Timeout (timeout)
import Test.Hspec (Spec, anyIOException, describe, expectationFailure, it, shouldBe, shouldReturn, shouldSatisfy, shouldThrow)

spec :: Spec
spec = describe "gitlib adapter with real local Git repositories" $ do
    it "initializes a path with spaces and records the canonical remote" $ withGitFixture $ \base _ _ _ -> do
        let tree = base </> "gitlib init with spaces"
        void (runGitlib False base ["init", "--template=", "--", tree])
        doesDirectoryExist (tree </> ".git") `shouldReturn` True
        void (runGitlib False tree ["remote", "add", "origin", fixedURL])
        runGitlib False tree ["config", "--local", "--get", "remote.origin.url"] `shouldReturn` (fixedURL ++ "\n")
        runGitlib True tree ["ls-remote", "--get-url", "--", fixedURL] `shouldReturn` (fixedURL ++ "\n")

    it "resolves HEAD and preserves the recursive NUL-delimited tree protocol" $ withGitFixture $ \_ repository _ _ -> do
        writeFixture (repository </> "package/日本語 with spaces.txt") "Unicode filename"
        commit <- gitCommit repository "Unicode tree entry"
        expected <- gitCommand repository ["ls-tree", "-r", "-z", "HEAD"]
        runGitlib False repository ["rev-parse", "--verify", "HEAD^{commit}"] `shouldReturn` (commit ++ "\n")
        runGitlib False repository ["ls-tree", "-r", "-z", "HEAD"] `shouldReturn` expected

    it "preserves binary files, Unicode, executable modes and literal symlinks in snapshots" $ withGitFixture $ \base repository _ _ -> do
        let binary = BS.pack [0, 255, 128, 10, 13, 0, 65]
        writeFixture (repository </> "package/file with spaces.txt") "space content"
        writeFixture (repository </> "package/日本語.txt") "Unicode filename"
        writeFixture (repository </> "package/binary.bin") binary
        writeFixture (repository </> "package/run.sh") "#!/bin/sh\nexit 0\n"
        setFileMode (repository </> "package/run.sh") 0o755
        createSymbolicLink "file with spaces.txt" (repository </> "package/content alias")
        _ <- gitCommit repository "checkout edge cases"
        (_, root) <- fetchFixture base repository
        BS.readFile (absoluteText root </> "binary.bin") `shouldReturn` binary
        BS.readFile (absoluteText root </> "日本語.txt") `shouldReturn` "Unicode filename"
        readSymbolicLink (absoluteText root </> "content alias") `shouldReturn` "file with spaces.txt"
        mode <- fileMode <$> getFileStatus (absoluteText root </> "run.sh")
        mode .&. 0o100 `shouldBe` 0o100

    it "returns blob output containing embedded NULs without truncation" $ withGitFixture $ \_ repository _ _ -> do
        writeFixture (repository </> "nul blob") (BS.pack [65, 0, 66, 10])
        _ <- gitCommit repository "NUL blob"
        oid <- trimLine <$> gitCommand repository ["rev-parse", "HEAD:nul blob"]
        runGitlib False repository ["cat-file", "blob", oid] `shouldReturn` "A\0B\n"

    it "hashes binary bytes and a wide argv batch in the original order" $ withGitFixture $ \_ repository _ _ -> do
        writeWideFixture repository
        writeFixture (repository </> "package/binary.bin") (BS.pack [0, 255, 128, 10])
        let paths = "package/binary.bin" : ["package/content/file " ++ show index ++ ".txt" | index <- [65, 64 .. 1 :: Int]]
            arguments = ["hash-object", "--no-filters", "--"] ++ paths
        expected <- gitCommand repository arguments
        runGitlib False repository arguments `shouldReturn` expected
        length (lines expected) `shouldBe` length paths

    it "verifies a pinned snapshot offline and uses it through the default Sync command" $ withGitFixture $ \base repository commit initial -> do
        (origin, root) <- fetchFixture base repository
        let tree = takeDirectory (absoluteText root)
        runGitlib False tree ["rev-parse", "--verify", "FETCH_HEAD^{commit}"] `shouldReturn` (commit ++ "\n")
        verifyGitHubWith offlineGitlib base origin `shouldReturn` root
        verifyGitHub base origin `shouldReturn` root
        name <- nameIO "remote"
        skill <- nameIO "alpha"
        plugin <- either (ioError . userError) pure (makePluginWithOrigin name (githubSource origin) [skill] (Just origin))
        lock <- either (ioError . userError) pure (makeLock [] (Map.elems (plugins initial) ++ [plugin]))
        writeLock (base </> "c-plugin-lock.json") lock
        runCommand (Sync False False)
        readSymbolicLink (base </> ".agents/skills/alpha") `shouldReturn` ("../c-plugin/sources/fixture-owner/fixture-repo/" ++ commit ++ "/tree/package/skills/alpha")
        readSymbolicLink (base </> ".agents/skills/existing") `shouldReturn` "../../plugin/skills/existing"

    it "rejects dirty pinned content without repairing it or rewriting provenance" $ withGitFixture $ \base repository _ _ -> do
        (origin, root) <- fetchFixture base repository
        let marker = takeDirectory (takeDirectory (absoluteText root)) </> "origin.json"
            manifest = absoluteText root </> "plugin.json"
        before <- BS.readFile marker
        BS.writeFile manifest "foreign change"
        verifyGitHub base origin `shouldThrow` anyIOException
        BS.readFile manifest `shouldReturn` "foreign change"
        BS.readFile marker `shouldReturn` before

    it "rejects corrupt cached objects without replacing their bytes or provenance" $ withGitFixture $ \base repository _ _ -> do
        (origin, root) <- fetchFixture base repository
        let tree = takeDirectory (absoluteText root)
            packDirectory = tree </> ".git/objects/pack"
            marker = takeDirectory tree </> "origin.json"
        void (runGitlib False tree ["repack", "-ad"])
        packs <- filter (".pack" `isSuffixOf`) <$> listDirectory packDirectory
        object <- case packs of
            [pack] -> pure (packDirectory </> pack)
            _ -> ioError (userError "expected one fetched fixture object pack")
        before <- BS.readFile marker
        setFileMode object 0o644
        BS.writeFile object "not a Git object pack"
        verifyGitHub base origin `shouldThrow` anyIOException
        BS.readFile object `shouldReturn` "not a Git object pack"
        BS.readFile marker `shouldReturn` before

    it "passes shell metacharacters as literal filename arguments" $ withGitFixture $ \_ repository _ _ -> do
        let path = "$(touch injected); file with spaces"
            arguments = ["hash-object", "--no-filters", "--", path]
        writeFixture (repository </> path) "literal argument"
        expected <- gitCommand repository arguments
        runGitlib False repository arguments `shouldReturn` expected
        doesFileExist (repository </> "injected") `shouldReturn` False

    it "raises IO errors and keeps concurrent child cwd and environment changes scoped" $ withGitFixture $ \base repository commit _ ->
        bracket (lookupEnv "GIT_DIR") restoreGitDir $ \_ -> do
            setEnv "GIT_DIR" (base </> "must-not-be-used")
            beforeEnvironment <- getEnvironment
            beforeDirectory <- getCurrentDirectory
            concurrently
                (runGitlib False repository ["rev-parse", "--verify", "HEAD^{commit}"])
                (runGitlib False base ["rev-parse", "--resolve-git-dir", repository </> ".git"])
                `shouldReturn` (commit ++ "\n", repository </> ".git" ++ "\n")
            runGitlib False repository ["rev-parse", "--verify", "refs/heads/missing"] `shouldThrow` anyIOException
            getEnvironment `shouldReturn` beforeEnvironment
            getCurrentDirectory `shouldReturn` beforeDirectory

    it "permits installed helper configuration only in the network child without contacting a remote" $ withGitFixture $ \base repository _ _ -> do
        writeFixture (base </> ".gitconfig") "[credential]\n\thelper = fixture-installed-helper\n"
        runGitlib True repository ["config", "--get", "credential.helper"] `shouldReturn` "fixture-installed-helper\n"
        runGitlib False repository ["config", "--get", "credential.helper"] `shouldThrow` anyIOException

    it "releases the shared IO slot when a real Git child blocked on a FIFO is cancelled" $ withGitFixture $ \base repository commit _ -> do
        let fifo = base </> "blocked Git input"
            openWriter =
                openFd fifo WriteOnly Nothing defaultFileFlags{nonBlock = True} `catchIOError` \err ->
                    if fmap Errno (ioe_errno err) == Just eNXIO
                        then threadDelay 1000 >> openWriter
                        else ioError err
        createNamedPipe fifo 0o600
        withAsync (runGitlib False repository ["hash-object", "--no-filters", "--", fifo]) $ \worker ->
            -- Opening the writer proves Git opened the reader. Keep it open so
            -- cancellation, rather than EOF, must end the blocked operation.
            watchdog $ bracket (openWriter >>= fdToHandle) hClose $ \_ -> do
                watchdog (cancel worker)
                result <- waitCatch worker
                case result of
                    Left err -> (fromException err :: Maybe AsyncCancelled) `shouldSatisfy` isJust
                    Right _ -> expectationFailure "cancelled Git worker unexpectedly succeeded"
        arrivals <- newEmptyMVar
        release <- newEmptyMVar
        void $ withAsync (mapConcurrently (\_ -> withIO (putMVar arrivals () >> readMVar release)) [1 .. 8 :: Int]) $ \workers -> do
            watchdog (replicateM_ 8 (takeMVar arrivals))
            putMVar release ()
            watchdog (wait workers)
        runGitlib False repository ["rev-parse", "--verify", "HEAD^{commit}"] `shouldReturn` (commit ++ "\n")

fixedURL :: String
fixedURL = "https://github.com/fixture-owner/fixture-repo.git"

fetchFixture :: FilePath -> FilePath -> IO (GitHubOrigin, AbsolutePath)
fetchFixture base repository = do
    typedRepository <- either (ioError . userError) pure (githubRepository "fixture-owner/fixture-repo")
    subpath <- either (ioError . userError) pure (githubSubpath "package")
    fetchGitHubWith localFetch base typedRepository Nothing subpath
  where
    localFetch network directory arguments
        | network && fixedURL `elem` arguments && "fetch" `elem` arguments =
            runGitlib False directory (["-c", "protocol.file.allow=always"] ++ map (\argument -> if argument == fixedURL then repository else argument) arguments)
        | network && fixedURL `elem` arguments && "ls-remote" `elem` arguments = runGitlib False directory arguments
        | network = ioError (userError "synthetic transport refused an unexpected network operation")
        | otherwise = runGitlib False directory arguments

offlineGitlib :: GitRunner
offlineGitlib network directory arguments
    | network = ioError (userError "offline verification attempted network access")
    | otherwise = runGitlib False directory arguments

restoreGitDir :: Maybe String -> IO ()
restoreGitDir Nothing = unsetEnv "GIT_DIR"
restoreGitDir (Just value) = setEnv "GIT_DIR" value

watchdog :: IO a -> IO a
watchdog action = timeout 10000000 action >>= maybe (ioError (userError "Gitlib test timed out")) pure

trimLine :: String -> String
trimLine = filter (`notElem` ['\r', '\n'])
