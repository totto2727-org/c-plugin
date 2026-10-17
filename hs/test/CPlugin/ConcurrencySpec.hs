{-# LANGUAGE OverloadedStrings #-}

-- Real local Git repositories back these public command tests. Only the fixed
-- HTTPS transport is mapped to fixtures, so this is not GitHub acceptance coverage.
module CPlugin.ConcurrencySpec (spec) where

import CPlugin.Commands (Command (..), runCommandWithGit)
import CPlugin.GitHubTestSupport (gitCommand, gitCommit, writeRemotePlugin)
import CPlugin.Interaction (Interaction (NonInteractive))
import CPlugin.Paths (PathKind (PhysicalDirectory, RegularFile, SymbolicLink), nameIO, pathKind, relativeIO, relativeLinkTarget, within)
import CPlugin.Reconcile (planSyncWithGit, syncPlannedLock)
import CPlugin.Source.GitHub (GitRunner, runGit, verifyGitHubSourcesWith)
import CPlugin.StateStore (readLock, writeLock)
import CPlugin.TestSupport (fixturePlugin, inEnvironment, skillBytes, withFixture, writeFixture)
import CPlugin.Types.GitHub (GitHubOrigin (..), commitText, githubSource, githubSubpath)
import CPlugin.Types.InstalledSkill (InstalledSkill (..))
import CPlugin.Types.Lock (Lock (..), emptyLock, makeLock, makeLockWithSkills)
import CPlugin.Types.Name (nameText)
import CPlugin.Types.Path (absoluteText, relativeText)
import CPlugin.Types.Plugin (Plugin (..), makePluginWithOrigin)
import CPlugin.Types.Selection (SelectionRequest (SelectItems))
import CPlugin.Types.Sync (SyncCompletion (Finished), syncCompletion, unavailablePlugins)
import Control.Concurrent (MVar, modifyMVar, newEmptyMVar, newMVar, putMVar, readMVar, throwTo, tryPutMVar)
import Control.Concurrent.Async (asyncThreadId, cancel, mapConcurrently, wait, waitCatch, withAsync)
import Control.Exception (AsyncException (UserInterrupt), IOException, SomeException, bracket, finally, fromException, mask)
import Control.Monad (foldM, forM, forM_, replicateM, void, when)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Either (isLeft)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf, sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes)
import qualified Data.Set as Set
import System.Directory (createDirectoryIfMissing, listDirectory, removeFile, withCurrentDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO (BufferMode (LineBuffering), Handle, hClose, hGetLine, hSetBuffering)
import System.Posix.Files (createNamedPipe, readSymbolicLink, setFileMode)
import System.Posix.IO (OpenMode (ReadWrite), defaultFileFlags, fdToHandle, openFd)
import System.Timeout (timeout)
import Test.Hspec (Spec, describe, it, shouldBe, shouldReturn, shouldSatisfy)

spec :: Spec
spec = describe "bounded independent IO through public sync and update APIs" $ do
    it "bounds real runGit processes at eight and returns all slots after cancellation" $ withFixture [] $ \base _ -> inEnvironment base $
        withFakeGit base [1 .. 40 :: Int] $ \events release -> do
            let jobs = [1 .. 24 :: Int]
                run index = runGit False base ["fixture-worker", show index]
                started = readProcessEvent events "start"
                ended index = readProcessEvent events "end" `shouldReturn` index
            withAsync (mapConcurrently run jobs) $ \worker -> do
                initial <- replicateM 8 started
                Set.size (Set.fromList initial) `shouldBe` 8
                -- All eight processes remain blocked until their own FIFO is
                -- released. A ninth start before an end is a bound violation.
                release (head initial)
                lastStarted <-
                    foldM
                        ( \previous _ -> do
                            ended previous
                            next <- started
                            release next
                            pure next
                        )
                        (head initial)
                        [9 .. 24 :: Int]
                ended lastStarted
                mapM_ release (tail initial)
                remaining <- replicateM 7 (readProcessEvent events "end")
                sort remaining `shouldBe` sort (tail initial)
                watchdog "bounded real process wave completion" (wait worker) `shouldReturn` ["ok " ++ show index ++ "\n" | index <- jobs]
            -- Cancellation must wait for subprocess cleanup before the shared
            -- leaf slots become available to a complete new eight-process wave.
            withAsync (mapConcurrently run [25 .. 32 :: Int]) $ \worker -> do
                cancelled <- replicateM 8 started
                sort cancelled `shouldBe` sort (map show [25 .. 32 :: Int])
                watchdog "blocked subprocess cancellation" (cancel worker)
            withAsync (mapConcurrently run [33 .. 40 :: Int]) $ \worker -> do
                recovered <- replicateM 8 started
                sort recovered `shouldBe` sort (map show [33 .. 40 :: Int])
                mapM_ release recovered
                completed <- replicateM 8 (readProcessEvent events "end")
                sort completed `shouldBe` sort recovered
                watchdog "recovered process slot completion" (wait worker) `shouldReturn` ["ok " ++ show index ++ "\n" | index <- [33 .. 40 :: Int]]

    it "overlaps independent repository refreshes before mutating the candidate" $ withRemotes $ \base remotes -> do
        registerPlugins remotes
        expected <- mapM advanceRemote remotes
        before <- snapshot base
        gates <- mapM (const newGate) remotes
        let runner = gateFetches (zip (map remoteURL remotes) gates) (transport remotes)
        withAsync (command runner (Update False False)) $ \worker -> do
            mapM_ awaitArrival gates
            snapshot base `shouldReturn` before
            mapM_ releaseGate (reverse gates)
            watchdog "independent update completion" (wait worker)
        current <- readLock (lockPath base)
        pluginPins current `shouldBe` expected
        assertPluginLinks base current

    it "overlaps distinct requested refs of one repository while sharing the resulting snapshot safely" $ withRemotes $ \base remotes -> do
        let remote = head remotes
        registerPair remote "v1"
        expected <- advanceRemote remote
        _ <- gitCommand (remoteDirectory remote) ["tag", "--force", "v1"]
        mainGate <- newGate
        tagGate <- newGate
        fetches <- newIORef ([] :: [String])
        let runner network directory arguments
                | network && "fetch" `elem` arguments = do
                    let requested = last arguments
                    atomicModifyIORef' fetches (\values -> (requested : values, ()))
                    gate <- case requested of
                        "main" -> pure mainGate
                        "v1" -> pure tagGate
                        _ -> ioError (userError "unexpected requested ref")
                    throughGate gate (transport remotes network directory arguments)
                | otherwise = transport remotes network directory arguments
        withAsync (command runner (Update False False)) $ \worker -> do
            mapM_ awaitArrival [mainGate, tagGate]
            mapM_ releaseGate [tagGate, mainGate]
            watchdog "distinct ref update completion" (wait worker)
        sort <$> readIORef fetches `shouldReturn` ["main", "v1"]
        current <- readLock (lockPath base)
        allPins current `shouldBe` [expected, expected]
        assertPluginLinks base current
        pathKind (base </> ".agents/skills/standalone") `shouldReturn` Just SymbolicLink

    it "fetches the same repository and ref once across plugin and standalone subpaths" $ withRemotes $ \base remotes -> do
        let remote = head remotes
        registerPair remote "main"
        oldPluginLink <- readSymbolicLink (base </> ".agents/skills/left")
        oldSkillLink <- readSymbolicLink (base </> ".agents/skills/standalone")
        expected <- advanceRemote remote
        fetches <- newIORef (0 :: Int)
        let runner network directory arguments = do
                when (network && "fetch" `elem` arguments) $
                    atomicModifyIORef' fetches (\count -> (count + 1, ()))
                transport remotes network directory arguments
        command runner (Update False False)
        readIORef fetches `shouldReturn` 1
        current <- readLock (lockPath base)
        allPins current `shouldBe` [expected, expected]
        [relativeText (pluginSource plugin) | plugin <- Map.elems (plugins current), Just _ <- [pluginOrigin plugin]] `shouldSatisfy` all (isSuffixOf "/tree/package")
        map (relativeText . installedSkillSource) (Map.elems (standaloneSkills current)) `shouldSatisfy` all (isSuffixOf "/tree/standalone")
        readSymbolicLink (base </> ".agents/skills/left") >>= (`shouldSatisfy` (/= oldPluginLink))
        readSymbolicLink (base </> ".agents/skills/standalone") >>= (`shouldSatisfy` (/= oldSkillLink))

    it "verifies one immutable snapshot across refs and isolates a missing selected subpath" $ withRemotes $ \base remotes -> do
        registerPair (head remotes) "v1"
        current <- readLock (lockPath base)
        let origins = reverse (pinnedOrigins current)
            cache = base </> ".agents/c-plugin/sources"
        length origins `shouldBe` 2
        map githubOriginCommit origins `shouldBe` replicate 2 (githubOriginCommit (head origins))
        githubOriginRef (head origins) `shouldSatisfy` (/= githubOriginRef (last origins))
        githubOriginSubpath (head origins) `shouldSatisfy` (/= githubOriginSubpath (last origins))
        before <- cacheBytes cache
        checks <- newIORef (0 :: Int)
        let runner = countedOfflineChecks checks
        verified <- verifyGitHubSourcesWith runner base origins
        roots <- mapM (either (ioError . userError . show) pure) verified
        map absoluteText roots `shouldBe` [base </> relativeText (githubSource origin) | origin <- origins]
        readIORef checks `shouldReturn` 1
        missingSubpath <- either (ioError . userError) pure (githubSubpath "missing-selected-subpath")
        let valid = head origins
            missing = (last origins){githubOriginSubpath = missingSubpath}
        -- The missing selection is deliberately last, so grouping's first
        -- representative is not itself a usable selected directory.
        selections <- verifyGitHubSourcesWith runner base [valid, missing]
        case selections of
            [Right validRoot, Left _] -> absoluteText validRoot `shouldBe` base </> relativeText (githubSource valid)
            _ -> ioError (userError ("unexpected grouped subpath verification: " ++ show selections))
        readIORef checks `shouldReturn` 2
        cacheBytes cache `shouldReturn` before

    it "rejects every selection of a corrupt shared snapshot without changing existing cache bytes" $ withRemotes $ \base remotes -> do
        registerPair (head remotes) "v1"
        current <- readLock (lockPath base)
        let origins = pinnedOrigins current
            cache = base </> ".agents/c-plugin/sources"
            plugin = head [entry | entry <- Map.elems (plugins current), Just _ <- [pluginOrigin entry]]
        length origins `shouldBe` 2
        writeFixture (base </> relativeText (pluginSource plugin) </> "plugin.json") "corrupt cached manifest sentinel"
        before <- cacheBytes cache
        checks <- newIORef (0 :: Int)
        verified <- verifyGitHubSourcesWith (countedOfflineChecks checks) base origins
        map isLeft verified `shouldBe` [True, True]
        readIORef checks `shouldReturn` 1
        cacheBytes cache `shouldReturn` before

    it "overlaps pinned repository verification in real offline sync" $ withRemotes $ \base remotes -> do
        registerPlugins remotes
        before <- snapshot base
        gates <- mapM (const newGate) remotes
        let runner network directory arguments
                | network = ioError (userError "sync attempted network access")
                | "fsck" `elem` arguments = case findRemote remotes directory of
                    Just remote -> throughGate (gateFor remotes gates remote) (runGit False directory arguments)
                    Nothing -> ioError (userError "unexpected cached repository")
                | otherwise = runGit False directory arguments
        withAsync (command runner (Sync False False)) $ \worker -> do
            mapM_ awaitArrival gates
            snapshot base `shouldReturn` before
            mapM_ releaseGate gates
            watchdog "offline sync completion" (wait worker)
        current <- readLock (lockPath base)
        assertPluginLinks base current
        snapshot base `shouldReturn` before

    it "overlaps independent metadata Git commands for one pinned source" $ withRemotes $ \base remotes -> do
        registerPlugins [head remotes]
        gates <- mapM (const newGate) [1 .. 4 :: Int]
        let operations = ["fsck", "config", "rev-parse", "ls-tree"]
            runner network directory arguments
                | network = ioError (userError "metadata verification attempted network access")
                | otherwise = case [gate | (operation, gate) <- zip operations gates, operation `elem` arguments] of
                    gate : _ -> throughGate gate (runGit False directory arguments)
                    [] -> runGit False directory arguments
        withAsync (command runner (Sync False False)) $ \worker -> do
            mapM_ awaitArrival gates
            mapM_ releaseGate (reverse gates)
            watchdog "metadata verification completion" (wait worker)
        readLock (lockPath base) >>= assertPluginLinks base

    it "joins independent metadata check siblings when one check fails" $ withRemotes $ \base remotes -> do
        registerPlugins [head remotes]
        current <- readLock (lockPath base)
        before <- snapshot base
        gates <- mapM (const newGate) [1 .. 4 :: Int]
        let operations = ["fsck", "config", "rev-parse", "ls-tree"]
            runner network directory arguments
                | network = ioError (userError "metadata verification attempted network access")
                | otherwise = case [(operation, gate) | (operation, gate) <- zip operations gates, operation `elem` arguments] of
                    (operation, gate) : _ ->
                        throughGate gate $
                            if operation == "fsck"
                                then ioError (userError "injected metadata check failure")
                                else runGit False directory arguments
                    [] -> runGit False directory arguments
        withAsync (planSyncWithGit runner (lockPath base) current) $ \worker -> do
            mapM_ awaitArrival gates
            releaseGate (head gates)
            plan <- watchdog "failed metadata check sibling cleanup" (wait worker)
            mapM_ awaitDeparture gates
            snapshot base `shouldReturn` before
            result <- syncPlannedLock plan False
            left <- nameIO "left"
            Map.keys (unavailablePlugins result) `shouldBe` [left]
        snapshot base `shouldReturn` before

    it "keeps the lexical collision winner when independent Git checks finish out of order" $ withRemotes $ \base remotes -> do
        registerPlugins remotes
        current <- readLock (lockPath base)
        shared <- nameIO "shared"
        replacements <- forM (Map.elems (plugins current)) $ \plugin ->
            case pluginOrigin plugin of
                Nothing -> pure plugin
                Just _ ->
                    either (ioError . userError) pure $
                        makePluginWithOrigin (pluginName plugin) (pluginSource plugin) [shared] (pluginOrigin plugin)
        candidate <- either (ioError . userError) pure (makeLockWithSkills [] replacements [])
        writeLock (lockPath base) candidate
        gates <- mapM (const newGate) remotes
        let runner network directory arguments
                | network = ioError (userError "planning attempted network access")
                | "fsck" `elem` arguments = case findRemote remotes directory of
                    Just remote -> throughGate (gateFor remotes gates remote) (runGit False directory arguments)
                    Nothing -> ioError (userError "unexpected cached repository")
                | otherwise = runGit False directory arguments
        before <- snapshot base
        withAsync (planSyncWithGit runner (lockPath base) candidate) $ \worker -> do
            mapM_ awaitArrival gates
            releaseGate (last gates)
            awaitDeparture (last gates)
            snapshot base `shouldReturn` before
            releaseGate (head gates)
            plan <- watchdog "ordered planning completion" (wait worker)
            result <- syncPlannedLock plan False
            syncCompletion result `shouldBe` Finished
        winner <- nameIO "right"
        let expected = base </> relativeText (pluginSource (plugins candidate Map.! winner)) </> "skills/shared"
        literal <- readSymbolicLink (base </> ".agents/skills/shared")
        -- Exact literal identity matters, not just physical resolution.
        literal `shouldBe` relativeLinkTarget (base </> ".agents/skills") expected

    it "cancels and joins a blocked refresh sibling before returning a failed update" $ withRemotes $ \base remotes -> do
        registerPlugins remotes
        mapM_ advanceRemote remotes
        before <- snapshot base
        gates <- mapM (const newGate) remotes
        let failure = ioError (userError "injected independent refresh failure")
            runner network directory arguments
                | network && "fetch" `elem` arguments = case [index | (index, remote) <- zip [0 :: Int ..] remotes, remoteURL remote `elem` arguments] of
                    index : _ ->
                        throughGate (gates !! index) $
                            if index == 0 then failure else transport remotes network directory arguments
                    [] -> ioError (userError "unexpected fetch URL")
                | otherwise = transport remotes network directory arguments
        withAsync (command runner (Update False False)) $ \worker -> do
            mapM_ awaitArrival gates
            releaseGate (head gates)
            result <- watchdog "failed update and sibling cancellation" (waitCatch worker)
            result `shouldSatisfy` isIOException
            mapM_ awaitDeparture gates
        snapshot base `shouldReturn` before
        assertNoStaging base

    it "propagates asynchronous interruption and joins all blocked refresh workers" $ withRemotes $ \base remotes -> do
        registerPlugins remotes
        mapM_ advanceRemote remotes
        before <- snapshot base
        gates <- mapM (const newGate) remotes
        let runner = gateFetches (zip (map remoteURL remotes) gates) (transport remotes)
        withAsync (command runner (Update False False)) $ \worker -> do
            mapM_ awaitArrival gates
            throwTo (asyncThreadId worker) UserInterrupt
            result <- watchdog "interrupted update and child cleanup" (waitCatch worker)
            case result of
                Left exception -> fromException exception `shouldBe` Just UserInterrupt
                Right () -> ioError (userError "update swallowed asynchronous interruption")
            mapM_ awaitDeparture gates
        snapshot base `shouldReturn` before
        assertNoStaging base

    it "joins a successful sibling checkpoint after a terminal failure and never prepares the next nested wave" $ withRemotes $ \base remotes -> do
        let project = base </> "wave-project"
            failing = project </> "a"
            sibling = project </> "b"
            nested = sibling </> "nested"
            siblingState = sibling </> ".agents/c-plugin-state.json"
            blocker = failing </> ".agents/c-plugin-state.json.tmp"
        createDirectoryIfMissing True project
        writeLock (lockPath project) emptyLock
        forM_ [(failing, head remotes), (sibling, last remotes), (nested, head remotes)] $ \(root, remote) -> do
            createDirectoryIfMissing True root
            writeLock (lockPath root) emptyLock
            withCurrentDirectory root (registerPlugins [remote])
        siblingCheckpoint <- BS.readFile siblingState
        BS.appendFile siblingState "\n \t"
        removeFile (failing </> ".agents/skills/left")
        removeFile (sibling </> ".agents/skills/right")
        writeFixture blocker "foreign checkpoint sibling must remain untouched"
        nestedBefore <- snapshot nested
        laterChecks <- newIORef (0 :: Int)
        gates <- mapM (const newGate) remotes
        let runner network directory arguments
                | within nested directory = do
                    atomicModifyIORef' laterChecks (\count -> (count + 1, ()))
                    ioError (userError "a later nested wave reached source verification")
                | network = ioError (userError "recursive sync attempted network access")
                | "fsck" `elem` arguments =
                    let gate = if within failing directory then head gates else last gates
                     in throughGate gate (runGit False directory arguments)
                | otherwise = runGit False directory arguments
        withCurrentDirectory project $
            withAsync (command runner (Sync False True)) $ \worker -> do
                mapM_ awaitArrival gates
                pathKind (project </> ".agents/c-plugin-state.json") `shouldReturn` Just RegularFile
                mapM_ releaseGate gates
                result <- watchdog "current wave checkpoint completion and terminal failure" (waitCatch worker)
                result `shouldSatisfy` isIOException
        readIORef laterChecks `shouldReturn` 0
        snapshot nested `shouldReturn` nestedBefore
        BS.readFile blocker `shouldReturn` "foreign checkpoint sibling must remain untouched"
        pathKind (failing </> ".agents/skills/left") `shouldReturn` Nothing
        readLock (lockPath sibling) >>= assertPluginLinks sibling
        -- Canonical bytes prove that the successful sibling actually completed
        -- its durable checkpoint, not merely that it created a link.
        BS.readFile siblingState `shouldReturn` siblingCheckpoint

    forM_ [Sync False True, Update False True] $ \operation ->
        it ("plans a descendant only after its ancestor repoints the descendant source for " ++ show operation) $ withFixture [] $ \base _ -> inEnvironment base $ do
            let child = base </> "child"
                noGit _ _ _ = ioError (userError "local recursive operation unexpectedly invoked Git")
                prepareSource version = do
                    let repository = child </> ("content-" ++ version)
                        nested = repository </> "package/skills/foo"
                    writeRemotePlugin repository "outer" ["foo"]
                    writeFixture (nested </> "plugin.json") (BSC.pack "{\"$schema\":\"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json\",\"name\":\"nested\"}")
                    writeFixture (nested </> "skills/inner/SKILL.md") (skillBytes "inner")
                    writeFixture (nested </> "skills/inner/revision.txt") (BSC.pack version)
                    fixturePlugin "outer" ("child/content-" ++ version ++ "/package") ["foo"]
            previous <- prepareSource "old"
            next <- prepareSource "new"
            target <- relativeIO "child/source"
            previousLock <- either (ioError . userError) pure (makeLock [target] [previous])
            nextLock <- either (ioError . userError) pure (makeLock [target] [next])
            writeLock (lockPath base) previousLock
            command noGit (Sync False False)
            nested <- fixturePlugin "nested" "source/foo" ["inner"]
            childLock <- either (ioError . userError) pure (makeLock [] [nested])
            writeLock (lockPath child) childLock
            withCurrentDirectory child (command noGit (Sync False False))
            let childLink = child </> ".agents/skills/inner"
            readSymbolicLink childLink `shouldReturn` "../../content-old/package/skills/foo/skills/inner"
            BS.readFile (childLink </> "revision.txt") `shouldReturn` "old"
            childLockBytes <- BS.readFile (lockPath child)
            writeLock (lockPath base) nextLock
            command noGit operation
            readSymbolicLink (child </> "source/foo") `shouldReturn` "../content-new/package/skills/foo"
            readSymbolicLink childLink `shouldReturn` "../../content-new/package/skills/foo/skills/inner"
            BS.readFile (childLink </> "revision.txt") `shouldReturn` "new"
            BS.readFile (lockPath child) `shouldReturn` childLockBytes

    forM_ [Sync False True, Update False True] $ \operation ->
        it ("overlaps recursive sibling lock preparation for " ++ show operation) $ withRemotes $ \base remotes -> do
            let project = base </> "project"
                roots = [project </> "left-project", project </> "right-project"]
            createDirectoryIfMissing True project
            writeLock (lockPath project) emptyLock
            forM_ (zip roots remotes) $ \(root, remote) -> do
                createDirectoryIfMissing True root
                writeLock (lockPath root) emptyLock
                withCurrentDirectory root (registerPlugins [remote])
            expected <-
                if operation == Update False True
                    then mapM advanceRemote remotes
                    else mapM (fmap (head . pluginPins) . readLock . lockPath) roots
            before <- mapM snapshot roots
            gates <- mapM (const newGate) remotes
            let runner network directory arguments
                    | operation == Update False True && network && "fetch" `elem` arguments =
                        gateFetches (zip (map remoteURL remotes) gates) (transport remotes) network directory arguments
                    | operation == Sync False True && "fsck" `elem` arguments = case findRemote remotes directory of
                        Just remote -> throughGate (gateFor remotes gates remote) (runGit False directory arguments)
                        Nothing -> ioError (userError "unexpected recursive source")
                    | operation == Sync False True && network = ioError (userError "recursive sync attempted network access")
                    | otherwise = transport remotes network directory arguments
            withCurrentDirectory project $
                withAsync (command runner operation) $ \worker -> do
                    mapM_ awaitArrival gates
                    pathKind (project </> ".agents/c-plugin-state.json") `shouldReturn` Just RegularFile
                    mapM snapshot roots `shouldReturn` before
                    mapM_ releaseGate gates
                    watchdog "recursive preparation completion" (wait worker)
            forM_ (zip roots expected) $ \(root, pin) -> do
                current <- readLock (lockPath root)
                pluginPins current `shouldBe` [pin]
                assertPluginLinks root current

-- HOME and CWD are changed only once outside the concurrent product operation.
-- Worker runners never change process-global environment or current directory.
data Remote = Remote
    { remoteName :: String
    , remoteDirectory :: FilePath
    }
    deriving (Eq, Show)

withRemotes :: (FilePath -> [Remote] -> IO a) -> IO a
withRemotes action = withFixture ["existing"] $ \base _ -> inEnvironment base $ do
    remotes <- forM ["left", "right"] $ \name -> do
        let remote = Remote name (base </> "fixture-remotes" </> name)
            repository = remoteDirectory remote
        createDirectoryIfMissing True repository
        _ <- gitCommand repository ["init", "--initial-branch=main"]
        writeRemotePlugin repository name [name, "shared"]
        writeFixture (repository </> "standalone/SKILL.md") (skillBytes "standalone")
        _ <- gitCommit repository "initial isolated concurrency fixture"
        _ <- gitCommand repository ["tag", "v1"]
        pure remote
    action base remotes

remoteSlug :: Remote -> String
remoteSlug remote = "concurrency-fixture/" ++ remoteName remote

remoteURL :: Remote -> String
remoteURL remote = "https://github.com/" ++ remoteSlug remote ++ ".git"

transport :: [Remote] -> GitRunner
transport remotes network directory arguments
    | not network = runGit False directory arguments
    | otherwise = case [remote | remote <- remotes, remoteURL remote `elem` arguments] of
        [remote]
            | "ls-remote" `elem` arguments && "--get-url" `elem` arguments -> runGit False directory arguments
            | "fetch" `elem` arguments ->
                runGit False directory (["-c", "protocol.file.allow=always"] ++ map (replaceURL remote) arguments)
        _ -> ioError (userError "fixture transport refused unexpected network operation")
  where
    replaceURL remote argument
        | argument == remoteURL remote = remoteDirectory remote
        | otherwise = argument

command :: GitRunner -> Command -> IO ()
command runner = runCommandWithGit runner NonInteractive

registerPlugins :: [Remote] -> IO ()
registerPlugins remotes = forM_ remotes $ \remote ->
    command (transport remotes) (PluginAddGitHub False (remoteSlug remote) (Just "main") (Just "package") (SelectItems [remoteName remote]) False)

registerPair :: Remote -> String -> IO ()
registerPair remote requested = do
    registerPlugins [remote]
    command (transport [remote]) (SkillAddGitHub False (remoteSlug remote) (Just requested) (Just "standalone") False)

advanceRemote :: Remote -> IO String
advanceRemote remote = do
    writeFixture (remoteDirectory remote </> "revision.txt") "a new pinned concurrency fixture revision"
    gitCommit (remoteDirectory remote) "advance isolated concurrency fixture"

pluginPins :: Lock -> [String]
pluginPins lock = [commitText (githubOriginCommit origin) | plugin <- Map.elems (plugins lock), Just origin <- [pluginOrigin plugin]]

allPins :: Lock -> [String]
allPins lock = pluginPins lock ++ [commitText (githubOriginCommit origin) | skill <- Map.elems (standaloneSkills lock), Just origin <- [installedSkillOrigin skill]]

pinnedOrigins :: Lock -> [GitHubOrigin]
pinnedOrigins lock = catMaybes (map pluginOrigin (Map.elems (plugins lock)) ++ map installedSkillOrigin (Map.elems (standaloneSkills lock)))

countedOfflineChecks :: IORef Int -> GitRunner
countedOfflineChecks checks network directory arguments
    | network = ioError (userError "pinned verification attempted network access")
    | otherwise = do
        when ("fsck" `elem` arguments) $ atomicModifyIORef' checks (\count -> (count + 1, ()))
        runGit False directory arguments

-- Include the entire existing cache, including provenance, Git metadata and
-- tracked content, so verification cannot silently repair one selected source.
cacheBytes :: FilePath -> IO [(FilePath, BS.ByteString)]
cacheBytes root = walk ""
  where
    walk relative = do
        names <- sort <$> listDirectory (root </> relative)
        concat
            <$> forM
                names
                ( \name -> do
                    let child = relative </> name
                        path = root </> child
                    kind <- pathKind path
                    case kind of
                        Just PhysicalDirectory -> walk child
                        Just RegularFile -> do
                            bytes <- BS.readFile path
                            pure [(child, bytes)]
                        Just SymbolicLink -> do
                            literal <- readSymbolicLink path
                            pure [(child, BSC.pack literal)]
                        _ -> ioError (userError "unexpected cache fixture entry")
                )

lockPath :: FilePath -> FilePath
lockPath base = base </> "c-plugin-lock.json"

assertPluginLinks :: FilePath -> Lock -> IO ()
assertPluginLinks base lock = forM_ (Map.elems (plugins lock)) $ \plugin ->
    forM_ (Set.toAscList (enabledSkills plugin)) $ \skill -> do
        let root = base </> ".agents/skills"
            link = root </> showName skill
            source = base </> relativeText (pluginSource plugin) </> "skills" </> showName skill
            literal = relativeLinkTarget root source
        pathKind link `shouldReturn` Just SymbolicLink
        readSymbolicLink link `shouldReturn` literal
  where
    showName = nameText

-- Preserve exact desired-state bytes, checkpoint bytes, and literal link targets.
-- Cache population is allowed during preparation and is deliberately separate.
snapshot :: FilePath -> IO (BS.ByteString, BS.ByteString, [(FilePath, Maybe String)])
snapshot base = do
    desired <- BS.readFile (lockPath base)
    ownership <- BS.readFile (base </> ".agents/c-plugin-state.json")
    let root = base </> ".agents/skills"
    names <- sort <$> listDirectory root
    links <- forM names $ \name -> do
        kind <- pathKind (root </> name)
        literal <- if kind == Just SymbolicLink then Just <$> readSymbolicLink (root </> name) else pure Nothing
        pure (name, literal)
    pure (desired, ownership, links)

assertNoStaging :: FilePath -> IO ()
assertNoStaging base = do
    names <- listDirectory (base </> ".agents/c-plugin/sources")
    filter (isPrefixOf ".fetch-") names `shouldBe` []

findRemote :: [Remote] -> FilePath -> Maybe Remote
findRemote remotes directory = case [remote | remote <- remotes, ("/" ++ remoteSlug remote ++ "/") `isInfixOf` directory] of
    remote : _ -> Just remote
    [] -> Nothing

gateFor :: [Remote] -> [Gate] -> Remote -> Gate
gateFor remotes gates remote = case [gate | (candidate, gate) <- zip remotes gates, candidate == remote] of
    gate : _ -> gate
    [] -> error "missing fixture gate"

-- This executable contains only shell builtins. It neither invokes Git nor
-- creates child processes of its own. Each subprocess reports its start before
-- waiting on a private FIFO, and reports its end before exiting. The controller
-- can therefore check the exact eight-active-process trace without sleeps.
withFakeGit :: FilePath -> [Int] -> (Handle -> (String -> IO ()) -> IO a) -> IO a
withFakeGit base identifiers action = do
    let bin = base </> "fake-git"
        executable = bin </> "git"
        eventsPath = bin </> "events"
        releasePath identifier = bin </> ("release-" ++ identifier)
    createDirectoryIfMissing True bin
    writeFile executable $
        unlines
            [ "#!/bin/sh"
            , "set -eu"
            , "root=${0%/*}"
            , "for argument in \"$@\"; do worker=$argument; done"
            , "printf 'start %s\\n' \"$worker\" > \"$root/events\""
            , "read -r token < \"$root/release-$worker\""
            , "test \"$token\" = finish"
            , "printf 'end %s\\n' \"$worker\" > \"$root/events\""
            , "printf 'ok %s\\n' \"$worker\""
            ]
    setFileMode executable 0o700
    createNamedPipe eventsPath 0o600
    forM_ identifiers $ \identifier -> createNamedPipe (releasePath (show identifier)) 0o600
    let openEvents = openFd eventsPath ReadWrite Nothing defaultFileFlags >>= fdToHandle
        release identifier = watchdog "fake Git release FIFO" (writeFile (releasePath identifier) "finish\n")
        restorePath Nothing = unsetEnv "PATH"
        restorePath (Just previous) = setEnv "PATH" previous
    bracket (lookupEnv "PATH") restorePath $ \previous -> do
        setEnv "PATH" (bin ++ maybe "" (':' :) previous)
        bracket openEvents hClose $ \events -> do
            hSetBuffering events LineBuffering
            action events release

readProcessEvent :: Handle -> String -> IO String
readProcessEvent events expected = do
    line <- watchdog ("fake Git " ++ expected ++ " event") (hGetLine events)
    case words line of
        [event, identifier] -> do
            event `shouldBe` expected
            pure identifier
        _ -> ioError (userError ("invalid fake Git event: " ++ show line))

data Gate = Gate
    { gateClaimed :: MVar Bool
    , gateArrival :: MVar ()
    , gateRelease :: MVar ()
    , gateDeparture :: MVar ()
    }

newGate :: IO Gate
newGate = Gate <$> newMVar False <*> newEmptyMVar <*> newEmptyMVar <*> newEmptyMVar

-- A gate is one-shot, so repeated verification cannot accidentally block again.
-- finally acknowledges both normal completion and asynchronous child cleanup.
throughGate :: Gate -> IO a -> IO a
throughGate gate action = mask $ \restore -> do
    claimed <- modifyMVar (gateClaimed gate) (\old -> pure (True, not old))
    if claimed
        then
            restore (putMVar (gateArrival gate) () >> readMVar (gateRelease gate) >> action)
                `finally` void (tryPutMVar (gateDeparture gate) ())
        else restore action

gateFetches :: [(String, Gate)] -> GitRunner -> GitRunner
gateFetches gates runner network directory arguments
    | network && "fetch" `elem` arguments = case [gate | (url, gate) <- gates, url `elem` arguments] of
        [gate] -> throughGate gate (runner network directory arguments)
        _ -> ioError (userError "unexpected barrier fetch URL")
    | otherwise = runner network directory arguments

awaitArrival :: Gate -> IO ()
awaitArrival gate = watchdog "worker barrier arrival" (readMVar (gateArrival gate))

awaitDeparture :: Gate -> IO ()
awaitDeparture gate = watchdog "worker barrier cleanup acknowledgement" (readMVar (gateDeparture gate))

releaseGate :: Gate -> IO ()
releaseGate gate = void (tryPutMVar (gateRelease gate) ())

-- Timeouts diagnose deadlocks only. Success requires observed barrier events,
-- exact fetch counts, and actual product state, never elapsed time or sleeps.
watchdog :: String -> IO a -> IO a
watchdog label action = do
    result <- timeout (20 * 1000000) action
    maybe (ioError (userError ("timed out waiting for " ++ label))) pure result

isIOException :: Either SomeException () -> Bool
isIOException (Left exception) = case fromException exception :: Maybe IOException of
    Just _ -> True
    Nothing -> False
isIOException (Right ()) = False
