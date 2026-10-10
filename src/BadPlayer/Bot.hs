module BadPlayer.Bot (
  Config (..),
  runBot,
) where

import BadPlayer.YouTube (isOnlyYouTubeLinks)
import Calamity
import Calamity.Cache.Eff (getGuildChannel, getMessage)
import Calamity.Cache.InMemory (runCacheInMemory)
import Calamity.Internal.Utils (MaybeNull (..))
import Calamity.Metrics.Noop (runMetricsNoop)
import Calamity.Types.Model.Channel.UpdatedMessage (UpdatedMessage)
import Control.Concurrent (threadDelay)
import Control.Monad (void, when)
import Data.Bits (bit)
import Data.Either (isLeft)
import Data.Flags ((.+.))
import Data.Foldable (for_, toList, traverse_)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (NominalDiffTime, diffUTCTime, getCurrentTime)
import Df1 qualified
import Di qualified
import Di.Core qualified
import DiPolysemy qualified as DiP
import Optics ((%), (^.))
import Polysemy qualified as P
import Polysemy.Async qualified as P
import TextShow (showt)

data Config = Config
  { botToken :: Text
  , playlistChannel :: Text
  , catchUpWindow :: NominalDiffTime
  }

runBot :: Config -> IO (Maybe StartupError)
runBot cfg =
  Di.new \di ->
    P.runFinal
      . P.embedToFinal
      . DiP.runDiToIO (Di.Core.filter (\level _ _ -> level >= Df1.Info) di)
      . runCacheInMemory
      . runMetricsNoop
      $ runBotIO (BotToken (botToken cfg)) intents do
        void $ react @'ReadyEvt \ready ->
          DiP.info $ "Connected as " <> ready ^. #user % #username
        void $ react @'GuildCreateEvt \(guild, _) ->
          catchUp (playlistChannel cfg) (catchUpWindow cfg) guild
        void $ react @'MessageCreateEvt \(msg, _, _) ->
          enforce (playlistChannel cfg) WarnAuthor msg
        void $ react @'RawMessageUpdateEvt \(update, _, _) -> do
          restricted <- inPlaylistChannel (playlistChannel cfg) (getID @Channel update)
          when (restricted && wasEdited update) $
            currentMessage update >>= traverse_ (enforce (playlistChannel cfg) WarnAuthor)

intents :: Intents
intents = intentGuilds .+. intentGuildMessages .+. messageContent
  where
    -- calamity has no name for this one
    messageContent = Intents (bit 15)

data Notify = WarnAuthor | Silently

enforce :: (BotC r) => Text -> Notify -> Message -> P.Sem r ()
enforce playlist notify msg =
  when (postedByHuman && isUserMessage) do
    restricted <- inPlaylistChannel playlist (msg ^. #channelID)
    when (restricted && not allowed) do
      deleted <- invoke $ DeleteMessage msg msg
      case deleted of
        Left err ->
          DiP.warning $ "Could not delete message " <> showt (getID @Message msg) <> ": " <> T.pack (show err)
        Right () -> do
          DiP.info $ "Deleted non-YouTube message " <> showt (getID @Message msg) <> " in channel " <> showt (msg ^. #channelID)
          case notify of
            WarnAuthor -> warnAuthor msg
            Silently -> pure ()
  where
    allowed = null (msg ^. #attachments) && isOnlyYouTubeLinks (msg ^. #content)
    isUserMessage = msg ^. #type_ `elem` [Default, Reply]
    postedByHuman = case msg ^. #author of
      User' u -> u ^. #bot /= Just True
      Webhook' _ -> False

inPlaylistChannel :: (BotC r) => Text -> Snowflake Channel -> P.Sem r Bool
inPlaylistChannel playlist cid =
  maybe False (isPlaylistChannel playlist) <$> getGuildChannel (coerceSnowflake cid)

isPlaylistChannel :: Text -> GuildChannel -> Bool
isPlaylistChannel playlist = \case
  GuildTextChannel chan -> chan ^. #name == playlist
  _ -> False

-- embed unfurls arrive as updates too, but without an edit timestamp
wasEdited :: UpdatedMessage -> Bool
wasEdited update = case update ^. #editedTimestamp of
  Just (NotNull _) -> True
  _ -> False

currentMessage :: (BotC r) => UpdatedMessage -> P.Sem r (Maybe Message)
currentMessage update =
  getMessage (getID @Message update) >>= \case
    Just msg -> pure (Just msg)
    Nothing ->
      invoke (GetMessage (getID @Channel update) (getID @Message update)) >>= \case
        Right msg -> pure (Just msg)
        Left err -> do
          DiP.warning $ "Could not fetch edited message " <> showt (getID @Message update) <> ": " <> T.pack (show err)
          pure Nothing

catchUp :: (BotC r) => Text -> NominalDiffTime -> Guild -> P.Sem r ()
catchUp playlist window guild =
  when (window > 0) do
    now <- P.embed getCurrentTime
    let isRecent msg = diffUTCTime now (msg ^. #timestamp) <= window
    for_ (filter (isPlaylistChannel playlist) (toList (guild ^. #channels))) \chan -> do
      res <- invoke $ GetChannelMessages (getID @Channel chan) Nothing (Just (ChannelMessagesLimit 100))
      case res of
        Left err ->
          DiP.warning $ "Could not read history of channel " <> showt (getID @Channel chan) <> ": " <> T.pack (show err)
        Right msgs ->
          for_ (filter isRecent msgs) (enforce playlist Silently)

warnAuthor :: (BotC r) => Message -> P.Sem r ()
warnAuthor msg = do
  notice <- tell @Text msg $ mention (getID @User msg) <> " only YouTube video links can be posted in this channel. Start a thread to chat about a video!"
  for_ notice \m -> P.async do
    P.embed $ threadDelay 10_000_000
    res <- invoke $ DeleteMessage m m
    when (isLeft res) $
      DiP.warning @Text "Could not delete warning message"
