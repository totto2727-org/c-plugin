module CPlugin.Source.GitHub (
    GitRunner,
    runGit,
    fetchGitHub,
    fetchGitHubWith,
    verifyGitHub,
    verifyGitHubWith,
) where

import CPlugin.Paths (PathKind (..), absoluteIO, ensureManagedRoot, pathKind, strictRealPath, validateManagedRoot, within)
import CPlugin.Types.GitHub
import CPlugin.Types.Path (AbsolutePath, absoluteText, relativePath, relativeText)
import Control.Exception (bracket)
import Control.Monad (unless, void, when)
import Data.Aeson (eitherDecode, encode)
import Data.Bits ((.&.))
import qualified Data.ByteString.Lazy as Lazy
import Data.List (isPrefixOf)
import Data.Maybe (isJust, isNothing)
import System.Directory (listDirectory, removeDirectory, renameDirectory)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.Posix.Files (fileMode, getFileStatus, readSymbolicLink, removeLink)
import System.Posix.Temp (mkdtemp)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)

-- The injected runner is a testing boundary, not a transport option exposed by
-- the CLI. Production only passes the fixed HTTPS URL to network operations.
type GitRunner = Bool -> FilePath -> [String] -> IO String

runGit :: GitRunner
runGit network directory arguments = do
    inherited <- getEnvironment
    let clean = filter (\(key, _) -> not ("GIT_" `isPrefixOf` key) && key `notElem` ["GCM_INTERACTIVE", "SSH_ASKPASS"]) inherited
        auth = [("GIT_OPTIONAL_LOCKS", "0"), ("GIT_NO_REPLACE_OBJECTS", "1"), ("GIT_TERMINAL_PROMPT", "0"), ("GIT_ASKPASS", "/usr/bin/false"), ("SSH_ASKPASS", "/usr/bin/false"), ("GCM_INTERACTIVE", "never")]
        isolated = if network then [] else [("GIT_CONFIG_GLOBAL", "/dev/null"), ("GIT_CONFIG_SYSTEM", "/dev/null"), ("GIT_CONFIG_NOSYSTEM", "1")]
        options = concatMap (\value -> ["-c", value]) ["core.hooksPath=/dev/null", "core.fsmonitor=false", "submodule.recurse=false", "protocol.allow=never", "protocol.https.allow=always", "http.followRedirects=false", "credential.interactive=false", "core.attributesFile=/dev/null"]
    (code, output, _) <- readCreateProcessWithExitCode ((proc "git" (options ++ arguments)){cwd = Just directory, env = Just (auth ++ isolated ++ clean)}) ""
    case code of
        ExitSuccess -> pure output
        ExitFailure _ -> ioError (userError "GitHub source Git operation failed (check repository/ref access and installed Git credentials)")

fetchGitHub :: FilePath -> GitHubRepository -> Maybe GitHubRef -> GitHubSubpath -> IO (GitHubOrigin, AbsolutePath)
fetchGitHub = fetchGitHubWith runGit

fetchGitHubWith :: GitRunner -> FilePath -> GitHubRepository -> Maybe GitHubRef -> GitHubSubpath -> IO (GitHubOrigin, AbsolutePath)
fetchGitHubWith git base repository requested subpath = do
    let cache = base </> ".agents/c-plugin/sources"
    cacheRoot <- absoluteIO cache
    ensureManagedRoot base cacheRoot
    -- Only this call-created staging directory may be removed. Existing cache
    -- entries, including corrupt entries, are never removed or adopted.
    bracket (mkdtemp (cache </> ".fetch-XXXXXX")) (cleanupStaging base) $ \staging -> do
        let tree = staging </> "tree"
        void (git False staging ["init", "--template=", "--", tree])
        void (git False tree ["remote", "add", "origin", repositoryURL repository])
        resolvedURL <- git True tree ["ls-remote", "--get-url", "--", repositoryURL repository]
        unless (trimLine resolvedURL == repositoryURL repository) (ioError (userError "installed Git configuration rewrites the fixed GitHub URL"))
        void (git True tree ["fetch", "--no-tags", "--no-recurse-submodules", "--depth=1", "--", repositoryURL repository, maybe "HEAD" refText requested])
        commit <- git False tree ["rev-parse", "--verify", "FETCH_HEAD^{commit}"] >>= either (ioError . userError) pure . githubCommit . trimLine
        let origin = makeGitHubOrigin repository requested subpath commit
            destination = cache </> repositoryText repository </> commitText commit
        void (validateTrackedTree git tree "FETCH_HEAD")
        void (git False tree ["-c", "advice.detachedHead=false", "checkout", "--detach", commitText commit, "--"])
        -- No repository-provided hooks, submodules, or symlink content is run.
        Lazy.writeFile (staging </> "origin.json") (encode (snapshotFor origin))
        parent <- absoluteIO (takeDirectory destination)
        ensureManagedRoot base parent
        kind <- pathKind destination
        case kind of
            Nothing -> renameDirectory staging destination
            Just PhysicalDirectory -> pure ()
            _ -> ioError (userError "GitHub cache entry is not a physical directory")
        root <- verifyGitHubWith git base origin
        pure (origin, root)

cleanupStaging :: FilePath -> FilePath -> IO ()
cleanupStaging base staging = do
    kind <- pathKind staging
    when (isJust kind) $ do
        root <- absoluteIO staging
        validateManagedRoot base root
        removeOwnedTree staging
  where
    removeOwnedTree path = do
        kind <- pathKind path
        case kind of
            Just PhysicalDirectory -> do
                names <- listDirectory path
                mapM_ (removeOwnedTree . (path </>)) names
                removeDirectory path
            Just _ -> removeLink path
            Nothing -> pure ()

verifyGitHub :: FilePath -> GitHubOrigin -> IO AbsolutePath
verifyGitHub = verifyGitHubWith runGit

verifyGitHubWith :: GitRunner -> FilePath -> GitHubOrigin -> IO AbsolutePath
verifyGitHubWith git base origin = do
    let snapshot = base </> ".agents/c-plugin/sources" </> repositoryText (githubOriginRepository origin) </> commitText (githubOriginCommit origin)
        tree = snapshot </> "tree"
        marker = snapshot </> "origin.json"
    snapshotRoot <- absoluteIO snapshot
    validateManagedRoot base snapshotRoot
    markerKind <- pathKind marker
    unless (markerKind == Just RegularFile) (ioError (userError "GitHub cache provenance must be a physical regular file"))
    recorded <- Lazy.readFile marker >>= either (ioError . userError) pure . eitherDecode
    unless (recorded == snapshotFor origin) (ioError (userError "GitHub cache provenance does not match locked origin"))
    treeRoot <- absoluteIO tree
    validateManagedRoot base treeRoot
    gitRoot <- absoluteIO (tree </> ".git")
    validateManagedRoot base gitRoot
    mapM_ requireDirectory [snapshot, tree, tree </> ".git"]
    -- Inspect .git without trusting an attacker-supplied config or alternates.
    validateGitMetadata tree
    void (git False tree ["fsck", "--full", "--no-reflogs"])
    remote <- git False tree ["config", "--local", "--get", "remote.origin.url"]
    unless (trimLine remote == repositoryURL (githubOriginRepository origin)) (ioError (userError "GitHub cache remote differs from locked repository"))
    headCommit <- git False tree ["rev-parse", "--verify", "HEAD^{commit}"]
    unless (trimLine headCommit == commitText (githubOriginCommit origin)) (ioError (userError "GitHub cache HEAD differs from locked commit"))
    entries <- validateTrackedTree git tree "HEAD"
    mapM_ (verifyTrackedEntry git tree) [entry | entry@(mode, _, _) <- entries, mode == "120000"]
    verifyRegularEntries git tree [entry | entry@(mode, _, _) <- entries, mode /= "120000"]
    dirty <- git False tree ["-c", "core.fileMode=true", "status", "--porcelain", "--untracked-files=all", "--ignored"]
    unless (null dirty) (ioError (userError "GitHub cache snapshot was modified"))
    root <- absoluteIO (base </> relativeText (githubSource origin))
    validateManagedRoot base root
    requireDirectory (absoluteText root)
    physicalTree <- strictRealPath tree
    physicalRoot <- strictRealPath (absoluteText root)
    unless (within physicalTree physicalRoot) (ioError (userError "GitHub selection escapes pinned snapshot"))
    pure root

requireDirectory :: FilePath -> IO ()
requireDirectory path = do
    kind <- pathKind path
    unless (kind == Just PhysicalDirectory) (ioError (userError ("GitHub cache directory is missing or redirected: " ++ path)))

validateTrackedTree :: GitRunner -> FilePath -> String -> IO [(String, String, FilePath)]
validateTrackedTree git tree revision = do
    output <- git False tree ["ls-tree", "-r", "-z", revision]
    mapM parseEntry (splitNul output)
  where
    parseEntry entry = case break (== '\t') entry of
        (header, '\t' : path) -> case words header of
            [mode, "blob", objectId] | mode `elem` ["100644", "100755", "120000"] -> do
                source <- either (ioError . userError) pure (relativePath path)
                unless (relativeText source == path && notElem ".git" (splitSlash path)) (ioError (userError "invalid GitHub tree path"))
                pure (mode, objectId, path)
            _ -> ioError (userError "GitHub snapshots cannot contain submodules or special entries")
        _ -> ioError (userError "invalid GitHub tree entry")
    splitSlash value = case break (== '/') value of
        (part, []) -> [part]
        (part, _ : rest) -> part : splitSlash rest

-- Rehash contents rather than trusting index timestamps, skip-worktree flags,
-- or assume-unchanged bits. Symlinks may only resolve inside the source tree.
verifyTrackedEntry :: GitRunner -> FilePath -> (String, String, FilePath) -> IO ()
verifyTrackedEntry git tree (mode, objectId, path) = do
    let full = tree </> path
    parent <- absoluteIO (takeDirectory full)
    validateManagedRoot tree parent
    kind <- pathKind full
    if mode == "120000"
        then do
            unless (kind == Just SymbolicLink) (ioError (userError "GitHub tracked symlink was replaced"))
            literal <- readSymbolicLink full
            expected <- git False tree ["cat-file", "blob", objectId]
            unless (literal == expected) (ioError (userError "GitHub tracked symlink was modified"))
            target <- strictRealPath full
            unless (within tree target && not (within (tree </> ".git") target)) (ioError (userError "GitHub tracked symlink escapes source tree"))
        else do
            unless (kind == Just RegularFile) (ioError (userError "GitHub tracked file was replaced"))
            status <- getFileStatus full
            let executable = fileMode status .&. 0o100 /= 0
            unless (executable == (mode == "100755")) (ioError (userError "GitHub tracked file mode differs from pinned commit"))

-- Bound argv growth and process startup cost while validating each physical
-- file immediately before its batch. Git emits one blob hash per argv path.
verifyRegularEntries :: GitRunner -> FilePath -> [(String, String, FilePath)] -> IO ()
verifyRegularEntries _ _ [] = pure ()
verifyRegularEntries git tree entries = do
    let (batch, remaining) = splitAt 32 entries
        paths = [path | (_, _, path) <- batch]
        expected = [objectId | (_, objectId, _) <- batch]
    mapM_ (verifyTrackedEntry git tree) batch
    output <- git False tree (["hash-object", "--no-filters", "--"] ++ paths)
    let actual = map trimLine (lines output)
    unless (length actual == length expected) (ioError (userError "GitHub cache hash output count differs from tracked file batch"))
    unless (and (zipWith (==) actual expected)) (ioError (userError "GitHub tracked file differs from pinned commit"))
    verifyRegularEntries git tree remaining

splitNul :: String -> [String]
splitNul [] = []
splitNul value = case break (== '\0') value of
    (entry, []) -> [entry]
    (entry, _ : rest) -> entry : splitNul rest

validateGitMetadata :: FilePath -> IO ()
validateGitMetadata tree = do
    let metadata = tree </> ".git"
    -- A physical metadata tree prevents gitdir/worktree indirection. No cached
    -- repository config is trusted for command execution or transport changes.
    inspect metadata
    config <- readFile (metadata </> "config")
    let permitted line = null line || line `elem` ["[core]", "[remote \"origin\"]"] || any (`isPrefixOf` line) ["repositoryformatversion = ", "filemode = ", "bare = ", "logallrefupdates = ", "ignorecase = ", "precomposeunicode = ", "url = https://github.com/", "fetch = +refs/heads/*:refs/remotes/origin/*"]
    unless (all (permitted . dropWhile (`elem` [' ', '\t'])) (lines config)) (ioError (userError "GitHub cache contains unexpected Git configuration"))
    mapM_ rejectPresent [metadata </> "objects/info/alternates", metadata </> "info/grafts", metadata </> "commondir"]
  where
    inspect directory = do
        names <- listDirectory directory
        mapM_
            ( \name -> do
                let path = directory </> name
                kind <- pathKind path
                case kind of
                    Just PhysicalDirectory -> inspect path
                    Just RegularFile -> pure ()
                    _ -> ioError (userError "GitHub cache metadata contains a redirected or special entry")
            )
            names
    rejectPresent path = do
        kind <- pathKind path
        unless (isNothing kind) (ioError (userError "GitHub cache metadata redirects object resolution"))

trimLine :: String -> String
trimLine = reverse . dropWhile (`elem` ['\n', '\r']) . reverse
