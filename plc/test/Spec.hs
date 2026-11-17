module Main (main) where

import Control.Exception (SomeException, try)
import Data.List (intercalate, isPrefixOf)
import qualified Lexer
import qualified Evaluator
import Parser (parse, Program(..))
import ParserMonad (E(..))
import Resolver (resolveBindings, resolveQuery)
import System.Directory (doesDirectoryExist, getCurrentDirectory, withCurrentDirectory)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import qualified Turtle.Normaliser as Turtle
import TypeChecker (collectConstraints, unify)

data TestResult = Pass | Fail String

main :: IO ()
main = do
  cwd <- getCurrentDirectory
  isPlcDir <- doesDirectoryExist (cwd </> "data")
  let plcDir = if isPlcDir then cwd else cwd </> "plc"
      dataDir = plcDir </> "data"
      part1Dir = dataDir </> "part1"
      part2Dir = dataDir </> "part2"
      expectedDir = plcDir </> "test" </> "expected"

  results <- withCurrentDirectory dataDir $ sequence
    [ 
      expectOutputIn part1Dir "t1.rql" (expectedDir </> "t1.out"),
      expectOutputIn part1Dir "t2.rql" (expectedDir </> "t2.out"),
      expectOutputIn part1Dir "t3.rql" (expectedDir </> "t3.out"),
      expectOutputIn part1Dir "t4.rql" (expectedDir </> "t4.out"),
      expectOutputIn part1Dir "t5.rql" (expectedDir </> "t5.out"),
      expectOutputIn part2Dir "t6.rql" (expectedDir </> "t6.out"),
      expectOutputIn part2Dir "t7.rql" (expectedDir </> "t7.out"),
      expectOutputIn part2Dir "t8.rql" (expectedDir </> "t8.out"),
      expectOutputIn part2Dir "t9.rql" (expectedDir </> "t9.out"),
      expectOutputIn part2Dir "t10.rql" (expectedDir </> "t10.out"),
      expectOutputIn (dataDir </> "test") "test_order.rql" (expectedDir </> "test_order.out"),
      expectError "TypeError:" ("test" </> "type-checker" </> "test_and.rql"),
      expectSuccess ("test" </> "type-checker" </> "test_or.rql"),
      expectSuccess ("test" </> "type-checker" </> "test_or_null.rql"),
      expectError "TypeError:" ("test" </> "type-checker" </> "test_multi_conflicts.rql"),
      expectError "TypeError:" ("test" </> "type-checker" </> "typeError.rql"),
      expectError "ParseError:" ("test" </> "parseError.rql")
    ]

  let failures = [ msg | Fail msg <- results ]
  if null failures
    then putStrLn ("All tests passed (" ++ show (length results) ++ ").")
    else do
      putStrLn ("FAILED (" ++ show (length failures) ++ "/" ++ show (length results) ++ "):")
      putStrLn (intercalate "\n\n" failures)
      exitFailure

expectOutput :: FilePath -> FilePath -> IO TestResult
expectOutput rqlPath expectedPath = do
  expected <- readFile expectedPath
  actualOrErr <- runRqlFile rqlPath
  pure $ case actualOrErr of
    Left err -> Fail (rqlPath ++ ": expected success, got error:\n" ++ err)
    Right actual ->
      if normalise expected == normalise actual
        then Pass
        else Fail (rqlPath ++ ": output mismatch\n--- expected ---\n" ++ expected ++ "\n--- actual ---\n" ++ actual)

expectOutputIn :: FilePath -> FilePath -> FilePath -> IO TestResult
expectOutputIn dir rqlPath expectedPath = withCurrentDirectory dir (expectOutput rqlPath expectedPath)

expectSuccess :: FilePath -> IO TestResult
expectSuccess rqlPath = do
  res <- runRqlFile rqlPath
  pure $ case res of
    Left err -> Fail (rqlPath ++ ": expected success, got:\n" ++ err)
    Right _ -> Pass

expectError :: String -> FilePath -> IO TestResult
expectError tag rqlPath = do
  res <- runRqlFile rqlPath
  pure $ case res of
    Left err
      | tag `isPrefixOf` err -> Pass
      | otherwise -> Fail (rqlPath ++ ": expected " ++ tag ++ ", got:\n" ++ err)
    Right out -> Fail (rqlPath ++ ": expected " ++ tag ++ ", but succeeded with:\n" ++ out)

runRqlFile :: FilePath -> IO (Either String String)
runRqlFile rqlPath = do
  e <- try (readFile rqlPath) :: IO (Either SomeException String)
  case e of
    Left ex -> pure (Left ("IOError: " ++ show ex))
    Right rqlText -> do
      let tokens = Lexer.alexScanTokens rqlText
      case parse tokens of
        Failed _ _ msg -> pure (Left ("ParseError: " ++ msg))
        Ok (Program bs qs) -> do
          env <- resolveBindings bs
          let resolved = map (resolveQuery env) qs
          case unify (collectConstraints resolved) of
            Left errs -> pure (Left ("TypeError: " ++ show (head errs)))
            Right _ -> pure (Right (concatMap (Turtle.showTriples . Evaluator.evaluate env) resolved))

normalise :: String -> String
normalise = unlines . filter (not . null) . lines
