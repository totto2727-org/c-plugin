module CPlugin.Types.SelectionSpec (spec) where

import CPlugin.Types.Name (itemName)
import CPlugin.Types.Selection (RemovalChoice (..), Selection (..), parseRemovalSkill, parseSelectionResponse)
import Control.Monad (forM_)
import Data.Either (isLeft)
import qualified Data.Set as Set
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "selection response grammar" $ do
    it "uses the exact displayed order rather than value ordering" $
        parseSelectionResponse ["zeta", "alpha", "beta"] "1, 3" `shouldBe` Right (Selected (Set.fromList ["zeta", "beta"]))
    it "accepts whitespace separated indexes including both boundaries" $
        parseSelectionResponse ["zeta", "alpha", "beta"] " 3  1 " `shouldBe` Right (Selected (Set.fromList ["zeta", "beta"]))
    forM_ ["none", " NONE "] $ \response ->
        it ("returns explicit empty selection for " ++ show response) $
            parseSelectionResponse ["alpha"] response `shouldBe` Right (Selected Set.empty)
    forM_ ["", " \t ", "q", "cancel", " CANCEL ", "\ESC"] $ \response ->
        it ("distinguishes cancellation for " ++ show response) $
            parseSelectionResponse ["alpha"] response `shouldBe` Right Cancelled
    it "selects all choices case insensitively" $
        parseSelectionResponse ["beta", "alpha"] " ALL " `shouldBe` Right (Selected (Set.fromList ["alpha", "beta"]))
    it "allows all on an empty choice list" $
        parseSelectionResponse ([] :: [String]) "all" `shouldBe` Right (Selected Set.empty)
    forM_ ["0", "-1", "+1", "1.0", "1e0", "4", "999999999999999999999999999999", "1,1", "1 01", "1-3", "*", "alpha", "1 nope", ", ,"] $ \response ->
        it ("rejects invalid response without a partial selection: " ++ show response) $
            parseSelectionResponse ["alpha", "beta", "gamma"] response `shouldSatisfy` isLeft
    it "rejects indexes when no choices exist" $
        parseSelectionResponse ([] :: [String]) "1" `shouldSatisfy` isLeft
    describe "typed removal selectors" $ do
        it "distinguishes bare standalone selection from plugin skills" $
            parseRemovalSkill "alpha" `shouldBe` (RemoveStandalone <$> itemName "alpha")
        it "constructs a qualified plugin skill selection" $
            parseRemovalSkill "demo/alpha" `shouldBe` (RemoveSkill <$> itemName "demo" <*> itemName "alpha")
        forM_ ["", "../alpha", "/demo/alpha", "demo/group/alpha", "demo\\alpha", "demo/../alpha"] $ \response ->
            it ("rejects malformed removal selector " ++ show response) $
                parseRemovalSkill response `shouldSatisfy` isLeft
