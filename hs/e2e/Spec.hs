module Main (main) where

import qualified CPlugin.E2E.CoreSpec as Core
import qualified CPlugin.E2E.GitHubSpec as GitHub
import qualified CPlugin.E2E.InteractiveSpec as Interactive
import qualified CPlugin.E2E.ListSpec as List
import qualified CPlugin.E2E.StandaloneSpec as Standalone
import qualified CPlugin.E2E.UnifiedSpec as Unified
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    Core.spec
    GitHub.spec
    Standalone.spec
    List.spec
    Interactive.spec
    Unified.spec
