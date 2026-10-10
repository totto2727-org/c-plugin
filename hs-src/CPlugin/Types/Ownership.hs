{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.Ownership (OwnershipSource (..), OwnershipEntry (..), OwnershipState (..), PreviousOwnership (..), makeOwnership, makeEntry) where

import CPlugin.Internal.JSON (validated)
import CPlugin.Internal.Validation (uniqueMap)
import CPlugin.Types.Name
import CPlugin.Types.Path
import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.Types (Parser)
import qualified Data.Map.Strict as Map
import System.FilePath (takeDirectory, takeFileName)

data OwnershipSource = OwnershipSource
    {sourcePath :: RelativePath, sourcePlugin :: ItemName, sourceSkill :: ItemName}
    deriving (Eq, Ord, Show)
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
    _ <- pluginNameValue (nameText (sourcePlugin source))
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
