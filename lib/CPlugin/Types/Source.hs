module CPlugin.Types.Source (InstallSource (..), parseInstallSource) where

import CPlugin.Types.GitHub (GitHubRepository, GitHubSubpath, githubLocationInput)
import CPlugin.Types.Path (RelativePath, relativePath)
import Data.List (isPrefixOf, stripPrefix)

-- Source kind is mandatory and explicit. Parsing never scans directories,
-- detects vendor formats, or treats a GitHub subpath as a ref selection.
data InstallSource
    = LocalSource RelativePath
    | GitHubSource GitHubRepository GitHubSubpath
    deriving (Eq, Show)

parseInstallSource :: String -> Either String InstallSource
parseInstallSource value = case stripPrefix "local:" value of
    Just path
        | "./" `isPrefixOf` path -> LocalSource <$> relativePath path
        | otherwise -> Left "local source must use local:./PATH relative to the owning lock root"
    Nothing -> case stripPrefix "github:" value of
        Just location -> uncurry GitHubSource <$> githubLocationInput location
        Nothing -> Left "source must use an explicit local:./PATH or github:OWNER/REPO[/PATH] prefix"
