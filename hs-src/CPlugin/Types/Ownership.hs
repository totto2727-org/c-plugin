{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.Ownership (OwnershipSource (..), sourcePath, sourcePlugin, sourceSkill, OwnershipEntry (..), OwnershipState (..), PreviousOwnership (..), makeOwnership, makeEntry) where

import CPlugin.Internal.JSON (validated)
import CPlugin.Internal.Validation (uniqueMap)
import CPlugin.Types.Name
import CPlugin.Types.Path
import Control.Monad (unless, when)
import Data.Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Aeson.Types (Parser)
import qualified Data.Map.Strict as Map
import System.FilePath (takeDirectory, takeFileName)

data OwnershipSource = OwnershipSource RelativePath ItemName ItemName | StandaloneSource RelativePath ItemName
    deriving (Eq, Ord, Show)

sourcePath :: OwnershipSource -> RelativePath
sourcePath (OwnershipSource path _ _) = path
sourcePath (StandaloneSource path _) = path

sourcePlugin :: OwnershipSource -> Maybe ItemName
sourcePlugin (OwnershipSource _ plugin _) = Just plugin
sourcePlugin (StandaloneSource _ _) = Nothing

sourceSkill :: OwnershipSource -> ItemName
sourceSkill (OwnershipSource _ _ skill) = skill
sourceSkill (StandaloneSource _ skill) = skill
data OwnershipEntry = OwnershipEntry
    { entryLink :: AbsolutePath
    , symlinkTarget :: FilePath
    , resolvedTarget :: AbsolutePath
    , managedRoot :: AbsolutePath
    , entrySource :: OwnershipSource
    }
    deriving (Eq, Ord, Show)
newtype OwnershipState = OwnershipState {ownershipEntries :: Map.Map AbsolutePath OwnershipEntry}
    deriving (Eq, Show)
data PreviousOwnership = Trusted OwnershipState | Missing | Corrupt String deriving (Eq, Show)

makeEntry :: AbsolutePath -> FilePath -> AbsolutePath -> AbsolutePath -> OwnershipSource -> Either String OwnershipEntry
makeEntry link literal resolved root source = do
    mapM_ (pluginNameValue . nameText) (sourcePlugin source)
    _ <- skillNameValue (nameText (sourceSkill source))
    if takeDirectory (absoluteText link) /= absoluteText root
        then Left "ownership link must be a direct child of managed root"
        else
            if takeFileName (absoluteText link) /= nameText (sourceSkill source)
                then Left "ownership link name must match its source skill"
                else
                    if null literal || '\0' `elem` literal
                        then Left "ownership symlink target must be nonempty without NUL"
                        else Right (OwnershipEntry link literal resolved root source)
makeOwnership :: [OwnershipEntry] -> Either String OwnershipState
makeOwnership es = OwnershipState <$> uniqueMap "ownership links" entryLink es

instance FromJSON OwnershipSource where
    parseJSON = withObject "ownership source" $ \o -> do
        p <- o .: "path"
        skill <- o .: "skill" >>= validated . skillNameValue
        case KeyMap.lookup "kind" o of
            Nothing -> do
                plugin <- o .: "plugin" >>= validated . pluginNameValue
                pure (OwnershipSource p plugin skill)
            Just (String "standalone") -> do
                when (KeyMap.member "plugin" o) (fail "standalone ownership source must not contain plugin")
                pure (StandaloneSource p skill)
            _ -> fail "unsupported ownership source kind"
instance ToJSON OwnershipSource where
    toJSON (OwnershipSource path plugin skill) = object ["path" .= path, "plugin" .= plugin, "skill" .= skill]
    toJSON (StandaloneSource path skill) = object ["kind" .= String "standalone", "path" .= path, "skill" .= skill]
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
