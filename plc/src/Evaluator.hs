module Evaluator (evaluate, EvalError(..)) where

import Control.Exception (Exception, throw)
import Control.Monad (foldM)
import Data.List (nub, sortBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing, listToMaybe)
import Text.Regex.TDFA ((=~))

import Parser
import RDFTypes hiding (LitInt)
import qualified RDFTypes
import Resolver (QueryEnvironment(..))

data Term = TUri URI | TStr String | TInt Int deriving (Eq, Ord, Show)
-- Solution for a variable
type Solution = Map String Term
-- Solution set for a graph pattern matching (Wherebody)
type SolutionSet = [Solution]

data EvalError = EvalError String deriving (Show)
instance Exception EvalError

-- Helper functions

throwEvalError :: String -> a
throwEvalError = throw . EvalError

toTerm :: Object -> Term
toTerm (Resource u) = TUri u
toTerm (LitStr s) = TStr s
toTerm (RDFTypes.LitInt x) = TInt x

lookupGraph :: String -> QueryEnvironment -> Graph
lookupGraph varName env = 
  case Map.lookup varName (graphs env) of
    Just graph -> graph
    Nothing -> throwEvalError $ "undefined graph '@" ++ varName ++ "'"

-- Merge two solutions into one if there are no conflicting mappings, otherwise return Nothing.
mergeSolution :: Solution -> Solution -> Maybe Solution
mergeSolution s1 s2
  | isCompatible = Just (Map.union s1 s2)
  | otherwise = Nothing
  where
    isCompatible = all (noConflict s1) (Map.toList s2)
    -- conflict: the same variable is mapped to different values in the two solutions
    noConflict :: Solution -> (String, Term) -> Bool
    noConflict solution (k, v) = case Map.lookup k solution of
      Just v' -> v == v'
      Nothing -> True

compareTriple :: RDFTypes.Triple -> RDFTypes.Triple -> Ordering
compareTriple (RDFTypes.Triple s1 p1 o1) (RDFTypes.Triple s2 p2 o2) =
  compare s1 s2 <> compare p1 p2 <> compareObject o1 o2
  where
    compareObject :: RDFTypes.Object -> RDFTypes.Object -> Ordering
    compareObject (RDFTypes.LitStr a) (RDFTypes.LitStr b) = compare a b
    compareObject (RDFTypes.LitInt a) (RDFTypes.LitInt b) = compare a b
    compareObject (RDFTypes.Resource a) (RDFTypes.Resource b) = compare a b
    compareObject x y = compare (objectSortTag x) (objectSortTag y)
      where
        objectSortTag :: RDFTypes.Object -> Int
        objectSortTag (RDFTypes.LitStr _) = 0
        objectSortTag (RDFTypes.LitInt _) = 1
        objectSortTag (RDFTypes.Resource _) = 2

-- Main evaluation function

evaluate :: QueryEnvironment -> Query -> Graph
evaluate env (Query pms (WhereClause body outputOps)) =
  let solutions = applyOutputOps outputOps $ evalWhereBody body
      result = evalPatternMatches pms solutions
  -- If ORDER BY is specified, preserve its ordering; otherwise sort lexicographically
  in if any isOrderByOp outputOps then result else sortBy compareTriple result
  where
    isOrderByOp :: OperationOnOutput -> Bool
    isOrderByOp (OpOutOrderBy _) = True
    isOrderByOp _ = False

    evalWhereBody :: [WhereElement] -> SolutionSet
    evalWhereBody = foldl applyElement [Map.empty]
      where
        applyElement :: SolutionSet -> WhereElement -> SolutionSet
        applyElement acc (WEGraphExpr (GraphOptional y)) =
          let ys = evalGraphExpr y
          in concatMap (joinOptional ys) acc
        applyElement acc e = joinSolutions acc (evalWhereElement e)

        -- left outer join:
        --   extend x with all compatible solutions from ys if any exist, otherwise keep x as-is
        joinOptional :: SolutionSet -> Solution -> SolutionSet
        joinOptional ys x =
          case [ s | Just s <- map (mergeSolution x) ys ] of
            [] -> [x]
            ss -> ss

    joinSolutions :: SolutionSet -> SolutionSet -> SolutionSet
    joinSolutions xs ys = [ solution | x <- xs, y <- ys, Just solution <- [mergeSolution x y] ]

    evalWhereElement :: WhereElement -> SolutionSet
    evalWhereElement (WEClause (GPM g pm) graphOps) =
      let graph = lookupGraph g env
          -- try to match every triple in the graph with the PatternMatch
          solutions = [ solution | triple <- graph, Just solution <- [matchTriple pm triple] ]
      in applyGraphOps graphOps solutions
    evalWhereElement (WEGraphExpr expr) = evalGraphExpr expr

    evalGraphExpr :: GraphExpr -> SolutionSet
    evalGraphExpr (GraphAtom (SubBlock es ops)) = applyGraphOps ops (evalWhereBody es)
    evalGraphExpr (GraphUnion x y) = evalGraphExpr x ++ evalGraphExpr y
    evalGraphExpr (GraphIntersect x y) = joinSolutions (evalGraphExpr x) (evalGraphExpr y)
    evalGraphExpr (GraphExcept x y) =
      let xs = evalGraphExpr x
          ys = evalGraphExpr y
      -- filter out solutions that are in conflict with a solution in ys
      in filter (\s -> all (isNothing . mergeSolution s) ys) xs
    evalGraphExpr (GraphOptional _) = 
      throwEvalError "OPTIONAL cannot be used with UNION/INTERSECT/EXCEPT."

-- (Core) Triple pattern matching

matchTriple :: PatternMatch -> Triple -> Maybe Solution
matchTriple (PMatch subjPM predPM objPM) (Triple s p o) =
  do
    s1 <- matchURI subjPM s
    s2 <- matchURI predPM p
    s3 <- matchObject objPM o
    mergeSolutions s1 s2 s3
  where
    mergeSolutions :: Solution -> Solution -> Solution -> Maybe Solution
    mergeSolutions s1 s2 s3 = foldM mergeSolution Map.empty [s1, s2, s3]

    matchURI :: NodeSymbol -> URI -> Maybe Solution
    matchURI (NSUri (UriExprUri str)) uri
      | str == uri = Just Map.empty
      | otherwise = Nothing
    matchURI (NSVar v) uri = Just (Map.singleton v (TUri uri))
    matchURI NSWildcard _ = Just Map.empty
    matchURI _ _ = Nothing

    matchObject :: ObjectSymbol -> Object -> Maybe Solution
    matchObject (OSUri (UriExprUri str)) (Resource uri)
      | str == uri = Just Map.empty
      | otherwise = Nothing
    matchObject (OSVar v) obj = Just (Map.singleton v (toTerm obj))
    matchObject OSWildcard _ = Just Map.empty
    matchObject (OSLiteral (LitInt x)) (RDFTypes.LitInt y)
      | x == y = Just Map.empty
      | otherwise = Nothing
    matchObject (OSLiteral (LitString x)) (LitStr y)
      | x == y = Just Map.empty
      | otherwise = Nothing
    matchObject _ _ = Nothing

-- Graph-level operations

applyGraphOps :: [OperationOnGraph] -> SolutionSet -> SolutionSet
applyGraphOps ops initSolutions = foldl apply initSolutions ops
  where
    apply :: SolutionSet -> OperationOnGraph -> SolutionSet
    apply acc (OpGraphFilter b) = filter (evalBoolExpr b) acc
    apply acc (OpGraphTypeIs v typeName) = filter (hasType v typeName) acc
    apply acc (OpGraphRegex v pattern) = filter (matchRegex v pattern) acc
    apply _ (OpGraphAvg _) = throwEvalError "AVG is an aggregation function and can only be used in HAVING"
    apply _ (OpGraphMax _) = throwEvalError "MAX is an aggregation function and can only be used in HAVING"
    apply _ (OpGraphMin _) = throwEvalError "MIN is an aggregation function and can only be used in HAVING"
    apply _ (OpGraphSum _) = throwEvalError "SUM is an aggregation function and can only be used in HAVING"
    apply _ (OpGraphCount _) = throwEvalError "COUNT is an aggregation function and can only be used in HAVING"

    hasType :: String -> TypeName -> Solution -> Bool
    hasType v typeName solution = case Map.lookup v solution of
      Just (TUri _) -> typeName == TypeUri
      Just (TStr _) -> typeName == TypeString
      Just (TInt _) -> typeName == TypeInt
      Nothing -> False

    matchRegex :: String -> String -> Solution -> Bool
    matchRegex v pattern solution = 
      case Map.lookup v solution of
        Just (TStr str) -> str =~ pattern
        _ -> False

    evalBoolExpr :: BoolExpr -> Solution -> Bool
    evalBoolExpr (BoolOr a b) solution = evalBoolExpr a solution || evalBoolExpr b solution
    evalBoolExpr (BoolAnd a b) solution = evalBoolExpr a solution && evalBoolExpr b solution
    evalBoolExpr (BoolNot a) solution = not (evalBoolExpr a solution)
    evalBoolExpr (BoolComp c) solution = evalComp c solution

    evalComp :: Comparison -> Solution -> Bool
    evalComp (Comp l op r) solution = applyCompOp op (evalCompExpr l solution) (evalCompExpr r solution)
      where
        applyCompOp OpEqEq a b = (a == b)
        applyCompOp OpNeq a b = (a /= b)
        applyCompOp OpGte a b = (a >= b)
        applyCompOp OpLte a b = (a <= b)
        applyCompOp OpLt a b = (a < b)
        applyCompOp OpGt a b = (a > b)

    evalCompExpr :: ComparableExpr -> Solution -> Term
    evalCompExpr (CmpUri (UriExprUri uri)) _ = TUri uri
    evalCompExpr (CmpString str) _ = TStr str
    evalCompExpr (CmpArith arithExpr) solution = evalArithExpr arithExpr solution
    evalCompExpr (CmpUri _) _ = throwEvalError "unresolved URI prefix in FILTER"
    evalCompExpr (CmpIf condition thenExpr elseExpr) solution =
      if evalBoolExpr condition solution
        then evalCompExpr thenExpr solution
        else evalCompExpr elseExpr solution

    evalArithExpr :: ArithExpr -> Solution -> Term
    evalArithExpr (ArithInt x) _ = TInt x
    evalArithExpr (ArithVar var) solution = 
      case Map.lookup var solution of
        Just term -> term
        Nothing -> throwEvalError $ "unbound variable '?" ++ var ++ "'"
    evalArithExpr expr solution = TInt (evalIntArithExpr expr solution)
      where
        evalIntArithExpr :: ArithExpr -> Solution -> Int
        evalIntArithExpr (ArithInt x) _ = x
        evalIntArithExpr (ArithVar var) s =
          case Map.lookup var s of
            Just (TInt n) -> n
            Just _ -> throwEvalError $ "'?" ++ var ++ "' is not numeric"
            Nothing -> throwEvalError $ "unbound variable '?" ++ var ++ "'"
        evalIntArithExpr (ArithAbs e) s = abs (evalIntArithExpr e s)
        evalIntArithExpr (ArithNeg e) s = negate (evalIntArithExpr e s)
        evalIntArithExpr (ArithBinOp op expr1 expr2) s = applyArithOp op (evalIntArithExpr expr1 s) (evalIntArithExpr expr2 s)
          where
            applyArithOp OpPlus x y = x + y
            applyArithOp OpMinus x y = x - y
            applyArithOp OpMul x y = x * y
            applyArithOp OpDiv _ 0 = throwEvalError "division by zero"
            applyArithOp OpDiv x y = x `div` y
            applyArithOp OpMod _ 0 = throwEvalError "modulo by zero"
            applyArithOp OpMod x y = x `mod` y

-- Output-level operations

applyOutputOps :: [OperationOnOutput] -> SolutionSet -> SolutionSet
applyOutputOps ops initSolutions
  | any isGroupHavingOp ops =
      foldl apply (evalGroupHavingOps ops initSolutions) (filter (not . isGroupHavingOp) ops)
  | otherwise = foldl apply initSolutions ops
  where
    apply :: SolutionSet -> OperationOnOutput -> SolutionSet
    apply acc OpOutDistinct = nub acc
    apply acc (OpOutOrderBy conditions) = sortBy (compareBy conditions) acc
    apply acc (OpOutFirst n) = take n acc
    apply acc (OpOutLast n) = drop (max 0 (length acc - n)) acc
    apply _ op = throwEvalError $ "(internal error) unexpected operation in apply: " ++ show op

    compareBy :: [SortCondition] -> Solution -> Solution -> Ordering
    compareBy [] _ _ = EQ
    compareBy (SortAsc v : rest) s1 s2 =
      case compare (Map.lookup v s1) (Map.lookup v s2) of
        EQ -> compareBy rest s1 s2
        x -> x
    compareBy (SortDesc v : rest) s1 s2 =
      case compare (Map.lookup v s2) (Map.lookup v s1) of
        EQ -> compareBy rest s1 s2
        x -> x

    evalGroupHavingOps :: [OperationOnOutput] -> SolutionSet -> SolutionSet
    evalGroupHavingOps allOps solutions =
      let
        maybeGroupBy = listToMaybe [ groupBy | OpOutGroup groupBy <- allOps ]
        maybeHaving = listToMaybe [ having | OpOutHaving having <- allOps ]
      in case (maybeGroupBy, maybeHaving) of
        (Nothing, _) -> throwEvalError "HAVING without GROUP BY"
        -- only GroupBy: not allowed
        (Just _, Nothing) -> throwEvalError "GROUP BY requires HAVING with an aggregate function"
        -- GroupBy and Having
        (Just gb, Just (HavingOp var aggOp)) ->
          let groups = Map.elems $ evalGroupBy gb solutions
              -- generate the result solution for the current group
              -- (note: only keep the Group By variable and the aggregation result, unbound for others)
              result group = Map.insert var (applyAggOp aggOp group) (baseForGroup gb group)
          in map result groups
      where
        evalGroupBy :: GroupBy -> SolutionSet -> Map [Term] SolutionSet
        -- combine solutions with the same key tuple by concatenating
        evalGroupBy (GroupByVars vs) sols = Map.fromListWith (++) [([getByVar v solution | v <- vs], [solution]) | solution <- sols]
        evalGroupBy (GroupByUri u) sols = Map.fromList [([TUri u], sols)]

        baseForGroup :: GroupBy -> SolutionSet -> Solution
        baseForGroup (GroupByVars vs) group = Map.fromList [(v, getByVar v (head group)) | v <- vs]
        baseForGroup (GroupByUri _) _ = Map.empty

        applyAggOp :: OperationOnGraph -> SolutionSet -> Term
        applyAggOp (OpGraphMax v) group =
          let ns = [ n | solution <- group, Just (TInt n) <- [Map.lookup v solution] ]
          in if null ns then throwEvalError $ "MAX: no numeric values for '?" ++ v ++ "'"
             else TInt $ maximum ns
        applyAggOp (OpGraphMin v) group =
          let ns = [ n | solution <- group, Just (TInt n) <- [Map.lookup v solution] ]
          in if null ns then throwEvalError $ "MIN: no numeric values for '?" ++ v ++ "'"
             else TInt $ minimum ns
        applyAggOp (OpGraphSum v) group = TInt $ sum [ n | solution <- group, Just (TInt n) <- [Map.lookup v solution] ]
        applyAggOp (OpGraphAvg v) group
          | null ns = throwEvalError $ "AVG: no numeric values for '?" ++ v ++ "'"
          | otherwise = TInt $ sum ns `div` length ns
          where ns = [ n | solution <- group, Just (TInt n) <- [Map.lookup v solution] ]
        applyAggOp (OpGraphCount (CountVar v)) group = TInt $ length [ () | solution <- group, Just _ <- [Map.lookup v solution] ]
        applyAggOp (OpGraphCount (CountUri u)) group = TInt $ length [ () | solution <- group, TUri u `elem` Map.elems solution ]
        applyAggOp op _ = throwEvalError $ "unsupported aggregation in HAVING: " ++ show op

        getByVar :: String -> Solution -> Term
        getByVar var solution = case Map.lookup var solution of
          Just term -> term
          Nothing -> throwEvalError $ "GROUP BY variable '?" ++ var ++ "' not found"

    isGroupHavingOp :: OperationOnOutput -> Bool
    isGroupHavingOp (OpOutGroup _) = True
    isGroupHavingOp (OpOutHaving _) = True
    isGroupHavingOp _ = False

-- CONSTRUCT

evalPatternMatches :: [PatternMatch] -> SolutionSet -> Graph
evalPatternMatches pms solutions = 
  nub [ triple | pm <- pms, solution <- solutions, triple <- evalPatternMatch pm solution ]
  where
    evalPatternMatch :: PatternMatch -> Solution -> [Triple]
    evalPatternMatch (PMatch subjPM predPM objPM) solution =
      case (evalNodeSymbol subjPM solution, evalNodeSymbol predPM solution, evalObjectSymbol objPM solution) of
        (Just s, Just p, Just o) -> [Triple s p o]
        _ -> []

    evalNodeSymbol :: NodeSymbol -> Solution -> Maybe URI
    evalNodeSymbol (NSUri (UriExprUri u)) _ = Just u
    evalNodeSymbol (NSUri (UriExprVar _ _)) _ = throwEvalError "unresolved URI prefix in CONSTRUCT"
    evalNodeSymbol (NSVar v) solution = 
      case Map.lookup v solution of
        Just (TUri u) -> Just u
        _ -> Nothing
    evalNodeSymbol NSWildcard _ = throwEvalError "wildcard in CONSTRUCT (subject/predicate)"

    evalObjectSymbol :: ObjectSymbol -> Solution -> Maybe Object
    evalObjectSymbol (OSUri (UriExprUri u)) _ = Just (Resource u)
    evalObjectSymbol (OSUri (UriExprVar _ _)) _ = throwEvalError "unresolved URI prefix in CONSTRUCT"
    evalObjectSymbol (OSVar v) solution = 
      case Map.lookup v solution of
        Just (TUri u) -> Just (Resource u)
        Just (TStr s) -> Just (LitStr s)
        Just (TInt n) -> Just (RDFTypes.LitInt n)
        Nothing -> Nothing
    evalObjectSymbol (OSLiteral (LitInt n)) _ = Just (RDFTypes.LitInt n)
    evalObjectSymbol (OSLiteral (LitString s)) _ = Just (LitStr s)
    evalObjectSymbol OSWildcard _ = throwEvalError "wildcard in CONSTRUCT (object)"
