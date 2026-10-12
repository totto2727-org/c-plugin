{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.InstalledSkill (InstalledSkill (..), makeInstalledSkill, makeInstalledSkillWithOrigin, sameInstalledSkillSource) where

import CPlugin.Internal.JSON (validated)
import CPlugin.Types.GitHub
import CPlugin.Types.Name (ItemName, nameText, skillNameValue)
import CPlugin.Types.Path (RelativePath, relativePath, relativeText)
import Control.Monad (unless)
import Data.Aeson
import Data.List (isPrefixOf)

data InstalledSkill = InstalledSkill
    { installedSkillName :: ItemName
    , installedSkillSource :: RelativePath
    , installedSkillOrigin :: Maybe GitHubOrigin
    }
    deriving (Eq, Show)

makeInstalledSkill :: ItemName -> RelativePath -> Either String InstalledSkill
makeInstalledSkill name source = makeInstalledSkillWithOrigin name source Nothing

makeInstalledSkillWithOrigin :: ItemName -> RelativePath -> Maybe GitHubOrigin -> Either String InstalledSkill
makeInstalledSkillWithOrigin name source origin = do
    _ <- skillNameValue (nameText name)
    mapM_ (\value -> unless (source == githubSource value) (Left "standalone source does not match GitHub origin")) origin
    pure (InstalledSkill name source origin)

sameInstalledSkillSource :: InstalledSkill -> InstalledSkill -> Bool
sameInstalledSkillSource a b = case (installedSkillOrigin a, installedSkillOrigin b) of
    (Just x, Just y) -> sameGitHubSelection x y
    (Nothing, Nothing) -> installedSkillSource a == installedSkillSource b
    _ -> False

instance FromJSON InstalledSkill where
    parseJSON = withObject "installed standalone skill" $ \o -> do
        name <- o .: "name" >>= validated . skillNameValue
        raw <- o .: "source"
        unless ("./" `isPrefixOf` raw) (fail "standalone skill source must begin with ./")
        source <- validated (relativePath raw)
        origin <- o .:? "origin"
        validated (makeInstalledSkillWithOrigin name source origin)

instance ToJSON InstalledSkill where
    toJSON skill = object (["name" .= installedSkillName skill, "source" .= ("./" ++ relativeText (installedSkillSource skill))] ++ ["origin" .= value | Just value <- [installedSkillOrigin skill]])
