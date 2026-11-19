module CPlugin.Source.Gitlib (runGitlib) where

import CPlugin.Internal.Concurrent (withIO)
import Control.Exception (SomeException, catch, throwIO)
import Control.Monad.Trans.Reader (runReaderT)
import Data.List (isPrefixOf)
import qualified Data.Text as Text
import Git (RepositoryOptions (..), defaultRepositoryOptions)
import Git.CmdLine (CliRepo (..), doRunGit)
import qualified Shelly
import System.Directory (makeAbsolute)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, (</>))
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)

runGitlib :: Bool -> FilePath -> [String] -> IO String
runGitlib network directory arguments = do
    workingDirectory <- makeAbsolute directory
    inherited <- getEnvironment
    let clean = filter (\(key, _) -> not ("GIT_" `isPrefixOf` key) && key `notElem` ["GCM_INTERACTIVE", "SSH_ASKPASS"]) inherited
        auth = [("GIT_OPTIONAL_LOCKS", "0"), ("GIT_NO_REPLACE_OBJECTS", "1"), ("GIT_TERMINAL_PROMPT", "0"), ("GIT_ASKPASS", "/usr/bin/false"), ("SSH_ASKPASS", "/usr/bin/false"), ("GCM_INTERACTIVE", "never")]
        isolated = if network then [] else [("GIT_CONFIG_GLOBAL", "/dev/null"), ("GIT_CONFIG_SYSTEM", "/dev/null"), ("GIT_CONFIG_NOSYSTEM", "1")]
        options = concatMap (\value -> ["-c", value]) ["core.hooksPath=/dev/null", "core.fsmonitor=false", "submodule.recurse=false", "protocol.allow=never", "protocol.https.allow=always", "http.followRedirects=false", "credential.interactive=false", "core.attributesFile=/dev/null"]
        -- gitlib adds explicit repository paths, including before init creates it.
        root = case arguments of
            ["init", "--template=", "--", target] -> if isAbsolute target then target else workingDirectory </> target
            _ -> workingDirectory
        repository = CliRepo defaultRepositoryOptions{repoPath = root </> ".git", repoWorkingDir = Just root}
        -- The supported execution callback retains raw output and the standard
        -- process runner's cancellation cleanup, unlike Shelly's line runner.
        execute executable argv =
            Shelly.liftIO $
                readCreateProcessWithExitCode
                    ((proc executable (map Text.unpack argv)){cwd = Just workingDirectory, env = Just (auth ++ isolated ++ clean)})
                    ""
    (code, output, _) <-
        withIO $
            runReaderT (doRunGit execute (map Text.pack (options ++ arguments)) (pure ())) repository
                `catch` unwrapShelly
    case code of
        ExitSuccess -> pure output
        ExitFailure _ -> ioError (userError "GitHub source Git operation failed (check repository/ref access and installed Git credentials)")

-- Shelly annotates every exception, including cancellation. Restore its exact
-- original type so asynchronous interruption and IO failures remain observable.
unwrapShelly :: Shelly.ReThrownException SomeException -> IO a
unwrapShelly (Shelly.ReThrownException exception _) = throwIO exception
