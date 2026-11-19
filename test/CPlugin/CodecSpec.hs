{-# LANGUAGE OverloadedStrings #-}

module CPlugin.CodecSpec (spec) where

import CPlugin.Paths (nameIO, relativeIO)
import CPlugin.StateStore (encodePretty, writeLock)
import CPlugin.TestSupport (fixtureLock, fixturePlugin, withFixture)
import CPlugin.Types.InstalledSkill (InstalledSkill, makeInstalledSkill)
import CPlugin.Types.Lock (Lock, decodeLock, emptyLock, makeLock, makeLockWithSkills, plugins, standaloneSkills)
import CPlugin.Types.Ownership (OwnershipSource (..), OwnershipState, decodeOwnership, makeEntry, makeOwnership)
import CPlugin.Types.Path (absolutePath)
import CPlugin.Types.Plugin (makePlugin)
import Control.Monad (forM_)
import Data.Aeson (Value, eitherDecodeStrict', object, toJSON, (.=))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Either (isLeft, isRight)
import qualified Data.Map.Strict as Map
import System.FilePath ((</>))
import Test.Hspec (Spec, anyIOException, describe, it, shouldBe, shouldReturn, shouldSatisfy, shouldThrow)

spec :: Spec
spec = do
    describe "generic lock and ownership codecs" $ do
        it "writes the actual empty lock fields without a version" $
            encodePretty emptyLock `shouldBe` "{\n  \"plugins\": {},\n  \"standaloneSkills\": {},\n  \"targets\": []\n}\n"
        it "uses actual record fields, string map keys, and explicit null origins" $ do
            plugin <- fixturePlugin "demo" "plugin" ["alpha"]
            skill <- installed "solo" "standalone/solo"
            lock <- either (ioError . userError) pure (makeLockWithSkills [] [plugin] [skill])
            toJSON lock
                `shouldBe` object
                    [ "targets" .= ([] :: [Value])
                    , "plugins" .= object ["demo" .= object ["pluginName" .= ("demo" :: String), "pluginSource" .= ("plugin" :: String), "enabledSkills" .= ["alpha" :: String], "pluginOrigin" .= (Nothing :: Maybe Value)]]
                    , "standaloneSkills" .= object ["solo" .= object ["installedSkillName" .= ("solo" :: String), "installedSkillSource" .= ("standalone/solo" :: String), "installedSkillOrigin" .= (Nothing :: Maybe Value)]]
                    ]
            decodeLock (encodePretty lock) `shouldBe` Right lock
        forM_ ["2", "3"] $ \version ->
            it ("rejects legacy version " ++ version ++ " instead of migrating") $
                decodeLock ("{\"version\":\"" <> BSC.pack version <> "\",\"targets\":[],\"plugins\":[]}") `shouldSatisfy` isLeft
        it "rejects duplicate normalized plugin sources" $ do
            lock <- fixtureLock ["alpha"]
            other <- fixturePlugin "other" "./plugin/./" ["beta"]
            makeLock [] (Map.elems (plugins lock) ++ [other]) `shouldSatisfy` isLeft
        it "rejects duplicate skill selections" $ do
            n <- nameIO "demo"
            p <- relativeIO "plugin"
            s <- nameIO "alpha"
            makePlugin n p [s, s] `shouldSatisfy` isLeft
        it "rejects invalid enabled skill names at the lock boundary" $
            decodeLock "{\"targets\":[],\"plugins\":{\"demo\":{\"pluginName\":\"demo\",\"pluginSource\":\"plugin\",\"enabledSkills\":[\"Alpha\"],\"pluginOrigin\":null}},\"standaloneSkills\":{}}" `shouldSatisfy` isLeft
        it "validates traversal after structural decoding" $ do
            let wire = "{\"targets\":[\"../escape\"],\"plugins\":{},\"standaloneSkills\":{}}"
            (eitherDecodeStrict' wire :: Either String Lock) `shouldSatisfy` isRight
            decodeLock wire `shouldSatisfy` isLeft
        it "rejects a plugin map key that spoofs the embedded name" $
            decodeLock "{\"targets\":[],\"plugins\":{\"other\":{\"pluginName\":\"demo\",\"pluginSource\":\"plugin\",\"enabledSkills\":[],\"pluginOrigin\":null}},\"standaloneSkills\":{}}" `shouldSatisfy` isLeft
        it "rejects a standalone map key that spoofs the embedded name" $
            decodeLock "{\"targets\":[],\"plugins\":{},\"standaloneSkills\":{\"other\":{\"installedSkillName\":\"solo\",\"installedSkillSource\":\"standalone/solo\",\"installedSkillOrigin\":null}}}" `shouldSatisfy` isLeft
        forM_ ["[\"target\",\"target\"]", "[\"target\",\"./target\"]"] $ \targets ->
            it ("rejects duplicate target wire values " ++ targets) $
                decodeLock ("{\"targets\":" <> BSC.pack targets <> ",\"plugins\":{},\"standaloneSkills\":{}}") `shouldSatisfy` isLeft
        it "rejects duplicate enabled skill wire values before set decoding loses them" $
            decodeLock "{\"targets\":[],\"plugins\":{\"demo\":{\"pluginName\":\"demo\",\"pluginSource\":\"plugin\",\"enabledSkills\":[\"alpha\",\"alpha\"],\"pluginOrigin\":null}},\"standaloneSkills\":{}}" `shouldSatisfy` isLeft
        it "rejects legacy ownership instead of migrating" $
            decodeOwnership "{\"version\":\"1\",\"entries\":[]}" `shouldSatisfy` isLeft
        forM_ [False, True] $ \standalone ->
            it ("encodes ownership with record fields and a tagged source, standalone=" ++ show standalone) $ do
                link <- either (ioError . userError) pure (absolutePath "/sandbox/skills/alpha")
                root <- either (ioError . userError) pure (absolutePath "/sandbox/skills")
                resolved <- either (ioError . userError) pure (absolutePath "/sandbox/plugin/skills/alpha")
                path <- relativeIO "plugin"
                plugin <- nameIO "demo"
                skill <- nameIO "alpha"
                let source = if standalone then StandaloneSource path skill else OwnershipSource path plugin skill
                    sourceJSON = object ["tag" .= (if standalone then "StandaloneSource" else "OwnershipSource" :: String), "contents" .= (if standalone then ["plugin", "alpha"] else ["plugin", "demo", "alpha"] :: [String])]
                entry <- either (ioError . userError) pure (makeEntry link "../plugin/skills/alpha" resolved root source)
                state <- either (ioError . userError) pure (makeOwnership [entry])
                toJSON state
                    `shouldBe` object
                        [ "ownershipEntries"
                            .= object
                                [ "/sandbox/skills/alpha"
                                    .= object
                                        [ "entryLink" .= ("/sandbox/skills/alpha" :: String)
                                        , "symlinkTarget" .= ("../plugin/skills/alpha" :: String)
                                        , "resolvedTarget" .= ("/sandbox/plugin/skills/alpha" :: String)
                                        , "managedRoot" .= ("/sandbox/skills" :: String)
                                        , "entrySource" .= sourceJSON
                                        ]
                                ]
                        ]
                decodeOwnership (encodePretty state) `shouldBe` Right state
        it "rejects an ownership key that spoofs its embedded link" $
            decodeOwnership (ownershipWire "/sandbox/skills/other" "plugin" "/sandbox/skills") `shouldSatisfy` isLeft
        it "rejects traversal in an ownership source after structural decoding" $ do
            let wire = ownershipWire "/sandbox/skills/alpha" "../escape" "/sandbox/skills"
            (eitherDecodeStrict' wire :: Either String OwnershipState) `shouldSatisfy` isRight
            decodeOwnership wire `shouldSatisfy` isLeft
        it "rejects ownership links outside their recorded managed root" $
            decodeOwnership (ownershipWire "/sandbox/skills/alpha" "plugin" "/sandbox/other") `shouldSatisfy` isLeft
        it "does not delete a pre-existing exclusive checkpoint sibling" $ withFixture ["alpha"] $ \base lock -> do
            let tmp = base </> "c-plugin-lock.json.tmp"
            BS.writeFile tmp "foreign checkpoint"
            writeLock (base </> "c-plugin-lock.json") lock `shouldThrow` anyIOException
            BS.readFile tmp `shouldReturn` "foreign checkpoint"

    describe "standalone skill lock codecs" $ do
        it "requires the actual standaloneSkills field without a legacy fallback" $
            decodeLock "{\"targets\":[],\"plugins\":{}}" `shouldSatisfy` isLeft
        it "round trips a complete standalone lock" $ do
            skill <- installed "standalone" "standalone"
            lock <- either (ioError . userError) pure (makeLockWithSkills [] [] [skill])
            decodeLock (encodePretty lock) `shouldBe` Right lock
        it "treats an explicit empty standalone map as an empty lock" $
            decodeLock "{\"targets\":[],\"plugins\":{},\"standaloneSkills\":{}}" `shouldBe` Right emptyLock
        it "rejects null instead of silently treating it as an absent standalone map" $
            decodeLock "{\"targets\":[],\"plugins\":{},\"standaloneSkills\":null}" `shouldSatisfy` isLeft
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
        forM_ ["../escape", "./safe/../escape", "/absolute"] $ \source ->
            it ("rejects unsafe standalone wire source " ++ show source) $
                decodeLock ("{\"targets\":[],\"plugins\":{},\"standaloneSkills\":{\"alpha\":{\"installedSkillName\":\"alpha\",\"installedSkillSource\":\"" <> BSC.pack source <> "\",\"installedSkillOrigin\":null}}}") `shouldSatisfy` isLeft
        it "validates standalone names through the constructor" $ do
            name <- nameIO "Alpha"
            source <- relativeIO "standalone"
            makeInstalledSkill name source `shouldSatisfy` isLeft

installed :: String -> FilePath -> IO InstalledSkill
installed name source = do
    n <- nameIO name
    p <- relativeIO source
    either (ioError . userError) pure (makeInstalledSkill n p)

ownershipWire :: String -> String -> String -> BS.ByteString
ownershipWire key source root = BSC.pack ("{\"ownershipEntries\":{\"" ++ key ++ "\":{\"entryLink\":\"/sandbox/skills/alpha\",\"symlinkTarget\":\"../plugin/skills/alpha\",\"resolvedTarget\":\"/sandbox/plugin/skills/alpha\",\"managedRoot\":\"" ++ root ++ "\",\"entrySource\":{\"tag\":\"OwnershipSource\",\"contents\":[\"" ++ source ++ "\",\"demo\",\"alpha\"]}}}}")
