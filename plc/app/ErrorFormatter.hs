module ErrorFormatter (setRed, setBlue, setGreen, formatError) where

import System.Console.ANSI


coloured :: [SGR] -> String -> String
coloured sgrs s = setSGRCode sgrs ++ s ++ setSGRCode [Reset]

setRed, setBlue, setGreen :: String -> String
setRed = coloured [SetColor Foreground Vivid Red]
setBlue = coloured [SetColor Foreground Vivid Blue]
setGreen = coloured [SetColor Foreground Vivid Green]


-- Error Name -> Error Message
formatError :: String -> String -> String
formatError n m = setRed "[" ++ setRed n ++ setRed "]" ++ ": " ++ m
