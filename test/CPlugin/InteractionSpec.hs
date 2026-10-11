module CPlugin.InteractionSpec (spec) where

import CPlugin.Interaction (Interaction (..), select)
import CPlugin.TestSupport (withInteractionInput)
import CPlugin.Types.Selection (Selection (..), SelectionRequest (..))
import Control.Concurrent (forkIO, killThread, myThreadId, throwTo, yield)
import Control.Exception (AsyncException (UserInterrupt), bracket, mask, throw)
import Control.Monad (forM_)
import Data.List (isInfixOf)
import qualified Data.Set as Set
import GHC.Conc (ThreadStatus (ThreadBlocked), threadStatus)
import System.IO (hClose)
import System.Posix.IO (createPipe, fdToHandle)
import Test.Hspec (Spec, anyIOException, describe, it, shouldBe, shouldReturn, shouldSatisfy, shouldThrow)

spec :: Spec
spec = describe "file-handle selection adapter" $ do
    it "rejects missing noninteractive selectors" $
        select NonInteractive "Choose skills" id ["alpha"] PromptSelection `shouldThrow` anyIOException
    it "accepts explicit noninteractive all" $
        select NonInteractive "Choose skills" id ["beta", "alpha"] SelectAll `shouldReturn` Selected (Set.fromList ["alpha", "beta"])
    it "accepts explicit noninteractive subset" $
        select NonInteractive "Choose skills" id ["alpha", "beta"] (SelectItems ["beta"]) `shouldReturn` Selected (Set.singleton "beta")
    it "accepts explicit noninteractive none without reading input" $
        select NonInteractive "Choose skills" id ["alpha"] SelectNone `shouldReturn` Selected Set.empty
    it "rejects duplicate explicit selections" $
        select NonInteractive "Choose skills" id ["alpha"] (SelectItems ["alpha", "alpha"]) `shouldThrow` anyIOException
    it "cancels an empty interactive menu without rendering a prompt" $ do
        result <- withInteractionInput "all\n" $ \interaction ->
            select interaction "Choose skills" id ([] :: [String]) PromptSelection
        result `shouldBe` (Cancelled, "")
    it "allows explicit all with no choices" $
        select NonInteractive "Choose skills" id ([] :: [String]) SelectAll `shouldReturn` Selected Set.empty
    it "displays labels in sorted order and selects by their displayed index" $ do
        (result, output) <- withInteractionInput "2\n" $ \interaction ->
            select interaction "Choose skills" ("skill: " ++) ["zeta", "alpha"] PromptSelection
        result `shouldBe` Selected (Set.singleton "zeta")
        output `shouldSatisfy` isInfixOf "skill: zeta"
        output `shouldSatisfy` isInfixOf "skill: alpha"
    forM_ ["1,1", "0", "3", "1-2", "not an index"] $ \invalid ->
        it ("reprompts after " ++ show invalid ++ " and applies only the valid answer") $ do
            (result, _) <- withInteractionInput (invalid ++ "\n2\n") $ \interaction ->
                select interaction "Choose skills" id ["alpha", "beta"] PromptSelection
            result `shouldBe` Selected (Set.singleton "beta")
    forM_ ["none\n"] $ \response ->
        it ("returns successful empty selection for " ++ show response) $ do
            (result, _) <- withInteractionInput response $ \interaction ->
                select interaction "Choose skills" id ["alpha"] PromptSelection
            result `shouldBe` Selected Set.empty
    forM_ ["\n", " \t\n", "q\n", "cancel\n", "", "invalid\n"] $ \response ->
        it ("cancels without choosing at input " ++ show response) $ do
            (result, _) <- withInteractionInput response $ \interaction ->
                select interaction "Choose skills" id ["alpha"] PromptSelection
            result `shouldBe` Cancelled
    it "does not catch a UserInterrupt raised while rendering the prompt" $
        withInteractionInput "1\n" (\interaction -> select interaction "Choose skills" (\_ -> throw UserInterrupt) ["alpha"] PromptSelection)
            `shouldThrow` (== UserInterrupt)
    it "propagates asynchronous UserInterrupt while waiting for a response" $
        withInteractionInput
            ""
            ( \interaction ->
                bracket
                    (createPipe >>= \(reader, writer) -> (,) <$> fdToHandle reader <*> fdToHandle writer)
                    (\(reader, writer) -> hClose reader >> hClose writer)
                    ( \(reader, _) -> case interaction of
                        NonInteractive -> select NonInteractive "Choose skills" id ["alpha"] PromptSelection
                        Interactive _ output -> mask $ \restore -> do
                            caller <- myThreadId
                            let interruptWhenBlocked = do
                                    status <- threadStatus caller
                                    case status of
                                        ThreadBlocked _ -> throwTo caller UserInterrupt
                                        _ -> yield >> interruptWhenBlocked
                            bracket (forkIO interruptWhenBlocked) killThread $ \_ ->
                                restore (select (Interactive reader output) "Choose skills" id ["alpha"] PromptSelection)
                    )
            )
            `shouldThrow` (== UserInterrupt)
