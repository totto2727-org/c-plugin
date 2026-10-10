module CPlugin.Plugin (loadPlugin) where

import CPlugin.Codec (decodeManifest, decodeSkill)
import CPlugin.Paths (absoluteIO, pathKind, strictRealPath, within)
import CPlugin.Types
import Control.Exception (IOException, try)
import Control.Monad (forM, unless)
import qualified Data.ByteString as BS
import Data.List (sort)
import System.Directory (listDirectory)
import System.FilePath ((</>))
import System.Posix.Files (getFileStatus, isDirectory, isRegularFile)

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
    manifest <- BS.readFile manifestPath >>= either (ioError . userError) pure . decodeManifest
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
                    candidates <- forM names $ \name -> do
                        result <- try (readSkill physicalRoot skillsRoot name) :: IO (Either IOException (Maybe ResolvedSkill))
                        pure $ case result of
                            Left e -> ([], ["invalid skill " ++ name ++ ": " ++ show e])
                            Right Nothing -> ([], [])
                            Right (Just skill) -> ([skill], [])
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
                            n <- BS.readFile marker >>= either (ioError . userError) pure . decodeSkill name
                            resolved <- absoluteIO physicalDirectory
                            pure (Just (ResolvedSkill n resolved))
