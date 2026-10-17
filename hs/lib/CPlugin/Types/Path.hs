{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module CPlugin.Types.Path (RelativePath, relativePath, relativeText, AbsolutePath, absolutePath, absoluteText) where

import Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import System.FilePath (dropTrailingPathSeparator, isAbsolute, normalise, splitDirectories)

newtype RelativePath = RelativePath FilePath deriving (Eq, Ord, Show, FromJSON, ToJSON, FromJSONKey, ToJSONKey)
newtype AbsolutePath = AbsolutePath FilePath deriving (Eq, Ord, Show, FromJSON, ToJSON, FromJSONKey, ToJSONKey)

relativeText :: RelativePath -> FilePath
relativeText (RelativePath p) = p
absoluteText :: AbsolutePath -> FilePath
absoluteText (AbsolutePath p) = p

relativePath :: FilePath -> Either String RelativePath
relativePath p
    | null p || isAbsolute p || '\\' `elem` p || '\0' `elem` p = Left "path must be relative"
    | ".." `elem` splitDirectories p = Left "path must not traverse parent directories"
    | otherwise = Right (RelativePath (dropTrailingPathSeparator (normalise p)))
absolutePath :: FilePath -> Either String AbsolutePath
absolutePath p
    | not (isAbsolute p) || '\0' `elem` p || ".." `elem` splitDirectories p = Left "path must be absolute without parent traversal"
    | otherwise = Right (AbsolutePath (dropTrailingPathSeparator (normalise p)))
