module CPlugin.Plugin (loadPlugin, loadStandaloneSkill) where

import CPlugin.Internal.Concurrent (mapConcurrentlyIO, withIO)
import CPlugin.Paths (absoluteIO, pathKind, strictRealPath, within)
import CPlugin.Types.Path (AbsolutePath, absoluteText)
import CPlugin.Types.PluginManifest
import CPlugin.Types.Skill
import Control.Exception (IOException, try)
import Control.Monad (unless)
import qualified Data.ByteString as BS
import Data.List (sort)
import System.Directory (listDirectory)
import System.FilePath (takeFileName, (</>))
import System.Posix.Files (getFileStatus, isDirectory, isRegularFile)

-- Standalone installation reads only this directory's SKILL.md. It never
-- infers a plugin or searches for skill roots in surrounding directories.
loadStandaloneSkill :: AbsolutePath -> IO ResolvedSkill
loadStandaloneSkill root = do
    let rootText = absoluteText root
        marker = rootText </> "SKILL.md"
    physicalRoot <- strictRealPath rootText
    status <- getFileStatus rootText
    unless (isDirectory status) (ioError (userError "skill root must resolve to a directory"))
    physicalMarker <- strictRealPath marker
    unless (within physicalRoot physicalMarker) (ioError (userError "SKILL.md resolves outside skill root"))
    markerStatus <- getFileStatus marker
    unless (isRegularFile markerStatus) (ioError (userError "SKILL.md must resolve to a regular file"))
    name <- withIO (BS.readFile marker) >>= either (ioError . userError) pure . decodeSkill (takeFileName rootText)
    physical <- absoluteIO physicalRoot
    pure (ResolvedSkill name physical)

-- A plugin is one root manifest plus fixed, immediate skill directories.
-- Manifest failure rejects the plugin. Component and skill failures are narrow
-- warnings, preserving valid siblings without probing unsupported components.
loadPlugin :: AbsolutePath -> IO (PluginManifest, [ResolvedSkill], [String])
loadPlugin root = do
    let rootText = absoluteText root
        manifestPath = rootText </> "plugin.json"
    physicalRoot <- strictRealPath rootText
    rootStatus <- getFileStatus rootText
    unless (isDirectory rootStatus) (ioError (userError "plugin root must resolve to a directory"))
    manifestPhysical <- strictRealPath manifestPath
    unless (within physicalRoot manifestPhysical) (ioError (userError "plugin.json resolves outside plugin root"))
    manifestStatus <- getFileStatus manifestPath
    unless (isRegularFile manifestStatus) (ioError (userError "plugin.json must resolve to a regular file"))
    manifest <- withIO (BS.readFile manifestPath) >>= either (ioError . userError) pure . decodeManifest
    let skillsRoot = rootText </> "skills"
    kind <- pathKind skillsRoot
    case kind of
        Nothing -> pure (manifest, [], manifestWarnings manifest)
        Just _ -> do
            component <-
                try
                    ( do
                        physical <- strictRealPath skillsRoot
                        unless (within physicalRoot physical) (ioError (userError "skills resolves outside plugin root"))
                        status <- getFileStatus skillsRoot
                        unless (isDirectory status) (ioError (userError "skills must resolve to a directory"))
                        sort <$> listDirectory skillsRoot
                    ) ::
                    IO (Either IOException [FilePath])
            case component of
                Left e -> pure (manifest, [], manifestWarnings manifest ++ ["invalid skills component: " ++ show e])
                Right names -> do
                    candidates <-
                        mapConcurrentlyIO
                            ( \name -> do
                                result <- try (readSkill physicalRoot skillsRoot name) :: IO (Either IOException (Maybe ResolvedSkill))
                                pure $ case result of
                                    Left e -> ([], ["invalid skill " ++ name ++ ": " ++ show e])
                                    Right Nothing -> ([], [])
                                    Right (Just skill) -> ([skill], [])
                            )
                            names
                    pure (manifest, concatMap fst candidates, manifestWarnings manifest ++ concatMap snd candidates)

readSkill :: FilePath -> FilePath -> String -> IO (Maybe ResolvedSkill)
readSkill physicalRoot skillsRoot name = do
    let directory = skillsRoot </> name
        marker = directory </> "SKILL.md"
    physicalDirectory <- strictRealPath directory
    unless (within physicalRoot physicalDirectory) (ioError (userError "skill directory resolves outside plugin root"))
    status <- getFileStatus directory
    if not (isDirectory status)
        then pure Nothing
        else do
            markerKind <- pathKind marker
            case markerKind of
                Nothing -> pure Nothing
                Just _ -> do
                    physicalMarker <- strictRealPath marker
                    unless (within physicalRoot physicalMarker) (ioError (userError "SKILL.md resolves outside plugin root"))
                    markerStatus <- getFileStatus marker
                    if not (isRegularFile markerStatus)
                        then pure Nothing
                        else do
                            n <- withIO (BS.readFile marker) >>= either (ioError . userError) pure . decodeSkill name
                            resolved <- absoluteIO physicalDirectory
                            pure (Just (ResolvedSkill n resolved))
