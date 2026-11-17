module Resolver (
  QueryEnvironment(..),
  ResolveError(..),
  resolveBindings, resolveQuery
) where

import RDFTypes
import qualified Turtle.Lexer (alexScanTokens)
import Turtle.Parser (parseTurtle)
import Turtle.Normaliser (normaliseTurtle)
import Parser
import qualified Data.Map.Strict as Map
import Data.Map (Map)
import Control.Monad (foldM)
import Control.Exception (Exception, throw)

data ResolveError = ResolveError String deriving (Show)
instance Exception ResolveError

throwResolveError :: String -> a
throwResolveError = throw . ResolveError

-- Environment of LET bindings
data QueryEnvironment = QueryEnvironment { 
  graphs :: Map String Graph,     -- @graphVar -> [Triple] 
  prefixes :: Map String String   -- @prefixLabel -> absolute URI
} deriving (Show)
emptyEnv :: QueryEnvironment
emptyEnv = QueryEnvironment Map.empty Map.empty


-- Load graphs and prefix bindings into the environment
resolveBindings :: [LetBinding] -> IO QueryEnvironment
resolveBindings = foldM f emptyEnv
  where
    f :: QueryEnvironment -> LetBinding -> IO QueryEnvironment
    f env (GBind varName path) = do 
      graph <- loadGraph path
      return env { graphs = Map.insert varName graph (graphs env) }
    f env (PBind prefixLabel uri) = return env { prefixes = Map.insert prefixLabel uri (prefixes env) }

loadGraph :: FilePath -> IO Graph
loadGraph path = do
  content <- readFile path
  return $ normaliseTurtle $ parseTurtle $ Turtle.Lexer.alexScanTokens content


-- Expand all UriExprVar to absolute URIs using the prefix bindings in the environment
resolveQuery :: QueryEnvironment -> Query -> Query
resolveQuery env (Query pms whereClause) = Query (map resolvePMatch pms) (resolveWhereClause whereClause)
  where
    resolvePMatch :: PatternMatch -> PatternMatch
    resolvePMatch (PMatch s p o) = PMatch (resolveNodeSymbol s) (resolveNodeSymbol p) (resolveObjSymbol o)

    resolveWhereClause :: WhereClause -> WhereClause
    resolveWhereClause (WhereClause es ops) = WhereClause (map resolveWhereElement es) ops

    resolveWhereElement :: WhereElement -> WhereElement
    resolveWhereElement (WEClause gpm ops) = WEClause (resolveGPM gpm) ops
    resolveWhereElement (WEGraphExpr expr) = WEGraphExpr (resolveGraphExpr expr)

    resolveGPM :: GPM -> GPM
    resolveGPM (GPM name pm)
      | Map.member name (graphs env) = GPM name (resolvePMatch pm)
      | Map.member name (prefixes env) = throwResolveError $ "'@" ++ name ++ "' is a prefix variable, not a graph variable"
      | otherwise = throwResolveError $ "Undefined graph variable '@" ++ name ++ "'"

    resolveSubBlock :: SubBlock -> SubBlock
    resolveSubBlock (SubBlock elements ops) = SubBlock (map resolveWhereElement elements) ops

    resolveNodeSymbol :: NodeSymbol -> NodeSymbol
    resolveNodeSymbol (NSUri expr) = NSUri (resolveUriExpr env expr)
    resolveNodeSymbol symbol = symbol

    resolveObjSymbol :: ObjectSymbol -> ObjectSymbol
    resolveObjSymbol (OSUri expr) = OSUri (resolveUriExpr env expr)
    resolveObjSymbol symbol = symbol

    resolveGraphExpr :: GraphExpr -> GraphExpr
    resolveGraphExpr (GraphAtom block) = GraphAtom (resolveSubBlock block)
    resolveGraphExpr (GraphUnion a b) = GraphUnion (resolveGraphExpr a) (resolveGraphExpr b)
    resolveGraphExpr (GraphIntersect a b) = GraphIntersect (resolveGraphExpr a) (resolveGraphExpr b)
    resolveGraphExpr (GraphExcept a b) = GraphExcept (resolveGraphExpr a) (resolveGraphExpr b)
    resolveGraphExpr (GraphOptional x) = GraphOptional (resolveGraphExpr x)

resolveUriExpr :: QueryEnvironment -> UriExpression -> UriExpression
resolveUriExpr _ uri@(UriExprUri _) = uri
resolveUriExpr env (UriExprVar name local) =
  case Map.lookup name (prefixes env) of
    Just prefix -> UriExprUri (prefix ++ local)
    Nothing
      | Map.member name (graphs env) -> throwResolveError $ "'@" ++ name ++ "' is a graph variable, not a prefix variable"
      | otherwise -> throwResolveError $ "Undefined prefix '@" ++ name ++ "'"
