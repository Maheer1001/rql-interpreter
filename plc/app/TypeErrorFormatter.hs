module TypeErrorFormatter (formatTypeError) where

import Data.List (intercalate)
import Lexer
import TypeChecker (TypeError(..))
import ErrorFormatter (setRed, setBlue)

formatTypeError :: TypeError -> String -> [PosnToken] -> String
formatTypeError (TypeConflict var types) rawText tokens =
  let varInstances = findVarLines var tokens
      errorLines = map (getErrorLines rawText) varInstances
  in unlines [
    setRed "[Type Error]" ++ ": '?" ++ var ++ "' is used as multiple incompatible types",
    "Can not unify types: " ++ show types
  ] ++ intercalate "\n" (map (intercalate "\n") errorLines) ++ "\n"


findVarLines :: String -> [PosnToken] -> [(Int, Int)]
findVarLines target tokens = [(l, c) | PT (AlexPn _ l c) (TokenVar v) <- tokens, v == target ]


getErrorLines :: String -> (Int, Int) -> [String]
getErrorLines raw (line, col) =
    let allLines = lines raw
        len = length allLines
        errorLine = if line <= len
                    then allLines !! (line-1)
                    else "Source not found"
        gutter =  " " ++ show line ++ " | "
        coloured_gutter = setBlue gutter
        formattedErrorLine = coloured_gutter ++ errorLine
        pointer = replicate (col -1 + (length gutter)) ' ' ++ "^"
    in [formattedErrorLine, pointer]
