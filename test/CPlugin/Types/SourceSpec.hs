module CPlugin.Types.SourceSpec (spec) where

import CPlugin.Types.GitHub (GitHubRepository, GitHubSubpath, githubLocationInput, githubRepository, githubSubpath)
import CPlugin.Types.Path (relativePath)
import CPlugin.Types.Source (InstallSource (..), parseInstallSource)
import Control.Monad (forM_)
import Data.Either (isLeft)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
    describe "mandatory explicit install source prefixes" $ do
        forM_ ["./plugin", "./skills/standalone", "./plugin/./", "./"] $ \path ->
            it ("accepts and validates explicit local source " ++ show path) $
                parseInstallSource ("local:" ++ path) `shouldBe` (LocalSource <$> relativePath path)
        forM_ ["", "./plugin", "owner/repo", "https://github.com/owner/repo", "plugin", "local", "github", "LOCAL:./plugin", "GitHub:owner/repo", "local:", "github:", "local:plugin", "local:/absolute", "local:../escape", "local:./../escape", "local:./safe/../escape", "local:./back\\slash", "local:./nul\0path", "local:github:owner/repo", "github:local:./plugin"] $ \input ->
            it ("rejects missing, malformed or unsafe source prefix " ++ show input) $ parseInstallSource input `shouldSatisfy` isLeft
        forM_
            [ ("owner/repo", "owner/repo", ".")
            , ("owner/repo/package", "owner/repo", "package")
            , ("Owner/Repo/plugins/demo", "owner/repo", "plugins/demo")
            , ("owner/repo.git/package", "owner/repo", "package")
            , ("https://github.com/owner/repo", "owner/repo", ".")
            , ("https://github.com/owner/repo.git/plugins/demo", "owner/repo", "plugins/demo")
            ]
            $ \(location, repository, subpath) ->
                it ("maps GitHub source to typed repository and explicit subpath " ++ show location) $
                    parseInstallSource ("github:" ++ location) `shouldBe` (uncurry GitHubSource <$> expectedLocation repository subpath)
    describe "typed GitHub location boundary" $ do
        forM_
            [ ("owner/repo", ".")
            , ("owner/repo.git", ".")
            , ("owner/repo/package", "package")
            , ("owner/repo/plugins/demo", "plugins/demo")
            , ("https://github.com/owner/repo.git/package", "package")
            , ("https://github.com/owner/repo/tree/main", "tree/main")
            ]
            $ \(location, subpath) ->
                it ("normalizes explicit GitHub location without inferring refs " ++ show location) $
                    githubLocationInput location `shouldBe` expectedLocation "owner/repo" subpath
        forM_
            [ "https://token@github.com/owner/repo/package"
            , "https://user:password@github.com/owner/repo/package"
            , "https://github.com.evil.invalid/owner/repo/package"
            , "https://evil.invalid/owner/repo/package"
            , "https://github.com:443/owner/repo/package"
            , "http://github.com/owner/repo/package"
            , "ssh://git@github.com/owner/repo/package"
            , "owner/repo/../escape"
            , "owner/repo/safe/../escape"
            , "owner/repo/.git/config"
            , "owner/repo//absolute"
            , "owner/repo/trailing/"
            , "owner/repo/back\\slash"
            , "owner/repo/nul\0path"
            , "https://github.com/owner/repo?token=secret"
            , "https://github.com/owner/repo#main"
            , "https://github.com/owner/repo/package?token=secret"
            , "https://github.com/owner/repo/package#main"
            ]
            $ \location -> it ("rejects unsafe GitHub location at both public boundaries " ++ show location) $ do
                githubLocationInput location `shouldSatisfy` isLeft
                parseInstallSource ("github:" ++ location) `shouldSatisfy` isLeft

expectedLocation :: String -> FilePath -> Either String (GitHubRepository, GitHubSubpath)
expectedLocation repository subpath = (,) <$> githubRepository repository <*> githubSubpath subpath
