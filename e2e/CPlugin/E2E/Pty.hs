{-# LANGUAGE OverloadedStrings #-}

module CPlugin.E2E.Pty where

import CPlugin.E2E.Support
import Data.Aeson (eitherDecodeStrict', encode, object, withObject, (.:), (.=))
import Data.Aeson.Types (parseEither)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Paths_c_plugin_e2e (getDataFileName)
import Test.Hspec (shouldBe, shouldNotBe)
import Prelude hiding (writeFile)

selectionPrompt, keyUp, keyDown, keySpace, keyEnter, keyEscape, keyEOF, keyInterrupt :: String
selectionPrompt = "Space: toggle"
keyUp = "\ESC[A"
keyDown = "\ESC[B"
keySpace = " "
keyEnter = "\r"
keyEscape = "\ESC"
keyEOF = "\EOT"
keyInterrupt = "\ETX"

data TerminalResult = TerminalResult
    { terminalExitCode :: Int
    , terminalStdout :: String
    , terminalStderr :: String
    , terminalSent :: Int
    , terminalUnread :: String
    , terminalRestored :: Bool
    , terminalDisplayRestored :: Bool
    }
    deriving (Show)

decodeTerminalResult :: BS.ByteString -> Either String TerminalResult
decodeTerminalResult bytes =
    eitherDecodeStrict' bytes
        >>= parseEither
            ( withObject "terminal result" $ \value ->
                TerminalResult
                    <$> value .: "exit_code"
                    <*> value .: "stdout"
                    <*> value .: "stderr"
                    <*> value .: "sent"
                    <*> value .: "unread"
                    <*> value .: "restored"
                    <*> value .: "display_restored"
            )

runTerminal :: Scenario -> String -> [String] -> Bool -> [String] -> IO TerminalResult
runTerminal s directory actions pipe = runTerminalWithTerm s directory actions pipe "xterm"

runTerminalWithTerm :: Scenario -> String -> [String] -> Bool -> String -> [String] -> IO TerminalResult
runTerminalWithTerm s directory actions pipe terminal arguments = do
    source <- getDataFileName "CPlugin/E2E/PtyDriver.py" >>= BS.readFile
    let driver = home s ++ "/terminal-driver.py"
    writeFile s driver (Text.unpack (Text.decodeUtf8 source))
    let request =
            LBS.unpack $
                encode $
                    object
                        [ "home" .= home s
                        , "cwd" .= directory
                        , "argv" .= (cPlugin : arguments)
                        , "actions" .= actions
                        , "pipe" .= pipe
                        , "prompt" .= selectionPrompt
                        , "term" .= terminal
                        ]
    result <- infra s directory ["/usr/bin/timeout", "15", "/usr/bin/python3", driver, request]
    requireSuccess result
    actual <-
        either
            (fail . ("terminal JSON: " ++))
            pure
            (decodeTerminalResult (Text.encodeUtf8 (Text.pack (stdoutText result))))
    terminalSent actual `shouldBe` length actions
    terminalRestored actual `shouldBe` True
    terminalDisplayRestored actual `shouldBe` True
    requireNotContains (terminalStdout actual) selectionPrompt
    requireNotContains (terminalStderr actual) "Select indexes"
    requireNotContains (terminalStderr actual) "1) "
    pure actual

requireTerminalSuccess :: TerminalResult -> IO ()
requireTerminalSuccess result = terminalExitCode result `shouldBe` 0

requireTerminalFailure :: TerminalResult -> IO ()
requireTerminalFailure result = terminalExitCode result `shouldNotBe` 0
