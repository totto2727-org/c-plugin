module CPlugin.E2E.CoreSpec (spec) where

import CPlugin.E2E.Fixtures
import CPlugin.E2E.Support
import Control.Monad (forM_)
import Data.List (isPrefixOf, tails)
import qualified Test.CLI.E2E as CLI
import Test.Hspec hiding (before, context)
import Prelude hiding (readFile, writeFile)

spec :: Spec
spec = parallel $ do
    it "error_help" $ CLI.withEnvironment "c-plugin-e2e:local" errorHelpScenario
    it "init_project" $ CLI.withEnvironment "c-plugin-e2e:local" (runInitWorkflow False)
    it "init_global" $ CLI.withEnvironment "c-plugin-e2e:local" (runInitWorkflow True)
    it "sync" $ CLI.withEnvironment "c-plugin-e2e:local" syncScenario
    it "sync_recursive" $ CLI.withEnvironment "c-plugin-e2e:local" syncRecursiveScenario
    it "add" $ CLI.withEnvironment "c-plugin-e2e:local" addScenario
    it "remove" $ CLI.withEnvironment "c-plugin-e2e:local" removeScenario
    it "target_add" $ CLI.withEnvironment "c-plugin-e2e:local" targetAddScenario
    it "target_remove" $ CLI.withEnvironment "c-plugin-e2e:local" targetRemoveScenario
    it "standard_minimal" $ CLI.withEnvironment "c-plugin-e2e:local" standardMinimalScenario
    it "standard_empty" $ CLI.withEnvironment "c-plugin-e2e:local" standardEmptyScenario
    it "standard_unknown_field" $ CLI.withEnvironment "c-plugin-e2e:local" standardUnknownFieldScenario
    it "standard_wrong_schema" $ CLI.withEnvironment "c-plugin-e2e:local" standardWrongSchemaScenario
    it "standard_invalid_skill" $ CLI.withEnvironment "c-plugin-e2e:local" standardInvalidSkillScenario
    it "standard_shallow_discovery" $ CLI.withEnvironment "c-plugin-e2e:local" standardShallowDiscoveryScenario
    it "standard_manifest_escape" $ CLI.withEnvironment "c-plugin-e2e:local" standardManifestEscapeScenario
    it "standard_skills_escape" $ CLI.withEnvironment "c-plugin-e2e:local" standardSkillsEscapeScenario
    it "standard_skill_file_escape" $ CLI.withEnvironment "c-plugin-e2e:local" standardSkillFileEscapeScenario

runInitWorkflow :: Bool -> CLI.Environment -> IO ()
runInitWorkflow global env = do
    let root = "/tmp/c-plugin-v2-init-e2e"
        homePath = root ++ "/home"
        project = root ++ "/totto2727-org/monorepo"
        lockPath = (if global then homePath else project) ++ "/c-plugin-lock.json"
        oppositeLock = (if global then project else homePath) ++ "/c-plugin-lock.json"
        initialArguments = "init" : ["-g" | global]
        repeatArguments = "init" : ["--global" | global]
    s <- newScenario env homePath
    mkdirAll s [homePath, project]
    initial <- run s project initialArguments
    requireSuccess initial
    requireOutput initial ("Created " ++ lockPath ++ "\n")
    requireJSON s lockPath emptyLock
    requireMissing s oppositeLock
    originalDigest <- digest s lockPath
    repeated <- run s project repeatArguments
    requireFailure repeated
    requireContains (stdoutText repeated) "totto2727/c-plugin.StateStoreError.AlreadyExists"
    requireDigest s lockPath originalDigest
    requireMissing s oppositeLock
    requireMissing s (project ++ "/.agents")
    requireMissing s (homePath ++ "/.agents")
    requireMissing s (homePath ++ "/.cache/c-plugin")

addScenario :: CLI.Environment -> IO ()
addScenario env = do
    let root = "/tmp/c-plugin-v2-add-e2e"
        homePath = root ++ "/home"
        project = homePath ++ "/project"
        repository = project ++ "/plugin"
        lockPath = project ++ "/c-plugin-lock.json"
        statePath = project ++ "/.agents/c-plugin-state.json"
        foreignPath = project ++ "/.agents/skills/alpha"
        link = project ++ "/.agents/skills/beta"
        addArguments = ["plugin", "add", "local:./plugin", "--skill", "alpha", "--skill", "beta"]
    s <- newScenario env homePath
    writePlugin s project ["alpha", "beta"]
    mkdirAll s [project]
    run s project ["init"] >>= requireSuccess
    writeFile s foreignPath "foreign\n"
    mkdirAll s [project ++ "/nested"]
    added <- run s (project ++ "/nested") addArguments
    requireSuccess added
    requireContains (stdoutText added) ("Added " ++ repository ++ " to " ++ lockPath ++ ": partial")
    requireJSON s lockPath (localLock [] "plugin" ["alpha", "beta"])
    requireSymlink s link (repository ++ "/skills/beta")
    requireRegularFile s foreignPath
    requireFile s foreignPath "foreign\n"
    state <- decodeText <$> readFile s statePath
    requireOwnershipSkill s state "beta" True
    requireOwnershipSkill s state "alpha" False
    beforeRepeat <- digest s lockPath
    stateBeforeRepeat <- digest s statePath
    repeated <- run s (project ++ "/nested") addArguments
    requireSuccess repeated
    requireOutput repeated ("No skill changes for " ++ lockPath ++ "\n")
    requireDigest s lockPath beforeRepeat
    requireDigest s statePath stateBeforeRepeat
    requireRegularFile s foreignPath
    requireFile s foreignPath "foreign\n"
    requireSymlink s link (repository ++ "/skills/beta")
    removed <- run s (project ++ "/nested") ["skill", "remove", "--skill", "demo/alpha", "--skill", "demo/beta"]
    requireSuccess removed
    requireRegularFile s foreignPath
    requireMissing s link
    mkdirAll s [link]
    writeFile s (link ++ "/keep") "directory-content\n"
    let neighbor = project ++ "/.agents/skills/neighbor"
    writeFile s neighbor "neighbor\n"
    forced <- run s (project ++ "/nested") (addArguments ++ ["--force"])
    requireSuccess forced
    requireContains (stdoutText forced) ("Added " ++ repository ++ " to " ++ lockPath ++ ": partial")
    requireSymlink s foreignPath (repository ++ "/skills/alpha")
    requireDirectory s link
    requireFile s (link ++ "/keep") "directory-content\n"
    requireFile s neighbor "neighbor\n"
    forcedState <- decodeText <$> readFile s statePath
    requireOwnershipSkill s forcedState "alpha" True
    requireOwnershipSkill s forcedState "beta" False

removeScenario :: CLI.Environment -> IO ()
removeScenario env = do
    let root = "/tmp/c-plugin-v2-remove-e2e"
        homePath = root ++ "/home"
        project = homePath ++ "/project"
        lockPath = project ++ "/c-plugin-lock.json"
        statePath = project ++ "/.agents/c-plugin-state.json"
        skillsRoot = project ++ "/.agents/skills"
    s <- newScenario env homePath
    writePlugin s project ["alpha", "beta"]
    writeFile s lockPath (localLock [] "plugin" ["alpha", "beta"])
    run s project ["sync"] >>= requireSuccess
    remove s [skillsRoot ++ "/alpha"]
    writeFile s (skillsRoot ++ "/alpha") "replacement\n"
    writeFile s (skillsRoot ++ "/neighbor") "foreign\n"
    lockDigest <- digest s lockPath
    stateDigest <- digest s statePath
    empty <- run s project ["skill", "remove"]
    requireFailure empty
    requireNotContains (stdoutText empty) "--plugin"
    requireContains (stdoutText empty) "--skill"
    requireDigest s lockPath lockDigest
    requireDigest s statePath stateDigest
    requireFile s (skillsRoot ++ "/alpha") "replacement\n"
    requireFile s (skillsRoot ++ "/neighbor") "foreign\n"
    requireSymlink s (skillsRoot ++ "/beta") (project ++ "/plugin/skills/beta")
    unknown <- run s project ["skill", "remove", "--skill", "demo/unknown"]
    requireSuccess unknown
    requireOutput unknown ("No skill changes for " ++ lockPath ++ "\n")
    requireDigest s lockPath lockDigest
    requireDigest s statePath stateDigest
    alpha <- run s project ["skill", "remove", "--skill", "demo/./alpha"]
    requireSuccess alpha
    requireContains (stdoutText alpha) ("Removed skills demo/alpha from " ++ lockPath ++ ": partial")
    requireJSON s lockPath (localLock [] "plugin" ["beta"])
    requireFile s (skillsRoot ++ "/alpha") "replacement\n"
    requireFile s (skillsRoot ++ "/neighbor") "foreign\n"
    requireSymlink s (skillsRoot ++ "/beta") (project ++ "/plugin/skills/beta")
    state <- decodeText <$> readFile s statePath
    requireOwnershipSkill s state "alpha" False
    requireOwnershipSkill s state "beta" True
    lockAfterAlpha <- digest s lockPath
    stateAfterAlpha <- digest s statePath
    repeated <- run s project ["skill", "remove", "--skill", "demo/alpha"]
    requireSuccess repeated
    requireOutput repeated ("No skill changes for " ++ lockPath ++ "\n")
    requireDigest s lockPath lockAfterAlpha
    requireDigest s statePath stateAfterAlpha
    beta <- run s project ["skill", "remove", "--skill", "demo/beta"]
    requireSuccess beta
    requireContains (stdoutText beta) ("Removed skills demo/beta from " ++ lockPath ++ ": complete")
    requireJSON s lockPath (localLock [] "plugin" [])
    requireMissing s (skillsRoot ++ "/beta")
    requireFile s (skillsRoot ++ "/alpha") "replacement\n"
    requireFile s (skillsRoot ++ "/neighbor") "foreign\n"
    let globalRepository = homePath ++ "/plugin"
        globalLock = homePath ++ "/c-plugin-lock.json"
        globalState = homePath ++ "/.agents/c-plugin-state.json"
    writeFile s (globalRepository ++ "/plugin.json") pluginJSON
    writeFile s (globalRepository ++ "/skills/gamma/SKILL.md") (skillMarkdown "gamma")
    writeFile s globalLock (localLock [] "plugin" ["gamma"])
    mkdirAll s [project ++ "/nested"]
    run s (project ++ "/nested") ["sync", "--global"] >>= requireSuccess
    global <- run s (project ++ "/nested") ["skill", "remove", "--global", "--skill", "demo/gamma"]
    requireSuccess global
    requireContains (stdoutText global) ("Removed skills demo/gamma from " ++ globalLock ++ ": complete")
    requireJSON s globalLock (localLock [] "plugin" [])
    requireMissing s (homePath ++ "/.agents/skills/gamma")
    globalStateText <- decodeText <$> readFile s globalState
    requireOwnershipSkill s globalStateText "gamma" False
    projectDisabled <- digest s lockPath
    deleted <- run s (project ++ "/nested") ["plugin", "remove", "--global", "--plugin", "demo"]
    requireSuccess deleted
    requireContains (stdoutText deleted) ("Removed plugins demo from " ++ globalLock ++ ": complete")
    requireJSON s globalLock emptyLock
    requireDigest s lockPath projectDisabled

syncScenario :: CLI.Environment -> IO ()
syncScenario env = do
    let root = "/tmp/c-plugin-v2-sync-e2e"
        homePath = root ++ "/home"
        project = homePath ++ "/project"
        repository = project ++ "/plugin"
        lockPath = project ++ "/c-plugin-lock.json"
        statePath = project ++ "/.agents/c-plugin-state.json"
    s <- newScenario env homePath
    writePlugin s project ["alpha", "beta"]
    writeFile s lockPath (localLock [".cursor/skills"] "plugin" ["alpha", "beta"])
    initialDigest <- digest s lockPath
    initial <- run s project ["sync"]
    requireSuccess initial
    requireContains (stdoutText initial) ("Synced " ++ lockPath ++ ": partial")
    requireDigest s lockPath initialDigest
    forM_ [project ++ "/.agents/skills", project ++ "/.cursor/skills"] $ \targetRoot ->
        forM_ ["alpha", "beta"] $ \skill -> requireSymlink s (targetRoot ++ "/" ++ skill) (repository ++ "/skills/" ++ skill)
    state <- decodeText <$> readFile s statePath
    requireOwnershipSkill s state "alpha" True
    requireOwnershipSkill s state "beta" True
    let primaryRoot = project ++ "/.agents/skills"
    remove s [primaryRoot ++ "/beta"]
    writeFile s (primaryRoot ++ "/beta") "foreign\n"
    writeFile s (primaryRoot ++ "/neighbor") "neighbor\n"
    writeFile s lockPath (localLock [".cursor/skills"] "plugin" [])
    editedDigest <- digest s lockPath
    edited <- run s project ["sync"]
    requireSuccess edited
    requireContains (stdoutText edited) ("Synced " ++ lockPath ++ ": partial")
    requireDigest s lockPath editedDigest
    requireMissing s (primaryRoot ++ "/alpha")
    requireMissing s (project ++ "/.cursor/skills/alpha")
    requireMissing s (project ++ "/.cursor/skills/beta")
    requireRegularFile s (primaryRoot ++ "/beta")
    requireFile s (primaryRoot ++ "/beta") "foreign\n"
    requireFile s (primaryRoot ++ "/neighbor") "neighbor\n"
    requireJSON s statePath "{\"ownershipEntries\":{}}"

syncRecursiveScenario :: CLI.Environment -> IO ()
syncRecursiveScenario env = do
    let root = "/tmp/c-plugin-v2-sync-recursive-e2e"
        homePath = root ++ "/home"
        project = homePath ++ "/project"
        child = project ++ "/child"
        ignored = project ++ "/ignored"
    s <- newScenario env homePath
    writePlugin s project ["alpha"]
    writePlugin s child ["beta"]
    writeFile s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha"])
    writeFile s (child ++ "/c-plugin-lock.json") (localLock [] "plugin" ["beta"])
    writeFile s (project ++ "/.gitignore") "ignored/\n"
    writeFile s (ignored ++ "/c-plugin-lock.json") "{invalid\n"
    writeFile s (project ++ "/.agents/skills/foreign") "foreign\n"
    parentDigest <- digest s (project ++ "/c-plugin-lock.json")
    childDigest <- digest s (child ++ "/c-plugin-lock.json")
    initial <- run s project ["sync", "-r"]
    requireSuccess initial
    length (filter (isPrefixOf "Synced ") (tails (stdoutText initial))) `shouldBe` 2
    requireContains (stdoutText initial) ("Synced " ++ project ++ "/c-plugin-lock.json:")
    requireContains (stdoutText initial) ("Synced " ++ child ++ "/c-plugin-lock.json:")
    requireNotContains (stdoutText initial) (ignored ++ "/c-plugin-lock.json")
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
    requireSymlink s (child ++ "/.agents/skills/beta") (child ++ "/plugin/skills/beta")
    pathExists s (project ++ "/.agents/c-plugin-state.json") >>= (`shouldBe` True)
    pathExists s (child ++ "/.agents/c-plugin-state.json") >>= (`shouldBe` True)
    requireFile s (project ++ "/.agents/skills/foreign") "foreign\n"
    requireDigest s (project ++ "/c-plugin-lock.json") parentDigest
    requireDigest s (child ++ "/c-plugin-lock.json") childDigest
    writeFile s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" [])
    editedParentDigest <- digest s (project ++ "/c-plugin-lock.json")
    edited <- run s project ["sync", "--recursive"]
    requireSuccess edited
    length (filter (isPrefixOf "Synced ") (tails (stdoutText edited))) `shouldBe` 2
    requireMissing s (project ++ "/.agents/skills/alpha")
    requireSymlink s (child ++ "/.agents/skills/beta") (child ++ "/plugin/skills/beta")
    childState <- decodeText <$> readFile s (child ++ "/.agents/c-plugin-state.json")
    requireOwnershipSkill s childState "beta" True
    requireFile s (project ++ "/.agents/skills/foreign") "foreign\n"
    requireDigest s (project ++ "/c-plugin-lock.json") editedParentDigest
    requireDigest s (child ++ "/c-plugin-lock.json") childDigest
    invalid <- run s project ["sync", "-g", "-r"]
    requireFailure invalid
    requireContains (stdoutText invalid) "totto2727/c-plugin.SyncError.Planning"

targetAddScenario :: CLI.Environment -> IO ()
targetAddScenario env = do
    let root = "/tmp/c-plugin-v2-target-add-e2e"
        homePath = root ++ "/home"
        project = homePath ++ "/project"
        projectPlugin = project ++ "/plugin"
        projectLock = project ++ "/c-plugin-lock.json"
        projectState = project ++ "/.agents/c-plugin-state.json"
    s <- newScenario env homePath
    writePlugin s project ["alpha"]
    writeFile s projectLock (localLock [] "plugin" ["alpha"])
    projectResult <- run s project ["target", "add", ".cursor/skills"]
    requireSuccess projectResult
    requireContains (stdoutText projectResult) ("Added target .cursor/skills to " ++ projectLock ++ ": partial")
    requireJSON s projectLock (localLock [".cursor/skills"] "plugin" ["alpha"])
    forM_ [project ++ "/.agents/skills", project ++ "/.cursor/skills"] $ \targetRoot ->
        requireSymlink s (targetRoot ++ "/alpha") (projectPlugin ++ "/skills/alpha")
    state <- decodeText <$> readFile s projectState
    requireContains state ("\"managedRoot\": \"" ++ project ++ "/.agents/skills\"")
    requireContains state ("\"managedRoot\": \"" ++ project ++ "/.cursor/skills\"")
    lockDigest <- digest s projectLock
    stateDigest <- digest s projectState
    repeated <- run s project ["target", "add", ".cursor/./skills"]
    requireSuccess repeated
    requireOutput repeated ("Target .cursor/skills already registered in " ++ projectLock ++ "\n")
    requireDigest s projectLock lockDigest
    requireDigest s projectState stateDigest
    let globalRepository = homePath ++ "/plugin"
        globalLock = homePath ++ "/c-plugin-lock.json"
        globalState = homePath ++ "/.agents/c-plugin-state.json"
    writeFile s (globalRepository ++ "/plugin.json") pluginJSON
    writeFile s (globalRepository ++ "/skills/beta/SKILL.md") (skillMarkdown "beta")
    writeFile s globalLock (localLock [] "plugin" ["beta"])
    mkdirAll s [project ++ "/nested"]
    global <- run s (project ++ "/nested") ["target", "add", ".claude/skills", "--global"]
    requireSuccess global
    requireContains (stdoutText global) ("Added target .claude/skills to " ++ globalLock ++ ": partial")
    forM_ [homePath ++ "/.agents/skills", homePath ++ "/.claude/skills"] $ \targetRoot ->
        requireSymlink s (targetRoot ++ "/beta") (globalRepository ++ "/skills/beta")
    requireJSON s globalLock (localLock [".claude/skills"] "plugin" ["beta"])
    globalStateText <- decodeText <$> readFile s globalState
    requireContains globalStateText ("\"managedRoot\": \"" ++ homePath ++ "/.claude/skills\"")

targetRemoveScenario :: CLI.Environment -> IO ()
targetRemoveScenario env = do
    let root = "/tmp/c-plugin-v2-target-remove-e2e"
        homePath = root ++ "/home"
        project = homePath ++ "/project"
        projectPlugin = project ++ "/plugin"
        projectLock = project ++ "/c-plugin-lock.json"
        projectState = project ++ "/.agents/c-plugin-state.json"
    s <- newScenario env homePath
    writePlugin s project ["alpha"]
    writeFile s projectLock (localLock [".cursor/skills", ".claude/skills"] "plugin" ["alpha"])
    run s project ["sync"] >>= requireSuccess
    writeFile s (project ++ "/.cursor/skills/neighbor") "foreign\n"
    lockDigest <- digest s projectLock
    stateDigest <- digest s projectState
    unknown <- run s project ["target", "remove", "--target", ".vscode/skills"]
    requireSuccess unknown
    requireOutput unknown ("No target changes for " ++ projectLock ++ "\n")
    empty <- run s project ["target", "remove"]
    requireFailure empty
    requireContains (stdoutText empty) "--target"
    forM_ [".agents/skills", ".cursor/skills", ".claude/skills"] $ \target ->
        requireSymlink s (project ++ "/" ++ target ++ "/alpha") (projectPlugin ++ "/skills/alpha")
    requireFile s (project ++ "/.cursor/skills/neighbor") "foreign\n"
    requireDigest s projectLock lockDigest
    requireDigest s projectState stateDigest
    cursor <- run s project ["target", "remove", "--target", ".cursor/./skills"]
    requireSuccess cursor
    requireContains (stdoutText cursor) ("Removed targets .cursor/skills from " ++ projectLock ++ ": complete")
    requireJSON s projectLock (localLock [".claude/skills"] "plugin" ["alpha"])
    requireMissing s (project ++ "/.cursor/skills/alpha")
    requireFile s (project ++ "/.cursor/skills/neighbor") "foreign\n"
    forM_ [project ++ "/.agents/skills", project ++ "/.claude/skills"] $ \targetRoot ->
        requireSymlink s (targetRoot ++ "/alpha") (projectPlugin ++ "/skills/alpha")
    state <- decodeText <$> readFile s projectState
    requireNotContains state ("\"managedRoot\": \"" ++ project ++ "/.cursor/skills\"")
    requireContains state ("\"managedRoot\": \"" ++ project ++ "/.claude/skills\"")
    claude <- run s project ["target", "remove", "--target", ".claude/skills"]
    requireSuccess claude
    requireContains (stdoutText claude) ("Removed targets .claude/skills from " ++ projectLock ++ ": complete")
    requireJSON s projectLock (localLock [] "plugin" ["alpha"])
    requireMissing s (project ++ "/.claude/skills/alpha")
    requireSymlink s (project ++ "/.agents/skills/alpha") (projectPlugin ++ "/skills/alpha")
    requireFile s (project ++ "/.cursor/skills/neighbor") "foreign\n"
    afterClaude <- decodeText <$> readFile s projectState
    requireNotContains afterClaude (project ++ "/.cursor/skills")
    requireNotContains afterClaude (project ++ "/.claude/skills")
    let globalRepository = homePath ++ "/plugin"
        globalLock = homePath ++ "/c-plugin-lock.json"
        globalState = homePath ++ "/.agents/c-plugin-state.json"
    writeFile s (globalRepository ++ "/plugin.json") pluginJSON
    writeFile s (globalRepository ++ "/skills/beta/SKILL.md") (skillMarkdown "beta")
    writeFile s globalLock (localLock [".cursor/skills"] "plugin" ["beta"])
    mkdirAll s [project ++ "/nested"]
    run s (project ++ "/nested") ["sync", "--global"] >>= requireSuccess
    global <- run s (project ++ "/nested") ["target", "remove", "--global", "--target", ".cursor/skills"]
    requireSuccess global
    requireContains (stdoutText global) ("Removed targets .cursor/skills from " ++ globalLock ++ ": complete")
    requireJSON s globalLock (localLock [] "plugin" ["beta"])
    requireMissing s (homePath ++ "/.cursor/skills/beta")
    requireSymlink s (homePath ++ "/.agents/skills/beta") (globalRepository ++ "/skills/beta")
    globalStateText <- decodeText <$> readFile s globalState
    requireNotContains globalStateText (homePath ++ "/.cursor/skills")

errorHelpScenario :: CLI.Environment -> IO ()
errorHelpScenario env = do
    let root = "/tmp/c-plugin-error-help-e2e"
        homePath = root ++ "/home"
        project = homePath ++ "/project"
        lock = project ++ "/c-plugin-lock.json"
        cases =
            [ ([], [], "Missing: COMMAND")
            , (["plugin"], ["plugin"], "Missing: COMMAND")
            , (["skill"], ["skill"], "Missing: COMMAND")
            , (["target"], ["target"], "Missing: COMMAND")
            , (["plugin", "add"], ["plugin", "add"], "Missing:")
            , (["skill", "add"], ["skill", "add"], "Missing:")
            , (["target", "add"], ["target", "add"], "Missing: PATH")
            , (["plugin", "add", "github:owner/repo", "--ref"], ["plugin", "add"], "The option `--ref` expects an argument.")
            , (["plugin", "add", "local:./plugin", "--skill"], ["plugin", "add"], "The option `--skill` expects an argument.")
            ]
    s <- newScenario env homePath
    mkdirAll s [homePath, project]
    run s project ["init"] >>= requireSuccess
    before <- digest s lock
    forM_ cases $ \(arguments, context, errorText) -> do
        help <- run s project (context ++ ["--help"])
        requireSuccess help
        requireContains (stdoutText help) "Available options:"
        failure <- run s project arguments
        requireExit failure 1
        requireContains (stderrText failure) errorText
        requireContains (stderrText failure) (stdoutText help)
        requireDigest s lock before
    requireMissing s (homePath ++ "/c-plugin-lock.json")
    requireMissing s (project ++ "/.agents")
    requireMissing s (homePath ++ "/.agents")

standardMinimalScenario :: CLI.Environment -> IO ()
standardMinimalScenario env = do
    (s, project) <- standardEnvironment env "minimal" ["alpha", "beta"]
    result <- run s project ["plugin", "add", "local:./plugin", "--all"]
    requireSuccess result
    requireContains (stdoutText result) ("Added " ++ project ++ "/plugin to " ++ project ++ "/c-plugin-lock.json: partial")
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha", "beta"])
    forM_ ["alpha", "beta"] $ \skill -> do
        requireSymlink s (project ++ "/.agents/skills/" ++ skill) (project ++ "/plugin/skills/" ++ skill)
        state <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
        requireOwnershipSkill s state skill True
    removed <- run s project ["plugin", "remove", "--plugin", "demo"]
    requireSuccess removed
    requireContains (stdoutText removed) ("Removed plugins demo from " ++ project ++ "/c-plugin-lock.json:")
    requireJSON s (project ++ "/c-plugin-lock.json") emptyLock
    requireMissing s (project ++ "/.agents/skills/alpha")
    requireMissing s (project ++ "/.agents/skills/beta")
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"

standardEmptyScenario :: CLI.Environment -> IO ()
standardEmptyScenario env = do
    (s, project) <- standardEnvironment env "empty" []
    result <- run s project ["plugin", "add", "local:./plugin", "--all"]
    requireSuccess result
    requireContains (stdoutText result) ("Added " ++ project ++ "/plugin")
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" [])
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"
    requireMissing s (project ++ "/.agents/skills/alpha")
    requireMissing s (project ++ "/.agents/skills/beta")

standardUnknownFieldScenario :: CLI.Environment -> IO ()
standardUnknownFieldScenario env = do
    (s, project) <- standardEnvironment env "unknown" ["alpha"]
    writeFile s (project ++ "/plugin/plugin.json") ("{\"$schema\":\"" ++ pluginSchema ++ "\",\"name\":\"demo\",\"skills\":\"./elsewhere\",\"custom\":true}")
    writeFile s (project ++ "/plugin/elsewhere/beta/SKILL.md") (skillMarkdown "beta")
    result <- run s project ["plugin", "add", "local:./plugin", "--all"]
    requireSuccess result
    requireContains (stdoutText result) "Warning: unknown top-level field: skills"
    requireContains (stdoutText result) "Warning: unknown top-level field: custom"
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha"])
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
    requireMissing s (project ++ "/.agents/skills/beta")

standardWrongSchemaScenario :: CLI.Environment -> IO ()
standardWrongSchemaScenario env = do
    (s, project) <- standardEnvironment env "wrong-schema" ["alpha"]
    writeFile s (project ++ "/plugin/plugin.json") "{\"$schema\":\"https://example.invalid/plugin.schema.json\",\"name\":\"demo\"}"
    writeFile s (project ++ "/.agents/skills/foreign") "foreign\n"
    before <- digest s (project ++ "/c-plugin-lock.json")
    result <- run s project ["plugin", "add", "local:./plugin", "--all"]
    requireFailure result
    requireContains (stdoutText result) "totto2727/c-plugin.PluginAddError.InvalidInput"
    requireDigest s (project ++ "/c-plugin-lock.json") before
    requireMissing s (project ++ "/.agents/c-plugin-state.json")
    requireMissing s (project ++ "/.agents/skills/alpha")
    requireFile s (project ++ "/.agents/skills/foreign") "foreign\n"

standardInvalidSkillScenario :: CLI.Environment -> IO ()
standardInvalidSkillScenario env = do
    (s, project) <- standardEnvironment env "invalid-skill" ["alpha"]
    writeFile s (project ++ "/plugin/skills/beta/SKILL.md") "---\nname: beta\n---\n"
    result <- run s project ["plugin", "add", "local:./plugin", "--all"]
    requireSuccess result
    requireContains (stdoutText result) "Warning: invalid skill beta:"
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha"])
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
    requireMissing s (project ++ "/.agents/skills/beta")
    state <- decodeText <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    requireOwnershipSkill s state "beta" False

standardShallowDiscoveryScenario :: CLI.Environment -> IO ()
standardShallowDiscoveryScenario env = do
    (s, project) <- standardEnvironment env "shallow" ["alpha"]
    writeFile s (project ++ "/plugin/skills/group/beta/SKILL.md") (skillMarkdown "beta")
    result <- run s project ["plugin", "add", "local:./plugin", "--all"]
    requireSuccess result
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha"])
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
    requireMissing s (project ++ "/.agents/skills/beta")
    requireMissing s (project ++ "/.agents/skills/group")

standardManifestEscapeScenario :: CLI.Environment -> IO ()
standardManifestEscapeScenario env = do
    (s, project) <- standardEnvironment env "manifest-escape" ["alpha"]
    let outside = project ++ "/outside/plugin.json"
    writeFile s outside pluginJSON
    outsideDigest <- digest s outside
    remove s [project ++ "/plugin/plugin.json"]
    infra s "" ["ln", "-s", outside, project ++ "/plugin/plugin.json"] >>= requireSuccess
    writeFile s (project ++ "/.agents/skills/foreign") "foreign\n"
    before <- digest s (project ++ "/c-plugin-lock.json")
    result <- run s project ["plugin", "add", "local:./plugin", "--all"]
    requireFailure result
    requireContains (stdoutText result) "outside plugin root"
    requireDigest s (project ++ "/c-plugin-lock.json") before
    requireDigest s outside outsideDigest
    requireMissing s (project ++ "/.agents/c-plugin-state.json")
    requireMissing s (project ++ "/.agents/skills/alpha")
    requireFile s (project ++ "/.agents/skills/foreign") "foreign\n"

standardSkillsEscapeScenario :: CLI.Environment -> IO ()
standardSkillsEscapeScenario env = do
    (s, project) <- standardEnvironment env "skills-escape" []
    let outside = project ++ "/outside/alpha/SKILL.md"
    writeFile s outside (skillMarkdown "alpha")
    outsideDigest <- digest s outside
    infra s "" ["ln", "-s", project ++ "/outside", project ++ "/plugin/skills"] >>= requireSuccess
    result <- run s project ["plugin", "add", "local:./plugin", "--all"]
    requireSuccess result
    requireContains (stdoutText result) "outside plugin root"
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" [])
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"
    requireMissing s (project ++ "/.agents/skills/alpha")
    requireDigest s outside outsideDigest

standardSkillFileEscapeScenario :: CLI.Environment -> IO ()
standardSkillFileEscapeScenario env = do
    (s, project) <- standardEnvironment env "skill-file-escape" ["alpha"]
    let outside = project ++ "/outside/SKILL.md"
    writeFile s outside (skillMarkdown "beta")
    outsideDigest <- digest s outside
    mkdirAll s [project ++ "/plugin/skills/beta"]
    infra s "" ["ln", "-s", outside, project ++ "/plugin/skills/beta/SKILL.md"] >>= requireSuccess
    result <- run s project ["plugin", "add", "local:./plugin", "--all"]
    requireSuccess result
    requireContains (stdoutText result) "Warning: invalid skill beta:"
    requireContains (stdoutText result) "outside plugin root"
    requireJSON s (project ++ "/c-plugin-lock.json") (localLock [] "plugin" ["alpha"])
    requireSymlink s (project ++ "/.agents/skills/alpha") (project ++ "/plugin/skills/alpha")
    requireMissing s (project ++ "/.agents/skills/beta")
    requireDigest s outside outsideDigest
