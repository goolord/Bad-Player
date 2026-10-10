module Main (main) where

import BadPlayer.YouTube (isOnlyYouTubeLinks)
import Control.Monad (unless)
import Data.Text (Text)
import System.Exit (exitFailure)

allowed :: [Text]
allowed =
  [ "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  , "https://youtube.com/watch?v=dQw4w9WgXcQ&t=42s"
  , "https://www.youtube.com/watch?list=PL123&v=dQw4w9WgXcQ"
  , "http://m.youtube.com/watch?v=dQw4w9WgXcQ"
  , "https://music.youtube.com/watch?v=dQw4w9WgXcQ"
  , "https://youtu.be/dQw4w9WgXcQ"
  , "https://youtu.be/dQw4w9WgXcQ?si=abc123"
  , "https://www.youtube.com/shorts/dQw4w9WgXcQ"
  , "https://www.youtube.com/live/dQw4w9WgXcQ"
  , "https://www.youtube.com/embed/dQw4w9WgXcQ"
  , "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"
  , "HTTPS://WWW.YOUTUBE.COM/watch?v=dQw4w9WgXcQ"
  , "<https://youtu.be/dQw4w9WgXcQ>"
  , "  https://youtu.be/dQw4w9WgXcQ\nhttps://youtu.be/9bZkp7q19f0  "
  ]

rejected :: [Text]
rejected =
  [ ""
  , "   "
  , "hello"
  , "check this out https://youtu.be/dQw4w9WgXcQ"
  , "https://youtu.be/dQw4w9WgXcQ lol"
  , "https://www.youtube.com/"
  , "https://www.youtube.com/@SomeChannel"
  , "https://www.youtube.com/channel/UC123"
  , "https://www.youtube.com/playlist?list=PL123"
  , "https://www.youtube.com/watch"
  , "https://www.youtube.com/watch?v=short"
  , "https://www.youtube.com/watch?v=dQw4w9WgXcQextra"
  , "https://youtu.be/"
  , "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ"
  , "https://www.youtube.com@evil.example/watch?v=dQw4w9WgXcQ"
  , "https://notyoutube.com/watch?v=dQw4w9WgXcQ"
  , "ftp://youtube.com/watch?v=dQw4w9WgXcQ"
  , "youtube.com/watch?v=dQw4w9WgXcQ"
  , "[video](https://youtu.be/dQw4w9WgXcQ)"
  , "||https://youtu.be/dQw4w9WgXcQ||"
  ]

main :: IO ()
main = do
  let failures =
        map ("should allow",) (filter (not . isOnlyYouTubeLinks) allowed)
          <> map ("should reject",) (filter isOnlyYouTubeLinks rejected)
  mapM_ (\(what, t) -> putStrLn (what <> ": " <> show t)) failures
  unless (null failures) exitFailure
  putStrLn ("All " <> show (length allowed + length rejected) <> " cases passed")
