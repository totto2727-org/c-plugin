{-# LANGUAGE OverloadedStrings #-}

module CPlugin.E2E.StandaloneSpec (spec) where

import CPlugin.E2E.Fixtures
import CPlugin.E2E.Support hiding (environment)
import Control.Monad (forM_)
import Test.CLI.E2E (Environment, withEnvironment)
import Test.Hspec hiding (after)
import Prelude hiding (readFile, writeFile)

spec :: Spec
spec = parallel $ do
    it "standalone_lifecycle" $ withEnvironment "c-plugin-e2e:local" standaloneLifecycle
    it "standalone_global" $ withEnvironment "c-plugin-e2e:local" standaloneGlobal
    it "explicit_root" $ withEnvironment "c-plugin-e2e:local" explicitRoot
    it "standalone_duplicate" $ withEnvironment "c-plugin-e2e:local" standaloneDuplicate
    it "standalone_unavailable" $ withEnvironment "c-plugin-e2e:local" standaloneUnavailable
    it "standalone_invalid" $ withEnvironment "c-plugin-e2e:local" standaloneInvalid
    it "standalone_escape" $ withEnvironment "c-plugin-e2e:local" standaloneEscape
    it "standalone_plugin_conflict" $ withEnvironment "c-plugin-e2e:local" standalonePluginConflict
    it "plugin_enabled_set" $ withEnvironment "c-plugin-e2e:local" pluginEnabledSet

standaloneFixture :: Environment -> String -> IO (Scenario, FilePath)
standaloneFixture environment name = do
    let fixtureHome = "/tmp/c-plugin-standalone-" ++ name ++ "/home"
        project = fixtureHome ++ "/project"
        s = newScenario environment fixtureHome
    writeFile s (project ++ "/standalone/solo/SKILL.md") (skillMarkdown "solo")
    run s project ["init"] >>= requireSuccess
    pure (s, project)

standaloneLifecycle :: Environment -> IO ()
standaloneLifecycle environment = do
    (s, project) <- standaloneFixture environment "lifecycle"
    mkdirAll s [project ++ "/nested"]
    added <- run s (project ++ "/nested") ["skill", "add", "local:./standalone/solo"]
    requireSuccess added
    requireContains (stdoutText added) ("Added skill " ++ project ++ "/standalone/solo")
    requireJSON s (project ++ "/c-plugin-lock.json") soloLock
    requireSymlink s (project ++ "/.agents/skills/solo") (project ++ "/standalone/solo")
    state0 <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    requireOwnershipSkill s state0 "solo" True
    requireMissing s (project ++ "/standalone/solo/plugin.json")
    lock <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    remove s [project ++ "/.agents/skills/solo"]
    repeated <- run s (project ++ "/nested") ["skill", "add", "local:./standalone/solo"]
    requireSuccess repeated
    requireOutput repeated ("No skill changes for " ++ project ++ "/c-plugin-lock.json\n")
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireFile s (project ++ "/.agents/c-plugin-state.json") state
    requireMissing s (project ++ "/.agents/skills/solo")
    run s project ["sync"] >>= requireSuccess
    requireSymlink s (project ++ "/.agents/skills/solo") (project ++ "/standalone/solo")
    run s (project ++ "/nested") ["skill", "remove", "--skill", "solo"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") emptyLock
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"
    requireMissing s (project ++ "/.agents/skills/solo")

standaloneGlobal :: Environment -> IO ()
standaloneGlobal environment = do
    (s, project) <- standaloneFixture environment "global"
    writeFile s (home s ++ "/standalone/solo/SKILL.md") (skillMarkdown "solo")
    run s project ["init", "--global"] >>= requireSuccess
    run s project ["skill", "add", "local:./standalone/solo"] >>= requireSuccess
    projectLock <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    projectState <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    mkdirAll s [project ++ "/nested"]
    run s (project ++ "/nested") ["skill", "add", "--global", "local:./standalone/solo"] >>= requireSuccess
    requireJSON s (home s ++ "/c-plugin-lock.json") soloLock
    requireSymlink s (home s ++ "/.agents/skills/solo") (home s ++ "/standalone/solo")
    run s (project ++ "/nested") ["skill", "remove", "--global", "--skill", "solo"] >>= requireSuccess
    requireJSON s (home s ++ "/c-plugin-lock.json") emptyLock
    requireMissing s (home s ++ "/.agents/skills/solo")
    requireFile s (project ++ "/c-plugin-lock.json") projectLock
    requireFile s (project ++ "/.agents/c-plugin-state.json") projectState
    requireSymlink s (project ++ "/.agents/skills/solo") (project ++ "/standalone/solo")

explicitRoot :: Environment -> IO ()
explicitRoot environment = do
    (s, project) <- standaloneFixture environment "explicit-root"
    writePlugin s (project ++ "/plugins") ["alpha"]
    lock <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    forM_ [["skill", "add", "local:./standalone"], ["plugin", "add", "local:./plugins", "--all"]] $ \arguments -> do
        run s project arguments >>= requireFailure
        requireFile s (project ++ "/c-plugin-lock.json") lock
        forM_ ["/.agents/c-plugin-state.json", "/.agents/skills/solo", "/.agents/skills/alpha"] $ requireMissing s . (project ++)

standaloneDuplicate :: Environment -> IO ()
standaloneDuplicate environment = do
    (s, project) <- standaloneFixture environment "duplicate"
    run s project ["skill", "add", "local:./standalone/solo"] >>= requireSuccess
    writeFile s (project ++ "/other/solo/SKILL.md") (skillMarkdown "solo")
    lock <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    run s project ["skill", "add", "local:./other/solo"] >>= requireFailure
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireFile s (project ++ "/.agents/c-plugin-state.json") state
    requireSymlink s (project ++ "/.agents/skills/solo") (project ++ "/standalone/solo")

standaloneUnavailable :: Environment -> IO ()
standaloneUnavailable environment = do
    (s, project) <- standaloneFixture environment "unavailable"
    run s project ["skill", "add", "local:./standalone/solo"] >>= requireSuccess
    lock <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    literal <- infra s "" ["readlink", project ++ "/.agents/skills/solo"]
    requireSuccess literal
    remove s [project ++ "/standalone/solo"]
    result <- run s project ["sync"]
    requireSuccess result
    requireContains (stdoutText result) "partial"
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireFile s (project ++ "/.agents/c-plugin-state.json") state
    infra s "" ["test", "-L", project ++ "/.agents/skills/solo"] >>= requireSuccess
    after <- infra s "" ["readlink", project ++ "/.agents/skills/solo"]
    requireSuccess after
    requireOutput after (stdoutText literal)

standaloneInvalid :: Environment -> IO ()
standaloneInvalid environment = do
    (s, project) <- standaloneFixture environment "invalid"
    writeFile s (project ++ "/standalone/solo/SKILL.md") "---\nname: solo\n---\n"
    writeFile s (project ++ "/.agents/skills/foreign") "foreign\n"
    lock <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    run s project ["skill", "add", "local:./standalone/solo"] >>= requireFailure
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireMissing s (project ++ "/.agents/c-plugin-state.json")
    requireMissing s (project ++ "/.agents/skills/solo")
    requireFile s (project ++ "/.agents/skills/foreign") "foreign\n"

standaloneEscape :: Environment -> IO ()
standaloneEscape environment = do
    (s, project) <- standaloneFixture environment "escape"
    let outside = home s ++ "/outside/SKILL.md"
    writeFile s outside (skillMarkdown "solo")
    checksum <- digest s outside
    remove s [project ++ "/standalone/solo/SKILL.md"]
    infra s "" ["ln", "-s", outside, project ++ "/standalone/solo/SKILL.md"] >>= requireSuccess
    lock <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    run s project ["skill", "add", "local:./standalone/solo"] >>= requireFailure
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireDigest s outside checksum
    requireSymlink s (project ++ "/standalone/solo/SKILL.md") outside
    requireMissing s (project ++ "/.agents/c-plugin-state.json")
    requireMissing s (project ++ "/.agents/skills/solo")

standalonePluginConflict :: Environment -> IO ()
standalonePluginConflict environment = do
    (s, project) <- standaloneFixture environment "plugin-conflict"
    writePlugin s project ["alpha"]
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    writeFile s (project ++ "/standalone/alpha/SKILL.md") (skillMarkdown "alpha")
    lock <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    run s project ["skill", "add", "local:./standalone/alpha"] >>= requireFailure
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireFile s (project ++ "/.agents/c-plugin-state.json") state
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")

pluginEnabledSet :: Environment -> IO ()
pluginEnabledSet environment = do
    (s, project) <- standardEnvironment environment "enabled-set" ["alpha", "beta"]
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    run s project ["plugin", "add", "local:./plugin", "--skill", "beta"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["beta"])
    requireMissing s (project ++ "/.agents/skills/alpha")
    requireSymlink s (project ++ "/.agents/skills/beta") (project ++ "/plugin/skills/beta")
    run s project ["plugin", "add", "local:./plugin", "--none"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" [])
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"
    requireMissing s (project ++ "/.agents/skills/beta")
    lock0 <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    state0 <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    repeated <- run s project ["plugin", "add", "local:./plugin", "--none"]
    requireSuccess repeated
    requireOutput repeated ("No skill changes for " ++ project ++ "/c-plugin-lock.json\n")
    requireFile s (project ++ "/c-plugin-lock.json") lock0
    requireFile s (project ++ "/.agents/c-plugin-state.json") state0
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha", "beta"])
    let checkLinks = forM_ ["alpha", "beta"] $ \skill -> requireSymlink s (project ++ "/.agents/skills/" ++ skill) (project ++ "/plugin/skills/" ++ skill)
    checkLinks
    lock <- decodeText <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    forM_ [["--all", "--skill", "alpha"], ["--all", "--none"], ["--none", "--skill", "alpha"]] $ \selectors -> do
        run s project (["plugin", "add", "local:./plugin"] ++ selectors) >>= requireFailure
        requireFile s (project ++ "/c-plugin-lock.json") lock
        requireFile s (project ++ "/.agents/c-plugin-state.json") state
        checkLinks
