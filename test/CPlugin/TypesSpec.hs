module CPlugin.TypesSpec (spec) where

import CPlugin.Types.Name (itemName, pluginNameValue, skillNameValue)
import CPlugin.Types.Path (absolutePath, relativePath)
import Control.Monad (forM_)
import Data.Either (isLeft)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
    describe "validated domain values" $ do
        it "normalizes dots in target paths" $ relativePath ".cursor/./skills" `shouldBe` relativePath ".cursor/skills"
        forM_ ["../escape", "safe/../escape", "/absolute", "back\\slash", "nul\0path"] $ \p ->
            it ("rejects unsafe relative path " ++ show p) $ relativePath p `shouldSatisfy` isLeft
        it "rejects NUL in absolute paths" $ absolutePath "/safe/\0" `shouldSatisfy` isLeft
        it "accepts Unicode lowercase skill names" $ skillNameValue "éclair" `shouldBe` itemName "éclair"
        it "rejects Unicode uppercase skill names" $ skillNameValue "Éclair" `shouldSatisfy` isLeft
        it "requires ASCII-only standard plugin names" $ pluginNameValue "éclair" `shouldSatisfy` isLeft
