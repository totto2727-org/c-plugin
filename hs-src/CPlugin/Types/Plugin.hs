{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.Plugin (Plugin (..), makePlugin) where

import CPlugin.Internal.JSON (validated)
import CPlugin.Internal.Validation (uniqueSet)
import CPlugin.Types.Name
import CPlugin.Types.Path
import Control.Monad (unless)
import Data.Aeson
import Data.List (isPrefixOf)
import qualified Data.Set as Set

data Plugin = Plugin
    {pluginName :: ItemName, pluginSource :: RelativePath, enabledSkills :: Set.Set ItemName}
    deriving (Eq, Show)

makePlugin :: ItemName -> RelativePath -> [ItemName] -> Either String Plugin
makePlugin n p ss = do
    _ <- pluginNameValue (nameText n)
    mapM_ (skillNameValue . nameText) ss
    Plugin n p <$> uniqueSet "enabled skills" ss

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
