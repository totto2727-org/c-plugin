{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module CPlugin.Types.Plugin (Plugin (..), makePlugin, makePluginWithOrigin, validatePlugin, samePluginSource) where

import CPlugin.Internal.Validation (uniqueSet)
import CPlugin.Types.GitHub
import CPlugin.Types.Name
import CPlugin.Types.Path
import Control.Monad (unless)
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Set as Set
import GHC.Generics (Generic)

data Plugin = Plugin
    { pluginName :: ItemName
    , pluginSource :: RelativePath
    , enabledSkills :: Set.Set ItemName
    , pluginOrigin :: Maybe GitHubOrigin
    }
    deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

makePlugin :: ItemName -> RelativePath -> [ItemName] -> Either String Plugin
makePlugin n p ss = makePluginWithOrigin n p ss Nothing

makePluginWithOrigin :: ItemName -> RelativePath -> [ItemName] -> Maybe GitHubOrigin -> Either String Plugin
makePluginWithOrigin n p ss origin = do
    name <- pluginNameValue (nameText n)
    source <- relativePath (relativeText p)
    skills <- traverse (skillNameValue . nameText) ss
    checkedOrigin <- traverse validateOrigin origin
    mapM_ (\value -> unless (source == githubSource value) (Left "plugin source does not match GitHub origin")) checkedOrigin
    selected <- uniqueSet "enabled skills" skills
    pure (Plugin name source selected checkedOrigin)

validatePlugin :: Plugin -> Either String Plugin
validatePlugin p = makePluginWithOrigin (pluginName p) (pluginSource p) (Set.toAscList (enabledSkills p)) (pluginOrigin p)

samePluginSource :: Plugin -> Plugin -> Bool
samePluginSource a b = case (pluginOrigin a, pluginOrigin b) of
    (Just x, Just y) -> sameGitHubSelection x y
    (Nothing, Nothing) -> pluginSource a == pluginSource b
    _ -> False
