-- | Test suite for the RQL interpreter.
--
-- Run with @cabal test@ (or @stack test@) from the @plc/@ directory. Every
-- stage of the pipeline is covered, from the RQL lexer through to the
-- evaluator, plus the bundled example programs end to end:
--
--   1. RQL lexer         : source text -> tokens
--   2. Turtle front end  : .ttl text -> normalised triples
--   3. Example programs  : every query listed in test/golden.txt is run and
--                          its output compared with test/expected/<name>.out
--   4. Query constructs  : a small inline program per language feature
--   5. Error paths       : lexical, parse, type, resolution, IO and
--                          evaluation errors are reported as such
--
-- test/golden.txt is also read by the setup-check scripts
-- (scripts/setup-check.sh and scripts/setup-check.ps1), which run the real
-- plc-exe binary on the same programs.
module Main (main) where

import Control.Exception (ErrorCall (..), IOException, SomeException, evaluate, fromException, try)
import Control.Monad (forM)
import Data.List (foldl', intercalate, isInfixOf, isPrefixOf)
import qualified Evaluator
import qualified Lexer
import Parser (Program (..), parse)
import ParserMonad (E (..))
import Resolver (ResolveError (..), resolveBindings, resolveQuery)
import System.Directory (doesDirectoryExist, getCurrentDirectory, withCurrentDirectory)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (BufferMode (..), hSetBuffering, stdout)
import qualified Turtle.Lexer as TL
import Turtle.Normaliser (Object (..), Triple (..), normaliseTurtle, showTriples)
import qualified Turtle.Parser as TP
import TypeChecker (collectConstraints, unify)

------------------------------------------------------------------------------
-- Minimal test harness

data Result = Pass | Fail String

data Test = Test String (IO Result)

data Group = Group String [Test]

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  cwd <- getCurrentDirectory
  isPlcDir <- doesDirectoryExist (cwd </> "data")
  let plcDir = if isPlcDir then cwd else cwd </> "plc"
      dataDir = plcDir </> "data"
      testDir = plcDir </> "test"

  golden <- goldenTests dataDir testDir
  let groups =
        [ Group "RQL lexer" lexerTests,
          Group "Turtle front end" (turtleTests dataDir),
          Group "Example programs (test/golden.txt)" golden,
          Group "Query constructs" (constructTests (dataDir </> "part1")),
          Group "Error paths" (errorTests dataDir)
        ]

  results <- forM groups $ \(Group gname tests) -> do
    putStrLn ("\n== " ++ gname)
    forM tests $ \(Test tname act) -> do
      r <- act `catchAll` (\e -> pure (Fail ("uncaught exception: " ++ show e)))
      case r of
        Pass -> putStrLn ("  PASS " ++ tname) >> pure Nothing
        Fail msg -> do
          putStrLn ("  FAIL " ++ tname)
          putStrLn (indent msg)
          pure (Just (gname ++ " / " ++ tname))

  let flat = concat results
      failures = [f | Just f <- flat]
      total = length flat
  putStrLn ""
  if null failures
    then putStrLn ("All tests passed (" ++ show total ++ ").")
    else do
      putStrLn ("FAILED " ++ show (length failures) ++ " of " ++ show total ++ ":")
      mapM_ (putStrLn . ("  - " ++)) failures
      exitFailure
  where
    catchAll :: IO a -> (SomeException -> IO a) -> IO a
    catchAll act h = try act >>= either h pure
    indent = unlines . map ("      " ++) . lines

------------------------------------------------------------------------------
-- Running RQL programs through the library pipeline

-- | Run RQL source text with the given working directory (graph files in
-- @LET@ bindings are resolved relative to it). Returns the Turtle output or a
-- tagged error string: "LexicalError:", "ParseError:", "TypeError:",
-- "ResolveError:", "EvalError:", "IOError:" or "Error:".
runSourceIn :: FilePath -> String -> IO (Either String String)
runSourceIn dir src = withCurrentDirectory dir $ do
  r <- try $ do
    let tokens = Lexer.alexScanTokens src
    case parse tokens of
      Failed _ _ msg
        | "Lexical" `isPrefixOf` msg -> pure (Left ("LexicalError: " ++ msg))
        | otherwise -> pure (Left ("ParseError: " ++ msg))
      Ok (Program bs qs) -> do
        env <- resolveBindings bs
        let resolved = map (resolveQuery env) qs
        case unify (collectConstraints resolved) of
          Left errs -> pure (Left ("TypeError: " ++ show errs))
          Right _ -> do
            let out = concatMap (showTriples . Evaluator.evaluate env) resolved
            _ <- evaluate (forceString out)
            pure (Right out)
  pure $ case r of
    Right v -> v
    Left e -> Left (describe e)
  where
    forceString = foldl' (\n c -> c `seq` n + 1) (0 :: Int)

describe :: SomeException -> String
describe e
  | Just (ResolveError m) <- fromException e = "ResolveError: " ++ m
  | Just (Evaluator.EvalError m) <- fromException e = "EvalError: " ++ m
  | Just ioe <- fromException e = "IOError: " ++ show (ioe :: IOException)
  | Just (ErrorCall m) <- fromException e = "Error: " ++ m
  | otherwise = "Error: " ++ show e

runFileIn :: FilePath -> FilePath -> IO (Either String String)
runFileIn dir rql = do
  src <- withCurrentDirectory dir (readFile rql)
  _ <- evaluate (length src)
  runSourceIn dir src

-- | Ignore blank lines and CR characters so CRLF checkouts compare equal.
normalise :: String -> [String]
normalise = filter (not . null) . lines . filter (/= '\r')

expectOutput :: String -> Either String String -> Result
expectOutput expected res = case res of
  Left err -> Fail ("expected success, got error:\n" ++ err)
  Right actual
    | normalise expected == normalise actual -> Pass
    | otherwise ->
        Fail ("output mismatch\n--- expected ---\n" ++ expected ++ "\n--- actual ---\n" ++ actual)

expectErr :: Show a => String -> String -> Either String a -> Result
expectErr tag needle res = case res of
  Left err
    | tag `isPrefixOf` err && needle `isInfixOf` err -> Pass
    | otherwise -> Fail ("expected " ++ tag ++ " mentioning " ++ show needle ++ ", got:\n" ++ err)
  Right out -> Fail ("expected " ++ tag ++ ", but succeeded with:\n" ++ show out)

------------------------------------------------------------------------------
-- 1. RQL lexer

lexerTests :: [Test]
lexerTests =
  [ tok "LET binding with graph file" "LET @g = <g.ttl>"
      [Lexer.TokenLet, Lexer.TokenGraph "g", Lexer.TokenEq, Lexer.TokenGraphFile "g.ttl"],
    tok "URI vs graph file literal" "<http://example.org/ont/> <data/x.ttl>"
      [Lexer.TokenURI "http://example.org/ont/", Lexer.TokenGraphFile "data/x.ttl"],
    tok "variables, ints, strings" "?x1 42 \"hi there\""
      [Lexer.TokenVar "x1", Lexer.TokenInt 42, Lexer.TokenString "hi there"],
    tok "prefixed local name" "@ont:hasAge"
      [Lexer.TokenGraph "ont", Lexer.TokenURIChar "hasAge"],
    tok "multi-word keywords allow any whitespace" "GROUP   BY ORDER\tBY"
      [Lexer.TokenGroupBy, Lexer.TokenOrderBy],
    tok "comparison and boolean operators" "== != >= <= < > && || !"
      [ Lexer.TokenEqEq, Lexer.TokenNeq, Lexer.TokenGte, Lexer.TokenLte,
        Lexer.TokenLAngle, Lexer.TokenRAngle, Lexer.TokenAnd, Lexer.TokenOr, Lexer.TokenNot ],
    tok "comments are skipped" "-- a comment\nCONSTRUCT -- trailing\nWHERE"
      [Lexer.TokenConstruct, Lexer.TokenWhere],
    tok "unknown character becomes an error token" "?a $"
      [Lexer.TokenVar "a", Lexer.TokenError "$"]
  ]
  where
    tok name src expected = Test name $ do
      let actual = Lexer.getTokens (Lexer.alexScanTokens src)
      pure $
        if actual == expected
          then Pass
          else Fail ("expected " ++ show expected ++ "\n     got " ++ show actual)

------------------------------------------------------------------------------
-- 2. Turtle front end

parseTtl :: String -> IO (Either String [Triple])
parseTtl src = do
  r <- try (evaluate (forceTriples (normaliseTurtle (TP.parseTurtle (TL.alexScanTokens src)))))
  pure $ either (Left . describe) Right r
  where
    forceTriples ts = length (showTriples ts) `seq` ts

turtleTests :: FilePath -> [Test]
turtleTests dataDir =
  [ Test "test_turtle.ttl: @base, @prefix, ';' and ',' lists, duplicates removed" $ do
      src <- readFile (dataDir </> "test" </> "test_turtle.ttl")
      r <- parseTtl src
      let ex = "http://example.org/"
          ont = "http://ont.example.org/"
          nmg = ex ++ "nmg"
          expected =
            [ Triple nmg (ont ++ "name") (LitStr "Nick Gibbins"),
              Triple nmg (ont ++ "age") (LitInt 23),
              Triple nmg (ont ++ "teaches") (Resource (ex ++ "comp2312")),
              Triple nmg (ont ++ "teaches") (Resource (ex ++ "comp2322")),
              Triple nmg (ont ++ "worksFor") (Resource (ex ++ "uos"))
            ]
      pure $ case r of
        Right ts | ts == expected -> Pass
        Right ts -> Fail ("got " ++ show ts)
        Left err -> Fail err,
    Test "absolute URIs ignore @base" $ do
      r <- parseTtl "@base <http://a.org/> .\n<http://b.org/x> <http://b.org/p> 1 ."
      pure $ case r of
        Right [Triple "http://b.org/x" "http://b.org/p" (LitInt 1)] -> Pass
        other -> Fail (show other),
    Test "comments are skipped" $ do
      r <- parseTtl "# header\n<http://a/s> <http://a/p> \"o\" . # trailing"
      pure $ case r of
        Right [Triple "http://a/s" "http://a/p" (LitStr "o")] -> Pass
        other -> Fail (show other),
    Test "syntax error is reported with a position" $ do
      r <- parseTtl "<http://a/s> <http://a/p> ."
      pure (expectErr "Error:" "Parse error at line 1" r),
    Test "relative @prefix URI is rejected" $ do
      r <- parseTtl "@prefix o: <rel/> .\n<http://a/s> o:p 1 ."
      pure (expectErr "Error:" "Directive requires absolute URI" r)
  ]

------------------------------------------------------------------------------
-- 3. Example programs, driven by test/golden.txt

-- | Each non-comment line of golden.txt is: <run dir> <query> <expected>.
-- The run dir is relative to plc/data, the query is relative to the run dir
-- and the expected file is relative to plc/test/expected.
goldenTests :: FilePath -> FilePath -> IO [Test]
goldenTests dataDir testDir = do
  manifest <- readFile (testDir </> "golden.txt")
  _ <- evaluate (length manifest)
  let entries = [ws | l <- lines (filter (/= '\r') manifest), let ws = words l, not (null ws), not ("#" `isPrefixOf` head ws)]
  forM entries $ \ws -> case ws of
    [dir, rql, out] -> pure $ Test (rql ++ " (from data/" ++ dir ++ ")") $ do
      expected <- readFile (testDir </> "expected" </> out)
      expectOutput expected <$> runFileIn (dataDir </> dir) rql
    _ -> pure $ Test (unwords ws) (pure (Fail "malformed line in test/golden.txt"))

------------------------------------------------------------------------------
-- 4. Query constructs (inline programs, run from data/part1)

prelude :: String
prelude =
  unlines
    [ "LET @foo = <foo.ttl>",
      "LET @bar = <bar.ttl>",
      "LET @baz = <baz.ttl>",
      "LET @quux = <quux.ttl>",
      "LET @ont = <http://example.org/ont/>"
    ]

constructTests :: FilePath -> [Test]
constructTests part1 =
  [ q "basic pattern with prefixed predicate"
      "CONSTRUCT { ?s @ont:name ?n } WHERE { @bar { ?s @ont:name ?n } }"
      [ "<http://example.org/bar/carol> <http://example.org/ont/name> \"Carol\" .",
        "<http://example.org/bar/dave> <http://example.org/ont/name> \"Dave\" .",
        "<http://example.org/bob> <http://example.org/ont/name> \"Bob\" .",
        "<http://example.org/shared> <http://example.org/ont/name> \"Same\" ." ],
    q "literal object in pattern + constant in template"
      "CONSTRUCT { ?s @ont:isTwentyOne \"yes\" } WHERE { @baz { ?s @ont:hasAge 21 } }"
      [ "<http://example.org/baz/carol> <http://example.org/ont/isTwentyOne> \"yes\" .",
        "<http://example.org/baz/frank> <http://example.org/ont/isTwentyOne> \"yes\" ." ],
    q "wildcard _"
      "CONSTRUCT { ?s @ont:seen 1 } WHERE { @foo { ?s @ont:email _ } }"
      ["<http://example.org/foo/alice> <http://example.org/ont/seen> 1 ."],
    q "INTERSECT"
      "CONSTRUCT { ?s @ont:name ?n } WHERE { { @foo { ?s @ont:name ?n } } INTERSECT { @foo { ?s @ont:age ?a } } }"
      [ "<http://example.org/bob> <http://example.org/ont/name> \"Bob\" .",
        "<http://example.org/foo/alice> <http://example.org/ont/name> \"Alice\" .",
        "<http://example.org/shared> <http://example.org/ont/name> \"Same\" ." ],
    q "EXCEPT"
      "CONSTRUCT { ?s @ont:name ?n } WHERE { { @foo { ?s @ont:name ?n } } EXCEPT { @foo { ?s @ont:email ?e } } }"
      [ "<http://example.org/bob> <http://example.org/ont/name> \"Bob\" .",
        "<http://example.org/shared> <http://example.org/ont/name> \"Same\" ." ],
    q "OPTIONAL with multi-triple template"
      "CONSTRUCT { ?s @ont:name ?n } . { ?s @ont:email ?e } WHERE { @foo { ?s @ont:name ?n } OPTIONAL { @foo { ?s @ont:email ?e } } }"
      [ "<http://example.org/bob> <http://example.org/ont/name> \"Bob\" .",
        "<http://example.org/foo/alice> <http://example.org/ont/email> \"alice@example.org\" .",
        "<http://example.org/foo/alice> <http://example.org/ont/name> \"Alice\" .",
        "<http://example.org/shared> <http://example.org/ont/name> \"Same\" ." ],
    q "FILTER with &&"
      "CONSTRUCT { ?s @ont:hasAge ?a } WHERE { @baz { ?s @ont:hasAge ?a } FILTER(?a > 18 && ?a < 30) }"
      [ "<http://example.org/baz/carol> <http://example.org/ont/hasAge> 21 .",
        "<http://example.org/baz/eve> <http://example.org/ont/hasAge> 25 .",
        "<http://example.org/baz/frank> <http://example.org/ont/hasAge> 21 ." ],
    q "FILTER with ||"
      "CONSTRUCT { ?s @ont:hasAge ?a } WHERE { @baz { ?s @ont:hasAge ?a } FILTER(?a == 15 || ?a == 100) }"
      [ "<http://example.org/baz/dave> <http://example.org/ont/hasAge> 15 .",
        "<http://example.org/baz/grace> <http://example.org/ont/hasAge> 100 ." ],
    q "FILTER with !"
      "CONSTRUCT { ?s @ont:hasAge ?a } WHERE { @baz { ?s @ont:hasAge ?a } FILTER(!(?a >= 21)) }"
      [ "<http://example.org/baz/bob> <http://example.org/ont/hasAge> 17 .",
        "<http://example.org/baz/dave> <http://example.org/ont/hasAge> 15 ." ],
    q "arithmetic: * - % ABS and unary minus"
      "CONSTRUCT { ?s @ont:hasAge ?a } WHERE { @baz { ?s @ont:hasAge ?a } FILTER(?a * 2 - 10 % 3 == 41 || ABS(-?a) == 15) }"
      [ "<http://example.org/baz/carol> <http://example.org/ont/hasAge> 21 .",
        "<http://example.org/baz/dave> <http://example.org/ont/hasAge> 15 .",
        "<http://example.org/baz/frank> <http://example.org/ont/hasAge> 21 ." ],
    q "string equality"
      "CONSTRUCT { ?s @ont:name ?n } WHERE { @foo { ?s @ont:name ?n } FILTER(?n == \"Bob\") }"
      ["<http://example.org/bob> <http://example.org/ont/name> \"Bob\" ."],
    q "URI inequality"
      "CONSTRUCT { ?s @ont:name ?n } WHERE { @foo { ?s @ont:name ?n } FILTER(?s != <http://example.org/shared>) }"
      [ "<http://example.org/bob> <http://example.org/ont/name> \"Bob\" .",
        "<http://example.org/foo/alice> <http://example.org/ont/name> \"Alice\" ." ],
    q "TYPE(?o) = STRING"
      "CONSTRUCT { ?s ?p ?o } WHERE { @foo { ?s ?p ?o } TYPE(?o) = STRING }"
      [ "<http://example.org/bob> <http://example.org/ont/name> \"Bob\" .",
        "<http://example.org/foo/alice> <http://example.org/ont/email> \"alice@example.org\" .",
        "<http://example.org/foo/alice> <http://example.org/ont/name> \"Alice\" .",
        "<http://example.org/shared> <http://example.org/ont/name> \"Same\" ." ],
    q "TYPE(?o) = INT"
      "CONSTRUCT { ?s ?p ?o } WHERE { @foo { ?s ?p ?o } TYPE(?o) = INT }"
      [ "<http://example.org/bob> <http://example.org/ont/age> 28 .",
        "<http://example.org/foo/alice> <http://example.org/ont/age> 30 .",
        "<http://example.org/shared> <http://example.org/ont/age> 1 ." ],
    q "GROUP BY + HAVING SUM (graphs are sets, duplicate triples count once)"
      "CONSTRUCT { ?s @ont:total ?t } WHERE { @quux { ?s @ont:price ?p } } GROUP BY (?s) HAVING (?t = SUM(?p))"
      [ "<http://example.org/quux/gadget> <http://example.org/ont/total> 276 .",
        "<http://example.org/quux/thing> <http://example.org/ont/total> 3 .",
        "<http://example.org/quux/widget> <http://example.org/ont/total> 50 ." ],
    q "GROUP BY + HAVING MIN"
      "CONSTRUCT { ?s @ont:min ?t } WHERE { @quux { ?s @ont:price ?p } } GROUP BY (?s) HAVING (?t = MIN(?p))"
      [ "<http://example.org/quux/gadget> <http://example.org/ont/min> 75 .",
        "<http://example.org/quux/thing> <http://example.org/ont/min> 3 .",
        "<http://example.org/quux/widget> <http://example.org/ont/min> 10 ." ],
    q "GROUP BY + HAVING MAX"
      "CONSTRUCT { ?s @ont:max ?t } WHERE { @quux { ?s @ont:price ?p } } GROUP BY (?s) HAVING (?t = MAX(?p))"
      [ "<http://example.org/quux/gadget> <http://example.org/ont/max> 101 .",
        "<http://example.org/quux/thing> <http://example.org/ont/max> 3 .",
        "<http://example.org/quux/widget> <http://example.org/ont/max> 25 ." ],
    q "GROUP BY + HAVING AVG (integer division)"
      "CONSTRUCT { ?s @ont:avg ?t } WHERE { @quux { ?s @ont:price ?p } } GROUP BY (?s) HAVING (?t = AVG(?p))"
      [ "<http://example.org/quux/gadget> <http://example.org/ont/avg> 92 .",
        "<http://example.org/quux/thing> <http://example.org/ont/avg> 3 .",
        "<http://example.org/quux/widget> <http://example.org/ont/avg> 16 ." ],
    q "GROUP BY over two variables (space separated)"
      "CONSTRUCT { ?s ?p ?m } WHERE { @quux { ?s ?p ?o } } GROUP BY (?s ?p) HAVING (?m = MAX(?o))"
      [ "<http://example.org/quux/gadget> <http://example.org/ont/price> 101 .",
        "<http://example.org/quux/thing> <http://example.org/ont/price> 3 .",
        "<http://example.org/quux/widget> <http://example.org/ont/price> 25 ." ],
    q "ORDER BY bare variable (ascending) + FIRST"
      "CONSTRUCT { ?s @ont:hasAge ?a } WHERE { @baz { ?s @ont:hasAge ?a } } ORDER BY ?a FIRST(2)"
      [ "<http://example.org/baz/dave> <http://example.org/ont/hasAge> 15 .",
        "<http://example.org/baz/bob> <http://example.org/ont/hasAge> 17 ." ],
    q "DISTINCT"
      "CONSTRUCT { ?s @ont:price ?p } WHERE { @quux { ?s @ont:price ?p } } DISTINCT"
      [ "<http://example.org/quux/gadget> <http://example.org/ont/price> 75 .",
        "<http://example.org/quux/gadget> <http://example.org/ont/price> 100 .",
        "<http://example.org/quux/gadget> <http://example.org/ont/price> 101 .",
        "<http://example.org/quux/thing> <http://example.org/ont/price> 3 .",
        "<http://example.org/quux/widget> <http://example.org/ont/price> 10 .",
        "<http://example.org/quux/widget> <http://example.org/ont/price> 15 .",
        "<http://example.org/quux/widget> <http://example.org/ont/price> 25 ." ],
    q "two queries in one program are output in order"
      ( "CONSTRUCT { ?s @ont:name ?n } WHERE { @bar { ?s @ont:name ?n } FILTER(?n == \"Dave\") }\n"
          ++ "CONSTRUCT { ?s @ont:name ?n } WHERE { @bar { ?s @ont:name ?n } FILTER(?n == \"Carol\") }" )
      [ "<http://example.org/bar/dave> <http://example.org/ont/name> \"Dave\" .",
        "<http://example.org/bar/carol> <http://example.org/ont/name> \"Carol\" ." ]
  ]
  where
    q name body expected = Test name $
      expectOutput (intercalate "\n" expected) <$> runSourceIn part1 (prelude ++ body)

------------------------------------------------------------------------------
-- 5. Error paths

errorTests :: FilePath -> [Test]
errorTests dataDir =
  [ file "ParseError:" "" "test/parseError.rql (missing LET, truncated WHERE)" ("test" </> "parseError.rql"),
    file "ParseError:" "" "test/test_multi_groupBy.rql (comma-separated GROUP BY vars are not RQL syntax)" ("test" </> "test_multi_groupBy.rql"),
    file "TypeError:" "" "type-checker/test_and.rql" ("test" </> "type-checker" </> "test_and.rql"),
    file "TypeError:" "" "type-checker/test_multi_conflicts.rql" ("test" </> "type-checker" </> "test_multi_conflicts.rql"),
    file "TypeError:" "" "type-checker/typeError.rql" ("test" </> "type-checker" </> "typeError.rql"),
    ok "type-checker/test_or.rql type-checks" ("test" </> "type-checker" </> "test_or.rql"),
    ok "type-checker/test_or_null.rql type-checks" ("test" </> "type-checker" </> "test_or_null.rql"),
    file "EvalError:" "unbound variable '?x'" "test/evalError.rql (unbound variable in FILTER)" ("test" </> "evalError.rql"),
    src "LexicalError:" "" "unknown character in RQL source"
      "LET @foo = <part1/foo.ttl>\nCONSTRUCT { ?s ?p ?o } WHERE { @foo { ?s ?p ?o } } $",
    src "ParseError:" "" "query without any LET binding"
      "CONSTRUCT { ?s ?p ?o } WHERE { }",
    src "ResolveError:" "@nope" "undefined graph variable"
      "LET @foo = <part1/foo.ttl>\nCONSTRUCT { ?s ?p ?o } WHERE { @nope { ?s ?p ?o } }",
    src "IOError:" "does_not_exist.ttl" "missing .ttl file"
      "LET @x = <does_not_exist.ttl>\nCONSTRUCT { ?s ?p ?o } WHERE { @x { ?s ?p ?o } }"
  ]
  where
    file tag needle name path = Test name (expectErr tag needle <$> runFileIn dataDir path)
    src tag needle name s = Test name (expectErr tag needle <$> runSourceIn dataDir s)
    ok name path = Test name $ do
      r <- runFileIn dataDir path
      pure $ case r of
        Right _ -> Pass
        Left err -> Fail ("expected success, got:\n" ++ err)
