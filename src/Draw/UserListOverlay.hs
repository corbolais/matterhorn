{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Draw.UserListOverlay where

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
import qualified Graphics.Vty as V
import           Lens.Micro.Platform ( (%~) )

import           Draw.Main
import           Draw.Util ( userSigilFromInfo )
import           Themes
import           Types


hLimitWithPadding :: Int -> Widget n -> Widget n
hLimitWithPadding pad contents = Widget
  { hSize  = Fixed
  , vSize  = (vSize contents)
  , render =
      withReaderT (& availWidthL  %~ (\ n -> n - (2 * pad))) $ render $ cropToContext contents
  }

drawUserListOverlay :: ChatState -> [Widget Name]
drawUserListOverlay st =
  (joinBorders $ drawUsersBox (st^.csUserListOverlay)) :
  (forceAttr "invalid" <$> drawMain st)

-- | Draw a PostListOverlay as a floating overlay on top of whatever
-- is rendered beneath it
drawUsersBox :: ListOverlayState UserInfo UserSearchScope -> Widget Name
drawUsersBox st =
  centerLayer $ hLimitWithPadding 10 $ vLimit 25 $
  borderWithLabel contentHeader body
  where
      body = vBox [ (padRight (Pad 1) $ str promptMsg) <+>
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
      promptMsg = case scope of
          ChannelMembers _ _    -> "Search channel members:"
          ChannelNonMembers _ _ -> "Search users:"
          AllUsers Nothing      -> "Search users:"
          AllUsers (Just _)     -> "Search team members:"

      userResultList =
          if st^.listOverlaySearching
          then showMessage "Searching..."
          else showResults

      showMessage = center . withDefAttr clientEmphAttr . str

      showResults
        | numSearchResults == 0 =
            showMessage $ case scope of
              ChannelMembers _ _    -> "No users in channel."
              ChannelNonMembers _ _ -> "All users in your team are already in this channel."
              AllUsers _            -> "No users found."
        | otherwise = renderedUserList

      contentHeader = str $ case scope of
          ChannelMembers _ _    -> "Channel Members"
          ChannelNonMembers _ _ -> "Invite Users to Channel"
          AllUsers Nothing      -> "Users On This Server"
          AllUsers (Just _)     -> "Users In My Team"

      renderedUserList = L.renderList renderUser True (st^.listOverlaySearchResults)
      numSearchResults = F.length $ st^.listOverlaySearchResults.L.listElementsL

      sanitize = T.strip . T.replace "\t" " "
      usernameWidth = 20
      renderUser foc ui =
          (if foc then forceAttr L.listSelectedFocusedAttr else id) $
          vLimit 2 $
          padRight Max $
          hBox $ (padRight (Pad 1) $ colorUsername (ui^.uiName) (T.singleton $ userSigilFromInfo ui))
                 : (hLimit usernameWidth $ padRight Max $ colorUsername (ui^.uiName) (ui^.uiName))
                 : extras
          where
              extras = padRight (Pad 1) <$> catMaybes [mFullname, mNickname, mEmail]
              mFullname = if (not (T.null (ui^.uiFirstName)) || not (T.null (ui^.uiLastName)))
                          then Just $ txt $ (sanitize $ ui^.uiFirstName) <> " " <> (sanitize $ ui^.uiLastName)
                          else Nothing
              mNickname = case ui^.uiNickName of
                            Just n | n /= (ui^.uiName) -> Just $ txt $ "(" <> n <> ")"
                            _ -> Nothing
              mEmail = if (T.null $ ui^.uiEmail)
                       then Nothing
                       else Just $ modifyDefAttr (`V.withURL` ("mailto:" <> ui^.uiEmail)) $
                                   withDefAttr urlAttr (txt ("<" <> ui^.uiEmail <> ">"))
