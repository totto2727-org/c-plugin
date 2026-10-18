{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module CPlugin.Types.Ownership (OwnershipSource (..), sourcePath, sourcePlugin, sourceSkill, OwnershipEntry (..), OwnershipState (..), PreviousOwnership (..), makeOwnership, makeEntry, decodeOwnership, validateOwnership) where

import CPlugin.Internal.Validation (uniqueMap)
import CPlugin.Types.Name
import CPlugin.Types.Path
import Control.Monad (unless)
import Data.Aeson (FromJSON, ToJSON, eitherDecodeStrict')
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import GHC.Generics (Generic)
import System.FilePath (takeDirectory, takeFileName)

data OwnershipSource = OwnershipSource RelativePath ItemName ItemName | StandaloneSource RelativePath ItemName
    deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

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
    deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

newtype OwnershipState = OwnershipState {ownershipEntries :: Map.Map AbsolutePath OwnershipEntry}
    deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

data PreviousOwnership = Trusted OwnershipState | Missing | Corrupt String deriving (Eq, Show)

makeEntry :: AbsolutePath -> FilePath -> AbsolutePath -> AbsolutePath -> OwnershipSource -> Either String OwnershipEntry
makeEntry link literal resolved root source = do
    checkedLink <- absolutePath (absoluteText link)
    checkedResolved <- absolutePath (absoluteText resolved)
    checkedRoot <- absolutePath (absoluteText root)
    checkedSource <- case source of
        OwnershipSource path plugin skill ->
            OwnershipSource
                <$> relativePath (relativeText path)
                <*> pluginNameValue (nameText plugin)
                <*> skillNameValue (nameText skill)
        StandaloneSource path skill ->
            StandaloneSource
                <$> relativePath (relativeText path)
                <*> skillNameValue (nameText skill)
    unless (takeDirectory (absoluteText checkedLink) == absoluteText checkedRoot) (Left "ownership link must be a direct child of managed root")
    unless (takeFileName (absoluteText checkedLink) == nameText (sourceSkill checkedSource)) (Left "ownership link name must match its source skill")
    unless (not (null literal) && '\0' `notElem` literal) (Left "ownership symlink target must be nonempty without NUL")
    pure (OwnershipEntry checkedLink literal checkedResolved checkedRoot checkedSource)

makeOwnership :: [OwnershipEntry] -> Either String OwnershipState
makeOwnership es = do
    checked <- traverse validateEntry es
    OwnershipState <$> uniqueMap "ownership links" entryLink checked

validateEntry :: OwnershipEntry -> Either String OwnershipEntry
validateEntry e = makeEntry (entryLink e) (symlinkTarget e) (resolvedTarget e) (managedRoot e) (entrySource e)

decodeOwnership :: BS.ByteString -> Either String OwnershipState
decodeOwnership bytes = eitherDecodeStrict' bytes >>= validateOwnership

validateOwnership :: OwnershipState -> Either String OwnershipState
validateOwnership (OwnershipState entries) = do
    mapM_ validateKey (Map.toList entries)
    makeOwnership (Map.elems entries)
  where
    validateKey (key, entry) = do
        checked <- absolutePath (absoluteText key)
        unless (checked == key && key == entryLink entry) (Left "ownership map key must match its canonical link path")
