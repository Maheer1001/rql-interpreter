module Main (main) where

import Control.Exception (SomeException, catch, fromException, ErrorCall(..))
import Control.Monad (when)
import qualified Lexer (alexScanTokens)
import Parser (parse, Program(..))
import ParserMonad (E(..))
import Resolver (resolveBindings, resolveQuery, ResolveError(..))
import qualified Evaluator (evaluate, EvalError(..))
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr, stdout, hSetEncoding, utf8)

import Turtle.Normaliser (showTriples)
import TypeChecker (collectConstraints, unify)
import System.Console.ANSI (hSupportsANSI)

import ErrorFormatter (formatError)
import ParseErrorFormatter (formatParseError)
import TypeErrorFormatter (formatTypeError)

main :: IO ()
main = catch main' handler

main' :: IO ()
main' = do
  supported <- hSupportsANSI stdout
  when supported (hSetEncoding stdout utf8)

  args <- getArgs
  case args of
    [] -> error "Expected a .rql file path"
    (filename : _) -> do
      rqlText <- readFile filename
      let tokens = Lexer.alexScanTokens rqlText
      case parse tokens of
        Failed token expected err -> do
          hPutStrLn stderr $ formatError err $ formatParseError rqlText token expected
          exitFailure
        Ok (Program bs qs) -> do
          env <- resolveBindings bs
          let resolved = map (resolveQuery env) qs
          let typeConstraints = collectConstraints resolved
          case unify typeConstraints of
            Left errs -> do
              mapM_ (\err -> hPutStrLn stderr $ formatTypeError err rqlText tokens) errs
              exitFailure
            Right _ ->
              mapM_ (putStr . showTriples . Evaluator.evaluate env) resolved

handler :: SomeException -> IO ()
handler e
  | Just (ResolveError m) <- fromException e =
      hPutStrLn stderr $ formatError "Resolution Error" m
  | Just (Evaluator.EvalError m) <- fromException e =
      hPutStrLn stderr $ formatError "Evaluation Error" m
  | Just (ErrorCall m) <- fromException e =
      hPutStrLn stderr $ "*** Error: " ++ m
  | otherwise =
      hPutStrLn stderr $ "*** Error: " ++ show e
