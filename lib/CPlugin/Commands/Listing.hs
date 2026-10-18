module CPlugin.Commands.Listing (printPlugins, printSkills) where

import CPlugin.Types.GitHub (GitHubOrigin (..), commitText, repositoryText, subpathText)
import CPlugin.Types.InstalledSkill (InstalledSkill (..))
import CPlugin.Types.Lock (Lock (..))
import CPlugin.Types.Name (nameText)
import CPlugin.Types.Path (RelativePath, relativeText)
import CPlugin.Types.Plugin (Plugin (..))
import Data.List (intercalate)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

printPlugins :: Lock -> IO ()
printPlugins current = do
    putStrLn "Plugins"
    putStrLn "name\tsource\tenabled-skills"
    mapM_ printPlugin (Map.elems (plugins current))
  where
    printPlugin plugin =
        printRecord
            [ nameText (pluginName plugin)
            , displaySource (pluginSource plugin) (pluginOrigin plugin)
            , if Set.null (enabledSkills plugin)
                then "-"
                else intercalate "," (map nameText (Set.toAscList (enabledSkills plugin)))
            ]

printSkills :: Lock -> IO ()
printSkills current = do
    putStrLn "Skills"
    putStrLn "name\towner\tsource"
    mapM_ printPluginSkills (Map.elems (plugins current))
    mapM_ printStandaloneSkill (Map.elems (standaloneSkills current))
  where
    printPluginSkills plugin =
        mapM_
            ( \name ->
                printRecord
                    [ nameText name
                    , "plugin:" ++ nameText (pluginName plugin)
                    , displaySource (pluginSource plugin) (pluginOrigin plugin)
                    ]
            )
            (Set.toAscList (enabledSkills plugin))
    printStandaloneSkill skill =
        printRecord
            [ nameText (installedSkillName skill)
            , "standalone"
            , displaySource (installedSkillSource skill) (installedSkillOrigin skill)
            ]

displaySource :: RelativePath -> Maybe GitHubOrigin -> String
displaySource source Nothing = "local:./" ++ relativeText source
displaySource _ (Just origin) =
    "github:"
        ++ repositoryText (githubOriginRepository origin)
        ++ (if subpath == "." then "" else "/" ++ subpath)
        ++ "@"
        ++ commitText (githubOriginCommit origin)
  where
    subpath = subpathText (githubOriginSubpath origin)

printRecord :: [String] -> IO ()
printRecord = putStrLn . intercalate "\t"
