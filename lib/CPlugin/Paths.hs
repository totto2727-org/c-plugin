module CPlugin.Paths (
    RuntimePaths (..),
    runtimePaths,
    discoverLocks,
    within,
    pathKind,
    PathKind (..),
    validateManagedRoot,
    ensureManagedRoot,
    containedEntry,
    matchingEntry,
    strictRealPath,
    absoluteIO,
    relativeIO,
    nameIO,
    relativeLinkTarget,
) where

import CPlugin.Internal.Concurrent (concurrentlyIO, mapConcurrentlyIO, withIO)
import CPlugin.Types.Name (ItemName, itemName)
import CPlugin.Types.Ownership (OwnershipEntry (..))
import CPlugin.Types.Path
import Control.Exception (IOException, catch, evaluate)
import Control.Monad (unless)
import Data.Char (isSpace)
import Data.List (isPrefixOf, sort, sortOn, tails)
import System.Directory (canonicalizePath, createDirectoryIfMissing, getCurrentDirectory, listDirectory)
import System.Environment (getEnv)
import System.FilePath (joinPath, makeRelative, normalise, splitDirectories, takeDirectory, takeFileName, (</>))
import System.IO.Error (isDoesNotExistError)
import System.Posix.Files (getFileStatus, getSymbolicLinkStatus, isDirectory, isRegularFile, isSymbolicLink, readSymbolicLink)

absoluteIO :: FilePath -> IO AbsolutePath
absoluteIO = either (ioError . userError) pure . absolutePath
relativeIO :: FilePath -> IO RelativePath
relativeIO = either (ioError . userError) pure . relativePath
nameIO :: String -> IO ItemName
nameIO = either (ioError . userError) pure . itemName

data RuntimePaths = RuntimePaths {homePath :: AbsolutePath, cwdPath :: AbsolutePath} deriving (Eq, Show)
runtimePaths :: IO RuntimePaths
runtimePaths = RuntimePaths <$> (getEnv "HOME" >>= absoluteIO) <*> (getCurrentDirectory >>= absoluteIO)

data PathKind = PhysicalDirectory | RegularFile | SymbolicLink | SpecialFile deriving (Eq, Show)
pathKind :: FilePath -> IO (Maybe PathKind)
pathKind p =
    ( do
        status <- getSymbolicLinkStatus p
        pure
            ( Just
                ( if isSymbolicLink status
                    then SymbolicLink
                    else
                        if isDirectory status
                            then PhysicalDirectory
                            else
                                if isRegularFile status then RegularFile else SpecialFile
                )
            )
    )
        `catch` \e ->
            if isDoesNotExistError e then pure Nothing else ioError (e :: IOException)

-- directory.canonicalizePath tolerates nonexistent suffixes. Ownership checks
-- need realpath semantics: broken symlinks and vanished targets are failures.
strictRealPath :: FilePath -> IO FilePath
strictRealPath p = getFileStatus p >> canonicalizePath p

within :: FilePath -> FilePath -> Bool
within base path = let b = splitDirectories (normalise base); p = splitDirectories (normalise path) in b `isPrefixOf` p

validateManagedRoot :: FilePath -> AbsolutePath -> IO ()
validateManagedRoot base root = do
    let p = absoluteText root
    unless (within base p) (ioError (userError "managed root must remain below lock root"))
    physicalBase <- strictRealPath base
    let parts = splitDirectories (makeRelative base p)
        ancestors = scanl (</>) base (filter (/= ".") parts)
    mapM_ (checkAncestor physicalBase) ancestors
  where
    checkAncestor physicalBase p = do
        kind <- pathKind p
        case kind of
            Nothing -> pure ()
            Just PhysicalDirectory -> do
                physical <- strictRealPath p
                unless (within physicalBase physical) (ioError (userError "managed root resolves outside lock root"))
            _ -> ioError (userError ("managed root ancestors must be physical directories: " ++ p))

ensureManagedRoot :: FilePath -> AbsolutePath -> IO ()
ensureManagedRoot base root = do
    validateManagedRoot base root
    createDirectoryIfMissing True (absoluteText root)
    validateManagedRoot base root

containedEntry :: FilePath -> OwnershipEntry -> IO Bool
containedEntry base e = do
    validateManagedRoot base (managedRoot e)
    kind <- pathKind (absoluteText (managedRoot e))
    case kind of
        Just PhysicalDirectory -> do
            root <- strictRealPath (absoluteText (managedRoot e))
            parent <- strictRealPath (takeDirectory (absoluteText (entryLink e)))
            pure (root == parent)
        _ -> pure False

matchingEntry :: FilePath -> OwnershipEntry -> IO Bool
matchingEntry base e = do
    contained <- containedEntry base e
    kind <- pathKind (absoluteText (entryLink e))
    if not contained || kind /= Just SymbolicLink
        then pure False
        else do
            literal <- readSymbolicLink (absoluteText (entryLink e))
            physical <- strictRealPath (absoluteText (entryLink e))
            pure (literal == symlinkTarget e && physical == absoluteText (resolvedTarget e))

-- makeRelative only removes a common prefix, whereas symlinks require '..'.
relativeLinkTarget :: FilePath -> FilePath -> FilePath
relativeLinkTarget base target = joinPath (replicate (length remainingBase) ".." ++ remainingTarget)
  where
    (remainingBase, remainingTarget) = strip (splitDirectories base) (splitDirectories target)
    strip (x : xs) (y : ys) | x == y = strip xs ys
    strip xs ys = (xs, ys)

discoverLocks :: RuntimePaths -> Bool -> Bool -> IO [FilePath]
discoverLocks paths global recursive
    | global && recursive = ioError (userError "totto2727/c-plugin.SyncError.Planning --global cannot be combined with --recursive")
    | global = do
        let p = absoluteText (homePath paths) </> "c-plugin-lock.json"
        requireLock p
        pure [p]
    | otherwise = do
        let home = absoluteText (homePath paths)
            cwd = absoluteText (cwdPath paths)
        unless (within home cwd) (notFound home)
        nearest <- findParent home cwd
        if recursive then sortOn (splitDirectories . takeDirectory) <$> walk [(takeDirectory nearest, [])] else pure [nearest]
  where
    notFound p = ioError (userError ("totto2727/c-plugin.LockDiscoveryError.LockFileNotFound " ++ p))
    requireLock p = do
        kind <- pathKind p
        unless (kind == Just RegularFile) (notFound p)
    findParent home dir = do
        let p = dir </> "c-plugin-lock.json"
        kind <- pathKind p
        if kind == Just RegularFile
            then pure p
            else
                if dir == home || takeDirectory dir == dir then notFound home else findParent home (takeDirectory dir)
    -- Traverse one frontier at a time instead of nesting worker pools at every
    -- directory. Sort by path components afterward to retain root-first DFS
    -- reporting, including names whose punctuation changes string-sort order.
    walk [] = pure []
    walk frontier = do
        inspected <- mapConcurrentlyIO inspect frontier
        descendants <- walk (concatMap snd inspected)
        pure (concatMap fst inspected ++ descendants)
    inspect (dir, inherited) = do
        localRules <- readIgnore dir
        let rules = inherited ++ [(dir, rule) | rule <- localRules]
            localLock = dir </> "c-plugin-lock.json"
        (localKind, names) <- concurrentlyIO (pathKind localLock) (sort <$> withIO (listDirectory dir))
        descendants <-
            concat
                <$> mapConcurrentlyIO
                    ( \name -> do
                        let p = dir </> name
                        kind <- pathKind p
                        if kind == Just PhysicalDirectory && name /= ".git" && not (sourceCache p) && not (ignored rules p)
                            then pure [(p, rules)]
                            else pure []
                    )
                    names
        pure ([localLock | localKind == Just RegularFile], descendants)
    -- Snapshots are implementation-owned inputs, not projects. A cloned
    -- repository's own lock must never enter recursive lock discovery.
    sourceCache p = takeFileName p == "sources" && takeFileName (takeDirectory p) == "c-plugin" && takeFileName (takeDirectory (takeDirectory p)) == ".agents"
    readIgnore dir =
        withIO
            ( do
                content <- readFile (dir </> ".gitignore")
                _ <- evaluate (length content)
                pure (parseIgnore (lines content))
            )
            `catch` ignoreReadFailure
    ignoreReadFailure :: IOException -> IO [String]
    ignoreReadFailure _ = pure []

-- Match the historical admiral 0.6.2 traversal-only rules. These are directory
-- patterns, not full gitignore semantics: no negation, anchoring, ?, or escapes.
parseIgnore :: [String] -> [String]
parseIgnore = map stripSlashes . filter accepted . map trim
  where
    trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace
    accepted line = not (null line) && head line `notElem` ['#', '!']
    stripSlashes = reverse . dropWhile (== '/') . reverse . dropWhile (== '/')

ignored :: [(FilePath, String)] -> FilePath -> Bool
ignored rules path = any (\(base, patternText) -> matchesPath (makeRelative base path) patternText) rules

matchesPath :: FilePath -> String -> Bool
matchesPath relative patternText = case pathSegments patternText of
    [] -> False
    [segment] -> any (globSegment segment) segments
    patterns -> any (\suffix -> length suffix >= length patterns && and (zipWith globSegment patterns suffix)) (tails segments)
  where
    segments = pathSegments relative

pathSegments :: String -> [String]
pathSegments [] = []
pathSegments value = case break (== '/') value of
    ("", _ : rest) -> pathSegments rest
    (part, []) -> [part]
    (part, _ : rest) -> part : pathSegments rest

globSegment :: String -> String -> Bool
globSegment patternText text = match patternText text Nothing
  where
    match patterns [] _ = all (== '*') patterns
    match (patternChar : patterns) remaining@(textChar : rest) previousStar
        | patternChar == textChar = match patterns rest previousStar
        | patternChar == '*' = match patterns remaining (Just (patterns, remaining))
    match _ _ (Just (afterStar, _ : retry)) = match afterStar retry (Just (afterStar, retry))
    match _ _ _ = False
