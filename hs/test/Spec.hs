module Main (main) where

import qualified CPlugin.CodecSpec as CodecSpec
import qualified CPlugin.CommandsSpec as CommandsSpec
import qualified CPlugin.GitHubSpec as GitHubSpec
import qualified CPlugin.InteractionSpec as InteractionSpec
import qualified CPlugin.PathsSpec as PathsSpec
import qualified CPlugin.PluginSpec as PluginSpec
import qualified CPlugin.ReconcileSpec as ReconcileSpec
import qualified CPlugin.Types.GitHubSpec as GitHubTypesSpec
import qualified CPlugin.Types.SelectionSpec as SelectionSpec
import qualified CPlugin.Types.SourceSpec as SourceSpec
import qualified CPlugin.TypesSpec as TypesSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    TypesSpec.spec
    CodecSpec.spec
    PluginSpec.spec
    ReconcileSpec.spec
    CommandsSpec.spec
    SelectionSpec.spec
    InteractionSpec.spec
    GitHubTypesSpec.spec
    GitHubSpec.spec
    PathsSpec.spec
    SourceSpec.spec
