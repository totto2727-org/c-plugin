{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.InstalledSkill (InstalledSkill (..), makeInstalledSkill) where

import CPlugin.Internal.JSON (validated)
import CPlugin.Types.Name (ItemName, nameText, skillNameValue)
import CPlugin.Types.Path (RelativePath, relativePath, relativeText)
import Control.Monad (unless)
import Data.Aeson
import Data.List (isPrefixOf)

data InstalledSkill = InstalledSkill
    { installedSkillName :: ItemName
    , installedSkillSource :: RelativePath
    }
    deriving (Eq, Show)

makeInstalledSkill :: ItemName -> RelativePath -> Either String InstalledSkill
makeInstalledSkill name source = do
    _ <- skillNameValue (nameText name)
    pure (InstalledSkill name source)

instance FromJSON InstalledSkill where
    parseJSON = withObject "installed standalone skill" $ \o -> do
        name <- o .: "name" >>= validated . skillNameValue
        raw <- o .: "source"
        unless ("./" `isPrefixOf` raw) (fail "standalone skill source must begin with ./")
        source <- validated (relativePath raw)
        validated (makeInstalledSkill name source)

instance ToJSON InstalledSkill where
    toJSON skill = object ["name" .= installedSkillName skill, "source" .= ("./" ++ relativeText (installedSkillSource skill))]
