{-# LANGUAGE OverloadedStrings #-}

module CPlugin.E2E.Fixtures where

import CPlugin.E2E.Support
import Control.Monad (forM_)
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy as Lazy
import qualified Test.CLI.E2E as CLI
import Prelude hiding (readFile, writeFile)

emptyLock, pluginSchema, pluginJSON, soloLock :: String
emptyLock = "{\"targets\":[],\"plugins\":{},\"standaloneSkills\":{}}"
soloLock = "{\"targets\":[],\"plugins\":{},\"standaloneSkills\":{\"solo\":{\"installedSkillName\":\"solo\",\"installedSkillSource\":\"standalone/solo\",\"installedSkillOrigin\":null}}}"
pluginSchema = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
pluginJSON = "{\"$schema\":\"" ++ pluginSchema ++ "\",\"name\":\"demo\"}\n"

localLock :: [String] -> String -> [String] -> String
localLock targets repository skills =
    decodeText . Lazy.toStrict . encode $
        object
            [ "targets" .= targets
            , "plugins"
                .= object
                    [ "demo"
                        .= object
                            [ "pluginSource" .= repository
                            , "pluginName" .= ("demo" :: String)
                            , "enabledSkills" .= skills
                            , "pluginOrigin" .= (Nothing :: Maybe String)
                            ]
                    ]
            , "standaloneSkills" .= object []
            ]

writePlugin :: Scenario -> String -> [String] -> IO ()
writePlugin s root skills = do
    let plugin = root ++ "/plugin"
    writeFile s (plugin ++ "/plugin.json") pluginJSON
    forM_ skills $ \skill -> writeFile s (plugin ++ "/skills/" ++ skill ++ "/SKILL.md") (skillMarkdown skill)

skillMarkdown :: String -> String
skillMarkdown name = "---\nname: " ++ name ++ "\ndescription: Fixture " ++ name ++ " skill.\n---\n"

standardEnvironment :: CLI.Environment -> String -> [String] -> IO (Scenario, String)
standardEnvironment env name skills = do
    let homePath = "/tmp/c-plugin-standard-" ++ name ++ "/home"
        project = homePath ++ "/project"
        s = newScenario env homePath
    writePlugin s project skills
    run s project ["init"] >>= requireSuccess
    pure (s, project)
