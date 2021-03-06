{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import           Control.Applicative    (Alternative (..), liftA2, (*>), (<*))
import           Control.Arrow          (second)
import           Control.Exception      (Exception, SomeException, catch)
import           Control.Exception.Base (throwIO)
import           Data.Char              (isSpace)
import           Data.IORef             (IORef, newIORef, readIORef, writeIORef)
import           Data.Map.Strict        (Map, (!))
import qualified Data.Map.Strict        as Map
import           Data.Maybe             (fromJust)
import           Data.Monoid            ((<>))
import           Data.Text              (Text, dropWhile, lines, pack, split, splitOn,
                                         strip, takeWhile, unpack)
import qualified Data.Text              as T
import           Data.Text.IO           (getLine, hGetContents, hPutStrLn, putStr,
                                         putStrLn)
import           Data.Typeable          (Typeable)
import           Prelude                hiding (dropWhile, getLine, lines, putStr,
                                         putStrLn, takeWhile)
import           System.Environment     (getArgs)
import           System.IO              (Handle, IOMode (ReadMode, WriteMode), stdout,
                                         withFile)
import           System.IO.Error        (isDoesNotExistError)

data AbortLoop = AbortLoop
    deriving (Show, Typeable, Exception)

propertyParser :: Text -> IO (Text, Text)
propertyParser s = do
    let striped = strip s
    let first_id = takeWhile (\x -> not $ (isSpace x) || (x == '=')) striped
    let without_first = dropWhile (\x -> not $ (isSpace x) || (x == '=')) striped
    let second_id = strip (dropWhile (=='=') (strip without_first))
    return (first_id, second_id)

type Config = Map Text (IO (IORef Text))

readConfig :: Handle -> IO Config
readConfig hFile = do
    content <- hGetContents hFile
    let params' = lines content
    let params  = filter (not . T.null) params'
    let parsedParams = map propertyParser params
    putStrLn ""
    putStrLn "parsed content: "
    mapM_ (>>= putStrLn . pack . show) parsedParams
    putStrLn ""

    let ioArrayOfParams = sequence parsedParams
    arrayOfParams <- ioArrayOfParams

    return $ Map.fromList $ map (second newIORef) arrayOfParams

readHandler :: Monoid a => IOError -> IO a
readHandler e =
    if isDoesNotExistError e then
        return mempty
    else
        throwIO e

printHeader :: IO ()
printHeader = do
    putStr "Interactive options:\n\
      \* B <value> : modify previous value\n\
      \* W         : finish session and write to file\n\
      \* A         : abort session (discard all changes)\n\
      \* S         : show current values\n"
    return ()

writeConfig :: Config -> Handle -> IO ()
writeConfig config hFile = do
    let lstConfig = Map.toList config :: [(Text, IO (IORef Text))]
    mapM_ (\(str, ioIoRef) -> do ioRef <- ioIoRef
                                 ref   <- readIORef ioRef
                                 hPutStrLn hFile (str <> " " <> ref)) lstConfig

mainLoop :: Config -> IO Config
mainLoop config = do
    putStrLn "Input property and value:"
    propWIthValue <- getLine
    (lhs, rhs) <- propertyParser propWIthValue
    case lhs of
        "W" -> do
            putStrLn ""
            putStrLn "Next properties are written:"
            writeConfig config stdout
            return config
        "B" -> do
            let prev_value_io_ref = config Map.! rhs
            prev_value_ref <- prev_value_io_ref
            prev_value <- readIORef prev_value_ref

            putStrLn ("Input new value for `" <> rhs <> "` property (previous: `" <> prev_value <> "`)")
            newProp <- getLine
            let nConfig = Map.insert rhs (newIORef newProp) config
            mainLoop nConfig
        "A" ->
            throwIO AbortLoop
        "S" -> do
            writeConfig config stdout
            mainLoop config
        otherwise -> do
            let nConfig = Map.insert lhs (newIORef rhs) config
            mainLoop nConfig


startInteractiveMode :: Config -> Handle -> IO ()
startInteractiveMode config hFile = do
    nConfig <- mainLoop config `catch` \(e :: SomeException) -> do
               writeConfig config hFile
               throwIO e
    writeConfig nConfig hFile
    return ()

main :: IO ()
main = do
    args <- getArgs
    let inFile = head args
    printHeader
    mp <- withFile inFile ReadMode readConfig `catch` readHandler
    withFile inFile WriteMode (startInteractiveMode mp)

