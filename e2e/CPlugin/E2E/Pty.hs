{-# LANGUAGE OverloadedStrings #-}

module CPlugin.E2E.Pty where

import CPlugin.E2E.Support
import Control.Monad (forM_, void, when)
import qualified Data.ByteString as BS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Text.Encoding.Error (lenientDecode)
import qualified Test.CLI.E2E as CLI
import Test.Hspec (shouldBe, shouldNotBe, shouldSatisfy)

selectionPrompt, keyUp, keyDown, keySpace, keyEnter, keyEscape, keyEOF, keyInterrupt :: String
selectionPrompt = "Space: toggle"
keyUp = "\ESC[A"
keyDown = "\ESC[B"
keySpace = " "
keyEnter = "\r"
keyEscape = "\ESC"
keyEOF = "\EOT"
keyInterrupt = "\ETX"

type TerminalResult = CLI.TerminalObservation

terminalStdout, terminalStderr :: TerminalResult -> String
terminalStdout = terminalText . CLI.terminalStdout
terminalStderr = terminalText . CLI.terminalOutput

terminalText :: BS.ByteString -> String
terminalText = Text.unpack . Text.decodeUtf8With lenientDecode

runTerminal :: Scenario -> String -> [String] -> Bool -> [String] -> IO TerminalResult
runTerminal s directory keys pipe = runTerminalWithTerm s directory keys pipe "xterm"

runTerminalWithTerm :: Scenario -> String -> [String] -> Bool -> String -> [String] -> IO TerminalResult
runTerminalWithTerm s directory keys pipe term arguments =
    runTerminalSession s directory pipe term (not (null keys)) arguments $ \terminal ->
        forM_ keys $ \input -> do
            awaitMenu terminal
            void (CLI.sendTerminal terminal (encodeText input))

-- Each nested selector starts a new alternate screen. Waiting for its entry avoids
-- mistaking an earlier menu's incremental redraw for the next selector's prompt.
awaitMenu :: CLI.Terminal -> IO ()
awaitMenu terminal = do
    void (CLI.expectTerminal terminal CLI.TerminalOutput "\ESC[?1049h" 5)
    void (CLI.expectTerminal terminal CLI.TerminalOutput (encodeText selectionPrompt) 5)

runTerminalSession :: Scenario -> String -> Bool -> String -> Bool -> [String] -> (CLI.Terminal -> IO ()) -> IO TerminalResult
runTerminalSession s directory pipe term interactive arguments interact =
    CLI.withTerminal (scenarioDriver s) command options $ \terminal -> do
        interact terminal
        actual <- CLI.waitTerminal terminal 10
        CLI.terminalTermiosRestored actual `shouldBe` True
        CLI.terminalCurrentTermios actual `shouldBe` CLI.terminalInitialTermios actual
        requireDisplayRestored interactive (CLI.terminalOutput actual)
        requireNotContains (terminalStdout actual) selectionPrompt
        requireNotContains (terminalStderr actual) "Select indexes"
        requireNotContains (terminalStderr actual) "1) "
        pure actual
  where
    command = CLI.Command (cPlugin : arguments) (workingDirectory directory) (environmentVariables [("HOME", home s), ("TERM", term)])
    options =
        CLI.defaultTerminalOptions
            { CLI.terminalInput = if pipe then Just "unconsumed-input\n" else Nothing
            , CLI.terminalTimeout = 10
            }

requireDisplayRestored :: Bool -> BS.ByteString -> IO ()
requireDisplayRestored interactive output =
    forM_ [("\ESC[?1049h", "\ESC[?1049l"), ("\ESC[?25l", "\ESC[?25h")] $ \(enter, leave) -> do
        when interactive $ output `shouldSatisfy` BS.isInfixOf enter
        when (enter `BS.isInfixOf` output) $
            lastMode enter leave Nothing output `shouldBe` Just False
  where
    lastMode enter leave current bytes =
        case BS.uncons bytes of
            Nothing -> current
            Just (_, rest)
                | enter `BS.isPrefixOf` bytes -> lastMode enter leave (Just True) (BS.drop (BS.length enter) bytes)
                | leave `BS.isPrefixOf` bytes -> lastMode enter leave (Just False) (BS.drop (BS.length leave) bytes)
                | otherwise -> lastMode enter leave current rest

requireTerminalSuccess :: TerminalResult -> IO ()
requireTerminalSuccess result = CLI.terminalStatus result `shouldBe` CLI.TerminalExited 0

requireTerminalFailure :: TerminalResult -> IO ()
requireTerminalFailure result = do
    CLI.terminalStatus result `shouldNotBe` CLI.TerminalRunning
    CLI.terminalStatus result `shouldNotBe` CLI.TerminalExited 0
