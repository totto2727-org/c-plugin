{-# LANGUAGE OverloadedStrings #-}

module CPlugin.ReconcileSpec (spec) where

import CPlugin.Paths (PathKind (SymbolicLink), nameIO, pathKind, relativeIO)
import CPlugin.Reconcile (syncLoadedLock)
import CPlugin.StateStore (readOwnership, writeLock)
import CPlugin.TestSupport (manifestBytes, skillBytes, withFixture, writeFixture)
import CPlugin.Types.InstalledSkill (makeInstalledSkill)
import CPlugin.Types.Lock (emptyLock, makeLockWithSkills)
import CPlugin.Types.Ownership (OwnershipState (OwnershipState), PreviousOwnership (Trusted))
import CPlugin.Types.Sync (Notice (ReplacedPreserved, UnmanagedPreserved), SyncCompletion (Finished, Interrupted), syncCompletion, syncNotices, unavailablePlugins, unavailableSkills)
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import System.Directory (createDirectoryIfMissing, listDirectory, removeDirectoryRecursive, removeFile)
import System.FilePath ((</>))
import System.Posix.Files (createSymbolicLink, readSymbolicLink)
import Test.Hspec (Spec, anyIOException, describe, it, shouldBe, shouldReturn, shouldSatisfy, shouldThrow)

spec :: Spec
spec = do
    describe "durable ownership reconciliation" $ do
        it "creates relative symlinks, checkpoints ownership, and leaves lock bytes untouched" $ withFixture ["alpha"] $ \base lock -> do
            let lockPath = base </> "c-plugin-lock.json"
            before <- BS.readFile lockPath
            result <- syncLoadedLock lockPath lock False
            syncCompletion result `shouldBe` Finished
            literal <- readSymbolicLink (base </> ".agents/skills/alpha")
            literal `shouldBe` "../../plugin/skills/alpha"
            readOwnership (base </> ".agents/c-plugin-state.json") >>= (`shouldSatisfy` isTrusted)
            BS.readFile lockPath `shouldReturn` before
        it "never adopts an existing unowned matching symlink" $ withFixture ["alpha"] $ \base lock -> do
            createDirectoryIfMissing True (base </> ".agents/skills")
            createSymbolicLink "../../plugin/skills/alpha" (base </> ".agents/skills/alpha")
            result <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            syncNotices result `shouldSatisfy` any isUnmanaged
            readOwnership (base </> ".agents/c-plugin-state.json") `shouldReturn` Trusted (OwnershipState Map.empty)
        it "preserves existing links when ownership is corrupt" $ withFixture ["alpha"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            BS.writeFile (base </> ".agents/c-plugin-state.json") "{corrupt"
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") emptyLock False
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
        it "preserves a replaced literal symlink even when its physical target is unchanged" $ withFixture ["alpha"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            let link = base </> ".agents/skills/alpha"
            removeFile link
            createSymbolicLink (base </> "plugin/skills/alpha") link
            result <- syncLoadedLock (base </> "c-plugin-lock.json") emptyLock False
            syncNotices result `shouldSatisfy` any isReplaced
            pathKind link `shouldReturn` Just SymbolicLink
            readOwnership (base </> ".agents/c-plugin-state.json") `shouldReturn` Trusted (OwnershipState Map.empty)
        it "preserves trusted links while their plugin is unavailable" $ withFixture ["alpha"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            previous <- BS.readFile (base </> ".agents/c-plugin-state.json")
            removeFile (base </> "plugin/plugin.json")
            result <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            Map.size (unavailablePlugins result) `shouldBe` 1
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
            BS.readFile (base </> ".agents/c-plugin-state.json") `shouldReturn` previous
        it "force preserves real directories and their neighbors" $ withFixture ["alpha"] $ \base lock -> do
            writeFixture (base </> ".agents/skills/alpha/keep") "keep"
            writeFixture (base </> ".agents/skills/neighbor") "neighbor"
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock True
            BS.readFile (base </> ".agents/skills/alpha/keep") `shouldReturn` "keep"
            BS.readFile (base </> ".agents/skills/neighbor") `shouldReturn` "neighbor"
        it "force replaces only eligible direct contained regular files" $ withFixture ["alpha"] $ \base lock -> do
            writeFixture (base </> ".agents/skills/alpha") "foreign"
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock True
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
        it "force unlink checkpoint failure stops before creating the replacement or the next skill" $ withFixture ["alpha", "beta"] $ \base lock -> do
            let lockPath = base </> "c-plugin-lock.json"
            beforeLock <- BS.readFile lockPath
            writeFixture (base </> ".agents/skills/alpha") "unowned"
            writeFixture (base </> ".agents/c-plugin-state.json.tmp") "foreign checkpoint"
            result <- syncLoadedLock lockPath lock True
            syncCompletion result `shouldBe` Interrupted
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Nothing
            BS.readFile (base </> ".agents/c-plugin-state.json.tmp") `shouldReturn` "foreign checkpoint"
            BS.readFile lockPath `shouldReturn` beforeLock
        it "checkpoint failure rolls back a created link and stops before the next skill" $ withFixture ["alpha", "beta"] $ \base lock -> do
            writeFixture (base </> ".agents/c-plugin-state.json.tmp") "foreign"
            result <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            syncCompletion result `shouldBe` Interrupted
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Nothing
            BS.readFile (base </> ".agents/c-plugin-state.json.tmp") `shouldReturn` "foreign"
        it "force checkpoint failure preserves the exact existing trusted link" $ withFixture ["alpha"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            let link = base </> ".agents/skills/alpha"
            literal <- readSymbolicLink link
            state <- BS.readFile (base </> ".agents/c-plugin-state.json")
            writeFixture (base </> ".agents/c-plugin-state.json.tmp") "foreign"
            result <- syncLoadedLock (base </> "c-plugin-lock.json") lock True
            syncCompletion result `shouldBe` Interrupted
            readSymbolicLink link `shouldReturn` literal
            BS.readFile (base </> ".agents/c-plugin-state.json") `shouldReturn` state
        it "deletion checkpoint failure stops before deleting the next owned skill" $ withFixture ["alpha", "beta"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            previous <- BS.readFile (base </> ".agents/c-plugin-state.json")
            writeFixture (base </> ".agents/c-plugin-state.json.tmp") "foreign"
            result <- syncLoadedLock (base </> "c-plugin-lock.json") emptyLock False
            syncCompletion result `shouldBe` Interrupted
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Just SymbolicLink
            BS.readFile (base </> ".agents/c-plugin-state.json") `shouldReturn` previous
        it "rejects redirected managed roots before touching outside paths" $ withFixture ["alpha"] $ \base lock -> do
            createDirectoryIfMissing True (base </> "outside")
            createDirectoryIfMissing True (base </> ".agents")
            createSymbolicLink "../outside" (base </> ".agents/skills")
            syncLoadedLock (base </> "c-plugin-lock.json") lock True `shouldThrow` anyIOException
            pathKind (base </> "outside/alpha") `shouldReturn` Nothing

    describe "redirected installed source containment" $ do
        it "marks a redirected plugin unavailable without recreating missing links or changing trusted state" $ withFixture ["alpha", "beta"] $ \base lock -> do
            let project = base </> "project"
                lockPath = project </> "c-plugin-lock.json"
                statePath = project </> ".agents/c-plugin-state.json"
            writeFixture (project </> "plugin/plugin.json") (manifestBytes "")
            writeFixture (project </> "plugin/skills/alpha/SKILL.md") (skillBytes "alpha")
            writeFixture (project </> "plugin/skills/beta/SKILL.md") (skillBytes "beta")
            writeLock lockPath lock
            _ <- syncLoadedLock lockPath lock False
            beforeLock <- BS.readFile lockPath
            beforeState <- BS.readFile statePath
            betaLiteral <- readSymbolicLink (project </> ".agents/skills/beta")
            removeFile (project </> ".agents/skills/alpha")
            removeDirectoryRecursive (project </> "plugin")
            createSymbolicLink "../plugin" (project </> "plugin")
            result <- syncLoadedLock lockPath lock True
            demo <- nameIO "demo"
            syncCompletion result `shouldBe` Finished
            Map.keys (unavailablePlugins result) `shouldBe` [demo]
            pathKind (project </> ".agents/skills/alpha") `shouldReturn` Nothing
            readSymbolicLink (project </> ".agents/skills/beta") `shouldReturn` betaLiteral
            BS.readFile lockPath `shouldReturn` beforeLock
            BS.readFile statePath `shouldReturn` beforeState
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
        it "preserves trusted standalone links and external source bytes without recreating missing targets after redirection" $ withFixture [] $ \base _ -> do
            let project = base </> "project"
                lockPath = project </> "c-plugin-lock.json"
                statePath = project </> ".agents/c-plugin-state.json"
            writeFixture (base </> "standalone/SKILL.md") (skillBytes "standalone")
            writeFixture (project </> "standalone/SKILL.md") (skillBytes "standalone")
            name <- nameIO "standalone"
            source <- relativeIO "standalone"
            target <- relativeIO "extra/skills"
            skill <- either (ioError . userError) pure (makeInstalledSkill name source)
            lock <- either (ioError . userError) pure (makeLockWithSkills [target] [] [skill])
            writeLock lockPath lock
            _ <- syncLoadedLock lockPath lock False
            beforeLock <- BS.readFile lockPath
            beforeState <- BS.readFile statePath
            defaultLiteral <- readSymbolicLink (project </> ".agents/skills/standalone")
            outsideBytes <- BS.readFile (base </> "standalone/SKILL.md")
            outsideEntries <- listDirectory (base </> "standalone")
            removeFile (project </> "extra/skills/standalone")
            removeDirectoryRecursive (project </> "standalone")
            createSymbolicLink "../standalone" (project </> "standalone")
            result <- syncLoadedLock lockPath lock True
            syncCompletion result `shouldBe` Finished
            Map.keys (unavailableSkills result) `shouldBe` [name]
            readSymbolicLink (project </> ".agents/skills/standalone") `shouldReturn` defaultLiteral
            pathKind (project </> "extra/skills/standalone") `shouldReturn` Nothing
            BS.readFile lockPath `shouldReturn` beforeLock
            BS.readFile statePath `shouldReturn` beforeState
            BS.readFile (base </> "standalone/SKILL.md") `shouldReturn` outsideBytes
            listDirectory (base </> "standalone") `shouldReturn` outsideEntries
            pathKind (base </> ".agents/skills/standalone") `shouldReturn` Nothing

isTrusted :: PreviousOwnership -> Bool
isTrusted (Trusted _) = True
isTrusted _ = False
isUnmanaged :: Notice -> Bool
isUnmanaged (UnmanagedPreserved _) = True
isUnmanaged _ = False
isReplaced :: Notice -> Bool
isReplaced (ReplacedPreserved _) = True
isReplaced _ = False
