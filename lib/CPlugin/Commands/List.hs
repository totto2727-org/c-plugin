module CPlugin.Commands.List (run) where

import CPlugin.Commands.Common (loadCurrent)
import CPlugin.Commands.Listing (printPlugins, printSkills)
import CPlugin.Paths (RuntimePaths)

run :: RuntimePaths -> Bool -> IO ()
run paths global = do
    (_, current) <- loadCurrent paths global
    printPlugins current
    putStrLn ""
    printSkills current
