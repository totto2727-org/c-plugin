{-# LANGUAGE OverloadedStrings #-}

module CPlugin.E2E.GitHubSpec where

import CPlugin.E2E.Fixtures
import CPlugin.E2E.Support hiding (environment)
import Control.Monad (forM_, unless)
import Data.Aeson (Value, eitherDecodeStrict', withObject, (.:))
import Data.Aeson.Types (Parser, parseEither)
import qualified Data.ByteString.Char8 as BS
import Data.List (findIndex, isInfixOf, isPrefixOf, tails)
import qualified Data.Map.Strict as Map
import System.FilePath.Posix (normalise, (</>))
import Test.CLI.E2E (Environment, withEnvironment)
import Test.Hspec
import Prelude hiding (readFile, writeFile)

spec :: Spec
spec = parallel $ do
    it "github_parser_invalid" $ withEnvironment "c-plugin-e2e:local" githubParserInvalid
    it "github_source_failure" $ withEnvironment "c-plugin-e2e:local" githubSourceFailure
    it "github_plugin_lifecycle" $ withEnvironment "c-plugin-e2e:local" githubPluginLifecycle
    it "github_standalone_offline" $ withEnvironment "c-plugin-e2e:local" githubStandaloneOffline
    it "github_global" $ withEnvironment "c-plugin-e2e:local" githubGlobal
    it "github_cache_safety" $ withEnvironment "c-plugin-e2e:local" githubCacheSafety
    it "github_force_safety" $ withEnvironment "c-plugin-e2e:local" githubForceSafety
    it "top_level_sync_update_recursive" $ withEnvironment "c-plugin-e2e:local" topLevelSyncUpdateRecursive

githubFixtureRepository, githubFixtureURL, githubFixtureRef, githubPluginPath, githubSoloPath, githubRootSource, githubPluginSource, githubSoloSource, githubPluginURLSource, githubSoloURLSource :: String
githubFixtureRepository = "totto2727-org/c-plugin"
githubFixtureURL = "https://github.com/" ++ githubFixtureRepository
-- Fixture paths refer to this published Git tree, not the local checkout layout.
githubFixtureRef = "test/e2e-unified-api"
githubPluginPath = "hs/test/fixtures/github/plugin"
githubSoloPath = "hs/test/fixtures/github/solo"
githubRootSource = "github:" ++ githubFixtureRepository
githubPluginSource = githubRootSource ++ "/" ++ githubPluginPath
githubSoloSource = githubRootSource ++ "/" ++ githubSoloPath
githubPluginURLSource = "github:" ++ githubFixtureURL ++ "/" ++ githubPluginPath
githubSoloURLSource = "github:" ++ githubFixtureURL ++ "/" ++ githubSoloPath

githubEnvironment :: Environment -> String -> IO (Scenario, FilePath)
githubEnvironment environment name = do
    let h = "/tmp/c-plugin-github-" ++ name ++ "/home"
        project = h ++ "/project"
        s = newScenario environment h
    mkdirAll s [project]
    run s project ["init"] >>= requireSuccess
    pure (s, project)

-- Decode only the public fields asserted by these scenarios.
data GitHubRegistration = GitHubRegistration
    { registrationName :: String
    , registrationSource :: String
    , registrationSkills :: [String]
    , registrationOrigin :: Value
    }
    deriving (Show)

githubRegisteredSource :: Scenario -> FilePath -> String -> String -> IO GitHubRegistration
githubRegisteredSource s root kind name = do
    bytes <- readFile s (root ++ "/c-plugin-lock.json")
    value <- either fail pure (eitherDecodeStrict' bytes)
    let entryParser = withObject "registration" $ \o ->
            if kind == "skill"
                then GitHubRegistration <$> o .: "installedSkillName" <*> o .: "installedSkillSource" <*> pure [] <*> o .: "installedSkillOrigin"
                else GitHubRegistration <$> o .: "pluginName" <*> o .: "pluginSource" <*> o .: "enabledSkills" <*> o .: "pluginOrigin"
        lockParser = withObject "lock" $ \o -> do
            entries <- o .: (if kind == "skill" then "standaloneSkills" else "plugins") :: Parser (Map.Map String Value)
            traverse entryParser entries
    entries <- either fail pure (parseEither lockParser value)
    Map.size entries `shouldBe` 1
    entry <- maybe (fail ("missing registration: " ++ name)) pure (Map.lookup name entries)
    registrationName entry `shouldBe` name
    let source = registrationSource entry
    source `shouldSatisfy` isPrefixOf ".agents/c-plugin/sources/"
    normalise source `shouldBe` source
    source `shouldSatisfy` (not . isInfixOf "..")
    requireDirectory s (root </> source)
    pure entry

githubPinnedCommit :: Scenario -> GitHubRegistration -> IO String
githubPinnedCommit _ entry = do
    let parser = withObject "GitHub origin" $ \o -> (,,,) <$> o .: "githubOriginRepository" <*> o .: "githubOriginRef" <*> o .: "githubOriginCommit" <*> o .: "githubOriginSubpath"
    (repository, ref, commit, subpath) <- either fail pure (parseEither parser (registrationOrigin entry))
    repository `shouldBe` githubFixtureRepository
    (ref :: String) `shouldSatisfy` (not . null)
    commit `shouldSatisfy` immutableCommit
    registrationSource entry `shouldBe` (".agents/c-plugin/sources/" ++ repository ++ "/" ++ commit ++ "/tree/" ++ subpath)
    pure commit

immutableCommit :: String -> Bool
immutableCommit commit = length commit == 40 && all (`elem` (['0' .. '9'] ++ ['a' .. 'f'])) commit

blockedNetwork :: [(String, String)]
blockedNetwork = [(key, "http://127.0.0.1:1") | key <- ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy"]] ++ [("NO_PROXY", ""), ("no_proxy", "")]

githubParserInvalid :: Environment -> IO ()
githubParserInvalid environment = do
    (s, project) <- githubEnvironment environment "parser-invalid"
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    forM_
        [ ["plugin", "add", "--github", githubFixtureRepository, "--all"]
        , ["skill", "add", "--local", "./solo"]
        , ["plugin", "add", githubPluginSource, "--path", githubPluginPath, "--all"]
        , ["plugin", "add", githubPluginSource, "--local", "./plugin", "--all"]
        , ["skill", "add", githubSoloSource, "--local", "./solo"]
        , ["plugin", "add", githubPluginSource, "local:./plugin", "--all"]
        , ["skill", "add", githubSoloSource, "local:./solo"]
        , ["plugin", "add", "local:./plugin", "--ref", githubFixtureRef, "--all"]
        , ["skill", "add", "local:./solo", "--path", githubSoloPath]
        , ["plugin", "add", "--ref", githubFixtureRef, "--all"]
        , ["skill", "add", "--ref", githubFixtureRef]
        , ["plugin", "add", githubFixtureRepository, "--all"]
        , ["skill", "add", githubFixtureURL]
        , ["skill", "add", "./solo"]
        , ["plugin", "add", "github:owner", "--all"]
        , ["skill", "add", "github:https://example.com/owner/repo"]
        , ["skill", "add", "github:https://github.com/owner/repo?ref=main"]
        , ["plugin", "add", githubRootSource ++ "/../plugin", "--all"]
        , ["skill", "add", githubRootSource ++ "//tmp/solo"]
        , ["skill", "add", githubRootSource ++ "/.git"]
        , ["skill", "add", "local:/tmp/solo"]
        , ["skill", "add", "local:solo"]
        , ["skill", "add", githubSoloSource, "--ref", "HEAD^{commit}"]
        , ["plugin", "add", githubPluginSource, "--all", "--none"]
        , ["plugin", "add", githubPluginSource, "--all", "--skill", "alpha"]
        ]
        $ \arguments -> do
            run s project arguments >>= requireFailure
            requireFile s (project ++ "/c-plugin-lock.json") lock
            forM_ ["/.agents/c-plugin-state.json", "/.agents/skills/alpha", "/.agents/skills/solo"] $ requireMissing s . (project ++)

githubSourceFailure :: Environment -> IO ()
githubSourceFailure environment = do
    (s, project) <- githubEnvironment environment "source-failure"
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    forM_
        [ ["plugin", "add", githubRootSource, "--ref", githubFixtureRef, "--all"]
        , ["skill", "add", githubRootSource ++ "/hs/test/fixtures/github", "--ref", githubFixtureRef]
        , ["plugin", "add", githubRootSource ++ "/hs/test/fixtures/github/missing", "--ref", githubFixtureRef, "--all"]
        , ["plugin", "add", githubPluginSource, "--ref", "c-plugin-e2e-ref-that-does-not-exist", "--all"]
        , ["skill", "add", "github:totto2727-org/c-plugin-e2e-repository-that-does-not-exist/" ++ githubSoloPath]
        ]
        $ \arguments -> do
            run s project arguments >>= requireFailure
            requireFile s (project ++ "/c-plugin-lock.json") lock
            forM_ ["/.agents/c-plugin-state.json", "/.agents/skills/alpha", "/.agents/skills/solo"] $ requireMissing s . (project ++)

githubPluginLifecycle :: Environment -> IO ()
githubPluginLifecycle environment = do
    (s, project) <- githubEnvironment environment "plugin-lifecycle"
    mkdirAll s [project ++ "/nested"]
    run s (project ++ "/nested") ["plugin", "add", githubPluginSource, "--ref", githubFixtureRef, "--all"] >>= requireSuccess
    entry <- githubRegisteredSource s project "plugin" "github-demo"
    _ <- githubPinnedCommit s entry
    let source = project </> registrationSource entry
    requireJSON s (source ++ "/plugin.json") ("{\"$schema\":\"" ++ pluginSchema ++ "\",\"name\":\"github-demo\"}")
    requireSymlink s (project ++ "/.agents/skills/alpha") (source ++ "/skills/alpha")
    requireSymlink s (project ++ "/.agents/skills/beta") (source ++ "/skills/beta")
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    remove s [project ++ "/.agents/skills/alpha"]
    run s project ["plugin", "add", githubPluginURLSource, "--ref", githubFixtureRef, "--all"] >>= requireSuccess
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireFile s (project ++ "/.agents/c-plugin-state.json") state
    requireMissing s (project ++ "/.agents/skills/alpha")
    run s project ["sync"] >>= requireSuccess
    requireSymlink s (project ++ "/.agents/skills/alpha") (source ++ "/skills/alpha")
    run s project ["plugin", "add", githubPluginSource, "--ref", githubFixtureRef, "--skill", "beta"] >>= requireSuccess
    selected <- githubRegisteredSource s project "plugin" "github-demo"
    registrationSkills selected `shouldBe` ["beta"]
    requireMissing s (project ++ "/.agents/skills/alpha")
    requireSymlink s (project ++ "/.agents/skills/beta") (source ++ "/skills/beta")
    run s project ["plugin", "add", githubPluginSource, "--ref", githubFixtureRef, "--none"] >>= requireSuccess
    disabled <- githubRegisteredSource s project "plugin" "github-demo"
    registrationSkills disabled `shouldBe` []
    requireMissing s (project ++ "/.agents/skills/beta")
    run s project ["plugin", "remove", "--plugin", "github-demo"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") emptyLock
    requireJSON s (project ++ "/.agents/c-plugin-state.json") "{\"ownershipEntries\":{}}"
    requireRegularFile s (source ++ "/plugin.json")

githubStandaloneOffline :: Environment -> IO ()
githubStandaloneOffline environment = do
    (s, project) <- githubEnvironment environment "standalone-offline"
    run s project ["skill", "add", githubSoloURLSource, "--ref", githubFixtureRef] >>= requireSuccess
    entry <- githubRegisteredSource s project "skill" "solo"
    _ <- githubPinnedCommit s entry
    let source = project </> registrationSource entry
    requireSymlink s (project ++ "/.agents/skills/solo") source
    requireMissing s (source ++ "/plugin.json")
    checksum <- digest s (source ++ "/SKILL.md")
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    remove s [project ++ "/.agents/skills/solo"]
    run s project ["skill", "add", githubSoloSource, "--ref", githubFixtureRef] >>= requireSuccess
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireFile s (project ++ "/.agents/c-plugin-state.json") state
    requireMissing s (project ++ "/.agents/skills/solo")
    -- A real network probe must fail under the same proxies used for offline sync.
    infraWithEnv s project (("HOME", home s) : blockedNetwork) ["git", "ls-remote", githubFixtureURL, "refs/heads/" ++ githubFixtureRef] >>= requireFailure
    runWithEnv s project blockedNetwork ["sync"] >>= requireSuccess
    requireSymlink s (project ++ "/.agents/skills/solo") source
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireDigest s (source ++ "/SKILL.md") checksum
    run s project ["skill", "remove", "--skill", "solo"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") emptyLock
    requireMissing s (project ++ "/.agents/skills/solo")
    requireDigest s (source ++ "/SKILL.md") checksum

githubGlobal :: Environment -> IO ()
githubGlobal environment = do
    (s, project) <- githubEnvironment environment "global"
    run s project ["init", "--global"] >>= requireSuccess
    run s project ["skill", "add", githubSoloSource, "--ref", githubFixtureRef] >>= requireSuccess
    projectEntry <- githubRegisteredSource s project "skill" "solo"
    commit <- githubPinnedCommit s projectEntry
    projectLock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    projectState <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    mkdirAll s [project ++ "/nested"]
    run s (project ++ "/nested") ["skill", "add", "--global", githubSoloURLSource, "--ref", commit] >>= requireSuccess
    globalEntry <- githubRegisteredSource s (home s) "skill" "solo"
    let globalSource = home s </> registrationSource globalEntry
        projectSource = project </> registrationSource projectEntry
    globalSource `shouldNotBe` projectSource
    globalSource `shouldSatisfy` isPrefixOf (home s ++ "/")
    globalSource `shouldSatisfy` (not . isPrefixOf (project ++ "/"))
    requireSymlink s (home s ++ "/.agents/skills/solo") globalSource
    run s (project ++ "/nested") ["sync", "--global"] >>= requireSuccess
    run s (project ++ "/nested") ["skill", "remove", "--global", "--skill", "solo"] >>= requireSuccess
    requireJSON s (home s ++ "/c-plugin-lock.json") emptyLock
    requireMissing s (home s ++ "/.agents/skills/solo")
    requireFile s (project ++ "/c-plugin-lock.json") projectLock
    requireFile s (project ++ "/.agents/c-plugin-state.json") projectState
    requireSymlink s (project ++ "/.agents/skills/solo") projectSource

githubCacheSafety :: Environment -> IO ()
githubCacheSafety environment = do
    (s, project) <- githubEnvironment environment "cache-safety"
    let outside = home s ++ "/outside"
    writeFile s (outside ++ "/sentinel") "foreign cache must survive\n"
    mkdirAll s [project ++ "/.agents/c-plugin"]
    infra s "" ["ln", "-s", outside, project ++ "/.agents/c-plugin/sources"] >>= requireSuccess
    lock0 <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    run s project ["skill", "add", githubSoloSource, "--ref", githubFixtureRef, "--force"] >>= requireFailure
    requireFile s (project ++ "/c-plugin-lock.json") lock0
    requireMissing s (project ++ "/.agents/c-plugin-state.json")
    requireMissing s (outside ++ "/totto2727-org")
    requireFile s (outside ++ "/sentinel") "foreign cache must survive\n"
    requireSymlink s (project ++ "/.agents/c-plugin/sources") outside
    remove s [project ++ "/.agents/c-plugin/sources"]
    run s project ["skill", "add", githubSoloSource, "--ref", githubFixtureRef] >>= requireSuccess
    entry <- githubRegisteredSource s project "skill" "solo"
    commit <- githubPinnedCommit s entry
    let cache = project ++ "/.agents/c-plugin/sources/" ++ githubFixtureRepository ++ "/" ++ commit
        source = project </> registrationSource entry
    requireJSON s (cache ++ "/origin.json") ("{\"snapshotRepository\":\"" ++ githubFixtureRepository ++ "\",\"snapshotCommit\":\"" ++ commit ++ "\"}")
    origin <- BS.unpack <$> readFile s (cache ++ "/origin.json")
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    checksum <- digest s (source ++ "/SKILL.md")
    writeFile s (cache ++ "/origin.json") ("{\"snapshotRepository\":\"foreign/repository\",\"snapshotCommit\":\"" ++ commit ++ "\"}")
    foreignOrigin <- BS.unpack <$> readFile s (cache ++ "/origin.json")
    partial <- run s project ["sync"]
    requireSuccess partial
    requireContains (stdoutText partial) "partial"
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireFile s (project ++ "/.agents/c-plugin-state.json") state
    requireFile s (cache ++ "/origin.json") foreignOrigin
    requireSymlink s (project ++ "/.agents/skills/solo") source
    requireDigest s (source ++ "/SKILL.md") checksum
    writeFile s (cache ++ "/origin.json") origin
    infra s "" ["git", "-C", cache ++ "/tree", "remote", "set-url", "origin", "https://github.com/foreign/repository.git"] >>= requireSuccess
    partialRemote <- run s project ["sync"]
    requireSuccess partialRemote
    requireContains (stdoutText partialRemote) "partial"
    requireFile s (project ++ "/c-plugin-lock.json") lock
    requireFile s (project ++ "/.agents/c-plugin-state.json") state
    requireSymlink s (project ++ "/.agents/skills/solo") source
    requireDigest s (source ++ "/SKILL.md") checksum
    remote <- infra s "" ["git", "-C", cache ++ "/tree", "remote", "get-url", "origin"]
    requireSuccess remote
    requireOutput remote "https://github.com/foreign/repository.git\n"
    requireFile s (outside ++ "/sentinel") "foreign cache must survive\n"

githubForceSafety :: Environment -> IO ()
githubForceSafety environment = do
    (s, project) <- githubEnvironment environment "force-safety"
    writeFile s (project ++ "/.agents/skills/alpha/keep") "foreign directory\n"
    writeFile s (project ++ "/.agents/skills/beta") "replace eligible file\n"
    writeFile s (project ++ "/.agents/skills/neighbor") "foreign neighbor\n"
    run s project ["plugin", "add", githubPluginSource, "--ref", githubFixtureRef, "--all", "--force"] >>= requireSuccess
    entry <- githubRegisteredSource s project "plugin" "github-demo"
    _ <- githubPinnedCommit s entry
    let source = project </> registrationSource entry
    requireDirectory s (project ++ "/.agents/skills/alpha")
    requireFile s (project ++ "/.agents/skills/alpha/keep") "foreign directory\n"
    requireFile s (project ++ "/.agents/skills/neighbor") "foreign neighbor\n"
    requireSymlink s (project ++ "/.agents/skills/beta") (source ++ "/skills/beta")
    run s project ["plugin", "remove", "--plugin", "github-demo"] >>= requireSuccess
    requireJSON s (project ++ "/c-plugin-lock.json") emptyLock
    requireMissing s (project ++ "/.agents/skills/beta")
    requireFile s (project ++ "/.agents/skills/alpha/keep") "foreign directory\n"
    requireFile s (project ++ "/.agents/skills/neighbor") "foreign neighbor\n"

topLevelSyncUpdateRecursive :: Environment -> IO ()
topLevelSyncUpdateRecursive environment = do
    (s, project) <- githubEnvironment environment "top-level-recursive"
    remote <- infra s "" ["git", "ls-remote", githubFixtureURL, "refs/heads/" ++ githubFixtureRef]
    requireSuccess remote
    commit <- case words (stdoutText remote) of
        [sha, ref] | ref == "refs/heads/" ++ githubFixtureRef && immutableCommit sha -> pure sha
        _ -> fail ("fixture ref resolution=" ++ show (stdoutText remote))
    run s project ["plugin", "add", "github:" ++ githubFixtureURL ++ ".git/" ++ githubPluginPath, "--ref", commit, "--all"] >>= requireSuccess
    run s project ["skill", "add", githubSoloSource, "--ref", commit] >>= requireSuccess
    plugin <- githubRegisteredSource s project "plugin" "github-demo"
    solo <- githubRegisteredSource s project "skill" "solo"
    githubPinnedCommit s plugin >>= (`shouldBe` commit)
    githubPinnedCommit s solo >>= (`shouldBe` commit)
    let pluginSource = project </> registrationSource plugin
        soloSource = project </> registrationSource solo
        parentLinks = [project ++ "/.agents/skills/" ++ skill | skill <- ["alpha", "beta", "solo"]]
        checkParentLinks = do
            requireSymlink s (project ++ "/.agents/skills/alpha") (pluginSource ++ "/skills/alpha")
            requireSymlink s (project ++ "/.agents/skills/beta") (pluginSource ++ "/skills/beta")
            requireSymlink s (project ++ "/.agents/skills/solo") soloSource
    lock <- BS.unpack <$> readFile s (project ++ "/c-plugin-lock.json")
    state <- BS.unpack <$> readFile s (project ++ "/.agents/c-plugin-state.json")
    lockIdentity <- infra s "" ["stat", "-c", "%i:%Y", project ++ "/c-plugin-lock.json"]
    requireSuccess lockIdentity
    let checkIdentity = do
            identity <- infra s "" ["stat", "-c", "%i:%Y", project ++ "/c-plugin-lock.json"]
            requireSuccess identity
            requireOutput identity (stdoutText lockIdentity)
    mkdirAll s [project ++ "/nested"]
    forM_ ["sync", "update"] $ \command -> do
        remove s parentLinks
        result <- run s (project ++ "/nested") [command]
        requireSuccess result
        requireContains (stdoutText result) (project ++ "/c-plugin-lock.json")
        checkParentLinks
        requireFile s (project ++ "/c-plugin-lock.json") lock
        requireFile s (project ++ "/.agents/c-plugin-state.json") state
        checkIdentity
    let child = project ++ "/child"
        childLock = "{\"targets\":[],\"plugins\":{\"demo\":{\"pluginName\":\"demo\",\"pluginSource\":\"plugin\",\"enabledSkills\":[\"child-skill\"],\"pluginOrigin\":null}},\"standaloneSkills\":{\"solo\":{\"installedSkillName\":\"solo\",\"installedSkillSource\":\"standalone/solo\",\"installedSkillOrigin\":null}}}"
    writePlugin s child ["child-skill"]
    writeFile s (child ++ "/standalone/solo/SKILL.md") (skillMarkdown "solo")
    writeFile s (child ++ "/c-plugin-lock.json") childLock
    -- These fixtures preserve Admiral 0.6.2's actual matcher semantics.
    writeFile s (project ++ "/.gitignore") "  # comment-visible/  \n  .hidden-excluded/  \n  ignored-*/  \n!ignored-keep/\n/anchored/\nglobstar/**/blocked/\npatterns/a*/blocked/\nquestion?/\nc-plugin-lock.json\n"
    writeFile s (project ++ "/directory-scope/.gitignore") "  scoped/  \n"
    let visibleRoots = [project, child] ++ map (project ++) ["/.hidden-included", "/comment-visible", "/globstar/a/b/blocked", "/other/scoped", "/questionx"]
        skippedRoots = map (project ++) ["/.git/trap", "/.hidden-excluded", "/ignored-alpha", "/ignored-keep", "/anchored", "/wrapped/anchored", "/globstar/a/blocked", "/wrapped/patterns/alpha/blocked", "/directory-scope/scoped", "/question?", "/.agents/c-plugin/sources/discovery-trap"]
    forM_ (drop 2 visibleRoots) $ \root -> writeFile s (root ++ "/c-plugin-lock.json") emptyLock
    forM_ skippedRoots $ \root -> writeFile s (root ++ "/c-plugin-lock.json") "{invalid discovery trap\n"
    let outside = home s ++ "/outside-project"
    writeFile s (outside ++ "/c-plugin-lock.json") emptyLock
    infra s "" ["ln", "-s", outside, project ++ "/symlinked-project"] >>= requireSuccess
    forM_ ["sync", "update"] $ \command -> do
        remove s (parentLinks ++ [child ++ "/.agents/skills/child-skill", child ++ "/.agents/skills/solo"])
        result <- run s (project ++ "/nested") [command, "-r"]
        requireSuccess result
        let output = stdoutText result
            index needle = findIndex (isPrefixOf needle) (tails output)
            parentIndex = index (project ++ "/c-plugin-lock.json")
        forM_ visibleRoots $ \root -> do
            requireContains output (root ++ "/c-plugin-lock.json")
            unless (root == project) $ index (root ++ "/c-plugin-lock.json") `shouldSatisfy` (>= parentIndex)
        forM_ skippedRoots $ \root -> do
            requireNotContains output (root ++ "/c-plugin-lock.json")
            requireFile s (root ++ "/c-plugin-lock.json") "{invalid discovery trap\n"
            requireMissing s (root ++ "/.agents/c-plugin-state.json")
        requireNotContains output "symlinked-project"
        requireMissing s (outside ++ "/.agents/c-plugin-state.json")
        requireJSON s (outside ++ "/c-plugin-lock.json") emptyLock
        checkParentLinks
        requireSymlink s (child ++ "/.agents/skills/child-skill") (child ++ "/plugin/skills/child-skill")
        requireSymlink s (child ++ "/.agents/skills/solo") (child ++ "/standalone/solo")
        requireFile s (project ++ "/c-plugin-lock.json") lock
        requireFile s (child ++ "/c-plugin-lock.json") childLock
        checkIdentity
    let missingRoot = home s ++ "/missing-root"
    writeFile s (missingRoot ++ "/child/c-plugin-lock.json") emptyLock
    forM_ ["sync", "update"] $ \command -> do
        missing <- run s missingRoot [command, "-r"]
        requireFailure missing
        requireContains (stdoutText missing) "LockFileNotFound"
        requireMissing s (missingRoot ++ "/c-plugin-lock.json")
        requireMissing s (missingRoot ++ "/child/.agents/c-plugin-state.json")
        requireJSON s (missingRoot ++ "/child/c-plugin-lock.json") emptyLock
        global <- run s project [command, "--global", "-r"]
        requireFailure global
        requireContains (stdoutText global) "--global cannot be combined with --recursive"
        requireMissing s (home s ++ "/c-plugin-lock.json")
        requireMissing s (home s ++ "/.agents/c-plugin-state.json")
        requireFile s (project ++ "/c-plugin-lock.json") lock
        requireFile s (child ++ "/c-plugin-lock.json") childLock
