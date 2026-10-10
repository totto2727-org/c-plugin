{-# LANGUAGE OverloadedStrings #-}

module CPlugin.TestSupport (
    manifestBytes,
    skillBytes,
    writeFixture,
    fixturePlugin,
    fixtureLock,
    withFixture,
    inEnvironment,
) where

import CPlugin.Paths (nameIO, relativeIO, strictRealPath)
import CPlugin.StateStore (writeLock)
import CPlugin.Types.Lock (Lock, makeLock)
import CPlugin.Types.Name (pluginNameValue)
import CPlugin.Types.Plugin (Plugin, makePlugin)
import Control.Exception (bracket)
import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import System.Directory (createDirectoryIfMissing, withCurrentDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withTempDirectory)

manifestBytes :: BS.ByteString -> BS.ByteString
manifestBytes extra = "{\"$schema\":\"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json\",\"name\":\"demo\"" <> extra <> "}"
skillBytes :: String -> BS.ByteString
skillBytes n = Text.encodeUtf8 (Text.pack ("---\nname: " ++ n ++ "\ndescription: Test skill.\n---\n"))
writeFixture :: FilePath -> BS.ByteString -> IO ()
writeFixture p bytes = createDirectoryIfMissing True (takeDirectory p) >> BS.writeFile p bytes
fixturePlugin :: String -> FilePath -> [String] -> IO Plugin
fixturePlugin n p ss = do
    name <- either (ioError . userError) pure (pluginNameValue n)
    source <- relativeIO p
    skills <- mapM nameIO ss
    either (ioError . userError) pure (makePlugin name source skills)
fixtureLock :: [String] -> IO Lock
fixtureLock ss = do
    plugin <- fixturePlugin "demo" "./plugin" ss
    either (ioError . userError) pure (makeLock [] [plugin])
withFixture :: [String] -> (FilePath -> Lock -> IO a) -> IO a
withFixture names action = do
    createDirectoryIfMissing True "tmp"
    withTempDirectory "tmp" "native-spec-" $ \raw -> do
        base <- strictRealPath raw
        writeFixture (base </> "plugin/plugin.json") (manifestBytes "")
        forM_ names $ \n -> writeFixture (base </> "plugin/skills" </> n </> "SKILL.md") (skillBytes n)
        lock <- fixtureLock names
        writeLock (base </> "c-plugin-lock.json") lock
        action base lock
inEnvironment :: FilePath -> IO a -> IO a
inEnvironment base action = bracket (lookupEnv "HOME") restore $ \_ -> do
    setEnv "HOME" base
    withCurrentDirectory base action
  where
    restore Nothing = unsetEnv "HOME"
    restore (Just old) = setEnv "HOME" old
