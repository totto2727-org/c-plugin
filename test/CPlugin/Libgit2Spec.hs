{-# LANGUAGE OverloadedStrings #-}

-- Git creates fixture commits only. Backend operations and snapshot verification
-- use libgit2, with an explicit local-only transport seam instead of GitHub.
module CPlugin.Libgit2Spec (spec) where

import CPlugin.Commands (Command (Sync), runCommand)
import CPlugin.GitHubTestSupport (gitCommand, gitCommit, withGitFixture, writeWideFixture)
import CPlugin.Source.GitHub (GitRunner, fetchGitHubWith, verifyGitHub, verifyGitHubWith)
import CPlugin.Source.Libgit2 (runLibgit2, runLibgit2LocalForTesting)
import CPlugin.TestSupport (writeFixture)
import CPlugin.Types.GitHub (GitHubOrigin, githubRepository, githubSubpath)
import CPlugin.Types.Path (AbsolutePath, absoluteText)
import Control.Exception (bracket)
import Control.Monad (forM_, void)
import Data.Bits ((.&.))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isInfixOf)
import System.Directory (doesDirectoryExist, removeFile)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath (takeDirectory, (</>))
import System.Posix.Files (createSymbolicLink, fileMode, getFileStatus, readSymbolicLink, setFileMode)
import Test.Hspec (Spec, anyIOException, describe, it, shouldBe, shouldReturn, shouldSatisfy, shouldThrow)

spec :: Spec
spec = describe "native libgit2 backend with real local repositories" $ do
    it "initializes an empty repository and records the canonical remote without Git on PATH" $ withGitFixture $ \base _ _ _ -> do
        let tree = base </> "native init with spaces"
        withoutGit $ do
            void (runLibgit2 False base ["init", "--template=", "--", tree])
            doesDirectoryExist (tree </> ".git") `shouldReturn` True
            void (runLibgit2 False tree ["remote", "add", "origin", fixedURL])
            runLibgit2 False tree ["config", "--local", "--get", "remote.origin.url"] `shouldReturn` (fixedURL ++ "\n")
            runLibgit2 True tree ["ls-remote", "--get-url", "--", fixedURL] `shouldReturn` (fixedURL ++ "\n")

    it "resolves committed HEAD and emits the NUL-delimited recursive tree protocol" $ withGitFixture $ \_ repository commit _ -> do
        expected <- gitCommand repository ["ls-tree", "-r", "-z", "HEAD"]
        withoutGit $ do
            runLibgit2 False repository ["rev-parse", "--verify", "HEAD^{commit}"] `shouldReturn` (commit ++ "\n")
            runLibgit2 False repository ["ls-tree", "-r", "-z", "HEAD"] `shouldReturn` expected

    it "preserves spaces, Unicode, executable modes, symlinks and binary bytes through native checkout" $ withGitFixture $ \base repository _ _ -> do
        let binary = BS.pack [0, 255, 128, 10, 13, 0, 65]
        writeFixture (repository </> "package/file with spaces.txt") "space content"
        writeFixture (repository </> "package/日本語.txt") "Unicode filename"
        writeFixture (repository </> "package/binary.bin") binary
        writeFixture (repository </> "package/run.sh") "#!/bin/sh\nexit 0\n"
        setFileMode (repository </> "package/run.sh") 0o755
        createSymbolicLink "file with spaces.txt" (repository </> "package/content alias")
        _ <- gitCommit repository "native checkout edge cases"
        expectedTree <- gitCommand repository ["ls-tree", "-r", "-z", "HEAD"]
        (_, root) <- withoutGit (fetchNativeFixture base repository)
        let tree = takeDirectory (absoluteText root)
        BS.readFile (absoluteText root </> "binary.bin") `shouldReturn` binary
        BS.readFile (absoluteText root </> "日本語.txt") `shouldReturn` "Unicode filename"
        readSymbolicLink (absoluteText root </> "content alias") `shouldReturn` "file with spaces.txt"
        mode <- fileMode <$> getFileStatus (absoluteText root </> "run.sh")
        mode .&. 0o100 `shouldBe` 0o100
        withoutGit $ runLibgit2 False tree ["ls-tree", "-r", "-z", "HEAD"] `shouldReturn` expectedTree

    it "returns complete blob content including embedded NULs instead of truncating C strings" $ withGitFixture $ \_ repository _ _ -> do
        writeFixture (repository </> "nul blob") (BS.pack [65, 0, 66, 10])
        _ <- gitCommit repository "NUL blob"
        oid <- trimLine <$> gitCommand repository ["rev-parse", "HEAD:nul blob"]
        withoutGit $ runLibgit2 False repository ["cat-file", "blob", oid] `shouldReturn` "A\0B\n"

    it "hashes a wide argv batch in order without filters and without Git on PATH" $ withGitFixture $ \_ repository _ _ -> do
        writeWideFixture repository
        writeFixture (repository </> "package/binary.bin") (BS.pack [0, 255, 128, 10])
        let paths = "package/binary.bin" : ["package/content/file " ++ show index ++ ".txt" | index <- [65, 64 .. 1 :: Int]]
            arguments = ["hash-object", "--no-filters", "--"] ++ paths
        expected <- gitCommand repository arguments
        withoutGit $ runLibgit2 False repository arguments `shouldReturn` expected
        length (lines expected) `shouldBe` length paths

    it "fetches locally, resolves FETCH_HEAD and validates a pinned snapshot entirely with libgit2" $ withGitFixture $ \base repository commit _ -> do
        (origin, root) <- withoutGit (fetchNativeFixture base repository)
        let tree = takeDirectory (absoluteText root)
        withoutGit $ do
            runLibgit2 False tree ["rev-parse", "--verify", "FETCH_HEAD^{commit}"] `shouldReturn` (commit ++ "\n")
            verifyGitHubWith offlineNative base origin `shouldReturn` root
            verifyGitHub base origin `shouldReturn` root

    it "accepts an unfetched parent only when HEAD is an explicit shallow boundary" $ withGitFixture $ \_ repository parent _ -> do
        writeFixture (repository </> "package/revision.txt") "second commit"
        commit <- gitCommit repository "commit with parent"
        void (gitCommand repository ["tag", "--delete", "v1"])
        -- The fixture-only local transport fetches full history. Model the
        -- production HTTPS shallow boundary directly in this isolated repository.
        writeFixture (repository </> ".git/shallow") (BSC.pack (commit ++ "\n"))
        removeFile (repository </> ".git/objects" </> take 2 parent </> drop 2 parent)
        withoutGit $ do
            runLibgit2 False repository ["rev-parse", "--verify", "HEAD^{commit}"] `shouldReturn` (commit ++ "\n")
            void (runLibgit2 False repository ["fsck", "--full", "--no-reflogs"])
            removeFile (repository </> ".git/shallow")
            runLibgit2 False repository ["fsck", "--full", "--no-reflogs"] `shouldThrow` anyIOException

    it "reports tracked edits, untracked files, ignored files and executable-bit changes" $ withGitFixture $ \_ repository _ _ -> do
        writeFixture (repository </> ".gitignore") "ignored.txt\n"
        _ <- gitCommit repository "ignore fixture"
        withoutGit $ runLibgit2 False repository statusArguments `shouldReturn` ""
        writeFixture (repository </> "package/plugin.json") "dirty manifest"
        writeFixture (repository </> "untracked.txt") "untracked"
        writeFixture (repository </> "ignored.txt") "ignored"
        setFileMode (repository </> "standalone/SKILL.md") 0o755
        dirty <- withoutGit (runLibgit2 False repository statusArguments)
        forM_ ["package/plugin.json", "untracked.txt", "ignored.txt", "standalone/SKILL.md"] $ \path ->
            dirty `shouldSatisfy` isInfixOf path

    it "rejects corrupt loose object contents instead of trusting their object filename" $ withGitFixture $ \_ repository commit _ -> do
        let object = repository </> ".git/objects" </> take 2 commit </> drop 2 commit
        setFileMode object 0o644
        BS.writeFile object "not a zlib Git object"
        withoutGit $ runLibgit2 False repository ["fsck", "--full", "--no-reflogs"] `shouldThrow` anyIOException

    it "rejects a valid compressed object stored under the wrong blob ID" $ withGitFixture $ \_ repository _ _ -> do
        writeFixture (repository </> "first blob") "first distinct blob"
        writeFixture (repository </> "second blob") "second distinct blob"
        _ <- gitCommit repository "object identity fixture"
        first <- trimLine <$> gitCommand repository ["rev-parse", "HEAD:first blob"]
        second <- trimLine <$> gitCommand repository ["rev-parse", "HEAD:second blob"]
        let object oid = repository </> ".git/objects" </> take 2 oid </> drop 2 oid
        replacement <- BS.readFile (object second)
        setFileMode (object first) 0o644
        BS.writeFile (object first) replacement
        withoutGit $ runLibgit2 False repository ["fsck", "--full", "--no-reflogs"] `shouldThrow` anyIOException

    it "rejects a missing reachable blob during object verification" $ withGitFixture $ \_ repository _ _ -> do
        oid <- trimLine <$> gitCommand repository ["rev-parse", "HEAD:package/plugin.json"]
        removeFile (repository </> ".git/objects" </> take 2 oid </> drop 2 oid)
        withoutGit $ runLibgit2 False repository ["fsck", "--full", "--no-reflogs"] `shouldThrow` anyIOException

    it "refuses dirty pinned content without repairing it or rewriting provenance" $ withGitFixture $ \base repository _ _ -> do
        (origin, root) <- fetchNativeFixture base repository
        let marker = takeDirectory (takeDirectory (absoluteText root)) </> "origin.json"
            manifest = absoluteText root </> "plugin.json"
        before <- BS.readFile marker
        BS.writeFile manifest "foreign change"
        withoutGit $ verifyGitHub base origin `shouldThrow` anyIOException
        BS.readFile manifest `shouldReturn` "foreign change"
        BS.readFile marker `shouldReturn` before

    it "rejects unsupported operations rather than falling back to the installed Git executable" $ withGitFixture $ \_ repository _ _ -> do
        -- Git itself accepts this operation. The internal native protocol must not.
        runLibgit2 False repository ["rev-parse", "HEAD"] `shouldThrow` anyIOException
        runLibgit2 False repository ["config", "--local", "core.hooksPath", "/unexpected"] `shouldThrow` anyIOException

    it "enforces network flags, canonical GitHub URLs and NUL-free inputs before transport" $ withGitFixture $ \_ repository _ _ -> do
        runLibgit2 True repository ["fsck", "--full", "--no-reflogs"] `shouldThrow` anyIOException
        runLibgit2 False repository ["ls-remote", "--get-url", "--", fixedURL] `shouldThrow` anyIOException
        forM_ [repository, "file:///tmp/fixture", "https://example.invalid/repo.git", "https://github.com/fixture-owner/fixture-repo.git\0suffix"] $ \url ->
            runLibgit2 True repository ["ls-remote", "--get-url", "--", url] `shouldThrow` anyIOException

    it "runs the default public local sync command without a Git executable on PATH" $ withGitFixture $ \base _ _ _ -> do
        withoutGit (runCommand (Sync False False))
        readSymbolicLink (base </> ".agents/skills/existing") `shouldReturn` "../../plugin/skills/existing"

fixedURL :: String
fixedURL = "https://github.com/fixture-owner/fixture-repo.git"

statusArguments :: [String]
statusArguments = ["-c", "core.fileMode=true", "status", "--porcelain", "--untracked-files=all", "--ignored"]

-- Only the fixed-URL fetch is redirected. Init, checkout, hashing, fsck and all
-- verification calls execute the production adapter, never the process runner.
fetchNativeFixture :: FilePath -> FilePath -> IO (GitHubOrigin, AbsolutePath)
fetchNativeFixture base repository = do
    typedRepository <- either (ioError . userError) pure (githubRepository "fixture-owner/fixture-repo")
    subpath <- either (ioError . userError) pure (githubSubpath "package")
    fetchGitHubWith localFetch base typedRepository Nothing subpath
  where
    localFetch network directory arguments
        | network && "fetch" `elem` arguments =
            runLibgit2LocalForTesting network directory (map (\argument -> if argument == fixedURL then repository else argument) arguments)
        | otherwise = runLibgit2 network directory arguments

offlineNative :: GitRunner
offlineNative network directory arguments
    | network = ioError (userError "offline verification attempted network access")
    | otherwise = runLibgit2 False directory arguments

withoutGit :: IO a -> IO a
withoutGit action = bracket (lookupEnv "PATH") restore $ \_ -> do
    setEnv "PATH" "/nonexistent-c-plugin-native-test-path"
    action
  where
    restore Nothing = unsetEnv "PATH"
    restore (Just value) = setEnv "PATH" value

trimLine :: String -> String
trimLine = filter (`notElem` ['\r', '\n'])
