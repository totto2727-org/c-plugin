{-# LANGUAGE OverloadedStrings #-}

module CPlugin.PathsSpec (spec) where

import CPlugin.Paths (discoverLocks, runtimePaths)
import CPlugin.TestSupport (inEnvironment, withFixture, writeFixture)
import Control.Monad (forM_)
import qualified Data.ByteString.Char8 as BSC
import Data.List (sort)
import System.Directory (createDirectoryIfMissing, removeFile, withCurrentDirectory)
import System.FilePath ((</>))
import System.Posix.Files (createSymbolicLink)
import Test.Hspec (Spec, describe, it, shouldReturn)

spec :: Spec
spec = describe "historical recursive directory discovery parity" $ do
    it "always includes the owning lock and does not ignore lock files by basename" $
        withDiscovery "c-plugin-lock.json\n" ["child"] $
            \base -> assertDiscovered base ["child"]
    it "trims directory ignore rules before matching" $
        withDiscovery "  blocked/  \n\tother\t\n" ["blocked", "other", "kept"] $
            \base -> assertDiscovered base ["kept"]
    it "ignores comments, blank lines and negation rules rather than interpreting negation" $
        withDiscovery "\n  # comment\n!included/\n" ["included", "kept"] $
            \base -> assertDiscovered base ["included", "kept"]
    it "does not let negation resurrect descendants of an excluded directory" $
        withDiscovery "blocked/\n!blocked/kept/\n" ["blocked/kept", "kept"] $
            \base -> assertDiscovered base ["kept"]
    it "strips boundary slashes and matches directory segments anywhere below the root" $
        withDiscovery "/blocked/\n" ["blocked", "level/blocked", "kept"] $
            \base -> assertDiscovered base ["kept"]
    it "matches contiguous multisegment rules anywhere rather than anchoring them to the root" $
        withDiscovery "/blocked/deep/\n" ["level/blocked/deep", "blocked/deep", "blocked/other", "level/deep"] $
            \base -> assertDiscovered base ["blocked/other", "level/deep"]
    it "does not match a multisegment rule across an intervening directory" $
        withDiscovery "blocked/deep\n" ["blocked/middle/deep", "blocked/deep"] $
            \base -> assertDiscovered base ["blocked/middle/deep"]
    it "treats double star as a repeated segment star rather than a recursive directory operator" $
        withDiscovery "a/**/b/\n" ["a/x/b", "z/a/x/b", "a/x/y/b", "a/b"] $
            \base -> assertDiscovered base ["a/x/y/b", "a/b"]
    it "includes ordinary hidden directories rather than blanket-skipping dot-prefixed names" $
        withDiscovery "" [".hidden/project", "kept"] $
            \base -> assertDiscovered base [".hidden/project", "kept"]
    it "treats a question mark as a literal directory character" $
        withDiscovery "with?mark/\n" ["with?mark", "withXmark"] $
            \base -> assertDiscovered base ["withXmark"]
    it "does not treat a backslash as a pattern escape" $
        withDiscovery "\\*/\n" ["\\literal", "*"] $
            \base -> assertDiscovered base ["*"]
    it "inherits directory rules while keeping child rules local to their declaring subtree" $
        withDiscovery "root-blocked/\n" ["project/blocked", "sibling/blocked", "sibling/root-blocked"] $ \base -> do
            writeFixture (base </> "project/.gitignore") "blocked/\n"
            assertDiscovered base ["sibling/blocked"]
    it "prunes Git metadata and immutable source caches even without ignore rules" $
        withDiscovery "" [".git/nested", ".agents/c-plugin/sources/owner/repo/commit/tree/nested", "kept"] $
            \base -> assertDiscovered base ["kept"]
    it "does not follow symlink directories during recursive discovery" $
        withDiscovery "" ["physical"] $ \base -> do
            createSymbolicLink "physical" (base </> "alias")
            assertDiscovered base ["physical"]
    it "starts recursive traversal from the owning lock even when invoked from a deeper directory" $
        withDiscovery "" ["child"] $ \base -> do
            createDirectoryIfMissing True (base </> "work/deep")
            withCurrentDirectory (base </> "work/deep") $ assertDiscovered base ["child"]
    it "preserves owning-lock-first sorted depth-first traversal order" $
        withDiscovery "c-plugin-lock.json\n" ["bbb", "aaa/deeper", "aaa"] $ \base -> do
            paths <- runtimePaths
            discoverLocks paths False True `shouldReturn` [base </> "c-plugin-lock.json", base </> "aaa/c-plugin-lock.json", base </> "aaa/deeper/c-plugin-lock.json", base </> "bbb/c-plugin-lock.json"]
    it "preserves historical literal equality before star wildcard retry" $
        withDiscovery "*a/\n" ["*ba", "ba", "*a"] $
            \base -> assertDiscovered base ["*ba"]
    it "ignores ordinary ignore-file read failures without losing discovered locks" $
        withDiscovery "" ["child"] $ \base -> do
            removeFile (base </> ".gitignore")
            createDirectoryIfMissing True (base </> ".gitignore")
            assertDiscovered base ["child"]
    it "nonrecursive discovery returns only the nearest owning lock" $
        withDiscovery "" ["child", "other"] $ \base -> do
            createDirectoryIfMissing True (base </> "child/work/deep")
            withCurrentDirectory (base </> "child/work/deep") $ do
                paths <- runtimePaths
                discoverLocks paths False False `shouldReturn` [base </> "child/c-plugin-lock.json"]

withDiscovery :: String -> [FilePath] -> (FilePath -> IO a) -> IO a
withDiscovery rules directories action = withFixture [] $ \base _ -> inEnvironment base $ do
    writeFixture (base </> ".gitignore") (BSC.pack rules)
    forM_ directories $ \directory -> writeFixture (base </> directory </> "c-plugin-lock.json") "synthetic discovery marker, deliberately not parsed"
    action base

assertDiscovered :: FilePath -> [FilePath] -> IO ()
assertDiscovered base directories = do
    paths <- runtimePaths
    (sort <$> discoverLocks paths False True) `shouldReturn` sort ((base </> "c-plugin-lock.json") : map (\directory -> base </> directory </> "c-plugin-lock.json") directories)
