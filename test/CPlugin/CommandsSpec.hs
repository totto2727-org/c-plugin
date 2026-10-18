{-# LANGUAGE OverloadedStrings #-}

module CPlugin.CommandsSpec (spec) where

import CPlugin.Commands (Command (..), runCommand, runCommandWith)
import CPlugin.Paths (PathKind (RegularFile, SymbolicLink), pathKind, relativeLinkTarget)
import CPlugin.Reconcile (syncLoadedLock)
import CPlugin.StateStore (readLock, writeLock)
import CPlugin.TestSupport (inEnvironment, skillBytes, withFixture, withInteractionInput, writeFixture)
import CPlugin.Types.InstalledSkill (InstalledSkill (..))
import CPlugin.Types.Lock (Lock (..), emptyLock)
import CPlugin.Types.Name (nameText)
import CPlugin.Types.Path (relativeText)
import CPlugin.Types.Plugin (Plugin (..))
import CPlugin.Types.Selection (SelectionRequest (..))
import Control.Exception (bracket)
import Control.Monad (forM_, when)
import qualified Data.ByteString as BS
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive, removeFile, withCurrentDirectory)
import System.FilePath ((</>))
import System.IO (IOMode (WriteMode), hClose, hFlush, stdout, withFile)
import System.IO.Temp (withTempDirectory)
import System.Posix.Files (createSymbolicLink, readSymbolicLink)
import Test.Hspec (Spec, anyIOException, describe, it, shouldReturn, shouldSatisfy, shouldThrow)

spec :: Spec
spec = do
    describe "command candidate persistence" $ do
        it "unknown remove selections preserve lock and ownership bytes without syncing" $ withFixture ["alpha"] $ \base lock ->
            inEnvironment base $
                assertNoMutation base lock (runCommand (SkillRemove False ["demo/unknown"]))
        it "terminal checkpoint failure makes the command fail and leaves later skills untouched" $ withFixture ["alpha", "beta"] $ \base _ -> inEnvironment base $ do
            writeFixture (base </> ".agents/c-plugin-state.json.tmp") "foreign"
            runCommand (Sync False False) `shouldThrow` anyIOException
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Nothing
            BS.readFile (base </> ".agents/c-plugin-state.json.tmp") `shouldReturn` "foreign"
        it "rejects an unsafe target before persisting a candidate" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            createDirectoryIfMissing True (base </> "outside")
            createSymbolicLink "outside" (base </> "redirected")
            before <- BS.readFile (base </> "c-plugin-lock.json")
            runCommand (TargetAdd False "redirected/skills") `shouldThrow` anyIOException
            BS.readFile (base </> "c-plugin-lock.json") `shouldReturn` before

    describe "add force scope" $ do
        it "plugin add forces selected links without replacing other registered plugin or standalone collisions" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            writePlugin (base </> "added") "added" ["selected", "unselected"]
            assertScopedForce base (base </> "added/skills/selected") (PluginAdd False "./added" (SelectItems ["selected"]) True)
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("added", "added", ["selected"]), ("demo", "plugin", ["alpha"])]
            standaloneView (base </> "c-plugin-lock.json") `shouldReturn` [("neighbor", "neighbor")]
        it "standalone add forces selected links without replacing other registered plugin or standalone collisions" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            writeFixture (base </> "selected/SKILL.md") (skillBytes "selected")
            assertScopedForce base (base </> "selected") (SkillAdd False "./selected" True)
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha"])]
            standaloneView (base </> "c-plugin-lock.json") `shouldReturn` [("neighbor", "neighbor"), ("selected", "selected")]

    describe "explicit plugin selection" $ do
        it "adds only a sorted interactive subset and does not enable siblings" $ withFixture ["alpha", "beta", "gamma"] $ \base _ -> inEnvironment base $ do
            writeLock (base </> "c-plugin-lock.json") emptyLock
            _ <- withInteractionInput "1,3\n" $ \interaction -> runCommandWith interaction (PluginAdd False "./plugin" PromptSelection False)
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha", "gamma"])]
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/gamma") `shouldReturn` Just SymbolicLink
        it "explicit skills replace the enabled set for the same plugin identity" $ withFixture ["alpha", "beta"] $ \base lock -> inEnvironment base $ do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            runCommand (PluginAdd False "./plugin" (SelectItems ["beta"]) False)
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["beta"])]
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Just SymbolicLink
        forM_ [("explicit none", SelectNone), ("explicit empty items", SelectItems [])] $ \(label, request) ->
            it (label ++ " disables all plugin skills but retains the plugin") $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
                _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
                runCommand (PluginAdd False "./plugin" request False)
                pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", [])]
                pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
        it "interactive none disables skills rather than cancelling" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            _ <- withInteractionInput "none\n" $ \interaction -> runCommandWith interaction (PluginAdd False "./plugin" PromptSelection False)
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", [])]
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
        it "all registers a plugin with no skills" $ withFixture [] $ \base _ -> inEnvironment base $ do
            writeLock (base </> "c-plugin-lock.json") emptyLock
            runCommand (PluginAdd False "./plugin" SelectAll False)
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", [])]
        it "none can register a plugin with all skills disabled" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            writeLock (base </> "c-plugin-lock.json") emptyLock
            runCommand (PluginAdd False "./plugin" SelectNone False)
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", [])]
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
        it "does not scan children when the requested root has no manifest" $ withFixture ["alpha"] $ \base lock ->
            inEnvironment base $
                assertRejectedUnchanged base lock (PluginAdd False "./" SelectAll False)
        it "rejects invalid manifests atomically" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            writeFixture (base </> "broken/plugin.json") "{invalid"
            assertRejectedUnchanged base lock (PluginAdd False "./broken" SelectAll False)
        it "rejects a selected skill that does not exist atomically" $ withFixture ["alpha"] $ \base lock ->
            inEnvironment base $
                assertRejectedUnchanged base lock (PluginAdd False "./plugin" (SelectItems ["unknown"]) False)
        it "rejects duplicate explicit skills atomically" $ withFixture ["alpha"] $ \base lock ->
            inEnvironment base $
                assertRejectedUnchanged base lock (PluginAdd False "./plugin" (SelectItems ["alpha", "alpha"]) False)
        forM_ [False, True] $ \force -> do
            it ("rejects a reused plugin name at another source, force=" ++ show force) $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
                writePlugin (base </> "duplicate") "demo" ["beta"]
                assertRejectedUnchanged base lock (PluginAdd False "./duplicate" SelectAll force)
            it ("rejects a renamed plugin at the same source, force=" ++ show force) $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
                assertNoMutation base lock $ do
                    writePlugin (base </> "plugin") "renamed" ["alpha"]
                    runCommand (PluginAdd False "./plugin" SelectAll force) `shouldThrow` anyIOException
        it "rejects a plugin source outside the lock root" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            let project = base </> "project"
            writePlugin (project </> "plugin") "demo" ["alpha"]
            writeLock (project </> "c-plugin-lock.json") lock
            withCurrentDirectory project $ assertRejectedUnchanged project lock (PluginAdd False "../plugin" SelectAll False)
        it "rejects a plugin source symlink escaping the lock root" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            let project = base </> "project"
            writePlugin (project </> "plugin") "demo" ["alpha"]
            writePlugin (base </> "outside") "outside" ["beta"]
            createSymbolicLink "../outside" (project </> "escaped")
            writeLock (project </> "c-plugin-lock.json") lock
            withCurrentDirectory project $ assertRejectedUnchanged project lock (PluginAdd False "./escaped" SelectAll False)
        it "an unchanged enabled set does not rewrite bytes or synchronize" $ withFixture ["alpha"] $ \base lock ->
            inEnvironment base $
                assertNoMutation base lock (runCommand (PluginAdd False "./plugin" SelectAll False))
        it "none on an already empty plugin does not rewrite bytes or synchronize" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            writePlugin (base </> "empty") "empty" []
            runCommand (PluginAdd False "./empty" SelectAll False)
            current <- readLock (base </> "c-plugin-lock.json")
            assertNoMutation base current (runCommand (PluginAdd False "./empty" SelectNone False))
        it "an empty interactive plugin menu cancels without registering or synchronizing" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            writePlugin (base </> "empty") "empty" []
            assertNoMutation base lock $ do
                _ <- withInteractionInput "all\n" $ \interaction -> runCommandWith interaction (PluginAdd False "./empty" PromptSelection False)
                pure ()

    describe "standalone skill commands" $ do
        it "adds a root SKILL.md without requiring any plugin manifest" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            writeFixture (base </> "standalone/SKILL.md") (skillBytes "standalone")
            runCommand (SkillAdd False "./standalone" False)
            standaloneView (base </> "c-plugin-lock.json") `shouldReturn` [("standalone", "standalone")]
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha"])]
            pathKind (base </> ".agents/skills/standalone") `shouldReturn` Just SymbolicLink
        it "rejects missing root SKILL.md rather than scanning child skills" $ withFixture ["alpha"] $ \base lock ->
            inEnvironment base $
                assertRejectedUnchanged base lock (SkillAdd False "./plugin" False)
        it "rejects invalid standalone frontmatter without mutation" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            writeFixture (base </> "standalone/SKILL.md") "---\nname: standalone\n---\n"
            assertRejectedUnchanged base lock (SkillAdd False "./standalone" False)
        it "rejects a standalone name colliding with an enabled plugin skill" $ withFixture ["alpha"] $ \base lock ->
            inEnvironment base $
                assertRejectedUnchanged base lock (SkillAdd False "./plugin/skills/alpha" False)
        it "adding an existing exact standalone identity preserves bytes and does not sync" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            writeFixture (base </> "standalone/SKILL.md") (skillBytes "standalone")
            runCommand (SkillAdd False "./standalone" False)
            current <- readLock (base </> "c-plugin-lock.json")
            assertNoMutation base current (runCommand (SkillAdd False "./standalone" False))
        it "rejects a reused standalone name at another source" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            writeFixture (base </> "first/standalone/SKILL.md") (skillBytes "standalone")
            writeFixture (base </> "second/standalone/SKILL.md") (skillBytes "standalone")
            runCommand (SkillAdd False "./first/standalone" False)
            current <- readLock (base </> "c-plugin-lock.json")
            assertRejectedUnchanged base current (SkillAdd False "./second/standalone" True)
        it "rejects escaping standalone SKILL.md without mutation" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            writeFixture (base </> "outside.md") (skillBytes "standalone")
            createDirectoryIfMissing True (base </> "standalone")
            createSymbolicLink "../outside.md" (base </> "standalone/SKILL.md")
            assertRejectedUnchanged base lock (SkillAdd False "./standalone" False)
        it "removes a bare standalone skill selection without removing plugin skills" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            writeFixture (base </> "standalone/SKILL.md") (skillBytes "standalone")
            runCommand (SkillAdd False "./standalone" False)
            runCommand (SkillRemove False ["standalone"])
            standaloneView (base </> "c-plugin-lock.json") `shouldReturn` []
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha"])]
            pathKind (base </> ".agents/skills/standalone") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink

    describe "selection command no-op boundaries" $ do
        forM_ [("plugin add", PluginAdd False "./plugin" PromptSelection False), ("plugin remove", PluginRemove False []), ("skill remove", SkillRemove False []), ("target remove", TargetRemove False [])] $ \(label, command) -> do
            it (label ++ " without noninteractive selectors rejects before mutation or sync") $ withFixture ["alpha"] $ \base lock ->
                inEnvironment base $
                    assertRejectedUnchanged base lock command
            forM_ ["\n", "q\n", "cancel\n", ""] $ \response ->
                it (label ++ " with " ++ show response ++ " preserves exact bytes and does not sync") $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
                    runCommand (TargetAdd False "extra/skills")
                    current <- readLock (base </> "c-plugin-lock.json")
                    assertNoMutation base current $ do
                        _ <- withInteractionInput response $ \interaction -> runCommandWith interaction command
                        pure ()
        forM_ [("plugin remove", PluginRemove False []), ("skill remove", SkillRemove False []), ("target remove", TargetRemove False [])] $ \(label, command) ->
            it (label ++ " with explicit none preserves exact bytes and does not sync") $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
                runCommand (TargetAdd False "extra/skills")
                current <- readLock (base </> "c-plugin-lock.json")
                assertNoMutation base current $ do
                    _ <- withInteractionInput "none\n" $ \interaction -> runCommandWith interaction command
                    pure ()
        it "explicit unknown target removal remains a no-op without syncing" $ withFixture ["alpha"] $ \base lock ->
            inEnvironment base $
                assertNoMutation base lock (runCommand (TargetRemove False ["unknown/skills"]))

    describe "typed removal selections" $ do
        it "selects a skill row without removing its plugin or sibling" $ withFixture ["alpha", "beta"] $ \base lock -> inEnvironment base $ do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            _ <- withInteractionInput "1\n" $ \interaction -> runCommandWith interaction (SkillRemove False [])
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["beta"])]
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Just SymbolicLink
        it "selects the whole plugin row and deletes all its managed links" $ withFixture ["alpha", "beta"] $ \base lock -> inEnvironment base $ do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            _ <- withInteractionInput "1\n" $ \interaction -> runCommandWith interaction (PluginRemove False [])
            readLock (base </> "c-plugin-lock.json") `shouldReturn` emptyLock
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Nothing
        it "selects one sorted target and preserves default and unselected target links" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            runCommand (TargetAdd False "z-target/skills")
            runCommand (TargetAdd False "a-target/skills")
            _ <- withInteractionInput "1\n" $ \interaction -> runCommandWith interaction (TargetRemove False [])
            targetView (base </> "c-plugin-lock.json") `shouldReturn` ["z-target/skills"]
            pathKind (base </> "a-target/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> "z-target/skills/alpha") `shouldReturn` Just SymbolicLink
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink

    describe "separate plugin and skill removal domains" $
        forM_ [False, True] $ \global -> describe (if global then "global scope" else "project scope") $ do
            it "plugin prompt lists only whole plugins, including disabled plugins" $ withRemovalScope global $ \root -> do
                writePlugin (root </> "disabled") "disabled" ["hidden"]
                runCommand (PluginAdd global "./disabled" SelectNone False)
                (_, transcript) <- withInteractionInput "q\n" $ \interaction -> runCommandWith interaction (PluginRemove global [])
                transcript `shouldSatisfy` isInfixOf "1) demo (entire plugin)"
                transcript `shouldSatisfy` isInfixOf "2) disabled (entire plugin)"
                transcript `shouldSatisfy` (not . isInfixOf "demo/alpha")
                transcript `shouldSatisfy` (not . isInfixOf "standalone (standalone skill)")
                transcript `shouldSatisfy` (not . isInfixOf "hidden")
            it "skill prompt lists enabled plugin skills and standalone skills only" $ withRemovalScope global $ \root -> do
                writePlugin (root </> "disabled") "disabled" ["hidden"]
                runCommand (PluginAdd global "./disabled" SelectNone False)
                (_, transcript) <- withInteractionInput "q\n" $ \interaction -> runCommandWith interaction (SkillRemove global [])
                transcript `shouldSatisfy` isInfixOf "1) demo/alpha"
                transcript `shouldSatisfy` isInfixOf "2) demo/beta"
                transcript `shouldSatisfy` isInfixOf "3) standalone (standalone skill)"
                transcript `shouldSatisfy` (not . isInfixOf "entire plugin")
                transcript `shouldSatisfy` (not . isInfixOf "disabled")
                transcript `shouldSatisfy` (not . isInfixOf "hidden")
            forM_ [False, True] $ \interactive -> do
                it ("removing the last plugin skill retains the disabled plugin, interactive=" ++ show interactive) $ withRemovalScope global $ \root -> do
                    if interactive
                        then do
                            _ <- withInteractionInput "1,2\n" $ \interaction -> runCommandWith interaction (SkillRemove global [])
                            pure ()
                        else runCommand (SkillRemove global ["demo/alpha", "demo/beta"])
                    pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", [])]
                    standaloneView (root </> "c-plugin-lock.json") `shouldReturn` [("standalone", "standalone")]
                    pathKind (root </> ".agents/skills/alpha") `shouldReturn` Nothing
                    pathKind (root </> ".agents/skills/beta") `shouldReturn` Nothing
                    pathKind (root </> ".agents/skills/standalone") `shouldReturn` Just SymbolicLink
                it ("plugin removal preserves unrelated standalone skills, interactive=" ++ show interactive) $ withRemovalScope global $ \root -> do
                    if interactive
                        then do
                            _ <- withInteractionInput "all\n" $ \interaction -> runCommandWith interaction (PluginRemove global [])
                            pure ()
                        else runCommand (PluginRemove global ["demo"])
                    pluginView (root </> "c-plugin-lock.json") `shouldReturn` []
                    standaloneView (root </> "c-plugin-lock.json") `shouldReturn` [("standalone", "standalone")]
                    pathKind (root </> ".agents/skills/alpha") `shouldReturn` Nothing
                    pathKind (root </> ".agents/skills/beta") `shouldReturn` Nothing
                    pathKind (root </> ".agents/skills/standalone") `shouldReturn` Just SymbolicLink
            it "interactive skill all removes skills but never unregisters plugins" $ withRemovalScope global $ \root -> do
                _ <- withInteractionInput "all\n" $ \interaction -> runCommandWith interaction (SkillRemove global [])
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", [])]
                standaloneView (root </> "c-plugin-lock.json") `shouldReturn` []
            it "only plugin remove unregisters a plugin after its last skill is disabled" $ withRemovalScope global $ \root -> do
                runCommand (SkillRemove global ["demo/alpha", "demo/beta"])
                current <- readLock (root </> "c-plugin-lock.json")
                assertBytesUnchanged root $ runCommand (SkillRemove global ["demo/alpha"])
                readLock (root </> "c-plugin-lock.json") `shouldReturn` current
                runCommand (PluginRemove global ["demo"])
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` []
                standaloneView (root </> "c-plugin-lock.json") `shouldReturn` [("standalone", "standalone")]
            forM_ [("plugin remove", PluginRemove global [], PluginRemove global ["unknown"]), ("skill remove", SkillRemove global [], SkillRemove global ["demo/unknown"])] $ \(label, command, unknown) -> do
                it (label ++ " rejects missing noninteractive selectors without mutation") $ withRemovalScope global $ \root -> do
                    current <- readLock (root </> "c-plugin-lock.json")
                    assertNoMutation root current (runCommand command `shouldThrow` anyIOException)
                it (label ++ " with unknown explicit selectors preserves exact bytes without syncing") $ withRemovalScope global $ \root -> do
                    current <- readLock (root </> "c-plugin-lock.json")
                    assertNoMutation root current (runCommand unknown)
                forM_ ["\n", "q\n", "cancel\n", "", "none\n"] $ \response ->
                    it (label ++ " with " ++ show response ++ " preserves exact bytes without syncing") $ withRemovalScope global $ \root -> do
                        current <- readLock (root </> "c-plugin-lock.json")
                        assertNoMutation root current $ do
                            _ <- withInteractionInput response $ \interaction -> runCommandWith interaction command
                            pure ()

    describe "incremental plugin skill configuration" $
        forM_ [False, True] $ \global -> describe (if global then "global scope" else "project scope") $ do
            it "enable unions selected skills and disable subtracts without replacing siblings" $ withRemovalScope global $ \root -> do
                writeFixture (root </> "plugin/skills/gamma/SKILL.md") (skillBytes "gamma")
                runCommand (PluginSkillDisable global (Just "demo") (SelectItems ["beta"]))
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha"])]
                runCommand (PluginSkillEnable global (Just "demo") (SelectItems ["gamma"]))
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha", "gamma"])]
                pathKind (root </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
                pathKind (root </> ".agents/skills/beta") `shouldReturn` Nothing
                pathKind (root </> ".agents/skills/gamma") `shouldReturn` Just SymbolicLink
                standaloneView (root </> "c-plugin-lock.json") `shouldReturn` [("standalone", "standalone")]
            it "disable all retains an empty plugin that enable all can reactivate" $ withRemovalScope global $ \root -> do
                runCommand (PluginSkillDisable global (Just "demo") SelectAll)
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", [])]
                pathKind (root </> ".agents/skills/alpha") `shouldReturn` Nothing
                pathKind (root </> ".agents/skills/beta") `shouldReturn` Nothing
                runCommand (PluginSkillEnable global (Just "demo") SelectAll)
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha", "beta"])]
                pathKind (root </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
                pathKind (root </> ".agents/skills/beta") `shouldReturn` Just SymbolicLink
            it "interactive enable shows current markers and enables only the selected disabled skill" $ withRemovalScope global $ \root -> do
                runCommand (PluginSkillDisable global (Just "demo") (SelectItems ["beta"]))
                (_, transcript) <- withInteractionInput "2\n" $ \interaction -> runCommandWith interaction (PluginSkillEnable global (Just "demo") PromptSelection)
                transcript `shouldSatisfy` isInfixOf "1) alpha [enabled]"
                transcript `shouldSatisfy` isInfixOf "2) beta [disabled]"
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha", "beta"])]
            it "interactive disable preserves siblings and explicit last-skill disable retains the plugin" $ withRemovalScope global $ \root -> do
                _ <- withInteractionInput "2\n" $ \interaction -> runCommandWith interaction (PluginSkillDisable global (Just "demo") PromptSelection)
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha"])]
                runCommand (PluginSkillDisable global (Just "demo") (SelectItems ["alpha"]))
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", [])]
                standaloneView (root </> "c-plugin-lock.json") `shouldReturn` [("standalone", "standalone")]
            it "enable rejects a standalone skill collision without persisting its candidate" $ withRemovalScope global $ \root -> do
                writeFixture (root </> "plugin/skills/standalone/SKILL.md") (skillBytes "standalone")
                current <- readLock (root </> "c-plugin-lock.json")
                assertNoMutation root current (runCommand (PluginSkillEnable global (Just "demo") (SelectItems ["standalone"])) `shouldThrow` anyIOException)
            it "enable rejects a collision with another plugin's enabled skill" $ withRemovalScope global $ \root -> do
                writePlugin (root </> "other") "other" ["gamma"]
                runCommand (PluginAdd global "./other" SelectAll False)
                writeFixture (root </> "plugin/skills/gamma/SKILL.md") (skillBytes "gamma")
                current <- readLock (root </> "c-plugin-lock.json")
                assertNoMutation root current (runCommand (PluginSkillEnable global (Just "demo") (SelectItems ["gamma"])) `shouldThrow` anyIOException)
            forM_ [("enable", PluginSkillEnable global), ("disable", PluginSkillDisable global)] $ \(label, command) -> do
                it (label ++ " rejects an empty plugin menu without rewriting state or selecting standalone skills") $ withRemovalScope global $ \root -> do
                    runCommand (PluginRemove global ["demo"])
                    BS.appendFile (root </> "c-plugin-lock.json") "\n \t"
                    BS.appendFile (root </> ".agents/c-plugin-state.json") "\n \t"
                    let standaloneLink = root </> ".agents/skills/standalone"
                    beforeLink <- readSymbolicLink standaloneLink
                    assertBytesUnchanged root $
                        withInteractionInput "all\n" (\interaction -> runCommandWith interaction (command Nothing SelectAll)) `shouldThrow` anyIOException
                    readSymbolicLink standaloneLink `shouldReturn` beforeLink
                it (label ++ " without a plugin prompts for one sorted registration and then its skills") $ withRemovalScope global $ \root -> do
                    writePlugin (root </> "aaa") "aaa" ["gamma"]
                    runCommand (PluginAdd global "./aaa" SelectNone False)
                    when (label == "enable") $
                        runCommand (PluginSkillDisable global (Just "demo") (SelectItems ["beta"]))
                    (_, transcript) <- withInteractionInput "2\n2\n" $ \interaction -> runCommandWith interaction (command Nothing PromptSelection)
                    transcript `shouldSatisfy` isInfixOf "1) aaa\n2) demo\n"
                    transcript `shouldSatisfy` isInfixOf "1) alpha [enabled]"
                    transcript `shouldSatisfy` (not . isInfixOf "entire plugin")
                    transcript `shouldSatisfy` (not . isInfixOf "standalone skill")
                    let expectedSkills = if label == "enable" then ["alpha", "beta"] else ["alpha"]
                    pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("aaa", "aaa", []), ("demo", "plugin", expectedSkills)]
                it (label ++ " retries a multi-plugin response before accepting exactly one plugin") $ withRemovalScope global $ \root -> do
                    writePlugin (root </> "aaa") "aaa" ["gamma"]
                    runCommand (PluginAdd global "./aaa" SelectNone False)
                    when (label == "enable") $
                        runCommand (PluginSkillDisable global (Just "demo") (SelectItems ["beta"]))
                    (_, transcript) <- withInteractionInput "1,2\n2\n2\n" $ \interaction -> runCommandWith interaction (command Nothing PromptSelection)
                    transcript `shouldSatisfy` ((== 2) . length . filter (== "1) aaa") . lines)
                    let expectedSkills = if label == "enable" then ["alpha", "beta"] else ["alpha"]
                    pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("aaa", "aaa", []), ("demo", "plugin", expectedSkills)]
                it (label ++ " with explicit skills prompts only for the omitted plugin") $ withRemovalScope global $ \root -> do
                    when (label == "enable") $
                        runCommand (PluginSkillDisable global (Just "demo") (SelectItems ["beta"]))
                    (_, transcript) <- withInteractionInput "1\n" $ \interaction -> runCommandWith interaction (command Nothing (SelectItems ["beta"]))
                    transcript `shouldSatisfy` isInfixOf "1) demo\n"
                    transcript `shouldSatisfy` (not . isInfixOf "alpha [enabled]")
                    let expectedSkills = if label == "enable" then ["alpha", "beta"] else ["alpha"]
                    pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", expectedSkills)]
                it (label ++ " rejects an omitted noninteractive plugin before loading an absent source") $ withRemovalScope global $ \root -> do
                    current <- readLock (root </> "c-plugin-lock.json")
                    assertNoMutation root current $ do
                        removeDirectoryRecursive (root </> "plugin")
                        runCommand (command Nothing SelectAll) `shouldThrow` anyIOException
                forM_ ["\n", "q\n", "cancel\n", "", "none\n"] $ \response ->
                    it (label ++ " plugin prompt with " ++ show response ++ " cancels without loading a source or synchronizing") $ withRemovalScope global $ \root -> do
                        current <- readLock (root </> "c-plugin-lock.json")
                        assertNoMutation root current $ do
                            removeDirectoryRecursive (root </> "plugin")
                            (_, transcript) <- withInteractionInput response $ \interaction -> runCommandWith interaction (command Nothing SelectAll)
                            transcript `shouldSatisfy` (not . isInfixOf "[enabled]")
                it (label ++ " rejects an unregistered plugin rather than registering it") $ withRemovalScope global $ \root -> do
                    current <- readLock (root </> "c-plugin-lock.json")
                    assertNoMutation root current (runCommand (command (Just "unknown") SelectAll) `shouldThrow` anyIOException)
                it (label ++ " rejects unknown skills atomically") $ withRemovalScope global $ \root -> do
                    current <- readLock (root </> "c-plugin-lock.json")
                    assertNoMutation root current (runCommand (command (Just "demo") (SelectItems ["alpha", "unknown"])) `shouldThrow` anyIOException)
                it (label ++ " rejects duplicate skill selectors atomically") $ withRemovalScope global $ \root -> do
                    current <- readLock (root </> "c-plugin-lock.json")
                    assertNoMutation root current (runCommand (command (Just "demo") (SelectItems ["alpha", "alpha"])) `shouldThrow` anyIOException)
                it (label ++ " rejects a missing source without changing configuration or links") $ withRemovalScope global $ \root -> do
                    removeDirectoryRecursive (root </> "plugin")
                    assertBytesUnchanged root (runCommand (command (Just "demo") SelectAll) `shouldThrow` anyIOException)
                    pathKind (root </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
                forM_ ["{invalid", "{\"$schema\":\"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json\",\"name\":\"renamed\"}"] $ \manifest ->
                    it (label ++ " rejects invalid or renamed manifests: " ++ show manifest) $ withRemovalScope global $ \root -> do
                        writeFixture (root </> "plugin/plugin.json") manifest
                        assertBytesUnchanged root (runCommand (command (Just "demo") SelectAll) `shouldThrow` anyIOException)
                it (label ++ " rejects missing noninteractive selection without mutation") $ withRemovalScope global $ \root -> do
                    current <- readLock (root </> "c-plugin-lock.json")
                    assertNoMutation root current (runCommand (command (Just "demo") PromptSelection) `shouldThrow` anyIOException)
                forM_ ["\n", "q\n", "cancel\n", "", "none\n"] $ \response ->
                    it (label ++ " with " ++ show response ++ " preserves exact bytes without syncing") $ withRemovalScope global $ \root -> do
                        current <- readLock (root </> "c-plugin-lock.json")
                        assertNoMutation root current $ do
                            _ <- withInteractionInput response $ \interaction -> runCommandWith interaction (command (Just "demo") PromptSelection)
                            pure ()
            it "already enabled skills are an exact-byte no-op and do not repair a missing link" $ withRemovalScope global $ \root -> do
                current <- readLock (root </> "c-plugin-lock.json")
                assertNoMutation root current (runCommand (PluginSkillEnable global (Just "demo") (SelectItems ["alpha"])))
            it "already disabled skills are an exact-byte no-op and do not repair sibling links" $ withRemovalScope global $ \root -> do
                runCommand (PluginSkillDisable global (Just "demo") (SelectItems ["beta"]))
                current <- readLock (root </> "c-plugin-lock.json")
                assertNoMutation root current (runCommand (PluginSkillDisable global (Just "demo") (SelectItems ["beta"])))
                pluginView (root </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha"])]

    describe "read-only listing commands" $
        forM_ [False, True] $ \global -> describe (if global then "global scope" else "project scope") $
            forM_ [("list", List global, pluginListing ++ "\n" ++ skillListing), ("plugin list", PluginList global, pluginListing), ("skill list", SkillList global, skillListing)] $ \(label, command, expected) -> do
                it (label ++ " lists only its selected scope including disabled plugin registrations") $ withListingScope global $ \root -> do
                    current <- readLock (root </> "c-plugin-lock.json")
                    assertNoMutation root current $ captureCommand root command `shouldReturn` expected
                it (label ++ " does not read absent sources or repair missing and foreign managed links") $ withListingScope global $ \root -> do
                    forM_ ["plugin", "disabled", "standalone"] $ \source -> removeDirectoryRecursive (root </> source)
                    removeFile (root </> ".agents/skills/alpha")
                    removeFile (root </> ".agents/skills/beta")
                    writeFixture (root </> ".agents/skills/beta") "foreign sentinel"
                    let standaloneLink = root </> ".agents/skills/standalone"
                    beforeLink <- readSymbolicLink standaloneLink
                    BS.appendFile (root </> "c-plugin-lock.json") "\n \t"
                    BS.appendFile (root </> ".agents/c-plugin-state.json") "\n \t"
                    assertBytesUnchanged root $ captureCommand root command `shouldReturn` expected
                    pathKind (root </> ".agents/skills/alpha") `shouldReturn` Nothing
                    BS.readFile (root </> ".agents/skills/beta") `shouldReturn` "foreign sentinel"
                    readSymbolicLink standaloneLink `shouldReturn` beforeLink
                it (label ++ " neither reads nor rewrites corrupt ownership state") $ withListingScope global $ \root -> do
                    writeFixture (root </> ".agents/c-plugin-state.json") "corrupt ownership sentinel"
                    assertBytesUnchanged root $ captureCommand root command `shouldReturn` expected
                it (label ++ " never initializes missing ownership state") $ withListingScope global $ \root -> do
                    removeFile (root </> ".agents/c-plugin-state.json")
                    before <- BS.readFile (root </> "c-plugin-lock.json")
                    captureCommand root command `shouldReturn` expected
                    BS.readFile (root </> "c-plugin-lock.json") `shouldReturn` before
                    pathKind (root </> ".agents/c-plugin-state.json") `shouldReturn` Nothing
                it (label ++ " rejects a missing lock without creating configuration or ownership state") $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
                    removeFile (base </> "c-plugin-lock.json")
                    runCommand command `shouldThrow` anyIOException
                    pathKind (base </> "c-plugin-lock.json") `shouldReturn` Nothing
                    pathKind (base </> ".agents/c-plugin-state.json") `shouldReturn` Nothing
                    pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
                it (label ++ " rejects a corrupt lock without rewriting lock or ownership bytes") $ withListingScope global $ \root -> do
                    writeFixture (root </> "c-plugin-lock.json") "corrupt lock sentinel"
                    assertBytesUnchanged root (runCommand command `shouldThrow` anyIOException)
                it (label ++ " renders empty sections without initializing state") $ withFixture [] $ \base _ -> inEnvironment base $ do
                    writeLock (base </> "c-plugin-lock.json") emptyLock
                    before <- BS.readFile (base </> "c-plugin-lock.json")
                    let emptyPlugins = "Plugins\nname\tsource\tenabled-skills\n"
                        emptySkills = "Skills\nname\towner\tsource\n"
                        emptyExpected = case command of
                            List _ -> emptyPlugins ++ "\n" ++ emptySkills
                            PluginList _ -> emptyPlugins
                            _ -> emptySkills
                    captureCommand base command `shouldReturn` emptyExpected
                    BS.readFile (base </> "c-plugin-lock.json") `shouldReturn` before
                    pathKind (base </> ".agents/c-plugin-state.json") `shouldReturn` Nothing

    describe "global selection scope" $ do
        it "adds a plugin to HOME's lock rather than the nearer project lock" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            let project = base </> "project"
            writePlugin (base </> "child") "other" ["gamma"]
            writeFixture (project </> "child/plugin.json") "invalid cwd-relative decoy"
            writeLock (project </> "c-plugin-lock.json") emptyLock
            localBytes <- BS.readFile (project </> "c-plugin-lock.json")
            withCurrentDirectory project $ runCommand (PluginAdd True "./child" SelectAll False)
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha"]), ("other", "child", ["gamma"])]
            BS.readFile (project </> "c-plugin-lock.json") `shouldReturn` localBytes
            pathKind (base </> ".agents/skills/gamma") `shouldReturn` Just SymbolicLink
            pathKind (project </> ".agents/skills/gamma") `shouldReturn` Nothing
        it "adds a standalone skill to HOME's lock rather than the nearer project lock" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            let project = base </> "project"
            writeFixture (base </> "standalone/SKILL.md") (skillBytes "standalone")
            writeFixture (project </> "standalone/SKILL.md") "invalid cwd-relative decoy"
            writeLock (project </> "c-plugin-lock.json") emptyLock
            localBytes <- BS.readFile (project </> "c-plugin-lock.json")
            withCurrentDirectory project $ runCommand (SkillAdd True "./standalone" False)
            standaloneView (base </> "c-plugin-lock.json") `shouldReturn` [("standalone", "standalone")]
            BS.readFile (project </> "c-plugin-lock.json") `shouldReturn` localBytes
            pathKind (base </> ".agents/skills/standalone") `shouldReturn` Just SymbolicLink
            pathKind (project </> ".agents/skills/standalone") `shouldReturn` Nothing
        it "interactive plugin removal changes only HOME's lock and links" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            let project = base </> "project"
            writePlugin (project </> "plugin") "demo" ["alpha"]
            writeLock (project </> "c-plugin-lock.json") lock
            _ <- syncLoadedLock (project </> "c-plugin-lock.json") lock False
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            localBytes <- BS.readFile (project </> "c-plugin-lock.json")
            localState <- BS.readFile (project </> ".agents/c-plugin-state.json")
            withCurrentDirectory project $ do
                _ <- withInteractionInput "1\n" $ \interaction -> runCommandWith interaction (PluginRemove True [])
                pure ()
            readLock (base </> "c-plugin-lock.json") `shouldReturn` emptyLock
            BS.readFile (project </> "c-plugin-lock.json") `shouldReturn` localBytes
            BS.readFile (project </> ".agents/c-plugin-state.json") `shouldReturn` localState
            pathKind (project </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
        it "interactive target removal changes only HOME's targets and managed links" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            let project = base </> "project"
            writePlugin (project </> "plugin") "demo" ["alpha"]
            writeLock (project </> "c-plugin-lock.json") lock
            runCommand (TargetAdd True "extra/skills")
            withCurrentDirectory project $ runCommand (TargetAdd False "extra/skills")
            localBytes <- BS.readFile (project </> "c-plugin-lock.json")
            localState <- BS.readFile (project </> ".agents/c-plugin-state.json")
            withCurrentDirectory project $ do
                _ <- withInteractionInput "1\n" $ \interaction -> runCommandWith interaction (TargetRemove True [])
                pure ()
            targetView (base </> "c-plugin-lock.json") `shouldReturn` []
            BS.readFile (project </> "c-plugin-lock.json") `shouldReturn` localBytes
            BS.readFile (project </> ".agents/c-plugin-state.json") `shouldReturn` localState
            pathKind (base </> "extra/skills/alpha") `shouldReturn` Nothing
            pathKind (project </> "extra/skills/alpha") `shouldReturn` Just SymbolicLink

pluginListing :: String
pluginListing = "Plugins\nname\tsource\tenabled-skills\ndemo\tlocal:./plugin\talpha,beta\ndisabled\tlocal:./disabled\t-\n"

skillListing :: String
skillListing = "Skills\nname\towner\tsource\nalpha\tplugin:demo\tlocal:./plugin\nbeta\tplugin:demo\tlocal:./plugin\nstandalone\tstandalone\tlocal:./standalone\n"

withListingScope :: Bool -> (FilePath -> IO ()) -> IO ()
withListingScope global action = withRemovalScope global $ \root -> do
    writePlugin (root </> "disabled") "disabled" ["hidden"]
    runCommand (PluginAdd global "./disabled" SelectNone False)
    action root

captureCommand :: FilePath -> Command -> IO String
captureCommand root command = do
    let tempRoot = root </> "tmp"
    createDirectoryIfMissing True tempRoot
    withTempDirectory tempRoot "list-output-" $ \temporary -> do
        let output = temporary </> "stdout"
        hFlush stdout
        withFile output WriteMode $ \writer ->
            bracket (hDuplicate stdout) restore $ \_ -> do
                hDuplicateTo writer stdout
                runCommand command
        Text.unpack . Text.decodeUtf8 <$> BS.readFile output
  where
    restore saved = do
        hFlush stdout
        hDuplicateTo saved stdout
        hClose saved

withRemovalScope :: Bool -> (FilePath -> IO ()) -> IO ()
withRemovalScope global action = withFixture ["alpha", "beta"] $ \base lock -> inEnvironment base $ do
    let project = base </> "project"
        root = if global then base else project
        other = if global then project else base
    writePlugin (project </> "plugin") "demo" ["alpha", "beta"]
    writeLock (project </> "c-plugin-lock.json") lock
    forM_ [base, project] $ \scope -> withCurrentDirectory scope $ do
        writeFixture (scope </> "standalone/SKILL.md") (skillBytes "standalone")
        runCommand (SkillAdd False "./standalone" False)
    assertBytesUnchanged other $ withCurrentDirectory project (action root)
    pathKind (other </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
    pathKind (other </> ".agents/skills/beta") `shouldReturn` Just SymbolicLink
    pathKind (other </> ".agents/skills/standalone") `shouldReturn` Just SymbolicLink

assertBytesUnchanged :: FilePath -> IO () -> IO ()
assertBytesUnchanged root action = do
    let lockPath = root </> "c-plugin-lock.json"
        statePath = root </> ".agents/c-plugin-state.json"
    beforeLock <- BS.readFile lockPath
    beforeState <- BS.readFile statePath
    action
    BS.readFile lockPath `shouldReturn` beforeLock
    BS.readFile statePath `shouldReturn` beforeState

assertScopedForce :: FilePath -> FilePath -> Command -> IO ()
assertScopedForce base selectedSource command = do
    let roots = [base </> ".agents/skills", base </> "extra/skills"]
        foreignRoot = base </> "foreign"
    writeFixture (base </> "neighbor/SKILL.md") (skillBytes "neighbor")
    writeFixture (foreignRoot </> "keep") "foreign destination must remain unchanged"
    forM_ roots $ \root -> do
        writeFixture (root </> "alpha") "registered plugin collision"
        createSymbolicLink foreignRoot (root </> "neighbor")
    runCommand (SkillAdd False "./neighbor" False)
    runCommand (TargetAdd False "extra/skills")
    writeFixture (head roots </> "selected") "replace selected file"
    createSymbolicLink foreignRoot (last roots </> "selected")
    runCommand command
    forM_ roots $ \root -> do
        pathKind (root </> "selected") `shouldReturn` Just SymbolicLink
        readSymbolicLink (root </> "selected") `shouldReturn` relativeLinkTarget root selectedSource
        pathKind (root </> "alpha") `shouldReturn` Just RegularFile
        BS.readFile (root </> "alpha") `shouldReturn` "registered plugin collision"
        readSymbolicLink (root </> "neighbor") `shouldReturn` foreignRoot
        pathKind (root </> "unselected") `shouldReturn` Nothing
    BS.readFile (foreignRoot </> "keep") `shouldReturn` "foreign destination must remain unchanged"

writePlugin :: FilePath -> String -> [String] -> IO ()
writePlugin root name skills = do
    writeFixture (root </> "plugin.json") ("{\"$schema\":\"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json\",\"name\":\"" <> Text.encodeUtf8 (Text.pack name) <> "\"}")
    forM_ skills $ \skill -> writeFixture (root </> "skills" </> skill </> "SKILL.md") (skillBytes skill)

pluginView :: FilePath -> IO [(String, FilePath, [String])]
pluginView path = do
    lock <- readLock path
    pure [(nameText (pluginName plugin), relativeText (pluginSource plugin), map nameText (Set.toAscList (enabledSkills plugin))) | plugin <- Map.elems (plugins lock)]

standaloneView :: FilePath -> IO [(String, FilePath)]
standaloneView path = do
    lock <- readLock path
    pure [(nameText (installedSkillName skill), relativeText (installedSkillSource skill)) | skill <- Map.elems (standaloneSkills lock)]

targetView :: FilePath -> IO [FilePath]
targetView path = map relativeText . Set.toAscList . targets <$> readLock path

assertRejectedUnchanged :: FilePath -> Lock -> Command -> IO ()
assertRejectedUnchanged base lock command = assertNoMutation base lock (runCommand command `shouldThrow` anyIOException)

assertNoMutation :: FilePath -> Lock -> IO () -> IO ()
assertNoMutation base lock action = do
    _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
    let lockPath = base </> "c-plugin-lock.json"
        statePath = base </> ".agents/c-plugin-state.json"
        managedLink = base </> ".agents/skills/alpha"
    BS.appendFile lockPath "\n \t"
    BS.appendFile statePath "\n \t"
    beforeLock <- BS.readFile lockPath
    beforeState <- BS.readFile statePath
    removeFile managedLink
    action
    BS.readFile lockPath `shouldReturn` beforeLock
    BS.readFile statePath `shouldReturn` beforeState
    pathKind managedLink `shouldReturn` Nothing
