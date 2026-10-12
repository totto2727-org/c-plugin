{-# LANGUAGE OverloadedStrings #-}

-- Real Git repositories are used throughout this module. Only the explicit
-- fixed-HTTPS fetch transport is mapped to an isolated local fixture repository.
-- These synthetic transport checks are not real GitHub CLI acceptance coverage.
module CPlugin.GitHubSpec (spec) where

import CPlugin.Commands (Command (..), runCommand, runCommandWithGit)
import CPlugin.GitHubTestSupport (gitCommit, withGitFixture, writeRemotePlugin, writeWideFixture)
import CPlugin.Interaction (Interaction (NonInteractive))
import CPlugin.Paths (PathKind (SymbolicLink), nameIO, pathKind)
import CPlugin.Reconcile (syncLoadedLock)
import CPlugin.Source.GitHub (GitRunner, fetchGitHubWith, runGit, verifyGitHubWith)
import CPlugin.StateStore (readLock, readOwnership, writeLock)
import CPlugin.TestSupport (skillBytes, withInteractionInput, writeFixture)
import CPlugin.Types.GitHub (GitHubOrigin (..), GitHubRef, GitHubRepository, GitHubSubpath, commitText, githubRef, githubRepository, githubSource, githubSubpath)
import CPlugin.Types.InstalledSkill (installedSkillOrigin)
import CPlugin.Types.Lock (Lock (..), emptyLock, makeLock)
import CPlugin.Types.Name (nameText)
import CPlugin.Types.Ownership (OwnershipState (OwnershipState), PreviousOwnership (Trusted))
import CPlugin.Types.Path (AbsolutePath, absoluteText, relativeText)
import CPlugin.Types.Plugin (Plugin (..), makePluginWithOrigin)
import CPlugin.Types.Selection (SelectionRequest (..))
import CPlugin.Types.Sync (unavailablePlugins, unavailableSkills)
import Control.Exception (AsyncException (UserInterrupt), throwIO)
import Control.Monad (forM_, when)
import qualified Data.ByteString as BS
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (sort)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.Directory (createDirectoryIfMissing, getModificationTime, listDirectory, removeDirectoryRecursive, removeFile, withCurrentDirectory)
import System.FilePath (takeDirectory, (</>))
import System.Posix.Files (createSymbolicLink, readSymbolicLink)
import Test.Hspec (Spec, anyIOException, describe, it, shouldBe, shouldReturn, shouldSatisfy, shouldThrow)

spec :: Spec
spec = do
    describe "GitHub immutable cache using real Git and synthetic local transport" $ do
        forM_ [Nothing, Just "main", Just "v1"] $ \revision ->
            it ("pins the exact resolved commit for " ++ show revision) $ withGitFixture $ \base repository commit _ -> do
                (origin, root) <- fetchFixture repository base revision "package"
                commitText (githubOriginCommit origin) `shouldBe` commit
                absoluteText root `shouldBe` base </> relativeText (githubSource origin)
                BS.readFile (absoluteText root </> "skills/alpha/SKILL.md") `shouldReturn` "---\nname: alpha\ndescription: Test skill.\n---\n"
                verifyGitHubWith (syntheticTransport repository) base origin `shouldReturn` root
        it "accepts an explicit full commit ref and standalone subpath" $ withGitFixture $ \base repository commit _ -> do
            (origin, root) <- fetchFixture repository base (Just commit) "standalone"
            commitText (githubOriginCommit origin) `shouldBe` commit
            BS.readFile (absoluteText root </> "SKILL.md") `shouldReturn` "---\nname: standalone\ndescription: Test skill.\n---\n"
        it "reuses the immutable same-commit snapshot without rewriting its provenance or source" $ withGitFixture $ \base repository _ _ -> do
            (origin, root) <- fetchFixture repository base (Just "main") "package"
            let marker = snapshotPath base origin </> "origin.json"
                manifest = absoluteText root </> "plugin.json"
            beforeMarker <- BS.readFile marker
            beforeMarkerTime <- getModificationTime marker
            beforeSourceTime <- getModificationTime manifest
            beforeEntries <- listDirectory (snapshotPath base origin)
            fetchFixture repository base (Just "main") "package" `shouldReturn` (origin, root)
            BS.readFile marker `shouldReturn` beforeMarker
            getModificationTime marker `shouldReturn` beforeMarkerTime
            getModificationTime manifest `shouldReturn` beforeSourceTime
            listDirectory (snapshotPath base origin) `shouldReturn` beforeEntries
        it "does not adopt or delete an existing unproven snapshot directory" $ withGitFixture $ \base repository commit _ -> do
            let destination = base </> ".agents/c-plugin/sources/fixture-owner/fixture-repo" </> commit
            writeFixture (destination </> "foreign") "preserve existing cache"
            fetchFixture repository base (Just "main") "package" `shouldThrow` anyIOException
            BS.readFile (destination </> "foreign") `shouldReturn` "preserve existing cache"
            listDirectory destination `shouldReturn` ["foreign"]
        it "rejects corrupt snapshot provenance rather than replacing or adopting it" $ withGitFixture $ \base repository _ _ -> do
            (origin, root) <- fetchFixture repository base Nothing "package"
            let marker = snapshotPath base origin </> "origin.json"
            BS.writeFile marker "{corrupt"
            before <- BS.readFile (absoluteText root </> "plugin.json")
            fetchFixture repository base Nothing "package" `shouldThrow` anyIOException
            BS.readFile marker `shouldReturn` "{corrupt"
            BS.readFile (absoluteText root </> "plugin.json") `shouldReturn` before
        it "rejects a dirty cached tree without silently repairing its content" $ withGitFixture $ \base repository _ _ -> do
            (origin, root) <- fetchFixture repository base Nothing "package"
            BS.writeFile (absoluteText root </> "plugin.json") "foreign change"
            verifyGitHubWith (syntheticTransport repository) base origin `shouldThrow` anyIOException
            BS.readFile (absoluteText root </> "plugin.json") `shouldReturn` "foreign change"
        it "rejects a cache ancestry symlink before writing outside the owning root" $ withGitFixture $ \base repository _ _ -> do
            let outside = base </> "outside"
            createDirectoryIfMissing True outside
            createDirectoryIfMissing True (base </> ".agents/c-plugin")
            createSymbolicLink "../../outside" (base </> ".agents/c-plugin/sources")
            fetchFixture repository base Nothing "package" `shouldThrow` anyIOException
            listDirectory outside `shouldReturn` []
        it "rejects a selected cached subpath redirected to a physical outside directory" $ withGitFixture $ \base repository _ _ -> do
            (origin, root) <- fetchFixture repository base Nothing "package"
            let outside = base </> "outside"
            writeFixture (outside </> "keep") "untouched"
            removeDirectoryRecursive (absoluteText root)
            createSymbolicLink outside (absoluteText root)
            verifyGitHubWith (syntheticTransport repository) base origin `shouldThrow` anyIOException
            BS.readFile (outside </> "keep") `shouldReturn` "untouched"
        it "rejects escaping tracked symlinks even after ordinary entries in the NUL-delimited tree" $ withGitFixture $ \base repository _ _ -> do
            createSymbolicLink "../outside" (repository </> "zz-redirect")
            _ <- gitCommit repository "tracked symlink"
            fetchFixture repository base Nothing "package" `shouldThrow` anyIOException
        it "accepts a tracked contained documentation symlink without altering its literal target" $ withGitFixture $ \base repository _ _ -> do
            writeFixture (repository </> "AGENTS.md") "synthetic maintenance instructions"
            createSymbolicLink "AGENTS.md" (repository </> "CLAUDE.md")
            commit <- gitCommit repository "contained documentation alias"
            (origin, root) <- fetchFixture repository base Nothing "package"
            commitText (githubOriginCommit origin) `shouldBe` commit
            readSymbolicLink (takeDirectory (absoluteText root) </> "CLAUDE.md") `shouldReturn` "AGENTS.md"
            verifyGitHubWith (syntheticTransport repository) base origin `shouldReturn` root
        it "rejects a missing explicit subpath without selecting another plugin root" $ withGitFixture $ \base repository _ _ ->
            fetchFixture repository base Nothing "missing" `shouldThrow` anyIOException

    describe "bounded argv hashing of real Git regular content" $ do
        it "verifies 69 regular files in three ordered batches no larger than 32" $ withGitFixture $ \base repository _ _ -> do
            writeWideFixture repository
            _ <- gitCommit repository "wide regular content fixture"
            (origin, root) <- fetchFixture repository base Nothing "package"
            batches <- newIORef ([] :: [[FilePath]])
            let counted network directory arguments = do
                    when ("hash-object" `elem` arguments) $
                        modifyIORef' batches (++ [drop 1 (dropWhile (/= "--") arguments)])
                    syntheticTransport repository network directory arguments
            verifyGitHubWith counted base origin `shouldReturn` root
            actual <- readIORef batches
            map length actual `shouldBe` [32, 32, 5]
            concat actual `shouldBe` sort (["package/plugin.json", "package/skills/alpha/SKILL.md", "package/skills/beta/SKILL.md", "standalone/SKILL.md"] ++ ["package/content/file " ++ show index ++ ".txt" | index <- [1 .. 65 :: Int]])
        forM_ ["missing output", "extra output", "reversed output", "wrong object ID"] $ \corruption ->
            it ("rejects batch hash " ++ corruption ++ " without mutating the pinned cache") $ withGitFixture $ \base repository _ _ -> do
                writeWideFixture repository
                _ <- gitCommit repository "wide regular content fixture"
                (origin, root) <- fetchFixture repository base Nothing "package"
                beforeMarker <- BS.readFile (snapshotPath base origin </> "origin.json")
                beforeContent <- BS.readFile (absoluteText root </> "content/file 1.txt")
                let altered network directory arguments = do
                        output <- syntheticTransport repository network directory arguments
                        if "hash-object" `elem` arguments
                            then pure (corruptHashOutput corruption output)
                            else pure output
                verifyGitHubWith altered base origin `shouldThrow` anyIOException
                BS.readFile (snapshotPath base origin </> "origin.json") `shouldReturn` beforeMarker
                BS.readFile (absoluteText root </> "content/file 1.txt") `shouldReturn` beforeContent

    describe "pinned GitHub source conservative native reconciliation" $ do
        it "preserves trusted state and remaining links when the pinned cache source is missing" $ withGitFixture $ \base repository _ initial -> do
            (origin, _) <- fetchFixture repository base (Just "main") "package"
            lock <- remoteLock initial origin ["alpha", "beta"]
            writeLock (base </> "c-plugin-lock.json") lock
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            beforeLock <- BS.readFile (base </> "c-plugin-lock.json")
            beforeState <- BS.readFile (base </> ".agents/c-plugin-state.json")
            beforeLiteral <- readSymbolicLink (base </> ".agents/skills/beta")
            removeFile (base </> ".agents/skills/alpha")
            removeDirectoryRecursive (snapshotPath base origin)
            result <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            Map.size (unavailablePlugins result) `shouldBe` 1
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Just SymbolicLink
            readSymbolicLink (base </> ".agents/skills/beta") `shouldReturn` beforeLiteral
            BS.readFile (base </> "c-plugin-lock.json") `shouldReturn` beforeLock
            BS.readFile (base </> ".agents/c-plugin-state.json") `shouldReturn` beforeState
        it "preserves an owned standalone link and state when its pinned snapshot disappears" $ withGitFixture $ \base repository _ _ -> do
            runRemote repository (SkillAddGitHub False "fixture-owner/fixture-repo" (Just "main") (Just "standalone") False)
            current <- readLock (base </> "c-plugin-lock.json")
            origin <- case map installedSkillOrigin (Map.elems (standaloneSkills current)) of
                [Just value] -> pure value
                _ -> ioError (userError "standalone GitHub provenance was not persisted")
            beforeState <- BS.readFile (base </> ".agents/c-plugin-state.json")
            beforeLock <- BS.readFile (base </> "c-plugin-lock.json")
            literal <- readSymbolicLink (base </> ".agents/skills/standalone")
            removeDirectoryRecursive (snapshotPath base origin)
            result <- syncLoadedLock (base </> "c-plugin-lock.json") current False
            Map.size (unavailableSkills result) `shouldBe` 1
            readSymbolicLink (base </> ".agents/skills/standalone") `shouldReturn` literal
            BS.readFile (base </> ".agents/c-plugin-state.json") `shouldReturn` beforeState
            BS.readFile (base </> "c-plugin-lock.json") `shouldReturn` beforeLock
        it "never adopts an unrecorded matching link to a verified pinned source" $ withGitFixture $ \base repository _ initial -> do
            (origin, _) <- fetchFixture repository base (Just "main") "package"
            lock <- remoteLock initial origin ["alpha"]
            writeLock (base </> "c-plugin-lock.json") lock
            createDirectoryIfMissing True (base </> ".agents/skills")
            let literal = "../../" ++ relativeText (githubSource origin) ++ "/skills/alpha"
            createSymbolicLink literal (base </> ".agents/skills/alpha")
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            readSymbolicLink (base </> ".agents/skills/alpha") `shouldReturn` literal
            ownership <- readOwnership (base </> ".agents/c-plugin-state.json")
            case ownership of
                Trusted (OwnershipState entries) -> Map.size entries `shouldBe` 1
                _ -> ownership `shouldBe` Trusted (OwnershipState Map.empty)

    describe "remote command safety using synthetic local Git transport" $ do
        forM_ ["init", "fetch", "checkout", "rev-parse"] $ \operation ->
            it ("preserves lock, ownership and links on injected " ++ operation ++ " process failure") $ withGitFixture $ \base repository _ initial -> do
                _ <- syncLoadedLock (base </> "c-plugin-lock.json") initial False
                let failing network directory arguments
                        | operation `elem` arguments = ioError (userError ("synthetic " ++ operation ++ " process failure"))
                        | otherwise = syntheticTransport repository network directory arguments
                assertStateUnchanged base $ runCommandWithGit failing NonInteractive (remoteCommand (Just "main") SelectAll False) `shouldThrow` anyIOException
        it "preserves lock, ownership and links on asynchronous remote interruption" $ withGitFixture $ \base repository _ initial -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") initial False
            let interrupted network directory arguments
                    | network = throwIO UserInterrupt
                    | otherwise = syntheticTransport repository network directory arguments
            assertStateUnchanged base $ runCommandWithGit interrupted NonInteractive (remoteCommand Nothing SelectAll False) `shouldThrow` (== UserInterrupt)
        forM_ ["cancel\n", "\n", ""] $ \response ->
            it ("remote selection cancellation preserves all configuration and links for " ++ show response) $ withGitFixture $ \base repository _ initial -> do
                _ <- syncLoadedLock (base </> "c-plugin-lock.json") initial False
                assertStateUnchanged base $ do
                    _ <- withInteractionInput response $ \interaction -> runCommandWithGit (syntheticTransport repository) interaction (remoteCommand Nothing PromptSelection False)
                    pure ()
        it "rejects an unavailable explicit remote skill before candidate persistence" $ withGitFixture $ \base repository _ initial -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") initial False
            assertStateUnchanged base $ runRemote repository (remoteCommand Nothing (SelectItems ["unknown"]) False) `shouldThrow` anyIOException
        it "same resolved commit and selection is a byte-preserving no-op without synchronization" $ withGitFixture $ \base repository _ _ -> do
            runRemote repository (remoteCommand (Just "main") (SelectItems ["alpha"]) False)
            let lockPath = base </> "c-plugin-lock.json"
            original <- BS.readFile lockPath
            BS.writeFile lockPath (" \n" <> original)
            removeFile (base </> ".agents/skills/alpha")
            assertStateUnchanged base $ runRemote repository (remoteCommand (Just "main") (SelectItems ["alpha"]) False)
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
        it "updates a moving ref to a new immutable source while retaining logical plugin identity" $ withGitFixture $ \base repository firstCommit _ -> do
            runRemote repository (remoteCommand (Just "main") (SelectItems ["alpha"]) False)
            oldLiteral <- readSymbolicLink (base </> ".agents/skills/alpha")
            writeFixture (repository </> "package/revision.txt") "second revision"
            nextCommit <- gitCommit repository "advance main"
            nextCommit `shouldSatisfy` (/= firstCommit)
            runRemote repository (remoteCommand (Just "main") (SelectItems ["alpha"]) False)
            remote <- readRemotePlugin base
            fmap (commitText . githubOriginCommit) (pluginOrigin remote) `shouldBe` Just nextCommit
            alpha <- nameIO "alpha"
            enabledSkills remote `shouldBe` Set.singleton alpha
            newLiteral <- readSymbolicLink (base </> ".agents/skills/alpha")
            newLiteral `shouldSatisfy` (/= oldLiteral)
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Nothing
            BS.readFile (base </> ".agents/c-plugin/sources/fixture-owner/fixture-repo" </> firstCommit </> "tree/package/plugin.json") `shouldReturn` "{\"$schema\":\"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json\",\"name\":\"remote\"}"
        forM_ [False, True] $ \force -> do
            it ("rejects another requested ref as a different identity even at the same commit, force=" ++ show force) $ withGitFixture $ \base repository _ _ -> do
                runRemote repository (remoteCommand (Just "main") SelectAll False)
                assertStateUnchanged base $ runRemote repository (remoteCommand (Just "v1") SelectAll force) `shouldThrow` anyIOException
            it ("rejects remote plugin name collision with a local installed plugin, force=" ++ show force) $ withGitFixture $ \base repository _ initial -> do
                _ <- syncLoadedLock (base </> "c-plugin-lock.json") initial False
                writeRemotePlugin repository "demo" ["alpha", "beta"]
                _ <- gitCommit repository "local identity collision"
                assertStateUnchanged base $ runRemote repository (remoteCommand Nothing SelectAll force) `shouldThrow` anyIOException
        it "registers a standalone remote skill with pinned provenance and preserves a repeated exact identity" $ withGitFixture $ \base repository commit _ -> do
            let command = SkillAddGitHub False "fixture-owner/fixture-repo" (Just "main") (Just "standalone") False
            runRemote repository command
            current <- readLock (base </> "c-plugin-lock.json")
            Map.size (standaloneSkills current) `shouldBe` 1
            pathKind (base </> ".agents/skills/standalone") `shouldReturn` Just SymbolicLink
            map (fmap (commitText . githubOriginCommit) . installedSkillOrigin) (Map.elems (standaloneSkills current)) `shouldBe` [Just commit]
            assertStateUnchanged base $ runRemote repository command

    describe "offline incremental pinned GitHub plugin skills" $
        forM_ [False, True] $ \global -> describe (if global then "global scope" else "project scope") $ do
            it "uses the existing pin after the remote advances and becomes unavailable" $ withPinnedSkillScope global $ \root repository commit -> do
                writeRemotePlugin repository "renamed-upstream" ["gamma"]
                _ <- gitCommit repository "advance remote without refreshing the pin"
                removeDirectoryRecursive repository
                before <- readRemotePlugin root
                runCommand (PluginSkillEnable global (Just "remote") (SelectItems ["beta"]))
                afterEnable <- readRemotePlugin root
                pluginOrigin afterEnable `shouldBe` pluginOrigin before
                fmap (commitText . githubOriginCommit) (pluginOrigin afterEnable) `shouldBe` Just commit
                map nameText (Set.toAscList (enabledSkills afterEnable)) `shouldBe` ["alpha", "beta"]
                runCommand (PluginSkillDisable global (Just "remote") SelectAll)
                afterDisable <- readRemotePlugin root
                pluginOrigin afterDisable `shouldBe` pluginOrigin before
                enabledSkills afterDisable `shouldBe` Set.empty
                pathKind (root </> ".agents/skills/alpha") `shouldReturn` Nothing
                pathKind (root </> ".agents/skills/beta") `shouldReturn` Nothing
                pathKind (root </> ".agents/skills/standalone") `shouldReturn` Just SymbolicLink
            forM_ [("enable", PluginSkillEnable global, "alpha"), ("disable", PluginSkillDisable global, "beta")] $ \(label, command, unchangedSkill) -> do
                it (label ++ " semantic no-op retains exact bytes and never repairs a missing link") $ withPinnedSkillScope global $ \root _ _ -> do
                    removeFile (root </> ".agents/skills/alpha")
                    BS.appendFile (root </> "c-plugin-lock.json") "\n \t"
                    BS.appendFile (root </> ".agents/c-plugin-state.json") "\n \t"
                    assertStateUnchanged root $ runCommand (command (Just "remote") (SelectItems [unchangedSkill]))
                    pathKind (root </> ".agents/skills/alpha") `shouldReturn` Nothing
                it (label ++ " rejects an unknown pinned skill before changing state") $ withPinnedSkillScope global $ \root _ _ ->
                    assertStateUnchanged root (runCommand (command (Just "remote") (SelectItems ["unknown"])) `shouldThrow` anyIOException)
                forM_ ["missing snapshot", "corrupt provenance", "dirty manifest"] $ \corruption ->
                    it (label ++ " rejects " ++ corruption ++ " without replacing or fetching the pin") $ withPinnedSkillScope global $ \root repository _ -> do
                        plugin <- readRemotePlugin root
                        origin <- maybe (ioError (userError "missing fixture origin")) pure (pluginOrigin plugin)
                        let snapshot = snapshotPath root origin
                            manifest = root </> relativeText (pluginSource plugin) </> "plugin.json"
                        case corruption of
                            "missing snapshot" -> removeDirectoryRecursive snapshot
                            "corrupt provenance" -> BS.writeFile (snapshot </> "origin.json") "corrupt provenance sentinel"
                            _ -> BS.writeFile manifest "dirty manifest sentinel"
                        removeDirectoryRecursive repository
                        assertStateUnchanged root (runCommand (command (Just "remote") SelectAll) `shouldThrow` anyIOException)
                        case corruption of
                            "missing snapshot" -> pathKind snapshot `shouldReturn` Nothing
                            "corrupt provenance" -> BS.readFile (snapshot </> "origin.json") `shouldReturn` "corrupt provenance sentinel"
                            _ -> BS.readFile manifest `shouldReturn` "dirty manifest sentinel"
            it "rejects a standalone name collision without modifying the pinned plugin" $ withPinnedSkillScope global $ \root _ _ -> do
                writeFixture (root </> "beta/SKILL.md") (skillBytes "beta")
                runCommand (SkillAdd global "./beta" False)
                assertStateUnchanged root (runCommand (PluginSkillEnable global (Just "remote") (SelectItems ["beta"])) `shouldThrow` anyIOException)

    describe "top-level update and historical recursive parity with synthetic local Git" $ do
        it "updates both remote domains while retaining local plugin and standalone registrations" $ withGitFixture $ \base repository _ _ -> do
            registerRemotePair repository
            writeFixture (base </> "local/SKILL.md") (skillBytes "local")
            runRemote repository (SkillAdd False "./local" False)
            before <- readLock (base </> "c-plugin-lock.json")
            oldPluginLink <- readSymbolicLink (base </> ".agents/skills/alpha")
            oldStandaloneLink <- readSymbolicLink (base </> ".agents/skills/standalone")
            next <- advanceFixture repository
            runRemote repository (Update False False)
            after <- readLock (base </> "c-plugin-lock.json")
            remotePins after `shouldBe` [next, next]
            Map.filter ((== Nothing) . pluginOrigin) (plugins after) `shouldBe` Map.filter ((== Nothing) . pluginOrigin) (plugins before)
            Map.filter ((== Nothing) . installedSkillOrigin) (standaloneSkills after) `shouldBe` Map.filter ((== Nothing) . installedSkillOrigin) (standaloneSkills before)
            readSymbolicLink (base </> ".agents/skills/alpha") >>= (`shouldSatisfy` (/= oldPluginLink))
            readSymbolicLink (base </> ".agents/skills/standalone") >>= (`shouldSatisfy` (/= oldStandaloneLink))
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Nothing
        it "does not write a partial candidate when the second domain refresh fails" $ withGitFixture $ \base repository _ _ -> do
            registerRemotePair repository
            _ <- advanceFixture repository
            fetches <- newIORef (0 :: Int)
            let failSecond network directory arguments = do
                    if network && "fetch" `elem` arguments
                        then do
                            modifyIORef' fetches (+ 1)
                            count <- readIORef fetches
                            if count == 2 then ioError (userError "synthetic second-domain refresh failure") else syntheticTransport repository network directory arguments
                        else syntheticTransport repository network directory arguments
            assertStateUnchanged base $ runCommandWithGit failSecond NonInteractive (Update False False) `shouldThrow` anyIOException
            readIORef fetches `shouldReturn` 2
        forM_ ["plugin rename", "missing enabled skill", "standalone rename"] $ \change ->
            it ("rejects " ++ change ++ " during update without mutating the owning lock or links") $ withGitFixture $ \base repository _ _ -> do
                registerRemotePair repository
                case change of
                    "plugin rename" -> writeRemotePlugin repository "renamed" ["alpha", "beta"]
                    "missing enabled skill" -> removeFile (repository </> "package/skills/alpha/SKILL.md")
                    _ -> writeFixture (repository </> "standalone/SKILL.md") (skillBytes "renamed")
                _ <- gitCommit repository change
                assertStateUnchanged base $ runRemote repository (Update False False) `shouldThrow` anyIOException
        it "unchanged update preserves noncanonical lock bytes" $ withGitFixture $ \base repository _ _ -> do
            registerRemotePair repository
            BS.appendFile (base </> "c-plugin-lock.json") " \n\t"
            assertStateUnchanged base $ runRemote repository (Update False False)
        it "unchanged explicit update repairs missing plugin and standalone links without rewriting the lock" $ withGitFixture $ \base repository _ _ -> do
            registerRemotePair repository
            let lockPath = base </> "c-plugin-lock.json"
            BS.appendFile lockPath " \n\t"
            beforeLock <- BS.readFile lockPath
            removeFile (base </> ".agents/skills/alpha")
            removeFile (base </> ".agents/skills/standalone")
            runRemote repository (Update False False)
            BS.readFile lockPath `shouldReturn` beforeLock
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
            pathKind (base </> ".agents/skills/standalone") `shouldReturn` Just SymbolicLink
        it "offline sync keeps both existing remote pins even after the branch advances" $ withGitFixture $ \base repository commit _ -> do
            registerRemotePair repository
            _ <- advanceFixture repository
            assertStateUnchanged base $ runRemote repository (Sync False False)
            current <- readLock (base </> "c-plugin-lock.json")
            remotePins current `shouldBe` [commit, commit]
        forM_ [Sync True True, Update True True] $ \command ->
            it ("rejects global plus recursive without touching state for " ++ show command) $ withGitFixture $ \base repository _ initial -> do
                _ <- syncLoadedLock (base </> "c-plugin-lock.json") initial False
                assertStateUnchanged base $ runRemote repository command `shouldThrow` anyIOException
        it "global update refreshes HOME only and preserves the nearer project lock and links" $ withGitFixture $ \base repository commit _ -> do
            registerRemotePair repository
            let project = base </> "project"
            initializeProject project
            withCurrentDirectory project $ registerRemotePair repository
            next <- advanceFixture repository
            assertStateUnchanged project $ withCurrentDirectory project $ runRemote repository (Update True False)
            globalLock <- readLock (base </> "c-plugin-lock.json")
            projectLock <- readLock (project </> "c-plugin-lock.json")
            remotePins globalLock `shouldBe` [next, next]
            remotePins projectLock `shouldBe` [commit, commit]
        it "recursive update refreshes discovered descendant locks without following symlink directories" $ withGitFixture $ \base repository _ _ -> do
            let project = base </> "project"
                child = project </> "child"
                decoy = base </> "external-decoy"
            initializeProject project
            initializeProject child
            withCurrentDirectory project $ registerRemotePair repository
            withCurrentDirectory child $ registerRemotePair repository
            writeFixture (decoy </> "c-plugin-lock.json") "foreign invalid lock must not be read"
            createSymbolicLink decoy (project </> "redirected")
            createDirectoryIfMissing True (project </> "work/deep")
            next <- advanceFixture repository
            withCurrentDirectory (project </> "work/deep") $ runRemote repository (Update False True)
            rootLock <- readLock (project </> "c-plugin-lock.json")
            childLock <- readLock (child </> "c-plugin-lock.json")
            remotePins rootLock `shouldBe` [next, next]
            remotePins childLock `shouldBe` [next, next]
            BS.readFile (decoy </> "c-plugin-lock.json") `shouldReturn` "foreign invalid lock must not be read"
            pathKind (decoy </> ".agents") `shouldReturn` Nothing
        it "nonrecursive update refreshes only the nearest lock and leaves descendants untouched" $ withGitFixture $ \base repository commit _ -> do
            let project = base </> "project"
                child = project </> "child"
            initializeProject project
            initializeProject child
            withCurrentDirectory project $ registerRemotePair repository
            withCurrentDirectory child $ registerRemotePair repository
            next <- advanceFixture repository
            assertStateUnchanged child $ withCurrentDirectory project $ runRemote repository (Update False False)
            rootLock <- readLock (project </> "c-plugin-lock.json")
            childLock <- readLock (child </> "c-plugin-lock.json")
            remotePins rootLock `shouldBe` [next, next]
            remotePins childLock `shouldBe` [commit, commit]
        it "recursive discovery prunes nested lock files inside pinned source snapshots" $ withGitFixture $ \base repository _ _ -> do
            writeFixture (repository </> "package/nested/c-plugin-lock.json") "cached nested lock must not be discovered"
            _ <- gitCommit repository "nested source lock fixture"
            let project = base </> "project"
            initializeProject project
            withCurrentDirectory project $ registerRemotePair repository
            next <- advanceFixture repository
            withCurrentDirectory project $ runRemote repository (Update False True)
            current <- readLock (project </> "c-plugin-lock.json")
            remotePins current `shouldBe` [next, next]
            remote <- readRemotePlugin project
            BS.readFile (project </> relativeText (pluginSource remote) </> "nested/c-plugin-lock.json") `shouldReturn` "cached nested lock must not be discovered"

withPinnedSkillScope :: Bool -> (FilePath -> FilePath -> String -> IO ()) -> IO ()
withPinnedSkillScope global action = withGitFixture $ \base repository commit _ -> do
    let project = base </> "project"
        root = if global then base else project
        other = if global then project else base
    initializeProject project
    registerRemotePair repository
    withCurrentDirectory project $ registerRemotePair repository
    assertStateUnchanged other $ withCurrentDirectory project (action root repository commit)

corruptHashOutput :: String -> String -> String
corruptHashOutput corruption output = unlines $ case corruption of
    "missing output" -> drop 1 hashes
    "extra output" -> hashes ++ [replicate 40 '0']
    "reversed output" -> reverse hashes
    _ -> replicate 40 '0' : drop 1 hashes
  where
    hashes = lines output

syntheticTransport :: FilePath -> GitRunner
syntheticTransport repository network directory arguments
    | network = do
        let fixedURL = "https://github.com/fixture-owner/fixture-repo.git"
        if fixedURL `elem` arguments && "ls-remote" `elem` arguments && "--get-url" `elem` arguments
            then runGit False directory arguments
            else
                if fixedURL `elem` arguments && "fetch" `elem` arguments
                    then runGit False directory (["-c", "protocol.file.allow=always"] ++ map (\argument -> if argument == fixedURL then repository else argument) arguments)
                    else ioError (userError "synthetic test transport refused an unexpected network operation")
    | otherwise = runGit False directory arguments

fetchFixture :: FilePath -> FilePath -> Maybe String -> FilePath -> IO (GitHubOrigin, AbsolutePath)
fetchFixture repository base revision subpath = do
    (typedRepository, typedRef, typedSubpath) <- fixtureRequest revision subpath
    fetchGitHubWith (syntheticTransport repository) base typedRepository typedRef typedSubpath

fixtureRequest :: Maybe String -> FilePath -> IO (GitHubRepository, Maybe GitHubRef, GitHubSubpath)
fixtureRequest revision subpath = either (ioError . userError) pure $ do
    repository <- githubRepository "fixture-owner/fixture-repo"
    ref <- traverse githubRef revision
    path <- githubSubpath subpath
    pure (repository, ref, path)

snapshotPath :: FilePath -> GitHubOrigin -> FilePath
snapshotPath base origin = takeDirectory (takeDirectory (base </> relativeText (githubSource origin)))

remoteLock :: Lock -> GitHubOrigin -> [String] -> IO Lock
remoteLock initial origin selections = do
    name <- nameIO "remote"
    skills <- mapM nameIO selections
    plugin <- either (ioError . userError) pure (makePluginWithOrigin name (githubSource origin) skills (Just origin))
    either (ioError . userError) pure (makeLock [] (Map.elems (plugins initial) ++ [plugin]))

remoteCommand :: Maybe String -> SelectionRequest String -> Bool -> Command
remoteCommand revision = PluginAddGitHub False "fixture-owner/fixture-repo" revision (Just "package")

runRemote :: FilePath -> Command -> IO ()
runRemote repository = runCommandWithGit (syntheticTransport repository) NonInteractive

registerRemotePair :: FilePath -> IO ()
registerRemotePair repository = do
    runRemote repository (remoteCommand (Just "main") (SelectItems ["alpha"]) False)
    runRemote repository (SkillAddGitHub False "fixture-owner/fixture-repo" (Just "main") (Just "standalone") False)

advanceFixture :: FilePath -> IO String
advanceFixture repository = do
    writeFixture (repository </> "package/revision.txt") "updated plugin revision"
    writeFixture (repository </> "standalone/revision.txt") "updated standalone revision"
    gitCommit repository "advance both remote domains"

remotePins :: Lock -> [String]
remotePins lock = [commitText (githubOriginCommit origin) | Just origin <- map pluginOrigin (Map.elems (plugins lock)) ++ map installedSkillOrigin (Map.elems (standaloneSkills lock))]

initializeProject :: FilePath -> IO ()
initializeProject project = do
    createDirectoryIfMissing True project
    writeLock (project </> "c-plugin-lock.json") emptyLock

readRemotePlugin :: FilePath -> IO Plugin
readRemotePlugin base = do
    current <- readLock (base </> "c-plugin-lock.json")
    name <- nameIO "remote"
    maybe (ioError (userError "remote plugin was not registered")) pure (Map.lookup name (plugins current))

assertStateUnchanged :: FilePath -> IO () -> IO ()
assertStateUnchanged base action = do
    let lockPath = base </> "c-plugin-lock.json"
        statePath = base </> ".agents/c-plugin-state.json"
    beforeLock <- BS.readFile lockPath
    beforeState <- BS.readFile statePath
    beforeLinks <- linkSnapshot base
    action
    BS.readFile lockPath `shouldReturn` beforeLock
    BS.readFile statePath `shouldReturn` beforeState
    linkSnapshot base `shouldReturn` beforeLinks

linkSnapshot :: FilePath -> IO [(String, Maybe String)]
linkSnapshot base = do
    let directory = base </> ".agents/skills"
    entries <- sort <$> listDirectory directory
    mapM
        ( \entry -> do
            let path = directory </> entry
            kind <- pathKind path
            literal <- if kind == Just SymbolicLink then Just <$> readSymbolicLink path else pure Nothing
            pure (entry, literal)
        )
        entries
