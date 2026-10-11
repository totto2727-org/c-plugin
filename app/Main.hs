module Main (main) where

import CPlugin.Commands (Command (..), runCommandWith)
import qualified CPlugin.Interaction as Interaction
import CPlugin.Types.Selection (SelectionRequest (..))
import Control.Exception (IOException, catch, displayException)
import Control.Monad.IO.Class (liftIO)
import Data.Version (makeVersion)
import qualified Iris
import qualified Iris.Cli.Interactive as IrisInteractive
import Options.Applicative
import System.Exit (exitFailure)
import System.IO (hIsTerminalDevice, stderr, stdin)

global :: Parser Bool
global = switch (long "global" <> short 'g' <> help "Use the HOME lock")

forceOption :: Parser Bool
forceOption = switch (long "force" <> short 'f' <> help "Replace eligible file or symlink collisions")

selector :: String -> String -> Parser [String]
selector name description = many (strOption (long name <> metavar "SELECTOR" <> help description))

addSelection :: Parser (SelectionRequest String)
addSelection =
    flag' SelectAll (long "all" <> help "Enable all valid plugin skills")
        <|> flag' SelectNone (long "none" <> help "Register the plugin with no enabled skills, or disable its existing skills")
        <|> (SelectItems <$> some (strOption (long "skill" <> metavar "SKILL" <> help "Skill name to enable in the replacement selection")))
        <|> pure PromptSelection

pluginAdd :: Parser Command
pluginAdd = PluginAdd <$> global <*> strOption (long "local" <> metavar "PATH" <> help "Explicit standard plugin root relative to the lock") <*> addSelection <*> forceOption

skillAdd :: Parser Command
skillAdd = SkillAdd <$> global <*> strOption (long "local" <> metavar "PATH" <> help "Explicit standalone skill directory containing SKILL.md, relative to the lock") <*> forceOption

commandParser :: Parser Command
commandParser =
    hsubparser
        ( command "init" (info (Init <$> global <**> helper) (progDesc "Create a version 3 lock without linking skills"))
            <> command "plugin" (info (hsubparser (command "add" (info (pluginAdd <**> helper) (progDesc "Add a plugin or replace its enabled skill selection"))) <**> helper) (progDesc "Manage standard plugins"))
            <> command "skill" (info (skills <**> helper) (progDesc "Manage plugin and standalone skills"))
        )
  where
    skills =
        hsubparser
            ( command "sync" (info (Sync <$> global <*> switch (long "recursive" <> short 'r' <> help "Sync descendant project locks") <**> helper) (progDesc "Reconcile owned skill links"))
                <> command "add" (info (skillAdd <**> helper) (progDesc "Add a standalone Agent Skill"))
                <> command "remove" (info (Remove <$> global <*> selector "plugin" "Plugin name to remove" <*> selector "skill" "Standalone skill name or plugin/skill to remove" <**> helper) (progDesc "Remove registered plugins or skills"))
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
        , Iris.cliEnvSettingsHeaderDesc = "c-plugin - ownership-safe plugin and skill manager"
        , Iris.cliEnvSettingsProgDesc = "Install Agent Plugins 1.0 skills and standalone Agent Skills with safe, owned links."
        , Iris.cliEnvSettingsVersionSettings = Just (Iris.defaultVersionSettings (makeVersion [0, 1, 0]))
        }

main :: IO ()
main = Iris.runCliApp settings $ do
    commandValue <- Iris.asksCliEnv Iris.cliEnvCmd
    mode <- Iris.asksCliEnv Iris.cliEnvInteractiveMode
    liftIO ((cliInteraction mode >>= \interaction -> runCommandWith interaction commandValue) `catch` reportFailure)
  where
    reportFailure :: IOException -> IO ()
    reportFailure exception = putStrLn (displayException exception) >> exitFailure

cliInteraction :: IrisInteractive.InteractiveMode -> IO Interaction.Interaction
cliInteraction IrisInteractive.NonInteractive = pure Interaction.NonInteractive
cliInteraction IrisInteractive.Interactive = do
    inputTerminal <- hIsTerminalDevice stdin
    outputTerminal <- hIsTerminalDevice stderr
    pure $ if inputTerminal && outputTerminal then Interaction.Interactive stdin stderr else Interaction.NonInteractive
