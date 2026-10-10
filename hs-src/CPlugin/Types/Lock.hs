{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.Lock (Lock (..), emptyLock, makeLock) where

import CPlugin.Internal.JSON (validated)
import CPlugin.Internal.Validation (uniqueMap, uniqueSet)
import CPlugin.Types.Name (ItemName)
import CPlugin.Types.Path (RelativePath)
import CPlugin.Types.Plugin
import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.Types (Parser)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

data Lock = Lock
    {targets :: Set.Set RelativePath, plugins :: Map.Map ItemName Plugin}
    deriving (Eq, Show)

emptyLock :: Lock
emptyLock = Lock Set.empty Map.empty

makeLock :: [RelativePath] -> [Plugin] -> Either String Lock
makeLock ts ps = do
    mapM_ (\p -> makePlugin (pluginName p) (pluginSource p) (Set.toAscList (enabledSkills p))) ps
    ts' <- uniqueSet "lock targets" ts
    ps' <- uniqueMap "plugin names" pluginName ps
    _ <- uniqueSet "plugin sources" (map pluginSource ps)
    pure (Lock ts' ps')

instance FromJSON Lock where
    parseJSON = withObject "lock" $ \o -> do
        version <- o .: "version" :: Parser String
        unless (version == "3") (fail "unsupported lock version, expected 3")
        ts <- o .: "targets"
        ps <- o .: "plugins"
        validated (makeLock ts ps)
instance ToJSON Lock where
    toJSON lock = object ["version" .= String "3", "targets" .= Set.toAscList (targets lock), "plugins" .= Map.elems (plugins lock)]
