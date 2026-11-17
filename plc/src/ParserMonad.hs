module ParserMonad (E(..), thenE, returnE, failE, catchE) where

import Lexer
-- return type of E a which is either Ok a or Failed String
data E a = Ok a | Failed PosnToken [String] String

thenE :: E a -> (a -> E b) -> E b
m `thenE` k =
  case m of
    Ok a -> k a
    Failed t expected e -> Failed t expected e

-- wraps in monad success
returnE :: a -> E a
returnE a = Ok a

-- wraps in monad fail
failE :: PosnToken -> [String] -> String -> E a
failE t expected err = Failed t expected err

catchE :: E a -> (String -> E a) -> E a
catchE m k =
  case m of
    Ok a -> Ok a
    Failed _ _ e -> k e
