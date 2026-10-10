module Main (main) where

import BadPlayer.Bot (Config (..), runBot)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import System.Environment (lookupEnv)
import System.Exit (die)
import System.IO (BufferMode (..), hSetBuffering, stderr, stdout)
import Text.Read (readMaybe)

-- env: BOT_TOKEN_FILE (preferred, keeps the token out of the environment)
-- or BOT_TOKEN, PLAYLIST_CHANNEL (bad-playlist), CATCHUP_HOURS (24, 0 = off)
main :: IO ()
main = do
  -- systemd
  hSetBuffering stdout LineBuffering
  hSetBuffering stderr LineBuffering
  token <- readToken
  playlist <- readPlaylistChannel
  catchUpHours <- readCatchUpHours
  result <-
    runBot
      Config
        { botToken = token
        , playlistChannel = playlist
        , catchUpWindow = fromInteger catchUpHours * 3600
        }
  case result of
    Just err -> die ("Bad Player failed to start: " <> show err)
    Nothing -> die "Bad Player stopped"

readToken :: IO T.Text
readToken =
  lookupEnv "BOT_TOKEN_FILE" >>= \case
    Just path -> nonEmpty ("token file " <> path) . T.strip =<< T.readFile path
    Nothing ->
      lookupEnv "BOT_TOKEN" >>= \case
        Just t -> nonEmpty "BOT_TOKEN" (T.strip (T.pack t))
        Nothing -> die "Set BOT_TOKEN_FILE or BOT_TOKEN"
  where
    nonEmpty source t
      | T.null t = die (source <> " is empty")
      | otherwise = pure t

readPlaylistChannel :: IO T.Text
readPlaylistChannel =
  lookupEnv "PLAYLIST_CHANNEL" >>= \case
    Nothing -> pure "bad-playlist"
    Just s -> case T.dropWhile (== '#') (T.strip (T.pack s)) of
      "" -> die "PLAYLIST_CHANNEL is empty"
      name -> pure name

readCatchUpHours :: IO Integer
readCatchUpHours =
  lookupEnv "CATCHUP_HOURS" >>= \case
    Nothing -> pure 24
    Just s -> case readMaybe s of
      Just h | h >= 0 -> pure h
      _ -> die ("CATCHUP_HOURS must be a non-negative whole number, got " <> show s)
