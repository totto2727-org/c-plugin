module Main (main) where

import CPlugin.Commands (Command (..), runCommandWith)
import qualified CPlugin.Interaction as Interaction
import CPlugin.Types.GitHub (GitHubRef, githubRef, refText, repositoryText, subpathText)
import CPlugin.Types.Path (relativeText)
import CPlugin.Types.Selection (SelectionRequest (..))
import qualified CPlugin.Types.Source as Source
import Control.Exception (IOException, catch, displayException)
import Control.Monad.IO.Class (liftIO)
import Data.Version (makeVersion)
import qualified Iris
import qualified Iris.Cli.Interactive as IrisInteractive
import Options.Applicative
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hIsTerminalDevice, stderr, stdin)

-- Cross-field CLI policy stays at the boundary. Product commands receive
-- already separated local roots or GitHub repository/ref/subpath values.
data Request
    = Execute Command
    | PluginRequest Bool Source.InstallSource (Maybe GitHubRef) (SelectionRequest String) Bool
    | SkillRequest Bool Source.InstallSource (Maybe GitHubRef) Bool

global :: Parser Bool
global = switch (long "global" <> short 'g' <> help "Use the HOME lock")

recursive :: Parser Bool
recursive = switch (long "recursive" <> short 'r' <> help "Include locks below the nearest project lock, respecting ignore rules")

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

addSource :: Parser Source.InstallSource
addSource = argument (eitherReader Source.parseInstallSource) (metavar "SOURCE" <> help "local:./path or github:owner/repo[/path]; one explicit plugin or skill root")

requestedRef :: Parser (Maybe GitHubRef)
requestedRef = optional (option (eitherReader githubRef) (long "ref" <> metavar "REF" <> help "GitHub branch, tag, or commit; defaults to remote HEAD"))

pluginAdd :: Parser Request
pluginAdd = PluginRequest <$> global <*> addSource <*> requestedRef <*> addSelection <*> forceOption

skillAdd :: Parser Request
skillAdd = SkillRequest <$> global <*> addSource <*> requestedRef <*> forceOption

changeSelection :: Parser (SelectionRequest String)
changeSelection =
    flag' SelectAll (long "all" <> help "Select every skill in the registered plugin")
        <|> (SelectItems <$> some (strOption (long "skill" <> metavar "SKILL" <> help "Skill name to enable or disable")))
        <|> pure PromptSelection

pluginSkillCommand :: (Bool -> Maybe String -> SelectionRequest String -> Command) -> Parser Request
pluginSkillCommand command = Execute <$> (command <$> global <*> optional (strArgument (metavar "PLUGIN")) <*> changeSelection)

commandParser :: Parser Request
commandParser =
    hsubparser
        ( command "init" (info (Execute . Init <$> global <**> helper) (progDesc "Create an empty lock without linking skills"))
            <> command "list" (info (Execute . List <$> global <**> helper) (progDesc "List registered plugins and skills without changing state"))
            <> command "sync" (info (Execute <$> (Sync <$> global <*> recursive) <**> helper) (progDesc "Reconcile all plugin and standalone skill links from pinned sources"))
            <> command "update" (info (Execute <$> (Update <$> global <*> recursive) <**> helper) (progDesc "Refresh GitHub plugins and standalone skills, then reconcile links"))
            <> command "plugin" (info (plugins <**> helper) (progDesc "Manage standard plugins"))
            <> command "skill" (info (skills <**> helper) (progDesc "Manage plugin and standalone skills"))
            <> command "target" (info (targets <**> helper) (progDesc "Manage additional link targets"))
        )
  where
    plugins =
        hsubparser
            ( command "add" (info (pluginAdd <**> helper) (progDesc "Add a plugin or replace its enabled skill selection"))
                <> command "list" (info (Execute . PluginList <$> global <**> helper) (progDesc "List registered plugins without changing state"))
                <> command "remove" (info (Execute <$> (PluginRemove <$> global <*> selector "plugin" "Plugin name to remove") <**> helper) (progDesc "Remove registered plugins and their owned skill links"))
                <> command "skill" (info (pluginSkills <**> helper) (progDesc "Enable or disable skills in a registered plugin"))
            )
    pluginSkills =
        hsubparser
            ( command "enable" (info (pluginSkillCommand PluginSkillEnable <**> helper) (progDesc "Enable selected skills without reinstalling the plugin"))
                <> command "disable" (info (pluginSkillCommand PluginSkillDisable <**> helper) (progDesc "Disable selected skills while keeping the plugin registered"))
            )
    skills =
        hsubparser
            ( command "add" (info (skillAdd <**> helper) (progDesc "Add a standalone directory containing SKILL.md"))
                <> command "list" (info (Execute . SkillList <$> global <**> helper) (progDesc "List enabled plugin skills and standalone skills without changing state"))
                <> command "remove" (info (Execute <$> (SkillRemove <$> global <*> selector "skill" "Standalone skill name or plugin/skill to remove") <**> helper) (progDesc "Remove standalone skills or disable plugin skills"))
            )
    targets =
        hsubparser
            ( command "add" (info (Execute <$> (TargetAdd <$> global <*> strArgument (metavar "PATH")) <**> helper) (progDesc "Add a relative link target"))
                <> command "remove" (info (Execute <$> (TargetRemove <$> global <*> selector "target" "Relative target to remove") <**> helper) (progDesc "Remove registered link targets"))
            )

resolveRequest :: Request -> IO Command
resolveRequest (Execute command) = pure command
resolveRequest (PluginRequest scope source ref selection force) = case source of
    Source.LocalSource path -> rejectLocalRef ref >> pure (PluginAdd scope ("./" ++ relativeText path) selection force)
    Source.GitHubSource repository path -> pure (PluginAddGitHub scope (repositoryText repository) (refText <$> ref) (Just (subpathText path)) selection force)
resolveRequest (SkillRequest scope source ref force) = case source of
    Source.LocalSource path -> rejectLocalRef ref >> pure (SkillAdd scope ("./" ++ relativeText path) force)
    Source.GitHubSource repository path -> pure (SkillAddGitHub scope (repositoryText repository) (refText <$> ref) (Just (subpathText path)) force)

rejectLocalRef :: Maybe GitHubRef -> IO ()
rejectLocalRef Nothing = pure ()
rejectLocalRef (Just _) = ioError (userError "--ref requires a github: source")

settings :: Iris.CliEnvSettings Request ()
settings =
    Iris.defaultCliEnvSettings
        { Iris.cliEnvSettingsCmdParser = commandParser
        , Iris.cliEnvSettingsAppName = Just "c-plugin"
        , Iris.cliEnvSettingsHeaderDesc = "c-plugin - ownership-safe plugin and skill manager"
        , Iris.cliEnvSettingsProgDesc = "Install Agent Plugins 1.0 skills and standalone Agent Skills with safe, owned links."
        , Iris.cliEnvSettingsVersionSettings = Just (Iris.defaultVersionSettings (makeVersion [0, 1, 0]))
        }

main :: IO ()
main = do
    arguments <- getArgs
    -- Iris fixes its execution preferences, so apply the standard failure
    -- renderer to its public parser before entering its normal runtime.
    case execParserPure (prefs showHelpOnError) (Iris.cmdParserInfo settings) arguments of
        Failure failure -> handleParseResult (Failure failure)
        _ -> runApp

runApp :: IO ()
runApp = Iris.runCliApp settings $ do
    request <- Iris.asksCliEnv Iris.cliEnvCmd
    mode <- Iris.asksCliEnv Iris.cliEnvInteractiveMode
    liftIO ((resolveRequest request >>= \command -> cliInteraction mode >>= \interaction -> runCommandWith interaction command) `catch` reportFailure)
  where
    reportFailure :: IOException -> IO ()
    reportFailure exception = putStrLn (displayException exception) >> exitFailure

cliInteraction :: IrisInteractive.InteractiveMode -> IO Interaction.Interaction
cliInteraction IrisInteractive.NonInteractive = pure Interaction.NonInteractive
cliInteraction IrisInteractive.Interactive = do
    inputTerminal <- hIsTerminalDevice stdin
    outputTerminal <- hIsTerminalDevice stderr
    pure $ if inputTerminal && outputTerminal then Interaction.Interactive stdin stderr else Interaction.NonInteractive
