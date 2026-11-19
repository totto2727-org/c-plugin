{-# LANGUAGE OverloadedStrings #-}

module CPlugin.E2E.ListSpec (spec) where

import CPlugin.E2E.Fixtures
import CPlugin.E2E.GitHubSpec hiding (spec)
import CPlugin.E2E.Support hiding (environment)
import Control.Monad (forM_, when)
import System.FilePath.Posix ((</>))
import Test.CLI.E2E (Environment, withEnvironment)
import Test.Hspec
import Prelude hiding (readFile, writeFile)

spec :: Spec
spec = parallel $ do
    it "list_read_only" $ withEnvironment "c-plugin-e2e:local" listReadOnly
    it "list_missing_corrupt" $ withEnvironment "c-plugin-e2e:local" listMissingCorrupt
    it "github_list_unavailable" $ withEnvironment "c-plugin-e2e:local" githubListUnavailable

pluginsHeading, skillsHeading :: String
pluginsHeading = "Plugins\nname\tsource\tenabled-skills\n"
skillsHeading = "Skills\nname\towner\tsource\n"

listCases :: String -> String -> [([String], String)]
listCases plugins skills = [(["list"], plugins ++ "\n" ++ skills), (["plugin", "list"], plugins), (["skill", "list"], skills)]

listReadOnly :: Environment -> IO ()
listReadOnly environment = do
    (s, project) <- standardEnvironment environment "list-read-only" ["alpha", "beta"]
    writeFile s (project ++ "/disabled/plugin.json") ("{\"$schema\":\"" ++ pluginSchema ++ "\",\"name\":\"disabled\"}")
    writeFile s (project ++ "/standalone/solo/SKILL.md") (skillMarkdown "solo")
    run s project ["plugin", "add", "local:./plugin", "--skill", "alpha"] >>= requireSuccess
    run s project ["plugin", "add", "local:./disabled", "--none"] >>= requireSuccess
    run s project ["skill", "add", "local:./standalone/solo"] >>= requireSuccess
    run s project ["init", "--global"] >>= requireSuccess
    writePlugin s (home s) ["gamma"]
    run s project ["plugin", "add", "local:./plugin", "--all", "--global"] >>= requireSuccess
    mkdirAll s [project ++ "/nested"]
    projectLock <- digest s (project ++ "/c-plugin-lock.json")
    globalLock <- digest s (home s ++ "/c-plugin-lock.json")
    globalState <- digest s (home s ++ "/.agents/c-plugin-state.json")
    -- Listing inspects desired state even when sources and ownership are unavailable.
    remove s [project ++ "/plugin", project ++ "/disabled", project ++ "/standalone", project ++ "/.agents/skills/alpha"]
    writeFile s (project ++ "/.agents/c-plugin-state.json") "corrupt ownership\n"
    writeFile s (project ++ "/.agents/skills/neighbor") "foreign\n"
    let plugins = pluginsHeading ++ "demo\tlocal:./plugin\talpha\ndisabled\tlocal:./disabled\t-\n"
        skills = skillsHeading ++ "alpha\tplugin:demo\tlocal:./plugin\nsolo\tstandalone\tlocal:./standalone/solo\n"
        globalPlugins = pluginsHeading ++ "demo\tlocal:./plugin\tgamma\n"
        globalSkills = skillsHeading ++ "gamma\tplugin:demo\tlocal:./plugin\n"
        globalCases = [(arguments ++ ["-g"], output) | (arguments, output) <- listCases globalPlugins globalSkills]
    forM_ (listCases plugins skills ++ globalCases) $ \(arguments, output) -> do
        result <- run s (project ++ "/nested") arguments
        requireSuccess result
        requireOutput result output
        requireDigest s (project ++ "/c-plugin-lock.json") projectLock
        requireDigest s (home s ++ "/c-plugin-lock.json") globalLock
        requireDigest s (home s ++ "/.agents/c-plugin-state.json") globalState
        requireFile s (project ++ "/.agents/c-plugin-state.json") "corrupt ownership\n"
        requireFile s (project ++ "/.agents/skills/neighbor") "foreign\n"
        forM_ ["/.agents/skills/alpha", "/plugin", "/disabled", "/standalone"] $ requireMissing s . (project ++)
        infra s "" ["test", "-L", project ++ "/.agents/skills/solo"] >>= requireSuccess
        requireSymlink s (home s ++ "/.agents/skills/gamma") (home s ++ "/plugin/skills/gamma")

listMissingCorrupt :: Environment -> IO ()
listMissingCorrupt environment = do
    let h = "/tmp/c-plugin-list-missing-corrupt/home"
        project = h ++ "/project"
        roots = [project, h]
        cases = listCases pluginsHeading skillsHeading
        allCases = cases ++ [(arguments ++ ["-g"], output) | (arguments, output) <- cases]
    s <- newScenario environment h
    mkdirAll s [project]
    forM_ ["", "not JSON\n", "{\"version\":\"2\",\"targets\":[],\"plugins\":[]}", "{\"version\":\"3\",\"targets\":[],\"plugins\":[]}"] $ \content -> do
        forM_ roots $ \root -> when (content /= "") $ writeFile s (root ++ "/c-plugin-lock.json") content
        forM_ allCases $ \(arguments, _) -> do
            run s project arguments >>= requireFailure
            forM_ roots $ \root -> do
                if content == ""
                    then requireMissing s (root ++ "/c-plugin-lock.json")
                    else requireFile s (root ++ "/c-plugin-lock.json") content
                requireMissing s (root ++ "/.agents")
    forM_ roots $ \root -> writeFile s (root ++ "/c-plugin-lock.json") emptyLock
    forM_ allCases $ \(arguments, output) -> do
        result <- run s project arguments
        requireSuccess result
        requireOutput result output
        forM_ roots $ \root -> do
            requireFile s (root ++ "/c-plugin-lock.json") emptyLock
            requireMissing s (root ++ "/.agents")

githubListUnavailable :: Environment -> IO ()
githubListUnavailable environment = do
    (s, project) <- githubEnvironment environment "list-unavailable"
    run s project ["plugin", "add", githubPluginSource, "--ref", githubFixtureRef, "--all"] >>= requireSuccess
    entry <- githubRegisteredSource s project "plugin" "github-demo"
    commit <- githubPinnedCommit s entry
    run s project ["skill", "add", githubSoloSource, "--ref", commit] >>= requireSuccess
    let source = project </> registrationSource entry
    infraWithEnv s project (("HOME", home s) : blockedNetwork) ["git", "ls-remote", githubFixtureURL, "refs/heads/" ++ githubFixtureRef] >>= requireFailure
    originalLock <- digest s (project ++ "/c-plugin-lock.json")
    manifest <- digest s (source ++ "/plugin.json")
    forM_
        [ ["plugin", "skill", "disable", "github-demo", "--all"]
        , ["plugin", "skill", "enable", "github-demo", "--skill", "alpha"]
        , ["plugin", "skill", "enable", "github-demo", "--all"]
        ]
        $ \arguments -> do
            runWithEnv s project blockedNetwork arguments >>= requireSuccess
            current <- githubRegisteredSource s project "plugin" "github-demo"
            githubPinnedCommit s current >>= (`shouldBe` commit)
            requireDigest s (source ++ "/plugin.json") manifest
            if arguments !! 2 == "disable"
                then do
                    registrationSkills current `shouldBe` []
                    requireMissing s (project ++ "/.agents/skills/alpha")
                    requireMissing s (project ++ "/.agents/skills/beta")
                else requireSymlink s (project ++ "/.agents/skills/alpha") (source ++ "/skills/alpha")
    requireDigest s (project ++ "/c-plugin-lock.json") originalLock
    requireSymlink s (project ++ "/.agents/skills/beta") (source ++ "/skills/beta")
    let cacheRoot = project ++ "/.agents/c-plugin/sources"
        gitCalled = home s ++ "/git-called"
    writeFile s (home s ++ "/bin/git-template") ("#!/bin/sh\nprintf called > '" ++ gitCalled ++ "'\nexit 99\n")
    -- Copy the root-owned archive fixture to a sandbox-owned executable.
    infra s "" ["cp", home s ++ "/bin/git-template", home s ++ "/bin/git"] >>= requireSuccess
    infra s "" ["chmod", "+x", home s ++ "/bin/git"] >>= requireSuccess
    let offlineEnv = ("PATH", home s ++ "/bin:/usr/bin:/bin") : blockedNetwork
    remove s [cacheRoot, project ++ "/.agents/skills/alpha"]
    lock <- digest s (project ++ "/c-plugin-lock.json")
    state <- digest s (project ++ "/.agents/c-plugin-state.json")
    let plugins = pluginsHeading ++ "github-demo\t" ++ githubPluginSource ++ "@" ++ commit ++ "\talpha,beta\n"
        skills =
            skillsHeading
                ++ "alpha\tplugin:github-demo\t"
                ++ githubPluginSource
                ++ "@"
                ++ commit
                ++ "\n"
                ++ "beta\tplugin:github-demo\t"
                ++ githubPluginSource
                ++ "@"
                ++ commit
                ++ "\n"
                ++ "solo\tstandalone\t"
                ++ githubSoloSource
                ++ "@"
                ++ commit
                ++ "\n"
    forM_ (listCases plugins skills) $ \(arguments, output) -> do
        result <- runWithEnv s project offlineEnv arguments
        requireSuccess result
        requireOutput result output
        requireDigest s (project ++ "/c-plugin-lock.json") lock
        requireDigest s (project ++ "/.agents/c-plugin-state.json") state
        forM_ [cacheRoot, source, gitCalled, project ++ "/.agents/skills/alpha"] $ requireMissing s
        infra s "" ["test", "-L", project ++ "/.agents/skills/beta"] >>= requireSuccess
        infra s "" ["test", "-L", project ++ "/.agents/skills/solo"] >>= requireSuccess
