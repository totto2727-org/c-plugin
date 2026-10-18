{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.GitHub (
    GitHubRepository,
    githubRepository,
    githubRepositoryInput,
    githubLocationInput,
    repositoryText,
    repositoryURL,
    GitHubRef,
    githubRef,
    refText,
    GitHubSubpath,
    githubSubpath,
    subpathText,
    GitHubCommit,
    githubCommit,
    commitText,
    GitHubOrigin (..),
    makeGitHubOrigin,
    sameGitHubSelection,
    githubSource,
    GitHubSnapshot (..),
    snapshotFor,
    decodeOrigin,
    validateOrigin,
    decodeSnapshot,
    validateSnapshot,
) where

import CPlugin.Types.Path (RelativePath, relativePath)
import Control.Monad (when)
import Data.Aeson
import qualified Data.ByteString as BS
import Data.Char (isAlphaNum, isAscii, isHexDigit, toLower)
import Data.List (isInfixOf, isSuffixOf, stripPrefix)
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import GHC.Generics (Generic)
import System.FilePath ((</>))

newtype GitHubRepository = GitHubRepository String
    deriving stock (Eq, Ord, Show)
    deriving newtype (FromJSON, ToJSON, FromJSONKey, ToJSONKey)
newtype GitHubRef = GitHubRef String
    deriving stock (Eq, Ord, Show)
    deriving newtype (FromJSON, ToJSON, FromJSONKey, ToJSONKey)
newtype GitHubSubpath = GitHubSubpath FilePath
    deriving stock (Eq, Ord, Show)
    deriving newtype (FromJSON, ToJSON, FromJSONKey, ToJSONKey)
newtype GitHubCommit = GitHubCommit String
    deriving stock (Eq, Ord, Show)
    deriving newtype (FromJSON, ToJSON, FromJSONKey, ToJSONKey)

repositoryText :: GitHubRepository -> String
repositoryText (GitHubRepository value) = value
repositoryURL :: GitHubRepository -> String
repositoryURL repository = "https://github.com/" ++ repositoryText repository ++ ".git"
refText :: GitHubRef -> String
refText (GitHubRef value) = value
subpathText :: GitHubSubpath -> FilePath
subpathText (GitHubSubpath value) = value
commitText :: GitHubCommit -> String
commitText (GitHubCommit value) = value

githubRepository :: String -> Either String GitHubRepository
githubRepository raw = case break (== '/') raw of
    (owner, '/' : repo)
        | validOwner owner && validRepo repo -> Right (GitHubRepository (map toLower owner ++ "/" ++ map toLower repo))
    _ -> Left "GitHub repository must be owner/repo, without a URL, credentials, or .git suffix"
  where
    alpha c = isAscii c && isAlphaNum c
    validOwner value = not (null value) && length value <= 39 && all (\c -> alpha c || c == '-') value && head value /= '-' && last value /= '-' && not ("--" `isInfixOf` value)
    validRepo value = not (null value) && length value <= 100 && value /= "." && value /= ".." && not (".git" `isSuffixOf` map toLower value) && all (\c -> alpha c || c `elem` ("._-" :: String)) value

githubRepositoryInput :: String -> Either String GitHubRepository
githubRepositoryInput value = case stripPrefix "https://github.com/" value of
    Just path -> githubRepository (if ".git" `isSuffixOf` path then take (length path - 4) path else path)
    Nothing -> githubRepository value

githubLocationInput :: String -> Either String (GitHubRepository, GitHubSubpath)
githubLocationInput value = do
    let https = stripPrefix "https://github.com/" value
        location = fromMaybe value https
    when (any (`elem` ['?', '#']) value) (Left "GitHub source must not contain a query or fragment")
    case break (== '/') location of
        (owner, '/' : repositoryAndPath) -> do
            let (repositoryPart, suffix) = break (== '/') repositoryAndPath
                repositoryName = if ".git" `isSuffixOf` repositoryPart then take (length repositoryPart - 4) repositoryPart else repositoryPart
                rawPath = case suffix of
                    [] -> "."
                    _ : path -> path
            repository <- githubRepository (owner ++ "/" ++ repositoryName)
            subpath <- githubSubpath rawPath
            pure (repository, subpath)
        _ -> Left "GitHub source must identify owner/repo with an optional explicit subpath"

githubRef :: String -> Either String GitHubRef
githubRef value
    | null value || head value `elem` ['-', '+'] || value == "@" || head value == '/' || last value == '/' || last value == '.' = invalid
    | any (\c -> not (isAscii c) || c <= ' ' || c == '\DEL' || c `elem` ("~^:?*[\\" :: String)) value = invalid
    | any (`isInfixOf` value) ["..", "@{", "//"] = invalid
    | any ((\part -> null part || head part == '.' || ".lock" `isSuffixOf` part) . Text.unpack) (Text.splitOn "/" (Text.pack value)) = invalid
    | otherwise = Right (GitHubRef value)
  where
    invalid = Left "invalid explicit Git ref (use a branch, tag, or commit, not a revision expression)"

githubSubpath :: FilePath -> Either String GitHubSubpath
githubSubpath "." = Right (GitHubSubpath ".")
githubSubpath value
    | null value || head value == '/' || last value == '/' || '\\' `elem` value || any (\c -> c < ' ' || c == '\DEL') value = invalid
    | any (\part -> part `elem` ["", ".", ".."] || map toLower part == ".git") parts = invalid
    | otherwise = Right (GitHubSubpath value)
  where
    parts = map Text.unpack (Text.splitOn "/" (Text.pack value))
    invalid = Left "GitHub subpath must be . or an explicit relative directory without traversal or .git components"

githubCommit :: String -> Either String GitHubCommit
githubCommit value
    | length value == 40 && all (\c -> isAscii c && isHexDigit c) value = Right (GitHubCommit (map toLower value))
    | otherwise = Left "GitHub commit must be a full 40-character hexadecimal commit ID"

data GitHubOrigin = GitHubOrigin
    { githubOriginRepository :: GitHubRepository
    , githubOriginRef :: Maybe GitHubRef
    , githubOriginSubpath :: GitHubSubpath
    , githubOriginCommit :: GitHubCommit
    }
    deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

makeGitHubOrigin :: GitHubRepository -> Maybe GitHubRef -> GitHubSubpath -> GitHubCommit -> GitHubOrigin
makeGitHubOrigin = GitHubOrigin

sameGitHubSelection :: GitHubOrigin -> GitHubOrigin -> Bool
sameGitHubSelection a b = githubOriginRepository a == githubOriginRepository b && githubOriginRef a == githubOriginRef b && githubOriginSubpath a == githubOriginSubpath b

githubSource :: GitHubOrigin -> RelativePath
githubSource origin = either error id (relativePath (".agents/c-plugin/sources" </> repositoryText (githubOriginRepository origin) </> commitText (githubOriginCommit origin) </> "tree" </> subpathText (githubOriginSubpath origin)))

data GitHubSnapshot = GitHubSnapshot
    { snapshotRepository :: GitHubRepository
    , snapshotCommit :: GitHubCommit
    }
    deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

snapshotFor :: GitHubOrigin -> GitHubSnapshot
snapshotFor origin = GitHubSnapshot (githubOriginRepository origin) (githubOriginCommit origin)

decodeOrigin :: BS.ByteString -> Either String GitHubOrigin
decodeOrigin bytes = eitherDecodeStrict' bytes >>= validateOrigin

validateOrigin :: GitHubOrigin -> Either String GitHubOrigin
validateOrigin origin =
    GitHubOrigin
        <$> githubRepository (repositoryText (githubOriginRepository origin))
        <*> traverse (githubRef . refText) (githubOriginRef origin)
        <*> githubSubpath (subpathText (githubOriginSubpath origin))
        <*> githubCommit (commitText (githubOriginCommit origin))

decodeSnapshot :: BS.ByteString -> Either String GitHubSnapshot
decodeSnapshot bytes = eitherDecodeStrict' bytes >>= validateSnapshot

validateSnapshot :: GitHubSnapshot -> Either String GitHubSnapshot
validateSnapshot snapshot =
    GitHubSnapshot
        <$> githubRepository (repositoryText (snapshotRepository snapshot))
        <*> githubCommit (commitText (snapshotCommit snapshot))
