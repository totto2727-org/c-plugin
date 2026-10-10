module CPlugin.Commands.Init (run) where

import CPlugin.Paths (RuntimePaths (..))
import CPlugin.StateStore (createLock)
import CPlugin.Types.Lock (emptyLock)
import CPlugin.Types.Path (absoluteText)
import System.FilePath ((</>))

run :: RuntimePaths -> Bool -> IO ()
run paths global = do
    let root = if global then homePath paths else cwdPath paths
        lockPath = absoluteText root </> "c-plugin-lock.json"
    createLock lockPath emptyLock
    putStrLn ("Created " ++ lockPath)
