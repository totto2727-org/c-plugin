module CPlugin.Reconcile.Plan (SyncPlan (..), planSync) where

import CPlugin.Paths (absoluteIO, relativeLinkTarget, strictRealPath, validateManagedRoot, within)
import CPlugin.Plugin (loadPlugin, loadStandaloneSkill)
import CPlugin.Types.InstalledSkill
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
    , planUnavailableSkills :: Map.Map ItemName String
    , planWarnings :: [Notice]
    }

type PluginResolution = (Plugin, AbsolutePath, Either IOException ([ResolvedSkill], [String]))
type SkillResolution = (InstalledSkill, Either IOException ResolvedSkill)

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
    skillResolutions <- mapM (resolveStandalone base) (Map.elems (standaloneSkills lock))
    pluginEntries <- concat <$> mapM (resolutionEntries roots) resolutions
    standaloneEntries <- concat <$> mapM (standaloneResolutionEntries roots) skillResolutions
    let entries = pluginEntries ++ standaloneEntries
    -- Sorted plugin traversal makes the lexically greatest plugin the collision
    -- winner, independent of filesystem enumeration order.
    pure
        SyncPlan
            { planBase = base
            , planStatePath = statePath
            , planStateRoot = stateRoot
            , planDesired = Map.fromList [(entryLink e, e) | e <- entries]
            , planUnavailable = Map.fromList [(pluginName p, show e) | (p, _, Left e) <- resolutions]
            , planUnavailableSkills = Map.fromList [(installedSkillName s, show e) | (s, Left e) <- skillResolutions]
            , planWarnings = [PluginWarning (absoluteText root) w | (_, root, Right (_, ws)) <- resolutions, w <- ws]
            }

resolvePlugin :: FilePath -> Plugin -> IO PluginResolution
resolvePlugin base plugin = do
    root <- absoluteIO (base </> relativeText (pluginSource plugin))
    result <- try $ do
        validateSourceRoot base root
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
desiredEntry plugin skill =
    desiredEntryFor (OwnershipSource (pluginSource plugin) (pluginName plugin) (resolvedSkillName skill)) skill

resolveStandalone :: FilePath -> InstalledSkill -> IO SkillResolution
resolveStandalone base installed = do
    root <- absoluteIO (base </> relativeText (installedSkillSource installed))
    result <- try $ do
        validateSourceRoot base root
        skill <- loadStandaloneSkill root
        unless (resolvedSkillName skill == installedSkillName installed) (ioError (userError "skill name differs from lock"))
        pure skill
    pure (installed, result)

validateSourceRoot :: FilePath -> AbsolutePath -> IO ()
validateSourceRoot base root = do
    physicalBase <- strictRealPath base
    physicalRoot <- strictRealPath (absoluteText root)
    unless (within physicalBase physicalRoot) (ioError (userError "local source resolves outside lock root"))

standaloneResolutionEntries :: Set.Set AbsolutePath -> SkillResolution -> IO [OwnershipEntry]
standaloneResolutionEntries _ (_, Left _) = pure []
standaloneResolutionEntries roots (installed, Right skill) =
    forM (Set.toAscList roots) (desiredEntryFor source skill)
  where
    source = StandaloneSource (installedSkillSource installed) (installedSkillName installed)

desiredEntryFor :: OwnershipSource -> ResolvedSkill -> AbsolutePath -> IO OwnershipEntry
desiredEntryFor source skill root = do
    link <- absoluteIO (absoluteText root </> nameText (resolvedSkillName skill))
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
