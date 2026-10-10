{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module CPlugin.Codec (
    readLock,
    readOwnership,
    writeLock,
    writeOwnership,
    createLock,
    encodePretty,
    decodeManifest,
    decodeSkill,
) where

import CPlugin.Types
import Control.Exception (IOException, bracket, catch, mask, onException)
import Control.Monad (forM_, unless, void, when)
import Data.Aeson
import qualified Data.Aeson.Encode.Pretty as Pretty
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Aeson.Types (Parser, parseEither)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.Foldable (for_)
import Data.List (isPrefixOf, sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.Yaml as Yaml
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (hClose, hFlush)
import System.IO.Error (isAlreadyExistsError, isDoesNotExistError)
import System.Posix.Files (deviceID, fileID, getFdStatus, getSymbolicLinkStatus, isRegularFile)
import System.Posix.IO (OpenFileFlags (..), OpenMode (ReadOnly, WriteOnly), closeFd, defaultFileFlags, fdToHandle, openFd)
import System.Posix.Unistd (fileSynchronise)

validated :: Either String a -> Parser a
validated = either fail pure
instance FromJSON RelativePath where
    parseJSON = withText "relative path" (validated . relativePath . Text.unpack)
instance ToJSON RelativePath where
    toJSON = toJSON . relativeText
instance FromJSON AbsolutePath where
    parseJSON = withText "absolute path" (validated . absolutePath . Text.unpack)
instance ToJSON AbsolutePath where
    toJSON = toJSON . absoluteText
instance FromJSON ItemName where
    parseJSON = withText "item name" (validated . itemName . Text.unpack)
instance ToJSON ItemName where
    toJSON = toJSON . nameText
instance FromJSON Plugin where
    parseJSON = withObject "installed plugin" $ \o -> do
        n <- o .: "name" >>= validated . pluginNameValue
        raw <- o .: "source"
        unless ("./" `isPrefixOf` raw) (fail "plugin source must begin with ./")
        p <- validated (relativePath raw)
        ss <- o .: "skills"
        validated (makePlugin n p ss)
instance ToJSON Plugin where
    toJSON p = object ["name" .= pluginName p, "source" .= ("./" ++ relativeText (pluginSource p)), "skills" .= Set.toAscList (enabledSkills p)]
instance FromJSON Lock where
    parseJSON = withObject "lock" $ \o -> do
        version <- o .: "version" :: Parser String
        unless (version == "3") (fail "unsupported lock version, expected 3")
        ts <- o .: "targets"
        ps <- o .: "plugins"
        validated (makeLock ts ps)
instance ToJSON Lock where
    toJSON lock = object ["version" .= String "3", "targets" .= Set.toAscList (targets lock), "plugins" .= Map.elems (plugins lock)]
instance FromJSON OwnershipSource where
    parseJSON = withObject "ownership source" $ \o -> do
        p <- o .: "path"
        plugin <- o .: "plugin" >>= validated . pluginNameValue
        skill <- o .: "skill" >>= validated . skillNameValue
        pure (OwnershipSource p plugin skill)
instance ToJSON OwnershipSource where
    toJSON s = object ["path" .= sourcePath s, "plugin" .= sourcePlugin s, "skill" .= sourceSkill s]
instance FromJSON OwnershipEntry where
    parseJSON = withObject "ownership entry" $ \o -> do
        link <- o .: "link"
        literal <- o .: "symlinkTarget"
        resolved <- o .: "resolvedTarget"
        root <- o .: "managedRoot"
        source <- o .: "source"
        validated (makeEntry link literal resolved root source)
instance ToJSON OwnershipEntry where
    toJSON e = object ["link" .= entryLink e, "symlinkTarget" .= symlinkTarget e, "resolvedTarget" .= resolvedTarget e, "managedRoot" .= managedRoot e, "source" .= entrySource e]
instance FromJSON OwnershipState where
    parseJSON = withObject "ownership state" $ \o -> do
        version <- o .: "version" :: Parser String
        unless (version == "1") (fail "unsupported ownership version")
        entries <- o .: "entries"
        validated (makeOwnership entries)
instance ToJSON OwnershipState where
    toJSON (OwnershipState es) = object ["version" .= String "1", "entries" .= Map.elems es]

-- Canonical ordering and whitespace do not depend on Aeson's map traversal.
encodePretty :: (ToJSON a) => a -> BS.ByteString
encodePretty =
    BL.toStrict
        . Pretty.encodePretty'
            Pretty.defConfig
                { Pretty.confIndent = Pretty.Spaces 2
                , Pretty.confCompare = compare
                , Pretty.confTrailingNewline = True
                }

readLock :: FilePath -> IO Lock
readLock p = do
    bytes <- BS.readFile p
    either (ioError . userError . ("totto2727/c-plugin.StateStoreError.Decode " ++)) pure (eitherDecodeStrict' bytes)
readOwnership :: FilePath -> IO PreviousOwnership
readOwnership p =
    ( do
        status <- getSymbolicLinkStatus p
        if not (isRegularFile status)
            then pure (Corrupt "ownership state must be a physical regular file")
            else do
                bytes <- BS.readFile p
                pure (either Corrupt Trusted (eitherDecodeStrict' bytes))
    )
        `catch` \e ->
            if isDoesNotExistError e then pure Missing else ioError (e :: IOException)

-- Only the process that acquired the exclusive sibling may clean it up.
-- Compare inode identity so a replaced temporary path is never removed.
writeAtomic :: (ToJSON a) => FilePath -> a -> IO ()
writeAtomic p a = mask $ \restore -> do
    createDirectoryIfMissing True (takeDirectory p)
    let tmp = takeDirectory p </> (takeFileName p ++ ".tmp")
    fd <- openFd tmp WriteOnly (Just 0o600) defaultFileFlags{exclusive = True}
    identity <- getFdStatus fd `onException` closeFd fd
    let cleanup =
            ( do
                live <- getSymbolicLinkStatus tmp
                when ((fileID live, deviceID live) == (fileID identity, deviceID identity)) (removeFile tmp)
            )
                `catch` \(_ :: IOException) -> pure ()
    ( do
            h <- fdToHandle fd `onException` closeFd fd
            restore (BS.hPut h (encodePretty a) >> hFlush h >> fileSynchronise fd) `onException` hClose h
            hClose h
            live <- getSymbolicLinkStatus tmp
            unless
                ((fileID live, deviceID live) == (fileID identity, deviceID identity))
                (ioError (userError "temporary state path was replaced before commit"))
            renameFile tmp p
            syncDirectory (takeDirectory p)
        )
        `onException` cleanup

syncDirectory :: FilePath -> IO ()
syncDirectory p = bracket (openFd p ReadOnly Nothing defaultFileFlags) closeFd fileSynchronise

createLock :: FilePath -> Lock -> IO ()
createLock p lock = do
    createDirectoryIfMissing True (takeDirectory p)
    ( do
            fd <- openFd p WriteOnly (Just 0o600) defaultFileFlags{exclusive = True}
            h <- fdToHandle fd `onException` closeFd fd
            (BS.hPut h (encodePretty lock) >> hFlush h >> fileSynchronise fd) `onException` hClose h
            hClose h
            syncDirectory (takeDirectory p)
        )
        `catch` \e ->
            if isAlreadyExistsError e
                then ioError (userError ("totto2727/c-plugin.StateStoreError.AlreadyExists " ++ p))
                else ioError (e :: IOException)
writeLock :: FilePath -> Lock -> IO ()
writeLock = writeAtomic
writeOwnership :: FilePath -> OwnershipState -> IO ()
writeOwnership = writeAtomic

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

optionalString :: Object -> Key.Key -> Parser ()
optionalString o k = case KeyMap.lookup k o of
    Nothing -> pure ()
    Just v -> void (parseJSON v :: Parser String)

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
