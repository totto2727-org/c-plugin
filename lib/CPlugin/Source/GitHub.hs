module CPlugin.Source.GitHub (
    GitRunner,
    runGit,
    fetchGitHub,
    fetchGitHubWith,
    fetchGitHubSourcesWith,
    verifyGitHub,
    verifyGitHubWith,
    verifyGitHubSourcesWith,
) where

import CPlugin.Internal.Concurrent (concurrentlyIO, mapConcurrentlyIO, withIO)
import CPlugin.Paths (PathKind (..), absoluteIO, ensureManagedRoot, pathKind, strictRealPath, validateManagedRoot, within)
import CPlugin.Source.Gitlib (runGitlib)
import CPlugin.Types.GitHub
import CPlugin.Types.Path (AbsolutePath, absoluteText, relativePath, relativeText)
import Control.Exception (IOException, bracket, evaluate)
import Control.Monad (unless, void, when)
import Data.Aeson (encode)
import Data.Bits ((.&.))
import qualified Data.ByteString as Strict
import qualified Data.ByteString.Lazy as Lazy
import Data.List (isPrefixOf, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust, isNothing)
import System.Directory (listDirectory, removeDirectory, renameDirectory)
import System.FilePath (takeDirectory, (</>))
import System.IO (IOMode (ReadMode), hGetContents, withFile)
import System.IO.Error (catchIOError, tryIOError)
import System.Posix.Files (fileMode, getFileStatus, readSymbolicLink, removeLink)
import System.Posix.Temp (mkdtemp)

-- The injected runner is a testing boundary, not a transport option exposed by
-- the CLI. Production only passes the fixed HTTPS URL to network operations.
type GitRunner = Bool -> FilePath -> [String] -> IO String

runGit :: GitRunner
runGit = runGitlib

fetchGitHub :: FilePath -> GitHubRepository -> Maybe GitHubRef -> GitHubSubpath -> IO (GitHubOrigin, AbsolutePath)
fetchGitHub = fetchGitHubWith runGitlib

fetchGitHubWith :: GitRunner -> FilePath -> GitHubRepository -> Maybe GitHubRef -> GitHubSubpath -> IO (GitHubOrigin, AbsolutePath)
fetchGitHubWith git base repository requested subpath = do
    (origin, tree) <- fetchGitHubSnapshotWith git base repository requested subpath
    root <- selectVerifiedRoot base tree origin
    pure (origin, root)

-- Refresh each repository/ref only once, even when plugins and standalone skills
-- select different subdirectories. Restore caller order after grouped work.
fetchGitHubSourcesWith :: GitRunner -> FilePath -> [GitHubOrigin] -> IO [(GitHubOrigin, AbsolutePath)]
fetchGitHubSourcesWith git base origins = do
    let groups = Map.elems (Map.fromListWith (++) [(selection origin, [(index, origin)]) | (index, origin) <- zip [0 :: Int ..] origins])
    refreshed <- mapConcurrentlyIO refreshGroup groups
    pure (map snd (sortOn fst (concat refreshed)))
  where
    selection origin = (githubOriginRepository origin, githubOriginRef origin)
    refreshGroup group = case group of
        [] -> pure []
        (_, first) : _ -> do
            (fresh, tree) <- fetchGitHubSnapshotWith git base (githubOriginRepository first) (githubOriginRef first) (githubOriginSubpath first)
            mapM
                ( \(index, previous) -> do
                    let origin = previous{githubOriginCommit = githubOriginCommit fresh}
                    root <- selectVerifiedRoot base tree origin
                    pure (index, (origin, root))
                )
                group

fetchGitHubSnapshotWith :: GitRunner -> FilePath -> GitHubRepository -> Maybe GitHubRef -> GitHubSubpath -> IO (GitHubOrigin, FilePath)
fetchGitHubSnapshotWith git base repository requested subpath = do
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
            Nothing ->
                renameDirectory staging destination `catchIOError` \err -> do
                    -- A concurrent publisher may win with EEXIST or
                    -- ENOTEMPTY, depending on the platform. Continue only
                    -- to the mandatory full verification below, never
                    -- replace or remove an existing destination.
                    existing <- pathKind destination
                    unless (existing == Just PhysicalDirectory) (ioError err)
            Just PhysicalDirectory -> pure ()
            _ -> ioError (userError "GitHub cache entry is not a physical directory")
        treeRoot <- verifyGitHubSnapshotWith git base origin
        pure (origin, treeRoot)

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
verifyGitHub = verifyGitHubWith runGitlib

verifyGitHubWith :: GitRunner -> FilePath -> GitHubOrigin -> IO AbsolutePath
verifyGitHubWith git base origin = do
    tree <- verifyGitHubSnapshotWith git base origin
    selectVerifiedRoot base tree origin

-- Requested refs do not affect immutable snapshot identity. A corrupt snapshot
-- makes every selection unavailable, but a missing subpath affects only that
-- selection. Only ordinary IO exceptions are collected, never cancellation.
verifyGitHubSourcesWith :: GitRunner -> FilePath -> [GitHubOrigin] -> IO [Either IOException AbsolutePath]
verifyGitHubSourcesWith git base origins = do
    let groups = Map.elems (Map.fromListWith (++) [(snapshot origin, [(index, origin)]) | (index, origin) <- zip [0 :: Int ..] origins])
    verified <- mapConcurrentlyIO verifyGroup groups
    pure (map snd (sortOn fst (concat verified)))
  where
    snapshot origin = (githubOriginRepository origin, githubOriginCommit origin)
    verifyGroup group = case group of
        [] -> pure []
        (_, first) : _ -> do
            whole <- either (ioError . userError) pure (githubSubpath ".")
            result <- tryIOError (verifyGitHubSnapshotWith git base first{githubOriginSubpath = whole})
            case result of
                Left failure -> pure [(index, Left failure) | (index, _) <- group]
                Right tree ->
                    mapM
                        ( \(index, origin) -> do
                            selected <- tryIOError (selectVerifiedRoot base tree origin)
                            pure (index, selected)
                        )
                        group

verifyGitHubSnapshotWith :: GitRunner -> FilePath -> GitHubOrigin -> IO FilePath
verifyGitHubSnapshotWith git base origin = do
    let snapshot = base </> ".agents/c-plugin/sources" </> repositoryText (githubOriginRepository origin) </> commitText (githubOriginCommit origin)
        tree = snapshot </> "tree"
        marker = snapshot </> "origin.json"
    snapshotRoot <- absoluteIO snapshot
    validateManagedRoot base snapshotRoot
    markerKind <- pathKind marker
    unless (markerKind == Just RegularFile) (ioError (userError "GitHub cache provenance must be a physical regular file"))
    recorded <- withIO (Strict.readFile marker) >>= either (ioError . userError) pure . decodeSnapshot
    unless (recorded == snapshotFor origin) (ioError (userError "GitHub cache provenance does not match locked origin"))
    treeRoot <- absoluteIO tree
    validateManagedRoot base treeRoot
    gitRoot <- absoluteIO (tree </> ".git")
    validateManagedRoot base gitRoot
    mapM_ requireDirectory [snapshot, tree, tree </> ".git"]
    -- Inspect .git without trusting an attacker-supplied config or alternates.
    validateGitMetadata tree
    (_, (remote, (headCommit, entries))) <-
        concurrentlyIO
            (git False tree ["fsck", "--full", "--no-reflogs"])
            ( concurrentlyIO
                (git False tree ["config", "--local", "--get", "remote.origin.url"])
                ( concurrentlyIO
                    (git False tree ["rev-parse", "--verify", "HEAD^{commit}"])
                    (validateTrackedTree git tree "HEAD")
                )
            )
    unless (trimLine remote == repositoryURL (githubOriginRepository origin)) (ioError (userError "GitHub cache remote differs from locked repository"))
    unless (trimLine headCommit == commitText (githubOriginCommit origin)) (ioError (userError "GitHub cache HEAD differs from locked commit"))
    void (mapConcurrentlyIO (verifyTrackedEntry git tree) [entry | entry@(mode, _, _) <- entries, mode == "120000"])
    verifyRegularEntries git tree [entry | entry@(mode, _, _) <- entries, mode /= "120000"]
    dirty <- git False tree ["-c", "core.fileMode=true", "status", "--porcelain", "--untracked-files=all", "--ignored"]
    unless (null dirty) (ioError (userError "GitHub cache snapshot was modified"))
    strictRealPath tree

-- Selection checks reuse the fully verified tree, never clone or rehash it for
-- another selection of the same immutable snapshot.
selectVerifiedRoot :: FilePath -> FilePath -> GitHubOrigin -> IO AbsolutePath
selectVerifiedRoot base physicalTree origin = do
    root <- absoluteIO (base </> relativeText (githubSource origin))
    validateManagedRoot base root
    requireDirectory (absoluteText root)
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

-- Bound argv growth and process startup cost. Check all physical file metadata
-- before hashing, with distinct bounded stages rather than nested worker pools.
-- Git emits one blob hash per argv path, in the same order as the input batch.
verifyRegularEntries :: GitRunner -> FilePath -> [(String, String, FilePath)] -> IO ()
verifyRegularEntries git tree entries = do
    void (mapConcurrentlyIO (verifyTrackedEntry git tree) entries)
    void (mapConcurrentlyIO verifyBatch (batches entries))
  where
    batches [] = []
    batches remaining = let (batch, rest) = splitAt 32 remaining in batch : batches rest
    verifyBatch batch = do
        let paths = [path | (_, _, path) <- batch]
            expected = [objectId | (_, objectId, _) <- batch]
        output <- git False tree (["hash-object", "--no-filters", "--"] ++ paths)
        let actual = map trimLine (lines output)
        unless (length actual == length expected) (ioError (userError "GitHub cache hash output count differs from tracked file batch"))
        unless (and (zipWith (==) actual expected)) (ioError (userError "GitHub tracked file differs from pinned commit"))

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
    inspect [metadata]
    config <- withIO $ withFile (metadata </> "config") ReadMode $ \handle -> do
        content <- hGetContents handle
        _ <- evaluate (length content)
        pure content
    let permitted line = null line || line `elem` ["[core]", "[remote \"origin\"]"] || any (`isPrefixOf` line) ["repositoryformatversion = ", "filemode = ", "bare = ", "logallrefupdates = ", "ignorecase = ", "precomposeunicode = ", "url = https://github.com/", "fetch = +refs/heads/*:refs/remotes/origin/*"]
    unless (all (permitted . dropWhile (`elem` [' ', '\t'])) (lines config)) (ioError (userError "GitHub cache contains unexpected Git configuration"))
    mapM_ rejectPresent [metadata </> "objects/info/alternates", metadata </> "info/grafts", metadata </> "commondir"]
  where
    -- Each frontier has separate bounded directory-read and metadata stages.
    -- Never keep a leaf permit while waiting for descendant traversal.
    inspect [] = pure ()
    inspect directories = do
        paths <- concat <$> mapConcurrentlyIO directoryPaths directories
        descendants <- concat <$> mapConcurrentlyIO inspectEntry paths
        inspect descendants
    directoryPaths directory = map (directory </>) <$> withIO (listDirectory directory)
    inspectEntry path = do
        kind <- withIO (pathKind path)
        case kind of
            Just PhysicalDirectory -> pure [path]
            Just RegularFile -> pure []
            _ -> ioError (userError "GitHub cache metadata contains a redirected or special entry")
    rejectPresent path = do
        kind <- pathKind path
        unless (isNothing kind) (ioError (userError "GitHub cache metadata redirects object resolution"))

trimLine :: String -> String
trimLine = reverse . dropWhile (`elem` ['\n', '\r']) . reverse
