{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module CPlugin.Types.InstalledSkill (InstalledSkill (..), makeInstalledSkill, makeInstalledSkillWithOrigin, validateInstalledSkill, sameInstalledSkillSource) where

import CPlugin.Types.GitHub
import CPlugin.Types.Name (ItemName, nameText, skillNameValue)
import CPlugin.Types.Path (RelativePath, relativePath, relativeText)
import Control.Monad (unless)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

data InstalledSkill = InstalledSkill
    { installedSkillName :: ItemName
    , installedSkillSource :: RelativePath
    , installedSkillOrigin :: Maybe GitHubOrigin
    }
    deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

makeInstalledSkill :: ItemName -> RelativePath -> Either String InstalledSkill
makeInstalledSkill name source = makeInstalledSkillWithOrigin name source Nothing

makeInstalledSkillWithOrigin :: ItemName -> RelativePath -> Maybe GitHubOrigin -> Either String InstalledSkill
makeInstalledSkillWithOrigin name source origin = do
    checkedName <- skillNameValue (nameText name)
    checkedSource <- relativePath (relativeText source)
    checkedOrigin <- traverse validateOrigin origin
    mapM_ (\value -> unless (checkedSource == githubSource value) (Left "standalone source does not match GitHub origin")) checkedOrigin
    pure (InstalledSkill checkedName checkedSource checkedOrigin)

validateInstalledSkill :: InstalledSkill -> Either String InstalledSkill
validateInstalledSkill skill = makeInstalledSkillWithOrigin (installedSkillName skill) (installedSkillSource skill) (installedSkillOrigin skill)

sameInstalledSkillSource :: InstalledSkill -> InstalledSkill -> Bool
sameInstalledSkillSource a b = case (installedSkillOrigin a, installedSkillOrigin b) of
    (Just x, Just y) -> sameGitHubSelection x y
    (Nothing, Nothing) -> installedSkillSource a == installedSkillSource b
    _ -> False
