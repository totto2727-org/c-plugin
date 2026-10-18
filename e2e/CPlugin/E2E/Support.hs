{-# LANGUAGE OverloadedStrings #-}

module CPlugin.E2E.Support where

import Control.Monad (forM, unless)
import qualified Crypto.Hash.SHA256 as SHA256
import Data.Aeson (Value (..), eitherDecodeStrict')
import qualified Data.Aeson.KeyMap as KeyMap
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.Vector as Vector
import System.Environment (getEnv)
import System.FilePath.Posix (takeDirectory)
import qualified Test.CLI.E2E as CLI
import Test.Hspec
import Prelude hiding (readFile, writeFile)

data Scenario = Scenario {environment :: CLI.Environment, home :: String, scenarioDriver :: CLI.Driver}

newScenario :: CLI.Environment -> String -> IO Scenario
newScenario env homePath = do
    driverPath <- getEnv "C_PLUGIN_E2E_DRIVER"
    driver <- BS.readFile driverPath >>= CLI.installDriver env
    pure (Scenario env homePath driver)

cPlugin :: String
cPlugin = "/sandbox/.local/bin/c-plugin"

run :: Scenario -> String -> [String] -> IO CLI.Result
run s directory = runWithEnv s directory []

runWithEnv :: Scenario -> String -> [(String, String)] -> [String] -> IO CLI.Result
runWithEnv s directory variables arguments =
    CLI.run (environment s) (CLI.Command (cPlugin : arguments) (workingDirectory directory) (environmentVariables (("HOME", home s) : variables)))

infra :: Scenario -> String -> [String] -> IO CLI.Result
infra s directory = infraWithEnv s directory []

infraWithEnv :: Scenario -> String -> [(String, String)] -> [String] -> IO CLI.Result
infraWithEnv s directory variables arguments =
    CLI.run (environment s) (CLI.Command arguments (workingDirectory directory) (environmentVariables variables))

workingDirectory :: String -> Maybe String
workingDirectory "" = Nothing
workingDirectory directory = Just directory

environmentVariables :: [(String, String)] -> [String]
environmentVariables = map (\(key, value) -> key ++ "=" ++ value)

mkdirAll :: Scenario -> [String] -> IO ()
mkdirAll s paths = infra s "" ("mkdir" : "-p" : paths) >>= requireSuccess

remove :: Scenario -> [String] -> IO ()
remove s paths = infra s "" (["rm", "-rf", "--"] ++ paths) >>= requireSuccess

encodeText :: String -> ByteString
encodeText = Text.encodeUtf8 . Text.pack

decodeText :: ByteString -> String
decodeText = Text.unpack . Text.decodeUtf8

writeFile :: Scenario -> String -> String -> IO ()
writeFile s path content = do
    mkdirAll s [takeDirectory path]
    CLI.writeFile (environment s) path (encodeText content)

readFile :: Scenario -> String -> IO ByteString
readFile s = CLI.readFile (environment s)

digest :: Scenario -> String -> IO ByteString
digest s path = SHA256.hash <$> readFile s path

stdoutText, stderrText :: CLI.Result -> String
stdoutText = decodeText . CLI.stdout
stderrText = decodeText . CLI.stderr

requireExit :: CLI.Result -> Int -> IO ()
requireExit result expected = CLI.exitCode result `shouldBe` expected

requireSuccess, requireFailure :: CLI.Result -> IO ()
requireSuccess result = requireExit result 0
requireFailure result = CLI.exitCode result `shouldNotBe` 0

requireOutput :: CLI.Result -> String -> IO ()
requireOutput result expected = CLI.stdout result `shouldBe` encodeText expected

requireContains, requireNotContains :: String -> String -> IO ()
requireContains value expected = value `shouldSatisfy` isInfixOf expected
requireNotContains value unexpected = value `shouldNotSatisfy` isInfixOf unexpected

captureSnapshot :: Scenario -> [FilePath] -> IO CLI.FileSystemSnapshot
captureSnapshot s = CLI.captureSnapshot (scenarioDriver s)

requireFile :: Scenario -> String -> String -> IO ()
requireFile s path expected =
    captureSnapshot s [path] `shouldReturn` CLI.FileSystemSnapshot (Map.singleton path (CLI.RegularFile (encodeText expected)))

parseJSON :: ByteString -> IO Value
parseJSON bytes = case eitherDecodeStrict' bytes of
    Left failure -> expectationFailure failure >> pure Null
    Right value -> pure value

requireJSON :: Scenario -> String -> String -> IO ()
requireJSON s path expected = do
    actual <- readFile s path >>= parseJSON
    wanted <- parseJSON (encodeText expected)
    actual `shouldBe` wanted

pathExists :: Scenario -> String -> IO Bool
pathExists s path = (/= CLI.PathMissing) <$> CLI.pathKind (environment s) path

requireMissing, requireRegularFile, requireDirectory :: Scenario -> String -> IO ()
requireMissing s path = CLI.pathKind (environment s) path `shouldReturn` CLI.PathMissing
requireRegularFile s path = CLI.pathKind (environment s) path `shouldReturn` CLI.PathRegularFile
requireDirectory s path = CLI.pathKind (environment s) path `shouldReturn` CLI.PathDirectory

-- Assert a physical symlink with its canonical resolved target.
requireSymlink :: Scenario -> String -> String -> IO ()
requireSymlink s link target = do
    CLI.pathKind (environment s) link `shouldReturn` CLI.PathSymlink
    result <- infra s "" ["realpath", link]
    requireSuccess result
    requireOutput result (target ++ "\n")

requireDigest :: Scenario -> String -> ByteString -> IO ()
requireDigest s path expected = digest s path >>= (`shouldBe` expected)

requireOwnershipSkill :: Scenario -> String -> String -> Bool -> IO ()
requireOwnershipSkill _ state skill present = do
    value <- parseJSON (encodeText state)
    entries <- case value of
        Object root | Just (Object entries) <- KeyMap.lookup "ownershipEntries" root -> pure entries
        _ -> expectationFailure "ownershipEntries must be an object" >> pure KeyMap.empty
    found <- forM (KeyMap.toList entries) $ \(link, entry) -> case entry of
        Object fields | Just (Object source) <- KeyMap.lookup "entrySource" fields ->
            case (KeyMap.lookup "tag" source, KeyMap.lookup "contents" source) of
                (Just (String tag), Just (Array contents)) -> do
                    let expected = if tag == "StandaloneSource" then 2 else 3
                    unless (tag == "StandaloneSource" || tag == "OwnershipSource") $
                        expectationFailure ("unknown ownership source at " ++ show link)
                    Vector.length contents `shouldBe` expected
                    pure (contents Vector.! (expected - 1) == String (Text.pack skill))
                _ -> expectationFailure ("invalid ownership source at " ++ show link) >> pure False
        _ -> expectationFailure ("invalid ownership entry at " ++ show link) >> pure False
    or found `shouldBe` present
