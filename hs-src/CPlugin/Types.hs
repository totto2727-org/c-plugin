module CPlugin.Types (
    RelativePath,
    relativePath,
    relativeText,
    AbsolutePath,
    absolutePath,
    absoluteText,
    ItemName,
    itemName,
    pluginNameValue,
    skillNameValue,
    nameText,
    Plugin (..),
    Lock (..),
    emptyLock,
    makeLock,
    makePlugin,
    OwnershipSource (..),
    OwnershipEntry (..),
    OwnershipState (..),
    makeOwnership,
    makeEntry,
    PluginManifest (..),
    ResolvedSkill (..),
    PreviousOwnership (..),
    Notice (..),
    SyncResult (..),
    SyncCompletion (..),
    uniqueSet,
    uniqueMap,
) where

import Data.Char (isAlphaNum, isAscii, isAsciiUpper, isControl, isLower, isNumber)
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.FilePath (dropTrailingPathSeparator, isAbsolute, normalise, splitDirectories, takeDirectory, takeFileName)

newtype RelativePath = RelativePath FilePath deriving (Eq, Ord, Show)
newtype AbsolutePath = AbsolutePath FilePath deriving (Eq, Ord, Show)
newtype ItemName = ItemName String deriving (Eq, Ord, Show)
relativeText :: RelativePath -> FilePath
relativeText (RelativePath p) = p
absoluteText :: AbsolutePath -> FilePath
absoluteText (AbsolutePath p) = p
nameText :: ItemName -> String
nameText (ItemName n) = n

relativePath :: FilePath -> Either String RelativePath
relativePath p
    | null p || isAbsolute p || '\\' `elem` p || '\0' `elem` p = Left "path must be relative"
    | ".." `elem` splitDirectories p = Left "path must not traverse parent directories"
    | otherwise = Right (RelativePath (dropTrailingPathSeparator (normalise p)))
absolutePath :: FilePath -> Either String AbsolutePath
absolutePath p
    | not (isAbsolute p) || '\0' `elem` p || ".." `elem` splitDirectories p = Left "path must be absolute without parent traversal"
    | otherwise = Right (AbsolutePath (dropTrailingPathSeparator (normalise p)))
itemName :: String -> Either String ItemName
itemName n
    | null n || n == "." || n == ".." || any (\c -> c `elem` "/\\" || isControl c) n = Left "item must be a non-path name"
    | otherwise = Right (ItemName n)
pluginNameValue :: String -> Either String ItemName
pluginNameValue n
    | null n
        || length n > 64
        || not (alnum (head n))
        || not (alnum (last n))
        || not (all (\c -> alnum c || c `elem` ".-") n)
        || "--" `isInfixOf` n
        || ".." `isInfixOf` n =
        Left "invalid standard plugin name"
    | otherwise = itemName n
  where
    alnum c = isAscii c && isAlphaNum c && not (isAsciiUpper c)

skillNameValue :: String -> Either String ItemName
skillNameValue n
    | null n
        || length n > 64
        || head n == '-'
        || last n == '-'
        || "--" `isInfixOf` n
        || not (all (\c -> c == '-' || isLower c || isNumber c) n) =
        Left "invalid Agent Skills name"
    | otherwise = itemName n

data Plugin = Plugin
    {pluginName :: ItemName, pluginSource :: RelativePath, enabledSkills :: Set.Set ItemName}
    deriving (Eq, Show)
data Lock = Lock
    {targets :: Set.Set RelativePath, plugins :: Map.Map ItemName Plugin}
    deriving (Eq, Show)
emptyLock :: Lock
emptyLock = Lock Set.empty Map.empty
uniqueSet :: (Ord a) => String -> [a] -> Either String (Set.Set a)
uniqueSet label xs =
    let result = Set.fromList xs
     in if Set.size result == length xs then Right result else Left (label ++ " must be unique")
uniqueMap :: (Ord k) => String -> (a -> k) -> [a] -> Either String (Map.Map k a)
uniqueMap label key xs =
    let result = Map.fromList [(key x, x) | x <- xs]
     in if Map.size result == length xs then Right result else Left (label ++ " must be unique")
makeLock :: [RelativePath] -> [Plugin] -> Either String Lock
makeLock ts ps = do
    mapM_ (\p -> makePlugin (pluginName p) (pluginSource p) (Set.toAscList (enabledSkills p))) ps
    ts' <- uniqueSet "lock targets" ts
    ps' <- uniqueMap "plugin names" pluginName ps
    _ <- uniqueSet "plugin sources" (map pluginSource ps)
    pure (Lock ts' ps')
makePlugin :: ItemName -> RelativePath -> [ItemName] -> Either String Plugin
makePlugin n p ss = do
    _ <- pluginNameValue (nameText n)
    mapM_ (skillNameValue . nameText) ss
    Plugin n p <$> uniqueSet "enabled skills" ss

data OwnershipSource = OwnershipSource
    {sourcePath :: RelativePath, sourcePlugin :: ItemName, sourceSkill :: ItemName}
    deriving (Eq, Ord, Show)
data OwnershipEntry = OwnershipEntry
    { entryLink :: AbsolutePath
    , symlinkTarget :: FilePath
    , resolvedTarget :: AbsolutePath
    , managedRoot :: AbsolutePath
    , entrySource :: OwnershipSource
    }
    deriving (Eq, Ord, Show)
newtype OwnershipState = OwnershipState {ownershipEntries :: Map.Map AbsolutePath OwnershipEntry}
    deriving (Eq, Show)
makeEntry :: AbsolutePath -> FilePath -> AbsolutePath -> AbsolutePath -> OwnershipSource -> Either String OwnershipEntry
makeEntry link literal resolved root source = do
    _ <- pluginNameValue (nameText (sourcePlugin source))
    _ <- skillNameValue (nameText (sourceSkill source))
    if takeDirectory (absoluteText link) /= absoluteText root
        then Left "ownership link must be a direct child of managed root"
        else
            if takeFileName (absoluteText link) /= nameText (sourceSkill source)
                then Left "ownership link name must match its source skill"
                else
                    if null literal || '\0' `elem` literal
                        then Left "ownership symlink target must be nonempty without NUL"
                        else Right (OwnershipEntry link literal resolved root source)
makeOwnership :: [OwnershipEntry] -> Either String OwnershipState
makeOwnership es = OwnershipState <$> uniqueMap "ownership links" entryLink es

data PluginManifest = PluginManifest {manifestName :: ItemName, manifestWarnings :: [String]} deriving (Eq, Show)
data ResolvedSkill = ResolvedSkill {resolvedSkillName :: ItemName, skillPath :: AbsolutePath} deriving (Eq, Show)
data PreviousOwnership = Trusted OwnershipState | Missing | Corrupt String deriving (Eq, Show)
data Notice
    = PreviousMissing
    | PreviousCorrupt String
    | UnmanagedPreserved AbsolutePath
    | ReplacedPreserved AbsolutePath
    | BrokenPreserved AbsolutePath
    | OperationFailed FilePath String
    | CheckpointFailed FilePath String
    | PluginWarning FilePath String
    deriving (Eq, Show)
data SyncCompletion = Finished | Interrupted deriving (Eq, Show)
data SyncResult = SyncResult
    {syncNotices :: [Notice], unavailablePlugins :: Map.Map ItemName String, syncCompletion :: SyncCompletion}
    deriving (Eq, Show)
