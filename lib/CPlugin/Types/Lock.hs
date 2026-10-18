{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Types.Lock (Lock (..), emptyLock, makeLock, makeLockWithSkills, decodeLock, validateLock) where

import CPlugin.Internal.Validation (uniqueMap, uniqueSet)
import CPlugin.Types.GitHub (GitHubOrigin (..))
import CPlugin.Types.InstalledSkill
import CPlugin.Types.Name (ItemName, nameText, pluginNameValue, skillNameValue)
import CPlugin.Types.Path (RelativePath, relativePath, relativeText)
import CPlugin.Types.Plugin
import Control.Monad (unless, void)
import Data.Aeson (FromJSON, ToJSON, Value (..), eitherDecodeStrict', parseJSON)
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Aeson.Types (parseEither)
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GHC.Generics (Generic)

data Lock = Lock
    {targets :: Set.Set RelativePath, plugins :: Map.Map ItemName Plugin, standaloneSkills :: Map.Map ItemName InstalledSkill}
    deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

emptyLock :: Lock
emptyLock = Lock Set.empty Map.empty Map.empty

makeLock :: [RelativePath] -> [Plugin] -> Either String Lock
makeLock ts ps = makeLockWithSkills ts ps []

makeLockWithSkills :: [RelativePath] -> [Plugin] -> [InstalledSkill] -> Either String Lock
makeLockWithSkills ts ps ss = do
    checkedTargets <- traverse (relativePath . relativeText) ts
    checkedPlugins <- traverse validatePlugin ps
    checkedSkills <- traverse validateInstalledSkill ss
    ts' <- uniqueSet "lock targets" checkedTargets
    ps' <- uniqueMap "plugin names" pluginName checkedPlugins
    _ <- uniqueSet "plugin sources" (map pluginSource checkedPlugins)
    ss' <- uniqueMap "standalone skill names" installedSkillName checkedSkills
    _ <- uniqueSet "standalone skill sources" (map installedSkillSource checkedSkills)
    _ <- uniqueSet "plugin GitHub selections" [githubIdentity origin | p <- checkedPlugins, Just origin <- [pluginOrigin p]]
    _ <- uniqueSet "standalone GitHub selections" [githubIdentity origin | s <- checkedSkills, Just origin <- [installedSkillOrigin s]]
    let pluginSkills = Set.unions (map enabledSkills checkedPlugins)
    unless (Set.null (Map.keysSet ss' `Set.intersection` pluginSkills)) (Left "standalone skill name conflicts with an enabled plugin skill")
    pure (Lock ts' ps' ss')
  where
    githubIdentity origin = (githubOriginRepository origin, githubOriginRef origin, githubOriginSubpath origin)

decodeLock :: BS.ByteString -> Either String Lock
decodeLock bytes = do
    value <- eitherDecodeStrict' bytes
    validateRawSets value
    lock <- parseEither parseJSON value
    validateLock lock

validateLock :: Lock -> Either String Lock
validateLock lock = do
    mapM_ validatePluginKey (Map.toList (plugins lock))
    mapM_ validateSkillKey (Map.toList (standaloneSkills lock))
    makeLockWithSkills (Set.toAscList (targets lock)) (Map.elems (plugins lock)) (Map.elems (standaloneSkills lock))
  where
    validatePluginKey (key, plugin) = do
        checked <- pluginNameValue (nameText key)
        unless (checked == key && key == pluginName plugin) (Left "plugin map key must match its plugin name")
    validateSkillKey (key, skill) = do
        checked <- skillNameValue (nameText key)
        unless (checked == key && key == installedSkillName skill) (Left "standalone skill map key must match its skill name")

-- Inspect arrays before stock Set decoding discards duplicate input values.
validateRawSets :: Value -> Either String ()
validateRawSets (Object fields) = do
    mapM_ validateTargets (KeyMap.lookup "targets" fields)
    case KeyMap.lookup "plugins" fields of
        Just (Object registrations) -> mapM_ validateSkills registrations
        _ -> pure ()
  where
    validateTargets value = do
        raw <- parseEither parseJSON value :: Either String [RelativePath]
        checked <- traverse (relativePath . relativeText) raw
        void (uniqueSet "lock targets" checked)
    validateSkills (Object plugin) = mapM_ validateSelected (KeyMap.lookup "enabledSkills" plugin)
    validateSkills _ = pure ()
    validateSelected value = do
        raw <- parseEither parseJSON value :: Either String [ItemName]
        checked <- traverse (skillNameValue . nameText) raw
        void (uniqueSet "enabled skills" checked)
validateRawSets _ = pure ()
