module CPlugin.Commands.PluginAddGitHub (run, runWithGit) where

import CPlugin.Commands.Common (failAs, loadCurrent, validateAs)
import qualified CPlugin.Commands.PluginAdd as PluginAdd
import CPlugin.Interaction (Interaction)
import CPlugin.Paths (RuntimePaths)
import CPlugin.Source.GitHub (GitRunner, fetchGitHubWith)
import CPlugin.Source.Libgit2 (runLibgit2)
import CPlugin.Types.GitHub (githubRef, githubRepositoryInput, githubSource, githubSubpath)
import CPlugin.Types.Selection (SelectionRequest)
import Control.Exception (IOException, catch)
import Data.Maybe (fromMaybe)
import System.FilePath (takeDirectory)

run :: Interaction -> RuntimePaths -> Bool -> String -> Maybe String -> Maybe FilePath -> SelectionRequest String -> Bool -> IO ()
run = runWithGit runLibgit2

runWithGit :: GitRunner -> Interaction -> RuntimePaths -> Bool -> String -> Maybe String -> Maybe FilePath -> SelectionRequest String -> Bool -> IO ()
runWithGit git interaction paths global raw rawRef rawPath request force = do
    let invalid = "totto2727/c-plugin.PluginAddError.InvalidInput"
    repository <- validateAs invalid (githubRepositoryInput raw)
    requested <- traverse (validateAs invalid . githubRef) rawRef
    subpath <- validateAs invalid (githubSubpath (fromMaybe "." rawPath))
    (lockPath, current) <- loadCurrent paths global
    (origin, root) <- fetchGitHubWith git (takeDirectory lockPath) repository requested subpath `catch` \e -> failAs invalid (show (e :: IOException))
    PluginAdd.runResolved interaction lockPath current (githubSource origin) root (Just origin) request force
