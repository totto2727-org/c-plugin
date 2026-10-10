{-# LANGUAGE OverloadedStrings #-}

module CPlugin.CommandsSpec (spec) where

import CPlugin.Commands (Command (Remove, Sync, TargetAdd), runCommand)
import CPlugin.Paths (pathKind)
import CPlugin.Reconcile (syncLoadedLock)
import CPlugin.TestSupport (inEnvironment, withFixture, writeFixture)
import qualified Data.ByteString as BS
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.Posix.Files (createSymbolicLink)
import Test.Hspec (Spec, anyIOException, describe, it, shouldReturn, shouldThrow)

spec :: Spec
spec = do
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
