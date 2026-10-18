{-# LANGUAGE OverloadedStrings #-}

module CPlugin.PluginSpec (spec) where

import CPlugin.Paths (absoluteIO)
import CPlugin.Plugin (loadPlugin)
import CPlugin.TestSupport (manifestBytes, skillBytes, withFixture, writeFixture)
import CPlugin.Types.Name (itemName, nameText)
import CPlugin.Types.PluginManifest (decodeManifest, manifestWarnings)
import CPlugin.Types.Skill (decodeSkill, resolvedSkillName)
import Data.Either (isLeft)
import Data.List (isInfixOf)
import System.Directory (createDirectoryIfMissing, removeDirectoryRecursive, removeFile)
import System.FilePath ((</>))
import System.Posix.Files (createSymbolicLink)
import Test.Hspec (Spec, anyIOException, describe, it, shouldBe, shouldSatisfy, shouldThrow)

spec :: Spec
spec = do
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
