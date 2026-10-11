{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.GitHubSpec (spec) where

import CPlugin.Paths (nameIO, relativeIO)
import CPlugin.StateStore (encodePretty)
import CPlugin.Types.GitHub (GitHubOrigin (..), GitHubSnapshot, githubCommit, githubRef, githubRepository, githubRepositoryInput, githubSource, githubSubpath, makeGitHubOrigin, repositoryURL, sameGitHubSelection, snapshotFor)
import CPlugin.Types.InstalledSkill (InstalledSkill (installedSkillOrigin), makeInstalledSkillWithOrigin)
import CPlugin.Types.Lock (makeLockWithSkills)
import CPlugin.Types.Path (relativeText)
import CPlugin.Types.Plugin (Plugin (pluginOrigin), makePluginWithOrigin)
import Control.Monad (forM_)
import Data.Aeson (eitherDecodeStrict')
import qualified Data.ByteString.Char8 as BSC
import Data.Either (isLeft, isRight)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
    describe "typed GitHub repository input" $ do
        it "constructs only the fixed HTTPS transport URL from a typed owner/repo" $
            fmap repositoryURL (githubRepository "fixture-owner/fixture-repo") `shouldBe` Right "https://github.com/fixture-owner/fixture-repo.git"
        it "normalizes ASCII repository identity case" $
            githubRepository "Fixture-Owner/Fixture-Repo" `shouldBe` githubRepository "fixture-owner/fixture-repo"
        forM_
            [ "https://github.com/owner/repo"
            , "https://user:password@github.com/owner/repo"
            , "https://token@github.com/owner/repo"
            , "https://github.com.evil.invalid/owner/repo"
            , "https://evil.invalid/owner/repo"
            , "http://github.com/owner/repo"
            , "ssh://git@github.com/owner/repo"
            , "git@github.com:owner/repo"
            , "https://github.com:443/owner/repo"
            , "https://github.com/owner/repo?token=secret"
            , "https://github.com/owner/repo#main"
            , "https://github.com/owner/repo/tree/main"
            , "owner/repo/child"
            , "../repo"
            , "owner/.."
            , "owner/repo\\child"
            , "owner/repo\0"
            , " owner/repo"
            , "owner/repo "
            , "owner/%2e%2e"
            , "--upload-pack/repo"
            ]
            $ \input -> it ("rejects unsafe repository " ++ show input) $ githubRepository input `shouldSatisfy` isLeft
    describe "public GitHub input normalization" $ do
        forM_ ["fixture-owner/fixture-repo", "https://github.com/fixture-owner/fixture-repo", "https://github.com/fixture-owner/fixture-repo.git"] $ \input ->
            it ("accepts and normalizes the approved input " ++ show input) $ githubRepositoryInput input `shouldBe` githubRepository "fixture-owner/fixture-repo"
        forM_ ["https://user:password@github.com/owner/repo", "https://token@github.com/owner/repo", "https://github.com.evil.invalid/owner/repo", "https://evil.invalid/owner/repo", "http://github.com/owner/repo", "ssh://git@github.com/owner/repo", "git@github.com:owner/repo", "https://github.com:443/owner/repo", "https://github.com/owner/repo?token=secret", "https://github.com/owner/repo#main", "https://github.com/owner/repo/tree/main", "https://github.com/owner/repo/../other", "https://github.com/owner/%2e%2e", "https://github.com/owner/repo\0"] $ \input ->
            it ("rejects unsafe public URL input " ++ show input) $ githubRepositoryInput input `shouldSatisfy` isLeft
    describe "typed GitHub revisions" $ do
        forM_ ["main", "v1.2.3", "feature/safe", replicate 40 'a'] $ \input ->
            it ("accepts safe revision " ++ show input) $ githubRef input `shouldSatisfy` isRight
        forM_ ["", "--upload-pack=evil", "-main", "main~1", "main^", "main:subpath", "main@{1}", "main..next", "main\\next", "main next", "main\nnext", "main\0", "/main", "main/"] $ \input ->
            it ("rejects unsafe revision " ++ show input) $ githubRef input `shouldSatisfy` isLeft
        forM_ ["", "main", replicate 39 'a', replicate 41 'a', replicate 40 'g'] $ \input ->
            it ("rejects non-full commit " ++ show input) $ githubCommit input `shouldSatisfy` isLeft
    describe "typed GitHub explicit subpaths" $ do
        it "accepts an explicit nested relative root" $ githubSubpath "plugins/example" `shouldSatisfy` isRight
        forM_ ["../escape", "safe/../escape", "/absolute", "back\\slash", "nul\0path"] $ \input ->
            it ("rejects unsafe repository subpath " ++ show input) $ githubSubpath input `shouldSatisfy` isLeft
    describe "GitHub provenance codec validation" $ do
        it "constructs a complete immutable origin from validated components" $ do
            let origin = do
                    repository <- githubRepository "fixture-owner/fixture-repo"
                    ref <- githubRef "main"
                    subpath <- githubSubpath "package"
                    commit <- githubCommit (replicate 40 'a')
                    pure (makeGitHubOrigin repository (Just ref) subpath commit)
            origin `shouldSatisfy` isRight
        it "encodes pinned provenance canonically and round trips" $ do
            origin <- testOrigin "main" 'a'
            encodePretty origin `shouldBe` "{\n  \"commit\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\n  \"kind\": \"github\",\n  \"ref\": \"main\",\n  \"repository\": \"fixture-owner/fixture-repo\",\n  \"subpath\": \"package\"\n}\n"
            eitherDecodeStrict' (encodePretty origin) `shouldBe` Right origin
            relativeText (githubSource origin) `shouldBe` ".agents/c-plugin/sources/fixture-owner/fixture-repo/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/tree/package"
        it "encodes snapshot provenance canonically without selection-specific ref or subpath" $ do
            origin <- testOrigin "main" 'a'
            let snapshot = snapshotFor origin
            encodePretty snapshot `shouldBe` "{\n  \"commit\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\n  \"repository\": \"fixture-owner/fixture-repo\",\n  \"version\": \"1\"\n}\n"
            eitherDecodeStrict' (encodePretty snapshot) `shouldBe` Right snapshot
        forM_ ["\"2\"", "1"] $ \version ->
            it ("rejects unsupported or numeric snapshot version wire " ++ version) $
                (eitherDecodeStrict' (BSC.pack ("{\"version\":" ++ version ++ ",\"repository\":\"fixture-owner/fixture-repo\",\"commit\":\"" ++ replicate 40 'a' ++ "\"}")) :: Either String GitHubSnapshot) `shouldSatisfy` isLeft
        it "keeps logical selection identity across commit updates but not across ref changes" $ do
            before <- testOrigin "main" 'a'
            updated <- testOrigin "main" 'b'
            otherRef <- testOrigin "v1" 'a'
            sameGitHubSelection before updated `shouldBe` True
            sameGitHubSelection before otherRef `shouldBe` False
        it "round trips a complete remote plugin and standalone version 3 lock" $ do
            origin <- testOrigin "main" 'a'
            name <- nameIO "remote"
            skillName <- nameIO "standalone"
            standaloneSubpath <- either (ioError . userError) pure (githubSubpath "standalone")
            let standaloneOrigin = origin{githubOriginSubpath = standaloneSubpath}
            plugin <- either (ioError . userError) pure (makePluginWithOrigin name (githubSource origin) [] (Just origin))
            skill <- either (ioError . userError) pure (makeInstalledSkillWithOrigin skillName (githubSource standaloneOrigin) (Just standaloneOrigin))
            lock <- either (ioError . userError) pure (makeLockWithSkills [] [plugin] [skill])
            eitherDecodeStrict' (encodePretty lock) `shouldBe` Right lock
        it "preserves existing local plugin and standalone codec shapes without origins" $ do
            let localPlugin = eitherDecodeStrict' "{\"name\":\"demo\",\"source\":\"./plugin\",\"skills\":[]}" :: Either String Plugin
                localSkill = eitherDecodeStrict' "{\"name\":\"alpha\",\"source\":\"./standalone\"}" :: Either String InstalledSkill
            fmap pluginOrigin localPlugin `shouldBe` Right Nothing
            fmap installedSkillOrigin localSkill `shouldBe` Right Nothing
            fmap encodePretty localPlugin `shouldBe` Right "{\n  \"name\": \"demo\",\n  \"skills\": [],\n  \"source\": \"./plugin\"\n}\n"
            fmap encodePretty localSkill `shouldBe` Right "{\n  \"name\": \"alpha\",\n  \"source\": \"./standalone\"\n}\n"
        it "rejects a local source paired with remote provenance at both constructors" $ do
            origin <- testOrigin "main" 'a'
            name <- nameIO "remote"
            source <- relativeIO "plugin"
            makePluginWithOrigin name source [] (Just origin) `shouldSatisfy` isLeft
            makeInstalledSkillWithOrigin name source (Just origin) `shouldSatisfy` isLeft
        forM_
            [ ("kind", "\"local\"")
            , ("repository", "\"https://token@github.com/owner/repo\"")
            , ("ref", "\"main^{tree}\"")
            , ("subpath", "\"../escape\"")
            , ("commit", "\"main\"")
            ]
            $ \(field, value) ->
                it ("rejects unsafe origin wire " ++ field) $
                    (eitherDecodeStrict' (originWire field value) :: Either String GitHubOrigin) `shouldSatisfy` isLeft
        it "rejects incomplete origin JSON rather than silently accepting unpinned provenance" $
            (eitherDecodeStrict' "{}" :: Either String GitHubOrigin) `shouldSatisfy` isLeft

testOrigin :: String -> Char -> IO GitHubOrigin
testOrigin ref digit = either (ioError . userError) pure $ do
    repository <- githubRepository "fixture-owner/fixture-repo"
    revision <- githubRef ref
    subpath <- githubSubpath "package"
    commit <- githubCommit (replicate 40 digit)
    pure (makeGitHubOrigin repository (Just revision) subpath commit)

originWire :: String -> String -> BSC.ByteString
originWire field replacement = BSC.pack ("{" ++ joinFields fields ++ "}")
  where
    fields = [("kind", "\"github\""), ("repository", "\"fixture-owner/fixture-repo\""), ("ref", "\"main\""), ("subpath", "\"package\""), ("commit", "\"" ++ replicate 40 'a' ++ "\"")]
    render (key, value) = "\"" ++ key ++ "\":" ++ if key == field then replacement else value
    joinFields [] = ""
    joinFields [entry] = render entry
    joinFields (entry : rest) = render entry ++ "," ++ joinFields rest
