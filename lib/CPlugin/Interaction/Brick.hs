{-# LANGUAGE OverloadedStrings #-}

module CPlugin.Interaction.Brick (select) where

import Brick (App (..), BrickEvent (..), EventM, Padding (Pad), Size (Fixed, Greedy), ViewportType (Vertical), Widget (..), attrMap, attrName, availHeight, availWidth, customMain, getContext, getVtyHandle, halt, neverShowCursor, padBottom, str, strWrap, vBox, viewport, visible, withAttr)
import CPlugin.Types.Selection (Selection (..))
import Control.Exception (AsyncException (UserInterrupt), bracket, finally, onException, throwIO)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.State.Strict (get, modify')
import qualified Data.Set as Set
import GHC.IO.Handle (hDuplicate)
import qualified Graphics.Vty as Vty
import qualified Graphics.Vty.Platform.Unix as Unix
import Graphics.Vty.Platform.Unix.Settings (UnixSettings (..), currentTerminalName)
import System.IO (Handle)
import System.Posix.IO (closeFd, handleToFd)
import System.Posix.Terminal (TerminalState (Immediately), getTerminalAttributes, setTerminalAttributes)

data Menu a = Menu
    { focused :: Int
    , checked :: Set.Set a
    , result :: Selection a
    }

select :: (Ord a) => Handle -> Handle -> String -> (a -> String) -> [a] -> IO (Selection a)
select input output guidance label choices =
    bracket (hDuplicate input >>= handleToFd) closeFd $ \inputFd ->
        bracket (hDuplicate output >>= handleToFd) closeFd $ \outputFd -> do
            terminal <- currentTerminalName >>= maybe (ioError (userError "TERM is required for interactive selection")) pure
            let settings = UnixSettings 1 100 inputFd outputFd terminal
                buildVty = Unix.mkVtyWithSettings Vty.defaultConfig settings
                app =
                    App
                        { appDraw = draw guidance label choices
                        , appChooseCursor = neverShowCursor
                        , appHandleEvent = handleEvent guidance choices
                        , appStartEvent = pure ()
                        , appAttrMap = const (attrMap Vty.defAttr [(attrName "focus", Vty.withStyle Vty.defAttr Vty.reverseVideo)])
                        }
            -- Vty can change input settings before terminal output setup fails.
            bracket (getTerminalAttributes inputFd) (\attributes -> setTerminalAttributes inputFd attributes Immediately) $ \_ ->
                bracket buildVty Vty.shutdown $ \vty ->
                    (result <$> customMain vty buildVty Nothing app (Menu 0 Set.empty Cancelled))
                        `onException` restoreDisplay vty

-- Vty marks shutdown complete before its interruptible input-thread cleanup.
-- Bypass that flag if interruption prevents its screen/cursor cleanup.
restoreDisplay :: Vty.Vty -> IO ()
restoreDisplay vty =
    Vty.releaseDisplay (Vty.outputIface vty)
        `finally` Vty.releaseTerminal (Vty.outputIface vty)

draw :: (Ord a) => String -> (a -> String) -> [a] -> Menu a -> [Widget ()]
draw guidance label choices menu =
    [ Widget Greedy Greedy $ do
        context <- getContext
        if menuFits guidance (availWidth context, availHeight context)
            then render menuWidget
            else render (strWrap "Enlarge terminal to select. Esc/q or Ctrl-D cancels.")
    ]
  where
    menuWidget =
        vBox
            [ padBottom (Pad 1) (wrapped guidance)
            , str "Up/Down: move | Space: toggle | Enter: confirm | Esc/q: cancel"
            , padBottom (Pad 1) (str "a: select all | n: clear | Ctrl-D: cancel")
            , viewport () Vertical (vBox (zipWith row [0 ..] choices))
            ]
    row index choice =
        let widget = wrapped ((if Set.member choice (checked menu) then "[x] " else "[ ] ") ++ label choice)
         in if index == focused menu then visible (withAttr (attrName "focus") widget) else widget

menuFits :: String -> (Int, Int) -> Bool
menuFits guidance (width, height) = width >= 2 && height > length (wrapLines width guidance) + 4

-- Wrap by terminal columns, including long names and paths with no spaces.
wrapped :: String -> Widget n
wrapped text = Widget Greedy Fixed $ do
    context <- getContext
    render (vBox (map str (wrapLines (availWidth context) text)))

wrapLines :: Int -> String -> [String]
wrapLines width = go 0 []
  where
    go _ line [] = [reverse line]
    go _ line ('\n' : rest) = reverse line : go 0 [] rest
    go used line text@(character : rest)
        | used + Vty.safeWcwidth character > max 2 width && not (null line) = reverse line : go 0 [] text
        | otherwise = go (used + Vty.safeWcwidth character) (character : line) rest

handleEvent :: (Ord a) => String -> [a] -> BrickEvent () () -> EventM () (Menu a) ()
handleEvent guidance choices (VtyEvent (Vty.EvKey key modifiers)) = case (key, modifiers) of
    (Vty.KUp, []) -> move (-1)
    (Vty.KDown, []) -> move 1
    (Vty.KChar ' ', []) -> do
        menu <- get
        let choice = choices !! focused menu
        modify' $ \current -> current{checked = if Set.member choice (checked current) then Set.delete choice (checked current) else Set.insert choice (checked current)}
    (Vty.KChar 'a', []) -> modify' (\menu -> menu{checked = Set.fromList choices})
    (Vty.KChar 'n', []) -> modify' (\menu -> menu{checked = Set.empty})
    (Vty.KEnter, []) -> do
        vty <- getVtyHandle
        size <- liftIO (Vty.displayBounds (Vty.outputIface vty))
        when (menuFits guidance size) $ do
            menu <- get
            modify' (\current -> current{result = Selected (checked menu)})
            halt
    (Vty.KEsc, []) -> halt
    (Vty.KChar 'q', []) -> halt
    (Vty.KChar 'd', [Vty.MCtrl]) -> halt
    (Vty.KChar 'c', [Vty.MCtrl]) -> liftIO (throwIO UserInterrupt)
    _ -> pure ()
  where
    move :: Int -> EventM () (Menu a) ()
    move delta = modify' (\menu -> menu{focused = max 0 (min (length choices - 1) (focused menu + delta))})
handleEvent _ _ _ = pure ()
