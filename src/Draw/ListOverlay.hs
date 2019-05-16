{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Draw.ListOverlay
  ( drawListOverlay
  )
where

import           Prelude ()
import           Prelude.MH

import           Brick
import           Brick.Widgets.Border
import           Brick.Widgets.Center
import           Brick.Widgets.Edit
import qualified Brick.Widgets.List as L
import           Control.Monad.Trans.Reader ( withReaderT )
import qualified Data.Foldable as F
import qualified Data.Text as T
import           Lens.Micro.Platform ( (%~) )

import           Themes
import           Types


hLimitWithPadding :: Int -> Widget n -> Widget n
hLimitWithPadding pad contents = Widget
  { hSize  = Fixed
  , vSize  = (vSize contents)
  , render =
      withReaderT (& availWidthL  %~ (\ n -> n - (2 * pad))) $ render $ cropToContext contents
  }

-- | Draw a ListOverlayState as a floating overlay on top of whatever is
-- rendered beneath it
drawListOverlay :: ListOverlayState a b
                -> (b -> Widget Name)
                -> (b -> Widget Name)
                -> (b -> Widget Name)
                -> (Bool -> a -> Widget Name)
                -> Widget Name
drawListOverlay st scopeHeader scopeNoResults scopePrompt renderItem =
  centerLayer $ hLimitWithPadding 10 $ vLimit 25 $
  borderWithLabel (scopeHeader scope) body
  where
      body = vBox [ (padRight (Pad 1) promptMsg) <+>
                    renderEditor (txt . T.unlines) True (st^.listOverlaySearchInput)
                  , cursorPositionBorder
                  , userResultList
                  ]
      plural 1 = ""
      plural _ = "s"
      cursorPositionBorder = case st^.listOverlaySearchResults.L.listSelectedL of
          Nothing -> hBorder
          Just _ ->
              let msg = case st^.listOverlayRequestingMore of
                          True -> "Fetching more results..."
                          False -> "Showing " <> show numSearchResults <> " result" <> plural numSearchResults
                          -- NOTE: one day when we resume doing
                          -- pagination, we want to reinstate the
                          -- following logic instead of the False case
                          -- above. Please see State.UserListOverlay for
                          -- details.
                          --
                          -- False -> case st^.userListHasAllResults of
                          --     True -> "Showing all results (" <> show numSearchResults <> ")"
                          --     False -> "Showing first " <>
                          --              show numSearchResults <>
                          --              " result" <> plural numSearchResults
              in hBorderWithLabel $ str $ "[" <> msg <> "]"

      scope = st^.listOverlaySearchScope
      promptMsg = scopePrompt scope

      userResultList =
          if st^.listOverlaySearching
          then showMessage $ txt "Searching..."
          else showResults

      showMessage = center . withDefAttr clientEmphAttr

      showResults
        | numSearchResults == 0 = showMessage $ scopeNoResults scope
        | otherwise = renderedUserList

      renderedUserList = L.renderList renderItem True (st^.listOverlaySearchResults)
      numSearchResults = F.length $ st^.listOverlaySearchResults.L.listElementsL