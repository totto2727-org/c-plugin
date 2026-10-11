{-# LANGUAGE OverloadedStrings #-}

module CPlugin.CommandsSpec (spec) where

import CPlugin.Commands (Command (..), runCommand, runCommandWith)
import CPlugin.Paths (PathKind (SymbolicLink), pathKind)
import CPlugin.Reconcile (syncLoadedLock)
import CPlugin.StateStore (readLock, writeLock)
import CPlugin.TestSupport (inEnvironment, skillBytes, withFixture, withInteractionInput, writeFixture)
import CPlugin.Types.InstalledSkill (InstalledSkill (..))
import CPlugin.Types.Lock (Lock (..), emptyLock)
import CPlugin.Types.Name (nameText)
import CPlugin.Types.Path (relativeText)
import CPlugin.Types.Plugin (Plugin (..))
import CPlugin.Types.Selection (SelectionRequest (..))
import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import System.Directory (createDirectoryIfMissing, removeFile, withCurrentDirectory)
import System.FilePath ((</>))
import System.Posix.Files (createSymbolicLink)
import Test.Hspec (Spec, anyIOException, describe, it, shouldReturn, shouldThrow)

spec :: Spec
spec = do
    describe "command candidate persistence" $ do
        it "unknown remove selections preserve lock and ownership bytes without syncing" $ withFixture ["alpha"] $ \base lock ->
            inEnvironment base $
                assertNoMutation base lock (runCommand (Remove False [] ["demo/unknown"]))
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
            runCommand (Remove False [] ["standalone"])
            standaloneView (base </> "c-plugin-lock.json") `shouldReturn` []
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["alpha"])]
            pathKind (base </> ".agents/skills/standalone") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink

    describe "selection command no-op boundaries" $ do
        forM_ [("plugin add", PluginAdd False "./plugin" PromptSelection False), ("remove", Remove False [] []), ("target remove", TargetRemove False [])] $ \(label, command) -> do
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
        forM_ [("remove", Remove False [] []), ("target remove", TargetRemove False [])] $ \(label, command) ->
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
            _ <- withInteractionInput "2\n" $ \interaction -> runCommandWith interaction (Remove False [] [])
            pluginView (base </> "c-plugin-lock.json") `shouldReturn` [("demo", "plugin", ["beta"])]
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Just SymbolicLink
        it "selects the whole plugin row and deletes all its managed links" $ withFixture ["alpha", "beta"] $ \base lock -> inEnvironment base $ do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            _ <- withInteractionInput "1\n" $ \interaction -> runCommandWith interaction (Remove False [] [])
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
                _ <- withInteractionInput "1\n" $ \interaction -> runCommandWith interaction (Remove True [] [])
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
