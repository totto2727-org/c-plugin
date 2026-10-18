module CPlugin.Commands.SkillList (run) where

import CPlugin.Commands.Common (loadCurrent)
import CPlugin.Commands.Listing (printSkills)
import CPlugin.Paths (RuntimePaths)

run :: RuntimePaths -> Bool -> IO ()
run paths global = do
    (_, current) <- loadCurrent paths global
    printSkills current
