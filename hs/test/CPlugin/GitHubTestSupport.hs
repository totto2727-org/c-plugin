{-# LANGUAGE OverloadedStrings #-}

-- These fixtures exercise real Git locally. Only the transport mapping in the
-- consuming spec is synthetic, so this is not public GitHub acceptance coverage.
module CPlugin.GitHubTestSupport (
    withGitFixture,
    gitCommand,
    gitCommit,
    writeRemotePlugin,
    writeWideFixture,
) where

import CPlugin.Source.GitHub (runGit)
import CPlugin.TestSupport (inEnvironment, skillBytes, withFixture, writeFixture)
import CPlugin.Types.Lock (Lock)
import Control.Monad (forM_)
import qualified Data.ByteString.Char8 as BSC
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

withGitFixture :: (FilePath -> FilePath -> String -> Lock -> IO a) -> IO a
withGitFixture action = withFixture ["existing"] $ \base lock -> inEnvironment base $ do
    let repository = base </> "synthetic-remote"
    createDirectoryIfMissing True repository
    _ <- gitCommand repository ["init", "--initial-branch=main"]
    writeRemotePlugin repository "remote" ["alpha", "beta"]
    writeFixture (repository </> "standalone/SKILL.md") (skillBytes "standalone")
    commit <- gitCommit repository "initial fixture"
    _ <- gitCommand repository ["tag", "v1"]
    action base repository commit lock

writeRemotePlugin :: FilePath -> String -> [String] -> IO ()
writeRemotePlugin repository name skills = do
    let bytes = BSC.pack ("{\"$schema\":\"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json\",\"name\":\"" ++ name ++ "\"}")
    writeFixture (repository </> "package/plugin.json") bytes
    forM_ skills $ \skill -> writeFixture (repository </> "package/skills" </> skill </> "SKILL.md") (skillBytes skill)

writeWideFixture :: FilePath -> IO ()
writeWideFixture repository = forM_ [1 .. 65 :: Int] $ \index ->
    writeFixture (repository </> "package/content" </> ("file " ++ show index ++ ".txt")) (BSC.pack ("distinct regular fixture content " ++ show index))

gitCommit :: FilePath -> String -> IO String
gitCommit repository message = do
    _ <- gitCommand repository ["add", "--all"]
    _ <- gitCommand repository ["commit", "--message", message]
    filter (/= '\n') <$> gitCommand repository ["rev-parse", "HEAD"]

gitCommand :: FilePath -> [String] -> IO String
gitCommand repository arguments =
    runGit
        False
        repository
        ( [ "-c"
          , "commit.gpgSign=false"
          , "-c"
          , "user.name=Native Git fixture"
          , "-c"
          , "user.email=native-fixture@example.invalid"
          ]
            ++ arguments
        )
