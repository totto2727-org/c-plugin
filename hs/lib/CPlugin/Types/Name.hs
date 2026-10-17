{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module CPlugin.Types.Name (ItemName, itemName, pluginNameValue, skillNameValue, nameText) where

import Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import Data.Char (isAlphaNum, isAscii, isAsciiUpper, isControl, isLower, isNumber)
import Data.List (isInfixOf)

newtype ItemName = ItemName String deriving (Eq, Ord, Show, FromJSON, ToJSON, FromJSONKey, ToJSONKey)

nameText :: ItemName -> String
nameText (ItemName n) = n

itemName :: String -> Either String ItemName
itemName n
    | null n || n == "." || n == ".." || any (\c -> c `elem` "/\\" || isControl c) n = Left "item must be a non-path name"
    | otherwise = Right (ItemName n)
pluginNameValue :: String -> Either String ItemName
pluginNameValue n
    | null n
        || length n > 64
        || not (alnum (head n))
        || not (alnum (last n))
        || not (all (\c -> alnum c || c `elem` ".-") n)
        || "--" `isInfixOf` n
        || ".." `isInfixOf` n =
        Left "invalid standard plugin name"
    | otherwise = itemName n
  where
    alnum c = isAscii c && isAlphaNum c && not (isAsciiUpper c)

skillNameValue :: String -> Either String ItemName
skillNameValue n
    | null n
        || length n > 64
        || head n == '-'
        || last n == '-'
        || "--" `isInfixOf` n
        || not (all (\c -> c == '-' || isLower c || isNumber c) n) =
        Left "invalid Agent Skills name"
    | otherwise = itemName n
