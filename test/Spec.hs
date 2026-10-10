module Main (main) where

import qualified CPlugin.CodecSpec as CodecSpec
import qualified CPlugin.CommandsSpec as CommandsSpec
import qualified CPlugin.PluginSpec as PluginSpec
import qualified CPlugin.ReconcileSpec as ReconcileSpec
import qualified CPlugin.TypesSpec as TypesSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    TypesSpec.spec
    CodecSpec.spec
    PluginSpec.spec
    ReconcileSpec.spec
    CommandsSpec.spec
