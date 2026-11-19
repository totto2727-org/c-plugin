module CPlugin.Interaction (Interaction (..), select) where

import qualified CPlugin.Interaction.Brick as Brick
import CPlugin.Types.Selection (Selection (..), SelectionRequest (..), parseSelectionResponse, validateSelectionItems)
import Control.Monad (forM_)
import Data.List (sortOn)
import qualified Data.Set as Set
import System.IO (Handle, hFlush, hGetLine, hIsTerminalDevice, hPutStr, hPutStrLn)
import System.IO.Error (catchIOError, isEOFError)

data Interaction = NonInteractive | Interactive Handle Handle

-- Explicit requests never read input. Terminal detection belongs at the CLI
-- boundary so tests and other callers can inject ordinary handles.
select :: (Ord a) => Interaction -> String -> (a -> String) -> [a] -> SelectionRequest a -> IO (Selection a)
select _ _ _ choices SelectAll = pure (Selected (Set.fromList choices))
select _ _ _ _ SelectNone = pure (Selected Set.empty)
select _ _ _ _ (SelectItems items) = either (ioError . userError) pure (validateSelectionItems items)
select NonInteractive guidance _ _ PromptSelection = ioError (userError ("Selection required in non-interactive mode. " ++ guidance))
select (Interactive input output) guidance label choices PromptSelection =
    if null ordered
        then pure Cancelled
        else do
            terminal <- (&&) <$> hIsTerminalDevice input <*> hIsTerminalDevice output
            if terminal
                then Brick.select input output guidance label ordered
                else do
                    hPutStrLn output guidance
                    hPutStrLn output "Blank input cancels and keeps the current configuration unchanged."
                    forM_ (zip [1 :: Int ..] ordered) $ \(index, choice) ->
                        hPutStrLn output (show index ++ ") " ++ label choice)
                    prompt input output ordered
  where
    ordered = sortOn label (Set.toList (Set.fromList choices))

prompt :: (Ord a) => Handle -> Handle -> [a] -> IO (Selection a)
prompt input output choices = do
    hPutStr output "Select indexes (comma/space separated), all, none, or q to cancel: "
    hFlush output
    response <-
        (Just <$> hGetLine input) `catchIOError` \exception ->
            if isEOFError exception then pure Nothing else ioError exception
    case response of
        Nothing -> pure Cancelled
        Just line -> case parseSelectionResponse choices line of
            Right selection -> pure selection
            Left reason -> do
                hPutStrLn output ("Invalid selection: " ++ reason)
                prompt input output choices
