module CPlugin.Types.Selection (
    SelectionRequest (..),
    Selection (..),
    RemovalChoice (..),
    RemovalScope (..),
    traverseSelectionRequest,
    parseSelectionResponse,
    parseRemovalSkill,
    parseSkillSelector,
    validateSelectionItems,
    removalLabel,
) where

import CPlugin.Internal.Validation (uniqueSet)
import CPlugin.Types.Name (ItemName, itemName, nameText, pluginNameValue)
import CPlugin.Types.Path (relativePath, relativeText)
import Control.Monad (when)
import Data.Char (isDigit, toLower)
import qualified Data.Set as Set
import System.FilePath (splitDirectories)
import Text.Read (readMaybe)

data SelectionRequest a = PromptSelection | SelectAll | SelectNone | SelectItems [a]
    deriving (Eq, Show)

data Selection a = Cancelled | Selected (Set.Set a)
    deriving (Eq, Show)

data RemovalChoice = RemovePlugin ItemName | RemoveSkill ItemName ItemName | RemoveStandalone ItemName
    deriving (Eq, Ord, Show)

data RemovalScope = PluginRemoval | SkillRemoval
    deriving (Eq, Show)

traverseSelectionRequest :: (Applicative f) => (a -> f b) -> SelectionRequest a -> f (SelectionRequest b)
traverseSelectionRequest _ PromptSelection = pure PromptSelection
traverseSelectionRequest _ SelectAll = pure SelectAll
traverseSelectionRequest _ SelectNone = pure SelectNone
traverseSelectionRequest f (SelectItems items) = SelectItems <$> traverse f items

validateSelectionItems :: (Ord a) => [a] -> Either String (Selection a)
validateSelectionItems items = Selected <$> uniqueSet "selections" items

-- The caller supplies the exact ordered choices displayed to the reader.
-- Reject duplicate indexes before constructing the selected set.
parseSelectionResponse :: (Ord a) => [a] -> String -> Either String (Selection a)
parseSelectionResponse choices response =
    case map toLower (unwords (words response)) of
        "" -> Right Cancelled
        "none" -> Right (Selected Set.empty)
        "all" -> Right (Selected (Set.fromList choices))
        "q" -> Right Cancelled
        "cancel" -> Right Cancelled
        "\ESC" -> Right Cancelled
        _ -> do
            let tokens = words (map (\c -> if c == ',' then ' ' else c) response)
            when (null tokens) (Left guidance)
            indexes <- traverse parseIndex tokens
            _ <- uniqueSet "selection indexes" indexes
            pure (Selected (Set.fromList [choices !! (index - 1) | index <- indexes]))
  where
    guidance = "Enter 1-based indexes separated by commas or spaces, all, none, or q to cancel."
    parseIndex token = case if all isDigit token then readMaybe token else Nothing :: Maybe Integer of
        Just index | index >= 1 && index <= toInteger (length choices) -> Right (fromInteger index)
        _ -> Left ("Invalid selection '" ++ token ++ "'. Choose an index from 1 to " ++ show (length choices) ++ ". " ++ guidance)

parseRemovalSkill :: String -> Either String RemovalChoice
parseRemovalSkill value
    | '/' `elem` value = uncurry RemoveSkill <$> parseSkillSelector value
    | otherwise = RemoveStandalone <$> itemName value

parseSkillSelector :: String -> Either String (ItemName, ItemName)
parseSkillSelector value = do
    path <- relativePath value
    case splitDirectories (relativeText path) of
        [plugin, skill] -> (,) <$> pluginNameValue plugin <*> itemName skill
        _ -> Left "skill selection must be plugin/skill"

removalLabel :: RemovalChoice -> String
removalLabel (RemovePlugin plugin) = nameText plugin ++ " (entire plugin)"
removalLabel (RemoveSkill plugin skill) = nameText plugin ++ "/" ++ nameText skill
removalLabel (RemoveStandalone skill) = nameText skill ++ " (standalone skill)"
