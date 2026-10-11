module CPlugin.Commands.SkillAddGitHub (run, runWithGit) where

import CPlugin.Commands.Common (failAs, loadCurrent, validateAs)
import qualified CPlugin.Commands.SkillAdd as SkillAdd
import CPlugin.Paths (RuntimePaths)
import CPlugin.Source.GitHub (GitRunner, fetchGitHubWith, runGit)
import CPlugin.Types.GitHub (githubRef, githubRepositoryInput, githubSource, githubSubpath)
import Control.Exception (IOException, catch)
import Data.Maybe (fromMaybe)
import System.FilePath (takeDirectory)

run :: RuntimePaths -> Bool -> String -> Maybe String -> Maybe FilePath -> Bool -> IO ()
run = runWithGit runGit

runWithGit :: GitRunner -> RuntimePaths -> Bool -> String -> Maybe String -> Maybe FilePath -> Bool -> IO ()
runWithGit git paths global raw rawRef rawPath force = do
    let invalid = "totto2727/c-plugin.SkillAddError.InvalidInput"
    repository <- validateAs invalid (githubRepositoryInput raw)
    requested <- traverse (validateAs invalid . githubRef) rawRef
    subpath <- validateAs invalid (githubSubpath (fromMaybe "." rawPath))
    (lockPath, current) <- loadCurrent paths global
    (origin, root) <- fetchGitHubWith git (takeDirectory lockPath) repository requested subpath `catch` \e -> failAs invalid (show (e :: IOException))
    SkillAdd.runResolved lockPath current (githubSource origin) root (Just origin) force
