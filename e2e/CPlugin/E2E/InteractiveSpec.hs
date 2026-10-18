module CPlugin.E2E.InteractiveSpec (spec) where

import CPlugin.E2E.Fixtures
import CPlugin.E2E.Pty
import CPlugin.E2E.Support hiding (environment)
import Control.Monad (forM_, when)
import qualified Data.ByteString.Char8 as BS
import Test.CLI.E2E (Environment, withEnvironment)
import Test.Hspec (Spec, it, parallel, shouldBe)
import Text.Printf (printf)
import Prelude hiding (readFile)

spec :: Spec
spec = parallel $ do
    it "interactive_selection" $ withEnvironment "c-plugin-e2e:local" interactiveSelectionScenario
    it "interactive_global" $ withEnvironment "c-plugin-e2e:local" interactiveGlobalScenario
    it "interactive_cancel" $ withEnvironment "c-plugin-e2e:local" interactiveCancelScenario
    it "interactive_empty" $ withEnvironment "c-plugin-e2e:local" interactiveEmptyScenario
    it "interactive_invalid" $ withEnvironment "c-plugin-e2e:local" interactiveInvalidScenario
    it "interactive_no_input" $ withEnvironment "c-plugin-e2e:local" interactiveNoInputScenario
    it "interactive_pipe" $ withEnvironment "c-plugin-e2e:local" interactivePipeScenario
    it "interactive_interrupt" $ withEnvironment "c-plugin-e2e:local" interactiveInterruptScenario
    it "interactive_eof" $ withEnvironment "c-plugin-e2e:local" interactiveEOFScenario

interactiveFixture :: Environment -> String -> IO (Scenario, String)
interactiveFixture environment name = do
    (s, project) <- standardEnvironment environment ("interactive-" ++ name) ["alpha", "beta", "gamma"]
    writePlugin s (home s) ["alpha", "beta", "gamma"]
    run s project ["init", "--global"] >>= requireSuccess
    pure (s, project)

interactiveSelectionScenario :: Environment -> IO ()
interactiveSelectionScenario environment = do
    (s, project) <- interactiveFixture environment "selection"
    globalBefore <- digest s (home s ++ "/c-plugin-lock.json")
    added <- runTerminal s project [keySpace ++ keyDown ++ keyDown ++ keySpace ++ keyEnter] False ["plugin", "add", "local:./plugin"]
    requireTerminalSuccess added
    forM_ ["alpha", "beta", "gamma"] $ \skill -> requireContains (terminalStderr added) (skill ++ " [disabled]")
    requireContains (terminalStdout added) "Added "
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha", "gamma"])
    forM_ ["alpha", "gamma"] $ \skill -> requireSymlink s (project ++ "/.agents/skills/" ++ skill) (project ++ "/plugin/skills/" ++ skill)
    requireMissing s (project ++ "/.agents/skills/beta")
    removed <- runTerminal s project [keyDown ++ keySpace ++ keyEnter] False ["skill", "remove"]
    requireTerminalSuccess removed
    requireNotContains (terminalStderr removed) "(entire plugin)"
    forM_ ["demo/alpha", "demo/gamma"] $ requireContains (terminalStderr removed)
    requireContains (terminalStdout removed) "Removed skills demo/gamma"
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha"])
    requireMissing s (project ++ "/.agents/skills/gamma")
    state <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    requireOwnershipSkill s state "gamma" False
    run s project ["target", "add", ".claude/skills"] >>= requireSuccess
    run s project ["target", "add", ".cursor/skills"] >>= requireSuccess
    target <- runTerminal s project [keyDown ++ keySpace ++ keyEnter] False ["target", "remove"]
    requireTerminalSuccess target
    forM_ [".claude/skills", ".cursor/skills"] $ requireContains (terminalStderr target)
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [".claude/skills"] "plugin" ["alpha"])
    requireMissing s (project ++ "/.cursor/skills/alpha")
    forM_ [".claude/skills", ".agents/skills"] $ \root -> requireSymlink s (project ++ "/" ++ root ++ "/alpha") (project ++ "/plugin/skills/alpha")
    stateAfter <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    requireNotContains stateAfter (project ++ "/.cursor/skills")
    requireDigest s (home s ++ "/c-plugin-lock.json") globalBefore
    requireMissing s (home s ++ "/.agents/c-plugin-state.json")

interactiveGlobalScenario :: Environment -> IO ()
interactiveGlobalScenario environment = do
    (s, project) <- interactiveFixture environment "global"
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    lockBefore <- digest s (project ++ "/c-plugin-lock.json")
    stateBefore <- digest s (project ++ "/.agents/c-plugin-state.json")
    mkdirAll s [project ++ "/nested"]
    added <- runTerminal s (project ++ "/nested") [keySpace ++ keyDown ++ keySpace ++ keyDown ++ keySpace ++ keyEnter] False ["plugin", "add", "--global", "local:./plugin"]
    requireTerminalSuccess added
    requireJSON s (home s ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha", "beta", "gamma"])
    run s project ["target", "add", "--global", ".cursor/skills"] >>= requireSuccess
    target <- runTerminal s (project ++ "/nested") [keySpace ++ keyEnter] False ["target", "remove", "--global"]
    requireTerminalSuccess target
    requireMissing s (home s ++ "/.cursor/skills/alpha")
    removed <- runTerminal s (project ++ "/nested") [keySpace ++ keyDown ++ keyDown ++ keySpace ++ keyEnter] False ["skill", "remove", "--global"]
    requireTerminalSuccess removed
    requireJSON s (home s ++ "/c-plugin-lock.json") (localLock [] "plugin" ["beta"])
    forM_ ["alpha", "gamma"] $ \skill -> requireMissing s (home s ++ "/.agents/skills/" ++ skill)
    requireSymlink s (home s ++ "/.agents/skills/beta") (home s ++ "/plugin/skills/beta")
    requireDigest s (project ++ "/c-plugin-lock.json") lockBefore
    requireDigest s (project ++ "/.agents/c-plugin-state.json") stateBefore
    forM_ ["alpha", "beta", "gamma"] $ \skill -> requireSymlink s (project ++ "/.agents/skills/" ++ skill) (project ++ "/plugin/skills/" ++ skill)

interactiveNoOp :: Scenario -> String -> [String] -> IO ()
interactiveNoOp s project actions = do
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    run s project ["target", "add", ".cursor/skills"] >>= requireSuccess
    remove s [project ++ "/.agents/skills/alpha", project ++ "/.cursor/skills/alpha"]
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    forM_ actions $ \action -> forM_ [["plugin", "add", "local:./plugin"], ["skill", "remove"], ["target", "remove"]] $ \arguments -> do
        result <- runTerminal s project [action] False arguments
        requireTerminalSuccess result
        requireContains (terminalStdout result) "Cancelled; no changes."
        requireFile s (project ++ "/c-plugin-lock.json") lock
        requireFile s (project ++ "/.agents/c-plugin-state.json") state
        requireMissing s (project ++ "/.agents/skills/alpha")
        requireMissing s (project ++ "/.cursor/skills/alpha")
        requireSymlink s (project ++ "/.agents/skills/beta") (project ++ "/plugin/skills/beta")

interactiveCancelScenario :: Environment -> IO ()
interactiveCancelScenario environment = do
    (s, project) <- interactiveFixture environment "cancel"
    interactiveNoOp s project ["q", keyEscape]

interactiveEmptyScenario :: Environment -> IO ()
interactiveEmptyScenario environment = do
    (s, project) <- interactiveFixture environment "empty"
    registered <- runTerminal s project [keyEnter] False ["plugin", "add", "local:./plugin"]
    requireTerminalSuccess registered
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" [])
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"
    forM_ ["alpha", "beta", "gamma"] $ \skill -> requireMissing s (project ++ "/.agents/skills/" ++ skill)
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    run s project ["target", "add", ".cursor/skills"] >>= requireSuccess
    remove s [project ++ "/.agents/skills/alpha", project ++ "/.cursor/skills/alpha"]
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    forM_ [keyEnter, keySpace ++ keySpace ++ keyEnter] $ \keys -> forM_ [["skill", "remove"], ["target", "remove"]] $ \arguments -> do
        result <- runTerminal s project [keys] False arguments
        requireTerminalSuccess result
        requireContains (terminalStdout result) "No selection; no changes."
        requireFile s (project ++ "/c-plugin-lock.json") lock
        requireFile s (project ++ "/.agents/c-plugin-state.json") state
        requireMissing s (project ++ "/.agents/skills/alpha")
        requireMissing s (project ++ "/.cursor/skills/alpha")
        requireSymlink s (project ++ "/.agents/skills/beta") (project ++ "/plugin/skills/beta")
    disabled <- runTerminal s project [keyEnter] False ["plugin", "add", "local:./plugin"]
    requireTerminalSuccess disabled
    forM_ ["alpha", "beta", "gamma"] $ \skill -> requireContains (terminalStderr disabled) (skill ++ " [enabled]")
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [".cursor/skills"] "plugin" [])
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"
    forM_ [".agents/skills", ".cursor/skills"] $ \root -> forM_ ["alpha", "beta", "gamma"] $ \skill -> requireMissing s (project ++ "/" ++ root ++ "/" ++ skill)
    enabled <- runTerminal s project [keyDown ++ keySpace ++ keyEnter] False ["plugin", "add", "local:./plugin"]
    requireTerminalSuccess enabled
    requireContains (terminalStderr enabled) "beta [disabled]"
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [".cursor/skills"] "plugin" ["beta"])
    changed <- runTerminal s project [keySpace ++ keyDown ++ keyDown ++ keySpace ++ keyEnter] False ["plugin", "add", "local:./plugin"]
    requireTerminalSuccess changed
    forM_ ["alpha [disabled]", "beta [enabled]", "gamma [disabled]"] $ requireContains (terminalStderr changed)
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [".cursor/skills"] "plugin" ["alpha", "gamma"])
    forM_ [".agents/skills", ".cursor/skills"] $ \root -> do
        requireMissing s (project ++ "/" ++ root ++ "/beta")
        forM_ ["alpha", "gamma"] $ \skill -> requireSymlink s (project ++ "/" ++ root ++ "/" ++ skill) (project ++ "/plugin/skills/" ++ skill)

interactiveInvalidScenario :: Environment -> IO ()
interactiveInvalidScenario environment = do
    (s, project) <- interactiveFixture environment "invalid"
    result <- runTerminal s project ["1,199xyz" ++ keySpace ++ keySpace ++ keyDown ++ keySpace ++ keyUp ++ keySpace ++ keyEnter] False ["plugin", "add", "local:./plugin"]
    requireTerminalSuccess result
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha", "beta"])
    forM_ ["alpha", "beta"] $ \skill -> requireSymlink s (project ++ "/.agents/skills/" ++ skill) (project ++ "/plugin/skills/" ++ skill)
    requireMissing s (project ++ "/.agents/skills/gamma")
    let scrollSkills = [printf "scroll-%02d" index | index <- [0 .. 49 :: Int]]
    writePlugin s project scrollSkills
    scrolled <- runTerminal s project ["<TINY>", "<TINY_CONFIRM>", concat (replicate 52 keyDown) ++ keySpace ++ keyEnter] False ["plugin", "add", "local:./plugin"]
    requireTerminalSuccess scrolled
    requireContains (terminalStderr scrolled) "scroll-49 [disabled]"
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["scroll-49"])
    requireSymlink s (project ++ "/.agents/skills/scroll-49") (project ++ "/plugin/skills/scroll-49")
    forM_ (["alpha", "beta", "gamma"] ++ take 49 scrollSkills) $ \skill -> requireMissing s (project ++ "/.agents/skills/" ++ skill)

interactiveNoInputScenario :: Environment -> IO ()
interactiveNoInputScenario environment = interactiveNonTerminal environment "no-input" False

interactivePipeScenario :: Environment -> IO ()
interactivePipeScenario environment = interactiveNonTerminal environment "pipe" True

interactiveNonTerminal :: Environment -> String -> Bool -> IO ()
interactiveNonTerminal environment name pipe = do
    (s, project) <- interactiveFixture environment name
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    run s project ["target", "add", ".cursor/skills"] >>= requireSuccess
    remove s [project ++ "/.agents/skills/alpha"]
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    forM_ [(["plugin", "add", "local:./plugin"], ["--all", "--none", "--skill"]), (["skill", "remove"], ["--skill"]), (["target", "remove"], ["--target"])] $ \(arguments, options) -> do
        result <- runTerminal s project [] pipe (["--no-input" | not pipe] ++ arguments)
        requireTerminalFailure result
        requireNotContains (terminalStderr result) selectionPrompt
        forM_ options $ requireContains (terminalStdout result)
        when pipe $ terminalUnread result `shouldBe` "unconsumed-input\n"
        requireFile s (project ++ "/c-plugin-lock.json") lock
        requireFile s (project ++ "/.agents/c-plugin-state.json") state
        requireMissing s (project ++ "/.agents/skills/alpha")

interactiveInterruptScenario :: Environment -> IO ()
interactiveInterruptScenario environment = do
    (s, project) <- interactiveFixture environment "interrupt"
    run s project ["plugin", "add", "local:./plugin", "--all"] >>= requireSuccess
    remove s [project ++ "/.agents/skills/alpha"]
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    forM_ [keyInterrupt, "<SIGINT>"] $ \action -> do
        result <- runTerminal s project [action] False ["skill", "remove"]
        requireTerminalFailure result
        requireNotContains (terminalStdout result) "Cancelled; no changes."
        requireFile s (project ++ "/c-plugin-lock.json") lock
        requireFile s (project ++ "/.agents/c-plugin-state.json") state
        requireMissing s (project ++ "/.agents/skills/alpha")
        requireSymlink s (project ++ "/.agents/skills/beta") (project ++ "/plugin/skills/beta")
    invalidTerm <- runTerminalWithTerm s project [] False "c-plugin-no-such-terminal" ["skill", "remove"]
    requireTerminalFailure invalidTerm
    requireNotContains (terminalStderr invalidTerm) selectionPrompt
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireFile s (project ++ "/.agents/c-plugin-state.json") state
    requireMissing s (project ++ "/.agents/skills/alpha")
    requireSymlink s (project ++ "/.agents/skills/beta") (project ++ "/plugin/skills/beta")

interactiveEOFScenario :: Environment -> IO ()
interactiveEOFScenario environment = do
    (s, project) <- interactiveFixture environment "eof"
    interactiveNoOp s project [keyEOF]
