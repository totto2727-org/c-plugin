{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.Skill (ResolvedSkill (..), decodeSkill) where

import CPlugin.Internal.JSON (optionalString, validated)
import CPlugin.Types.Name
import CPlugin.Types.Path (AbsolutePath)
import Control.Monad (forM_, unless, void)
import Data.Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Aeson.Types (Parser, parseEither)
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.Yaml as Yaml

data ResolvedSkill = ResolvedSkill {resolvedSkillName :: ItemName, skillPath :: AbsolutePath} deriving (Eq, Show)

decodeSkill :: String -> BS.ByteString -> Either String ItemName
decodeSkill directory bytes = do
    text <- either (Left . show) Right (Text.decodeUtf8' bytes)
    header <- case Text.lines text of
        first : rest
            | Text.strip first == "---" ->
                let (yamlLines, closing) = break ((== "---") . Text.strip) rest
                 in if null closing then Left "missing closing YAML frontmatter delimiter" else Right (Text.unlines yamlLines)
        _ -> Left "missing YAML frontmatter"
    value <- either (Left . Yaml.prettyPrintParseException) Right (Yaml.decodeEither' (Text.encodeUtf8 header))
    parseEither parser value
  where
    parser = withObject "skill frontmatter" $ \o -> do
        name <- o .: "name" :: Parser String
        n <- validated (skillNameValue name)
        unless (name == directory) (fail "skill name must match directory")
        description <- o .: "description" :: Parser String
        unless (not (null description) && length description <= 1024) (fail "skill description must contain 1-1024 characters")
        forM_ ["license", "allowed-tools"] (optionalString o)
        case KeyMap.lookup "compatibility" o of
            Nothing -> pure ()
            Just v -> do
                compatibility <- parseJSON v :: Parser String
                unless (not (null compatibility) && length compatibility <= 500) (fail "invalid skill compatibility")
        case KeyMap.lookup "metadata" o of
            Nothing -> pure ()
            Just v -> void (parseJSON v :: Parser (Map.Map String String))
        pure n
