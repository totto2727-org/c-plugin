{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.PluginManifest (PluginManifest (..), decodeManifest) where

import CPlugin.Internal.JSON (optionalString, validated)
import CPlugin.Types.Name
import Control.Monad (forM_, unless, void)
import Data.Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Aeson.Types (Parser, parseEither)
import qualified Data.ByteString as BS
import Data.Foldable (for_)
import Data.List (sortOn)

data PluginManifest = PluginManifest {manifestName :: ItemName, manifestWarnings :: [String]} deriving (Eq, Show)

decodeManifest :: BS.ByteString -> Either String PluginManifest
decodeManifest bytes = eitherDecodeStrict' bytes >>= parseEither parser
  where
    known = ["$schema", "name", "version", "description", "author", "homepage", "repository", "license", "keywords", "extensions"]
    parser = withObject "plugin manifest" $ \o -> do
        schema <- o .: "$schema" :: Parser String
        unless (schema == "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json") (fail "unsupported plugin $schema")
        n <- o .: "name" >>= validated . pluginNameValue
        forM_ ["version", "description", "homepage", "repository", "license"] (optionalString o)
        case KeyMap.lookup "keywords" o of
            Nothing -> pure ()
            Just v -> void (parseJSON v :: Parser [String])
        for_ (KeyMap.lookup "author" o) $
            withObject "author" $ \author -> do
                unless (all (`elem` ["name", "email", "url"]) (KeyMap.keys author)) (fail "unknown author field")
                forM_ ["name", "email", "url"] (optionalString author)
        let unknown = ["unknown top-level field: " ++ Key.toString k | k <- sortOn Key.toText (KeyMap.keys o), k `notElem` known]
            extensionsWarning = case KeyMap.lookup "extensions" o of
                Nothing -> []
                Just (Object _) -> []
                _ -> ["non-object extensions field ignored"]
        pure (PluginManifest n (unknown ++ extensionsWarning))
