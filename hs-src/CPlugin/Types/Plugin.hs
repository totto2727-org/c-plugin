{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.Plugin (Plugin (..), makePlugin, makePluginWithOrigin, samePluginSource) where

import CPlugin.Internal.JSON (validated)
import CPlugin.Internal.Validation (uniqueSet)
import CPlugin.Types.GitHub
import CPlugin.Types.Name
import CPlugin.Types.Path
import Control.Monad (unless)
import Data.Aeson
import Data.List (isPrefixOf)
import qualified Data.Set as Set

data Plugin = Plugin
    { pluginName :: ItemName
    , pluginSource :: RelativePath
    , enabledSkills :: Set.Set ItemName
    , pluginOrigin :: Maybe GitHubOrigin
    }
    deriving (Eq, Show)

makePlugin :: ItemName -> RelativePath -> [ItemName] -> Either String Plugin
makePlugin n p ss = makePluginWithOrigin n p ss Nothing

makePluginWithOrigin :: ItemName -> RelativePath -> [ItemName] -> Maybe GitHubOrigin -> Either String Plugin
makePluginWithOrigin n p ss origin = do
    _ <- pluginNameValue (nameText n)
    mapM_ (skillNameValue . nameText) ss
    mapM_ (\value -> unless (p == githubSource value) (Left "plugin source does not match GitHub origin")) origin
    selected <- uniqueSet "enabled skills" ss
    pure (Plugin n p selected origin)

samePluginSource :: Plugin -> Plugin -> Bool
samePluginSource a b = case (pluginOrigin a, pluginOrigin b) of
    (Just x, Just y) -> sameGitHubSelection x y
    (Nothing, Nothing) -> pluginSource a == pluginSource b
    _ -> False

instance FromJSON Plugin where
    parseJSON = withObject "installed plugin" $ \o -> do
        n <- o .: "name" >>= validated . pluginNameValue
        raw <- o .: "source"
        unless ("./" `isPrefixOf` raw) (fail "plugin source must begin with ./")
        p <- validated (relativePath raw)
        ss <- o .: "skills"
        origin <- o .:? "origin"
        validated (makePluginWithOrigin n p ss origin)
instance ToJSON Plugin where
    toJSON p = object (["name" .= pluginName p, "source" .= ("./" ++ relativeText (pluginSource p)), "skills" .= Set.toAscList (enabledSkills p)] ++ ["origin" .= value | Just value <- [pluginOrigin p]])
