module CPlugin.Internal.Validation (uniqueSet, uniqueMap) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

uniqueSet :: (Ord a) => String -> [a] -> Either String (Set.Set a)
uniqueSet label xs =
    let result = Set.fromList xs
     in if Set.size result == length xs then Right result else Left (label ++ " must be unique")

uniqueMap :: (Ord k) => String -> (a -> k) -> [a] -> Either String (Map.Map k a)
uniqueMap label key xs =
    let result = Map.fromList [(key x, x) | x <- xs]
     in if Map.size result == length xs then Right result else Left (label ++ " must be unique")
