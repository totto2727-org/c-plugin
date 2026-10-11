module CPlugin.Internal.JSON (validated, optionalString) where

import Control.Monad (void)
import Data.Aeson (Object, parseJSON)
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Aeson.Types (Parser)

validated :: Either String a -> Parser a
validated = either fail pure

optionalString :: Object -> Key.Key -> Parser ()
optionalString o k = case KeyMap.lookup k o of
    Nothing -> pure ()
    Just v -> void (parseJSON v :: Parser String)
