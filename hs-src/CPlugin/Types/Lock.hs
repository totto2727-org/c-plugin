{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.Lock (Lock (..), emptyLock, makeLock, makeLockWithSkills) where

import CPlugin.Internal.JSON (validated)
import CPlugin.Internal.Validation (uniqueMap, uniqueSet)
import CPlugin.Types.InstalledSkill
import CPlugin.Types.Name (ItemName)
import CPlugin.Types.Path (RelativePath)
import CPlugin.Types.Plugin
import Control.Monad (unless)
import Data.Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Aeson.Types (Parser)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

data Lock = Lock
    {targets :: Set.Set RelativePath, plugins :: Map.Map ItemName Plugin, standaloneSkills :: Map.Map ItemName InstalledSkill}
    deriving (Eq, Show)

emptyLock :: Lock
emptyLock = Lock Set.empty Map.empty Map.empty

makeLock :: [RelativePath] -> [Plugin] -> Either String Lock
makeLock ts ps = makeLockWithSkills ts ps []

makeLockWithSkills :: [RelativePath] -> [Plugin] -> [InstalledSkill] -> Either String Lock
makeLockWithSkills ts ps ss = do
    mapM_ (\p -> makePlugin (pluginName p) (pluginSource p) (Set.toAscList (enabledSkills p))) ps
    ts' <- uniqueSet "lock targets" ts
    ps' <- uniqueMap "plugin names" pluginName ps
    _ <- uniqueSet "plugin sources" (map pluginSource ps)
    mapM_ (\s -> makeInstalledSkill (installedSkillName s) (installedSkillSource s)) ss
    ss' <- uniqueMap "standalone skill names" installedSkillName ss
    _ <- uniqueSet "standalone skill sources" (map installedSkillSource ss)
    let pluginSkills = Set.unions (map enabledSkills ps)
    unless (Set.null (Map.keysSet ss' `Set.intersection` pluginSkills)) (Left "standalone skill name conflicts with an enabled plugin skill")
    pure (Lock ts' ps' ss')

instance FromJSON Lock where
    parseJSON = withObject "lock" $ \o -> do
        version <- o .: "version" :: Parser String
        unless (version == "3") (fail "unsupported lock version, expected 3")
        ts <- o .: "targets"
        ps <- o .: "plugins"
        ss <- if KeyMap.member "skills" o then o .: "skills" else pure []
        validated (makeLockWithSkills ts ps ss)
instance ToJSON Lock where
    toJSON lock = object (["version" .= String "3", "targets" .= Set.toAscList (targets lock), "plugins" .= Map.elems (plugins lock)] ++ ["skills" .= Map.elems (standaloneSkills lock) | not (Map.null (standaloneSkills lock))])
