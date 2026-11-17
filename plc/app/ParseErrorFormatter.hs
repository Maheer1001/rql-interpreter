module ParseErrorFormatter (formatParseError) where

import Lexer
import ErrorFormatter (setRed, setGreen, setBlue)
import Data.List (intercalate)

-- Warning: Does not handle truncating longer error lines

getErrorLines :: String -> Int -> [String]
getErrorLines raw line =
    let allLines = lines raw
        len = length allLines
        oneBack = if line > 2 && line <= len
                  then allLines !! (line - 2)
                  else " "
        errorLine = if line >= 1 && line <= len
                    then allLines !! (line - 1)
                    else "Source not found"
    in [oneBack, errorLine]

formatParseError :: String -> PosnToken -> [String] -> String
formatParseError _ (PT (AlexPn _ 0 _) _) _ = "Expected a query starting with LET or CONSTRUCT.\n"
formatParseError rawInput (PT (AlexPn _ line col) _ ) expected =
    let errorLines = getErrorLines rawInput line
        gutterWidth = length (show line) + 4
        pointer = replicate (col - 1 + gutterWidth) ' ' ++ "^"
        cleaned = filter (not . null) $ map (filter (/= '\'')) expected
        isSingle = length cleaned == 1
        msgPrefix = if isSingle then "Expected: " else "Expected one of: "
        msgPrefixAligned = replicate (col - 1 + gutterWidth) ' ' ++ msgPrefix
        message = if null cleaned then ""
                  else msgPrefixAligned ++ intercalate ", " cleaned
        fixedLine = if isSingle
                    then unlines ["Suggested fix:",
                                  setRed   ("   - " ++ errorLines !! 1),
                                  setGreen ("   + " ++ replace (col-1) (head cleaned) (errorLines !! 1))]
                    else ""
    in unlines $ filter (not . null) [
        "Line " ++ show line ++ ", Column " ++ show col ++ "\n",
        setBlue (" " ++ show (line-1) ++ " | ") ++ head errorLines,
        setBlue (" " ++ show line ++ " | ") ++ errorLines !! 1,
        pointer,
        message,
        fixedLine
    ]

replace :: Int -> [Char] -> [Char] -> [Char]
replace 0 y (' ':xs) = y ++ " " ++ xs
replace 0 y xs = y ++ " " ++ xs
replace n y (x:xs) = x : replace (n-1) y xs
replace _ _ [] = []
