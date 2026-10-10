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

import CPlugin.Types
import Control.Exception (IOException, catch)
import Control.Monad (forM, unless)
import Data.List (isPrefixOf, sort)
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
        if recursive then sort <$> walk (takeDirectory nearest) [] else pure [nearest]
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
    walk dir inherited = do
        localRules <- readIgnore dir
        let rules = inherited ++ [(dir, rule) | rule <- localRules]
        names <- sort <$> listDirectory dir
        fmap concat $ forM names $ \name -> do
            let p = dir </> name
            kind <- pathKind p
            if name == ".git" || ignored rules p (kind == Just PhysicalDirectory)
                then pure []
                else case kind of
                    Just PhysicalDirectory -> walk p rules
                    Just RegularFile | name == "c-plugin-lock.json" -> pure [p]
                    _ -> pure []
    readIgnore dir =
        (lines <$> readFile (dir </> ".gitignore")) `catch` \e ->
            if isDoesNotExistError e then pure [] else ioError (e :: IOException)

-- Gitignore rules are scoped to their declaring directory and later rules win.
-- Do not follow symlink directories during recursive lock discovery.
ignored :: [(FilePath, String)] -> FilePath -> Bool -> Bool
ignored rules p isDir = foldl apply False rules
  where
    apply old (_, "") = old
    apply old (_, '#' : _) = old
    apply old (base, raw) =
        let negateRule = head raw == '!'
            rule = if negateRule then tail raw else raw
            dirOnly = not (null rule) && last rule == '/'
            stripped = if dirOnly then init rule else rule
            anchored = not (null stripped) && head stripped == '/'
            patternText = if anchored then tail stripped else stripped
            relative = makeRelative base p
            candidate = if anchored || '/' `elem` patternText then relative else takeFileName relative
         in if (not dirOnly || isDir) && glob patternText candidate then not negateRule else old

glob :: String -> String -> Bool
glob [] s = null s
glob ('*' : '*' : ps) s = glob ps s || (not (null s) && glob ('*' : '*' : ps) (tail s))
glob ('*' : ps) s = glob ps s || (not (null s) && head s /= '/' && glob ('*' : ps) (tail s))
glob ('?' : ps) (_ : s) = glob ps s
glob ('\\' : p : ps) (c : s) = p == c && glob ps s
glob (p : ps) (c : s) = p == c && glob ps s
glob _ _ = False
