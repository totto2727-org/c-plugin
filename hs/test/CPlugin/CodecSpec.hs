{-# LANGUAGE OverloadedStrings #-}

module CPlugin.CodecSpec (spec) where

import CPlugin.Paths (nameIO, relativeIO)
import CPlugin.StateStore (encodePretty, writeLock)
import CPlugin.TestSupport (fixtureLock, fixturePlugin, withFixture)
import CPlugin.Types.InstalledSkill (InstalledSkill, makeInstalledSkill)
import CPlugin.Types.Lock (Lock, emptyLock, makeLock, makeLockWithSkills, plugins, standaloneSkills)
import CPlugin.Types.Ownership (OwnershipState)
import CPlugin.Types.Plugin (makePlugin)
import Control.Monad (forM_)
import Data.Aeson (eitherDecodeStrict')
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Either (isLeft)
import qualified Data.Map.Strict as Map
import System.FilePath ((</>))
import Test.Hspec (Spec, anyIOException, describe, it, shouldBe, shouldReturn, shouldSatisfy, shouldThrow)

spec :: Spec
spec = do
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

    describe "standalone skill lock codecs" $ do
        it "decodes existing version 3 locks without a standalone skills field" $
            (eitherDecodeStrict' "{\"version\":\"3\",\"targets\":[],\"plugins\":[]}" :: Either String Lock) `shouldBe` Right emptyLock
        it "encodes standalone skills canonically and round trips the complete lock" $ do
            skill <- installed "standalone" "standalone"
            lock <- either (ioError . userError) pure (makeLockWithSkills [] [] [skill])
            encodePretty lock `shouldBe` "{\n  \"plugins\": [],\n  \"skills\": [\n    {\n      \"name\": \"standalone\",\n      \"source\": \"./standalone\"\n    }\n  ],\n  \"targets\": [],\n  \"version\": \"3\"\n}\n"
            eitherDecodeStrict' (encodePretty lock) `shouldBe` Right lock
        it "treats an explicit empty standalone list as an empty lock" $
            (eitherDecodeStrict' "{\"version\":\"3\",\"targets\":[],\"plugins\":[],\"skills\":[]}" :: Either String Lock) `shouldBe` Right emptyLock
        it "rejects null instead of silently treating it as an absent standalone list" $
            (eitherDecodeStrict' "{\"version\":\"3\",\"targets\":[],\"plugins\":[],\"skills\":null}" :: Either String Lock) `shouldSatisfy` isLeft
        it "rejects duplicate standalone names" $ do
            first <- installed "alpha" "first/alpha"
            second <- installed "alpha" "second/alpha"
            makeLockWithSkills [] [] [first, second] `shouldSatisfy` isLeft
        it "rejects duplicate normalized standalone sources" $ do
            first <- installed "alpha" "standalone"
            second <- installed "beta" "./standalone/./"
            makeLockWithSkills [] [] [first, second] `shouldSatisfy` isLeft
        it "rejects a standalone name colliding with an enabled plugin skill" $ do
            plugin <- fixturePlugin "demo" "./plugin" ["alpha"]
            skill <- installed "alpha" "standalone"
            makeLockWithSkills [] [plugin] [skill] `shouldSatisfy` isLeft
        it "allows a standalone skill alongside a plugin with no enabled skills" $ do
            plugin <- fixturePlugin "demo" "./plugin" []
            skill <- installed "alpha" "standalone"
            fmap (Map.elems . standaloneSkills) (makeLockWithSkills [] [plugin] [skill]) `shouldBe` Right [skill]
        forM_ ["standalone", "../escape", "./safe/../escape", "/absolute"] $ \source ->
            it ("rejects unsafe standalone wire source " ++ show source) $
                (eitherDecodeStrict' ("{\"name\":\"alpha\",\"source\":\"" <> BSC.pack source <> "\"}") :: Either String InstalledSkill) `shouldSatisfy` isLeft
        it "validates standalone names through the constructor" $ do
            name <- nameIO "Alpha"
            source <- relativeIO "standalone"
            makeInstalledSkill name source `shouldSatisfy` isLeft

installed :: String -> FilePath -> IO InstalledSkill
installed name source = do
    n <- nameIO name
    p <- relativeIO source
    either (ioError . userError) pure (makeInstalledSkill n p)
