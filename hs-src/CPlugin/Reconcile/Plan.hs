module CPlugin.Reconcile.Plan (SyncPlan (..), planSync) where

import CPlugin.Paths (absoluteIO, relativeLinkTarget, validateManagedRoot)
import CPlugin.Plugin (loadPlugin)
import CPlugin.Types.Lock
import CPlugin.Types.Name (ItemName, nameText)
import CPlugin.Types.Ownership
import CPlugin.Types.Path (AbsolutePath, absoluteText, relativeText)
import CPlugin.Types.Plugin
import CPlugin.Types.PluginManifest (manifestName)
import CPlugin.Types.Skill
import CPlugin.Types.Sync
import Control.Exception (IOException, try)
import Control.Monad (forM, unless)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.FilePath (takeDirectory, (</>))

data SyncPlan = SyncPlan
    { planBase :: FilePath
    , planStatePath :: FilePath
    , planStateRoot :: AbsolutePath
    , planDesired :: Map.Map AbsolutePath OwnershipEntry
    , planUnavailable :: Map.Map ItemName String
    , planWarnings :: [Notice]
    }

type PluginResolution = (Plugin, AbsolutePath, Either IOException ([ResolvedSkill], [String]))

planSync :: FilePath -> Lock -> IO SyncPlan
planSync lockPath lock = do
    let base = takeDirectory lockPath
        statePath = base </> ".agents/c-plugin-state.json"
    stateRoot <- absoluteIO (base </> ".agents")
    validateManagedRoot base stateRoot
    roots <-
        Set.fromList
            <$> mapM
                (absoluteIO . (base </>))
                (".agents/skills" : map relativeText (Set.toAscList (targets lock)))
    mapM_ (validateManagedRoot base) roots
    resolutions <- mapM (resolvePlugin base) (Map.elems (plugins lock))
    entries <- concat <$> mapM (resolutionEntries roots) resolutions
    -- Sorted plugin traversal makes the lexically greatest plugin the collision
    -- winner, independent of filesystem enumeration order.
    pure
        SyncPlan
            { planBase = base
            , planStatePath = statePath
            , planStateRoot = stateRoot
            , planDesired = Map.fromList [(entryLink e, e) | e <- entries]
            , planUnavailable = Map.fromList [(pluginName p, show e) | (p, _, Left e) <- resolutions]
            , planWarnings = [PluginWarning (absoluteText root) w | (_, root, Right (_, ws)) <- resolutions, w <- ws]
            }

resolvePlugin :: FilePath -> Plugin -> IO PluginResolution
resolvePlugin base plugin = do
    root <- absoluteIO (base </> relativeText (pluginSource plugin))
    result <- try $ do
        (manifest, skills, warnings) <- loadPlugin root
        unless (manifestName manifest == pluginName plugin) (ioError (userError "plugin name differs from lock"))
        pure (skills, warnings)
    pure (plugin, root, result)

resolutionEntries :: Set.Set AbsolutePath -> PluginResolution -> IO [OwnershipEntry]
resolutionEntries _ (_, _, Left _) = pure []
resolutionEntries roots (plugin, _, Right (skills, _)) =
    concat <$> mapM (skillEntries roots plugin) skills

skillEntries :: Set.Set AbsolutePath -> Plugin -> ResolvedSkill -> IO [OwnershipEntry]
skillEntries roots plugin skill
    | not (Set.member (resolvedSkillName skill) (enabledSkills plugin)) = pure []
    | otherwise = forM (Set.toAscList roots) (desiredEntry plugin skill)

desiredEntry :: Plugin -> ResolvedSkill -> AbsolutePath -> IO OwnershipEntry
desiredEntry plugin skill root = do
    link <- absoluteIO (absoluteText root </> nameText (resolvedSkillName skill))
    let source = OwnershipSource (pluginSource plugin) (pluginName plugin) (resolvedSkillName skill)
    either
        (ioError . userError)
        pure
        ( makeEntry
            link
            (relativeLinkTarget (absoluteText root) (absoluteText (skillPath skill)))
            (skillPath skill)
            root
            source
        )
