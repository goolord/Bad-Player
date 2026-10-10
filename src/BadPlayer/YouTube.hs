module BadPlayer.YouTube (
  isYouTubeVideoUrl,
  isOnlyYouTubeLinks,
) where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List.NonEmpty qualified as NE
import Data.Maybe (fromMaybe, isNothing, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Text.URI (Authority (..), QueryParam (..), URI (..), mkURI, unRText)

isOnlyYouTubeLinks :: Text -> Bool
isOnlyYouTubeLinks t = case T.words t of
  [] -> False
  ws -> all (isYouTubeVideoUrl . unwrapAngles) ws
  where
    unwrapAngles w = fromMaybe w (T.stripPrefix "<" w >>= T.stripSuffix ">")

-- | True when the text is a single http(s) URL pointing at a YouTube video.
--
-- Accepted shapes:
--
-- * @youtube.com/watch?v=ID@ (also @www.@, @m.@ and @music.@)
-- * @youtube.com/shorts/ID@, @/live/ID@, @/embed/ID@, @/v/ID@
-- * @youtu.be/ID@
-- * @youtube-nocookie.com/embed/ID@
isYouTubeVideoUrl :: Text -> Bool
isYouTubeVideoUrl t = fromMaybe False do
  uri <- mkURI t
  scheme <- uriScheme uri
  auth <- either (const Nothing) Just (uriAuthority uri)
  pure $
    T.toLower (unRText scheme) `elem` ["http", "https"]
      && isNothing (authUserInfo auth)
      && isVideoLocation (T.toLower (unRText (authHost auth))) (pathPieces uri) (uriQuery uri)

isVideoLocation :: Text -> [Text] -> [QueryParam] -> Bool
isVideoLocation host segments query
  | host `elem` shortHosts = case segments of
      [vid] -> isVideoId vid
      _ -> False
  | host `elem` mainHosts = case segments of
      ["watch"] -> maybe False isVideoId (queryValue "v" query)
      [kind, vid] -> kind `elem` ["shorts", "live", "embed", "v"] && isVideoId vid
      _ -> False
  | host `elem` noCookieHosts = case segments of
      ["embed", vid] -> isVideoId vid
      _ -> False
  | otherwise = False
  where
    shortHosts = ["youtu.be", "www.youtu.be"]
    mainHosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
    noCookieHosts = ["youtube-nocookie.com", "www.youtube-nocookie.com"]

-- | YouTube video IDs are 11 characters from the URL-safe base64 alphabet.
isVideoId :: Text -> Bool
isVideoId s = T.length s == 11 && T.all isIdChar s
  where
    isIdChar c = isAsciiUpper c || isAsciiLower c || isDigit c || c == '-' || c == '_'

pathPieces :: URI -> [Text]
pathPieces = maybe [] (map unRText . NE.toList . snd) . uriPath

queryValue :: Text -> [QueryParam] -> Maybe Text
queryValue key = listToMaybe . mapMaybe match
  where
    match (QueryParam k v) | unRText k == key = Just (unRText v)
    match _ = Nothing
