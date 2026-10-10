{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import CPlugin.Codec
import CPlugin.Commands
import CPlugin.Paths
import CPlugin.Plugin
import CPlugin.Reconcile
import CPlugin.Types
import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.Aeson (eitherDecodeStrict')
import qualified Data.ByteString as BS
import Data.Either (isLeft)
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive, removeFile, withCurrentDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withTempDirectory)
import System.Posix.Files (createSymbolicLink, readSymbolicLink)
import Test.Hspec hiding (before)

main :: IO ()
main = hspec $ do
    describe "validated domain values" $ do
        it "normalizes dots in target paths" $ relativePath ".cursor/./skills" `shouldBe` relativePath ".cursor/skills"
        forM_ ["../escape", "safe/../escape", "/absolute", "back\\slash", "nul\0path"] $ \p ->
            it ("rejects unsafe relative path " ++ show p) $ relativePath p `shouldSatisfy` isLeft
        it "rejects NUL in absolute paths" $ absolutePath "/safe/\0" `shouldSatisfy` isLeft
        it "accepts Unicode lowercase skill names" $ skillNameValue "éclair" `shouldBe` itemName "éclair"
        it "rejects Unicode uppercase skill names" $ skillNameValue "Éclair" `shouldSatisfy` isLeft
        it "requires ASCII-only standard plugin names" $ pluginNameValue "éclair" `shouldSatisfy` isLeft
    describe "strict lock and ownership codecs" $ do
        it "writes canonical indented empty version 3 JSON" $
            encodePretty emptyLock `shouldBe` "{\n  \"plugins\": [],\n  \"targets\": [],\n  \"version\": \"3\"\n}\n"
        it "rejects legacy version 2 instead of migrating" $
            (eitherDecodeStrict' "{\"version\":\"2\",\"targets\":[],\"plugins\":[]}" :: Either String Lock) `shouldSatisfy` isLeft
        it "rejects numeric lock versions" $
            (eitherDecodeStrict' "{\"version\":3,\"targets\":[],\"plugins\":[]}" :: Either String Lock) `shouldSatisfy` isLeft
        it "rejects duplicate normalized plugin sources" $ do
            lock <- fixtureLock ["alpha"]
            other <- fixturePlugin "other" "./plugin/./" ["beta"]
            makeLock [] (Map.elems (plugins lock) ++ [other]) `shouldSatisfy` isLeft
        it "rejects duplicate skill selections" $ do
            n <- nameIO "demo"
            p <- relativeIO "plugin"
            s <- nameIO "alpha"
            makePlugin n p [s, s] `shouldSatisfy` isLeft
        it "rejects invalid enabled skill names" $
            (eitherDecodeStrict' "{\"version\":\"3\",\"targets\":[],\"plugins\":[{\"name\":\"demo\",\"source\":\"./plugin\",\"skills\":[\"Alpha\"]}]}" :: Either String Lock) `shouldSatisfy` isLeft
        it "rejects unsupported ownership versions" $
            (eitherDecodeStrict' "{\"version\":\"2\",\"entries\":[]}" :: Either String OwnershipState) `shouldSatisfy` isLeft
        it "does not delete a pre-existing exclusive checkpoint sibling" $ withFixture ["alpha"] $ \base lock -> do
            let tmp = base </> "c-plugin-lock.json.tmp"
            BS.writeFile tmp "foreign checkpoint"
            writeLock (base </> "c-plugin-lock.json") lock `shouldThrow` anyIOException
            BS.readFile tmp `shouldReturn` "foreign checkpoint"
    describe "standard plugin manifest" $ do
        it "requires the recognized canonical schema identifier" $ decodeManifest "{\"name\":\"demo\"}" `shouldSatisfy` isLeft
        it "reports and ignores unknown top-level fields" $ do
            let bytes = manifestBytes ",\"custom\":false"
            fmap manifestWarnings (decodeManifest bytes) `shouldBe` Right ["unknown top-level field: custom"]
        it "ignores non-object extensions with a warning" $
            fmap manifestWarnings (decodeManifest (manifestBytes ",\"extensions\":17")) `shouldBe` Right ["non-object extensions field ignored"]
        it "ignores values of unimplemented extension namespaces" $
            fmap manifestWarnings (decodeManifest (manifestBytes ",\"extensions\":{\"com.example\":17}")) `shouldBe` Right []
        it "validates metadata types without imposing SemVer or URL rules" $
            fmap manifestWarnings (decodeManifest (manifestBytes ",\"version\":\"not semver\",\"homepage\":\"not a URL\"")) `shouldBe` Right []
        it "rejects wrong metadata types" $ decodeManifest (manifestBytes ",\"version\":3") `shouldSatisfy` isLeft
        it "rejects unknown author fields" $ decodeManifest (manifestBytes ",\"author\":{\"extra\":\"x\"}") `shouldSatisfy` isLeft
    describe "Agent Skills YAML" $ do
        it "accepts minimal frontmatter without Markdown body" $ decodeSkill "alpha" (skillBytes "alpha") `shouldBe` itemName "alpha"
        it "requires directory and frontmatter name agreement" $ decodeSkill "beta" (skillBytes "alpha") `shouldSatisfy` isLeft
        it "rejects missing description" $ decodeSkill "alpha" "---\nname: alpha\n---\n" `shouldSatisfy` isLeft
        it "uses YAML block scalar descriptions" $ decodeSkill "alpha" "---\nname: alpha\ndescription: |\n  Multi line\n  description.\n---\n" `shouldBe` itemName "alpha"
        it "requires metadata values to be strings" $ decodeSkill "alpha" "---\nname: alpha\ndescription: Test\nmetadata:\n  count: 3\n---\n" `shouldSatisfy` isLeft
        it "accepts Unicode frontmatter names" $ decodeSkill "éclair" (skillBytes "éclair") `shouldBe` itemName "éclair"
    describe "fixed component discovery and containment" $ do
        it "accepts a plugin with no skills directory" $ withFixture [] $ \base _ -> do
            root <- absoluteIO (base </> "plugin")
            (_, skills, warnings) <- loadPlugin root
            skills `shouldBe` []
            warnings `shouldBe` []
        it "discovers only immediate skill directories" $ withFixture ["alpha"] $ \base _ -> do
            writeFixture (base </> "plugin/skills/group/nested/SKILL.md") (skillBytes "nested")
            root <- absoluteIO (base </> "plugin")
            (_, skills, _) <- loadPlugin root
            map (nameText . resolvedSkillName) skills `shouldBe` ["alpha"]
        it "rejects an escaping plugin manifest before component discovery" $ withFixture ["alpha"] $ \base _ -> do
            let manifest = base </> "plugin/plugin.json"
            removeFile manifest
            writeFixture (base </> "outside.json") (manifestBytes "")
            createSymbolicLink "../outside.json" manifest
            root <- absoluteIO (base </> "plugin")
            loadPlugin root `shouldThrow` anyIOException
        it "skips an escaping SKILL.md and keeps valid siblings" $ withFixture ["alpha", "beta"] $ \base _ -> do
            removeFile (base </> "plugin/skills/beta/SKILL.md")
            writeFixture (base </> "outside.md") (skillBytes "beta")
            createSymbolicLink "../../../outside.md" (base </> "plugin/skills/beta/SKILL.md")
            root <- absoluteIO (base </> "plugin")
            (_, skills, warnings) <- loadPlugin root
            map (nameText . resolvedSkillName) skills `shouldBe` ["alpha"]
            warnings `shouldSatisfy` any (isInfixOf "outside plugin root")
        it "warns and disables an escaping fixed skills location" $ withFixture ["alpha"] $ \base _ -> do
            removeDirectoryRecursive (base </> "plugin/skills")
            createDirectoryIfMissing True (base </> "outside")
            createSymbolicLink "../outside" (base </> "plugin/skills")
            root <- absoluteIO (base </> "plugin")
            (_, skills, warnings) <- loadPlugin root
            skills `shouldBe` []
            warnings `shouldSatisfy` any (isInfixOf "outside plugin root")
    describe "durable ownership reconciliation" $ do
        it "creates relative symlinks, checkpoints ownership, and leaves lock bytes untouched" $ withFixture ["alpha"] $ \base lock -> do
            let lockPath = base </> "c-plugin-lock.json"
            before <- BS.readFile lockPath
            result <- syncLoadedLock lockPath lock False
            syncCompletion result `shouldBe` Finished
            literal <- readSymbolicLink (base </> ".agents/skills/alpha")
            literal `shouldBe` "../../plugin/skills/alpha"
            readOwnership (base </> ".agents/c-plugin-state.json") >>= (`shouldSatisfy` isTrusted)
            BS.readFile lockPath `shouldReturn` before
        it "never adopts an existing unowned matching symlink" $ withFixture ["alpha"] $ \base lock -> do
            createDirectoryIfMissing True (base </> ".agents/skills")
            createSymbolicLink "../../plugin/skills/alpha" (base </> ".agents/skills/alpha")
            result <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            syncNotices result `shouldSatisfy` any isUnmanaged
            readOwnership (base </> ".agents/c-plugin-state.json") `shouldReturn` Trusted (OwnershipState Map.empty)
        it "preserves existing links when ownership is corrupt" $ withFixture ["alpha"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            BS.writeFile (base </> ".agents/c-plugin-state.json") "{corrupt"
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") emptyLock False
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
        it "preserves a replaced literal symlink even when its physical target is unchanged" $ withFixture ["alpha"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            let link = base </> ".agents/skills/alpha"
            removeFile link
            createSymbolicLink (base </> "plugin/skills/alpha") link
            result <- syncLoadedLock (base </> "c-plugin-lock.json") emptyLock False
            syncNotices result `shouldSatisfy` any isReplaced
            pathKind link `shouldReturn` Just SymbolicLink
            readOwnership (base </> ".agents/c-plugin-state.json") `shouldReturn` Trusted (OwnershipState Map.empty)
        it "preserves trusted links while their plugin is unavailable" $ withFixture ["alpha"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            previous <- BS.readFile (base </> ".agents/c-plugin-state.json")
            removeFile (base </> "plugin/plugin.json")
            result <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            Map.size (unavailablePlugins result) `shouldBe` 1
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
            BS.readFile (base </> ".agents/c-plugin-state.json") `shouldReturn` previous
        it "force preserves real directories and their neighbors" $ withFixture ["alpha"] $ \base lock -> do
            writeFixture (base </> ".agents/skills/alpha/keep") "keep"
            writeFixture (base </> ".agents/skills/neighbor") "neighbor"
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock True
            BS.readFile (base </> ".agents/skills/alpha/keep") `shouldReturn` "keep"
            BS.readFile (base </> ".agents/skills/neighbor") `shouldReturn` "neighbor"
        it "force replaces only eligible direct contained regular files" $ withFixture ["alpha"] $ \base lock -> do
            writeFixture (base </> ".agents/skills/alpha") "foreign"
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock True
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Just SymbolicLink
        it "checkpoint failure rolls back a created link and stops before the next skill" $ withFixture ["alpha", "beta"] $ \base lock -> do
            writeFixture (base </> ".agents/c-plugin-state.json.tmp") "foreign"
            result <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            syncCompletion result `shouldBe` Interrupted
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Nothing
            BS.readFile (base </> ".agents/c-plugin-state.json.tmp") `shouldReturn` "foreign"
        it "force checkpoint failure preserves the exact existing trusted link" $ withFixture ["alpha"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            let link = base </> ".agents/skills/alpha"
            literal <- readSymbolicLink link
            state <- BS.readFile (base </> ".agents/c-plugin-state.json")
            writeFixture (base </> ".agents/c-plugin-state.json.tmp") "foreign"
            result <- syncLoadedLock (base </> "c-plugin-lock.json") lock True
            syncCompletion result `shouldBe` Interrupted
            readSymbolicLink link `shouldReturn` literal
            BS.readFile (base </> ".agents/c-plugin-state.json") `shouldReturn` state
        it "deletion checkpoint failure stops before deleting the next owned skill" $ withFixture ["alpha", "beta"] $ \base lock -> do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            previous <- BS.readFile (base </> ".agents/c-plugin-state.json")
            writeFixture (base </> ".agents/c-plugin-state.json.tmp") "foreign"
            result <- syncLoadedLock (base </> "c-plugin-lock.json") emptyLock False
            syncCompletion result `shouldBe` Interrupted
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Just SymbolicLink
            BS.readFile (base </> ".agents/c-plugin-state.json") `shouldReturn` previous
        it "rejects redirected managed roots before touching outside paths" $ withFixture ["alpha"] $ \base lock -> do
            createDirectoryIfMissing True (base </> "outside")
            createDirectoryIfMissing True (base </> ".agents")
            createSymbolicLink "../outside" (base </> ".agents/skills")
            syncLoadedLock (base </> "c-plugin-lock.json") lock True `shouldThrow` anyIOException
            pathKind (base </> "outside/alpha") `shouldReturn` Nothing
    describe "command candidate persistence" $ do
        it "unknown remove selections preserve lock and ownership bytes" $ withFixture ["alpha"] $ \base lock -> inEnvironment base $ do
            _ <- syncLoadedLock (base </> "c-plugin-lock.json") lock False
            beforeLock <- BS.readFile (base </> "c-plugin-lock.json")
            beforeState <- BS.readFile (base </> ".agents/c-plugin-state.json")
            runCommand (Remove False [] ["demo/unknown"])
            BS.readFile (base </> "c-plugin-lock.json") `shouldReturn` beforeLock
            BS.readFile (base </> ".agents/c-plugin-state.json") `shouldReturn` beforeState
        it "terminal checkpoint failure makes the command fail and leaves later skills untouched" $ withFixture ["alpha", "beta"] $ \base _ -> inEnvironment base $ do
            writeFixture (base </> ".agents/c-plugin-state.json.tmp") "foreign"
            runCommand (Sync False False) `shouldThrow` anyIOException
            pathKind (base </> ".agents/skills/alpha") `shouldReturn` Nothing
            pathKind (base </> ".agents/skills/beta") `shouldReturn` Nothing
            BS.readFile (base </> ".agents/c-plugin-state.json.tmp") `shouldReturn` "foreign"
        it "rejects an unsafe target before persisting a candidate" $ withFixture ["alpha"] $ \base _ -> inEnvironment base $ do
            createDirectoryIfMissing True (base </> "outside")
            createSymbolicLink "outside" (base </> "redirected")
            before <- BS.readFile (base </> "c-plugin-lock.json")
            runCommand (TargetAdd False "redirected/skills") `shouldThrow` anyIOException
            BS.readFile (base </> "c-plugin-lock.json") `shouldReturn` before

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
isTrusted :: PreviousOwnership -> Bool
isTrusted (Trusted _) = True
isTrusted _ = False
isUnmanaged :: Notice -> Bool
isUnmanaged (UnmanagedPreserved _) = True
isUnmanaged _ = False
isReplaced :: Notice -> Bool
isReplaced (ReplacedPreserved _) = True
isReplaced _ = False
