{-# LANGUAGE OverloadedStrings #-}

module CPlugin.CodecSpec (spec) where

import CPlugin.Paths (nameIO, relativeIO)
import CPlugin.StateStore (encodePretty, writeLock)
import CPlugin.TestSupport (fixtureLock, fixturePlugin, withFixture)
import CPlugin.Types.Lock (Lock, emptyLock, makeLock, plugins)
import CPlugin.Types.Ownership (OwnershipState)
import CPlugin.Types.Plugin (makePlugin)
import Data.Aeson (eitherDecodeStrict')
import qualified Data.ByteString as BS
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
