module CPlugin.E2E.UnifiedSpec (spec) where

import CPlugin.E2E.Fixtures
import CPlugin.E2E.Pty
import CPlugin.E2E.Support hiding (environment)
import Control.Monad (forM_, when)
import Test.CLI.E2E (Environment, withEnvironment)
import Test.Hspec (Spec, it, parallel, shouldBe)
import Prelude hiding (writeFile)

spec :: Spec
spec = parallel $ do
    it "unified_help_hierarchy" $ withEnvironment "c-plugin-e2e:local" unifiedHelpHierarchyScenario
    it "plugin_toggle" $ withEnvironment "c-plugin-e2e:local" pluginToggleScenario
    it "separated_removal" $ withEnvironment "c-plugin-e2e:local" separatedRemovalScenario

unifiedHelpHierarchyScenario :: Environment -> IO ()
unifiedHelpHierarchyScenario environment = do
    (s, project) <- standardEnvironment environment "unified-help" ["alpha"]
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    lock <- digest s (project ++ "/c-plugin-lock.json")
    state <- digest s (project ++ "/.agents/c-plugin-state.json")
    forM_ [[], ["plugin"], ["skill"], ["target"], ["sync"], ["update"], ["list"], ["plugin", "list"], ["plugin", "remove"], ["skill", "list"], ["skill", "remove"], ["plugin", "skill", "enable"], ["plugin", "skill", "disable"], ["target", "add"], ["target", "remove"]] $ \command -> do
        result <- run s project (command ++ ["--help"])
        requireSuccess result
        requireContains (stdoutText result) "Available options:"
        requireDigest s (project ++ "/c-plugin-lock.json") lock
        requireDigest s (project ++ "/.agents/c-plugin-state.json") state
    plugin <- run s project ["plugin", "remove", "--help"]
    requireContains (stdoutText plugin) "--plugin"
    requireNotContains (stdoutText plugin) "--skill"
    skill <- run s project ["skill", "--help"]
    forM_ ["  sync", "  update", "  target"] $ requireNotContains (stdoutText skill)
    removed <- run s project ["skill", "remove", "--help"]
    requireContains (stdoutText removed) "--skill"
    requireNotContains (stdoutText removed) "--plugin"
    forM_
        [ ["skill", "sync"]
        , ["skill", "update"]
        , ["skill", "target", "add", ".cursor/skills"]
        , ["skill", "target", "remove", "--target", ".cursor/skills"]
        , ["skill", "remove", "--plugin", "demo"]
        , ["plugin", "remove", "--skill", "demo/alpha"]
        , ["target", "remove", "--plugin", "demo"]
        , ["target", "remove", "--skill", "alpha"]
        , ["list", "--skill", "alpha"]
        , ["plugin", "list", "--plugin", "demo"]
        , ["skill", "list", "--skill", "alpha"]
        , ["sync", "--skill", "alpha"]
        , ["update", "--plugin", "demo"]
        ]
        $ \arguments -> do
            run s project arguments >>= requireFailure
            requireDigest s (project ++ "/c-plugin-lock.json") lock
            requireDigest s (project ++ "/.agents/c-plugin-state.json") state
            requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
            requireMissing s (project ++ "/.cursor")

pluginToggleScenario :: Environment -> IO ()
pluginToggleScenario environment = do
    (s, project) <- standardEnvironment environment "plugin-toggle" ["alpha", "beta", "gamma"]
    run s project ["plugin", "add", "local:./plugin", "--none"] >>= requireSuccess
    run s project ["plugin", "skill", "enable", "demo", "--skill", "beta"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["beta"])
    run s project ["plugin", "skill", "enable", "demo", "--skill", "alpha"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha", "beta"])
    forM_ ["alpha", "beta"] $ \skill -> requireSymlink s (project ++ "/.agents/skills/" ++ skill) (project ++ "/plugin/skills/" ++ skill)
    requireMissing s (project ++ "/.agents/skills/gamma")
    run s project ["plugin", "skill", "disable", "demo", "--skill", "beta"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha"])
    requireMissing s (project ++ "/.agents/skills/beta")
    remove s [project ++ "/.agents/skills/alpha"]
    lock <- digest s (project ++ "/c-plugin-lock.json")
    state <- digest s (project ++ "/.agents/c-plugin-state.json")
    forM_ [["plugin", "skill", "enable", "demo", "--skill", "alpha"], ["plugin", "skill", "disable", "demo", "--skill", "beta"]] $ \arguments -> do
        run s project arguments >>= requireSuccess
        requireDigest s (project ++ "/c-plugin-lock.json") lock
        requireDigest s (project ++ "/.agents/c-plugin-state.json") state
        requireMissing s (project ++ "/.agents/skills/alpha")
    forM_ ["enable", "disable"] $ \command -> do
        cancel <- runTerminal s project ["q"] False ["plugin", "skill", command, "demo"]
        requireTerminalSuccess cancel
        requireContains (terminalStdout cancel) "Cancelled; no changes."
        requireDigest s (project ++ "/c-plugin-lock.json") lock
        requireDigest s (project ++ "/.agents/c-plugin-state.json") state
        requireMissing s (project ++ "/.agents/skills/alpha")
        forM_ [keyEnter, keySpace ++ keySpace ++ keyEnter] $ \keys -> do
            none <- runTerminal s project [keys] False ["plugin", "skill", command, "demo"]
            requireTerminalSuccess none
            requireContains (terminalStdout none) "No skill changes for "
            requireDigest s (project ++ "/c-plugin-lock.json") lock
            requireDigest s (project ++ "/.agents/c-plugin-state.json") state
            requireMissing s (project ++ "/.agents/skills/alpha")
        forM_ [False, True] $ \pipe -> do
            failure <- runTerminal s project [] pipe (["--no-input" | not pipe] ++ ["plugin", "skill", command, "demo"])
            requireTerminalFailure failure
            requireNotContains (terminalStderr failure) selectionPrompt
            forM_ ["--skill", "--all"] $ requireContains (terminalStdout failure)
            when pipe $ terminalUnread failure `shouldBe` "unconsumed-input\n"
            requireDigest s (project ++ "/c-plugin-lock.json") lock
            requireDigest s (project ++ "/.agents/c-plugin-state.json") state
    run s project ["plugin", "skill", "disable", "demo", "--all"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" [])
    enabled <- runTerminal s project [keyDown ++ keySpace ++ keyEnter] False ["plugin", "skill", "enable", "demo"]
    requireTerminalSuccess enabled
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["beta"])
    requireSymlink s (project ++ "/.agents/skills/beta") (project ++ "/plugin/skills/beta")
    disabled <- runTerminal s project [keySpace ++ keyDown ++ keySpace ++ keyDown ++ keySpace ++ keyEnter] False ["plugin", "skill", "disable", "demo"]
    requireTerminalSuccess disabled
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" [])
    requireMissing s (project ++ "/.agents/skills/beta")
    writePlugin s (home s) ["gamma"]
    run s project ["init", "--global"] >>= requireSuccess
    run s project ["plugin", "add", "local:./plugin", "--none", "--global"] >>= requireSuccess
    mkdirAll s [project ++ "/nested"]
    lockGlobal <- digest s (project ++ "/c-plugin-lock.json")
    stateGlobal <- digest s (project ++ "/.agents/c-plugin-state.json")
    run s (project ++ "/nested") ["plugin", "skill", "enable", "demo", "--all", "-g"] >>= requireSuccess
    requireJSON s (home s ++ "/c-plugin-lock.json") (localLock [] "plugin" ["gamma"])
    requireSymlink s (home s ++ "/.agents/skills/gamma") (home s ++ "/plugin/skills/gamma")
    run s (project ++ "/nested") ["plugin", "skill", "disable", "demo", "--skill", "gamma", "-g"] >>= requireSuccess
    requireJSON s (home s ++ "/c-plugin-lock.json") (localLock [] "plugin" [])
    requireMissing s (home s ++ "/.agents/skills/gamma")
    requireDigest s (project ++ "/c-plugin-lock.json") lockGlobal
    requireDigest s (project ++ "/.agents/c-plugin-state.json") stateGlobal
    forM_
        [ ["plugin", "skill", "enable", "missing", "--all"]
        , ["plugin", "skill", "disable", "missing", "--all"]
        , ["plugin", "skill", "enable", "demo", "--skill", "unknown"]
        , ["plugin", "skill", "disable", "demo", "--skill", "unknown"]
        , ["plugin", "skill", "enable", "--all"]
        , ["plugin", "skill", "disable", "--all"]
        , ["plugin", "skill", "enable", "demo", "--none"]
        , ["plugin", "skill", "disable", "demo", "--none"]
        , ["plugin", "skill", "enable", "demo", "--all", "--skill", "alpha"]
        ]
        $ \arguments -> do
            run s project arguments >>= requireFailure
            requireDigest s (project ++ "/c-plugin-lock.json") lockGlobal
            requireDigest s (project ++ "/.agents/c-plugin-state.json") stateGlobal
    writeFile s (project ++ "/standalone/alpha/SKILL.md") (skillMarkdown "alpha")
    run s project ["skill", "add", "local:./standalone/alpha"] >>= requireSuccess
    lockStandalone <- digest s (project ++ "/c-plugin-lock.json")
    stateStandalone <- digest s (project ++ "/.agents/c-plugin-state.json")
    run s project ["plugin", "skill", "enable", "demo", "--skill", "alpha"] >>= requireFailure
    requireDigest s (project ++ "/c-plugin-lock.json") lockStandalone
    requireDigest s (project ++ "/.agents/c-plugin-state.json") stateStandalone
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/standalone/alpha")
    writeFile s (project ++ "/other/plugin.json") ("{\"$schema\":\"" ++ pluginSchema ++ "\",\"name\":\"other\"}")
    writeFile s (project ++ "/other/skills/beta/SKILL.md") (skillMarkdown "beta")
    run s project ["plugin", "add", "local:./other", "--all"] >>= requireSuccess
    lockOther <- digest s (project ++ "/c-plugin-lock.json")
    stateOther <- digest s (project ++ "/.agents/c-plugin-state.json")
    run s project ["plugin", "skill", "enable", "demo", "--skill", "beta"] >>= requireFailure
    requireDigest s (project ++ "/c-plugin-lock.json") lockOther
    requireDigest s (project ++ "/.agents/c-plugin-state.json") stateOther
    requireSymlink s (project ++ "/.agents/skills/beta") (project ++ "/other/skills/beta")
    chosen <- runTerminal s project [keySpace ++ keyDown ++ keySpace ++ keyEnter, keySpace ++ keyEnter, keyDown ++ keyDown ++ keySpace ++ keyEnter] False ["plugin", "skill", "enable"]
    requireTerminalSuccess chosen
    forM_ ["Invalid selection: choose exactly one registered plugin.", "demo", "other", "gamma [disabled]"] $ requireContains (terminalStderr chosen)
    requireNotContains (terminalStderr chosen) "(entire plugin)"
    requireSymlink s (project ++ "/.agents/skills/gamma") (project ++ "/plugin/skills/gamma")
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/standalone/alpha")
    unselected <- runTerminal s project [keySpace ++ keyEnter, keyDown ++ keyDown ++ keySpace ++ keyEnter] False ["plugin", "skill", "disable"]
    requireTerminalSuccess unselected
    requireContains (terminalStderr unselected) "gamma [enabled]"
    requireMissing s (project ++ "/.agents/skills/gamma")
    requireDigest s (project ++ "/c-plugin-lock.json") lockOther
    stateAfter <- digest s (project ++ "/.agents/c-plugin-state.json")
    forM_ ["enable", "disable"] $ \command -> forM_ [False, True] $ \pipe -> do
        failure <- runTerminal s project [] pipe (["--no-input" | not pipe] ++ ["plugin", "skill", command, "--all"])
        requireTerminalFailure failure
        requireContains (terminalStdout failure) "PLUGIN"
        requireNotContains (terminalStderr failure) selectionPrompt
        when pipe $ terminalUnread failure `shouldBe` "unconsumed-input\n"
        requireDigest s (project ++ "/c-plugin-lock.json") lockOther
        requireDigest s (project ++ "/.agents/c-plugin-state.json") stateAfter
    forM_ ["enable", "disable"] $ \command -> forM_ ["q", keyEscape, keyEOF] $ \action -> do
        cancel <- runTerminal s project [keySpace ++ keyEnter, action] False ["plugin", "skill", command]
        requireTerminalSuccess cancel
        requireContains (terminalStdout cancel) "Cancelled; no changes."
        requireContains (terminalStderr cancel) "gamma [disabled]"
        requireDigest s (project ++ "/c-plugin-lock.json") lockOther
        requireDigest s (project ++ "/.agents/c-plugin-state.json") stateAfter
        requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/standalone/alpha")
        requireSymlink s (project ++ "/.agents/skills/beta") (project ++ "/other/skills/beta")
    remove s [project ++ "/plugin"]
    forM_ ["enable", "disable"] $ \command -> do
        forM_ ["q", keyEscape, keyEOF, keyEnter] $ \action -> do
            cancel <- runTerminal s project [action] False ["plugin", "skill", command]
            requireTerminalSuccess cancel
            requireContains (terminalStdout cancel) "Cancelled; no changes."
            forM_ ["demo", "other"] $ requireContains (terminalStderr cancel)
            requireNotContains (terminalStderr cancel) "[disabled]"
            requireDigest s (project ++ "/c-plugin-lock.json") lockOther
            requireDigest s (project ++ "/.agents/c-plugin-state.json") stateAfter
            requireMissing s (project ++ "/plugin")
        run s project ["plugin", "skill", command, "demo", "--all"] >>= requireFailure
        requireDigest s (project ++ "/c-plugin-lock.json") lockOther
        requireDigest s (project ++ "/.agents/c-plugin-state.json") stateAfter
        requireMissing s (project ++ "/plugin")

separatedRemovalScenario :: Environment -> IO ()
separatedRemovalScenario environment = do
    (s, project) <- standardEnvironment environment "separated-removal" ["alpha"]
    writeFile s (project ++ "/standalone/solo/SKILL.md") (skillMarkdown "solo")
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    run s project ["skill", "add", "local:./standalone/solo"] >>= requireSuccess
    -- Exact-target links without ownership must never be adopted or deleted.
    remove s [project ++ "/.agents/c-plugin-state.json"]
    run s project ["sync"] >>= requireSuccess
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
    requireSymlink s (project ++ "/.agents/skills/solo") (project ++ "/standalone/solo")
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"
    lock <- digest s (project ++ "/c-plugin-lock.json")
    state <- digest s (project ++ "/.agents/c-plugin-state.json")
    forM_ ["q", keyEscape, keyEOF] $ \action -> do
        cancel <- runTerminal s project [action] False ["plugin", "remove"]
        requireTerminalSuccess cancel
        requireContains (terminalStderr cancel) "demo (entire plugin)"
        forM_ ["demo/alpha", "solo"] $ requireNotContains (terminalStderr cancel)
        requireContains (terminalStdout cancel) "Cancelled; no changes."
        requireDigest s (project ++ "/c-plugin-lock.json") lock
        requireDigest s (project ++ "/.agents/c-plugin-state.json") state
    forM_ [keyEnter, keySpace ++ keySpace ++ keyEnter] $ \keys -> do
        none <- runTerminal s project [keys] False ["plugin", "remove"]
        requireTerminalSuccess none
        requireContains (terminalStdout none) "No selection; no changes."
        requireDigest s (project ++ "/c-plugin-lock.json") lock
        requireDigest s (project ++ "/.agents/c-plugin-state.json") state
        requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
        requireSymlink s (project ++ "/.agents/skills/solo") (project ++ "/standalone/solo")
    removed <- runTerminal s project [keySpace ++ keyEnter] False ["skill", "remove"]
    requireTerminalSuccess removed
    forM_ ["demo/alpha", "solo (standalone skill)"] $ requireContains (terminalStderr removed)
    requireNotContains (terminalStderr removed) "(entire plugin)"
    requireJSON s (project ++ "/c-plugin-lock.json") "{\"targets\":[],\"plugins\":{\"demo\":{\"pluginName\":\"demo\",\"pluginSource\":\"plugin\",\"enabledSkills\":[],\"pluginOrigin\":null}},\"standaloneSkills\":{\"solo\":{\"installedSkillName\":\"solo\",\"installedSkillSource\":\"standalone/solo\",\"installedSkillOrigin\":null}}}"
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
    requireSymlink s (project ++ "/.agents/skills/solo") (project ++ "/standalone/solo")
    disabled <- runTerminal s project [keySpace ++ keyEnter] False ["plugin", "remove"]
    requireTerminalSuccess disabled
    requireContains (terminalStderr disabled) "demo (entire plugin)"
    requireNotContains (terminalStderr disabled) "solo"
    requireContains (terminalStdout disabled) "Removed plugins demo"
    requireJSON s (project ++ "/c-plugin-lock.json") soloLock
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
    requireSymlink s (project ++ "/.agents/skills/solo") (project ++ "/standalone/solo")
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"
    before <- digest s (project ++ "/c-plugin-lock.json")
    run s project ["plugin", "remove", "--plugin", "demo"] >>= requireSuccess
    requireDigest s (project ++ "/c-plugin-lock.json") before
    run s project ["skill", "remove", "--skill", "solo"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") emptyLock
    requireSymlink s (project ++ "/.agents/skills/solo") (project ++ "/standalone/solo")
