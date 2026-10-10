module Main (main) where

import CPlugin.Commands (Command (..), runCommand)
import Control.Exception (IOException, catch, displayException)
import Control.Monad.IO.Class (liftIO)
import Data.Version (makeVersion)
import qualified Iris
import Options.Applicative
import System.Exit (exitFailure)

global :: Parser Bool
global = switch (long "global" <> short 'g' <> help "Use the HOME lock")

selector :: String -> String -> Parser [String]
selector name description = many (strOption (long name <> metavar "SELECTOR" <> help description))

commandParser :: Parser Command
commandParser =
    hsubparser
        ( command "init" (info (Init <$> global <**> helper) (progDesc "Create a version 3 lock without linking skills"))
            <> command "skill" (info (skills <**> helper) (progDesc "Manage plugin skills"))
        )
  where
    skills =
        hsubparser
            ( command "sync" (info (Sync <$> global <*> switch (long "recursive" <> short 'r' <> help "Sync descendant project locks") <**> helper) (progDesc "Reconcile owned skill links"))
                <> command "add" (info (AddLocal <$> global <*> strOption (long "local" <> metavar "PATH" <> help "Standard plugin root relative to the lock") <*> selector "skill" "Skill name to install (default: all valid skills)" <*> switch (long "force" <> short 'f' <> help "Replace eligible file or symlink collisions") <**> helper) (progDesc "Add a standard Agent Plugin"))
                <> command "remove" (info (Remove <$> global <*> selector "plugin" "Plugin name to remove" <*> selector "skill" "Plugin/skill to remove" <**> helper) (progDesc "Remove registered plugins or skills"))
                <> command "target" (info (targets <**> helper) (progDesc "Manage additional link targets"))
            )
    targets =
        hsubparser
            ( command "add" (info (TargetAdd <$> global <*> strArgument (metavar "PATH") <**> helper) (progDesc "Add a relative link target"))
                <> command "remove" (info (TargetRemove <$> global <*> selector "target" "Relative target to remove" <**> helper) (progDesc "Remove registered link targets"))
            )

settings :: Iris.CliEnvSettings Command ()
settings =
    Iris.defaultCliEnvSettings
        { Iris.cliEnvSettingsCmdParser = commandParser
        , Iris.cliEnvSettingsAppName = Just "c-plugin"
        , Iris.cliEnvSettingsHeaderDesc = "c-plugin - ownership-safe plugin skill manager"
        , Iris.cliEnvSettingsProgDesc = "Install Agent Plugins 1.0 skills and reconcile safe, owned links."
        , Iris.cliEnvSettingsVersionSettings = Just (Iris.defaultVersionSettings (makeVersion [0, 1, 0]))
        }

main :: IO ()
main = Iris.runCliApp settings $ do
    commandValue <- Iris.asksCliEnv Iris.cliEnvCmd
    liftIO (runCommand commandValue `catch` reportFailure)
  where
    reportFailure :: IOException -> IO ()
    reportFailure exception = putStrLn (displayException exception) >> exitFailure
