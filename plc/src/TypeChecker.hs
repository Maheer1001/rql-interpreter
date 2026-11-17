module TypeChecker (collectConstraints, unify, TypeError(..), TypeEnv) where

import Parser
import qualified Data.Map as Map
import Data.Map (Map)
import Data.List (nub, intersect)
import Data.Either (partitionEithers)

data RDFType = TUri | TInt | TStr | TGraph | TUnknown | TOr [RDFType]
  deriving(Eq, Show)
type Constraints = Map String [RDFType]
type TypeEnv = Map String RDFType
data TypeError = TypeConflict String [RDFType]
  deriving(Show)

unify :: Constraints -> Either [TypeError] TypeEnv
unify constraints =
  let f (k, v) = case unifyVar k v of
                    Left e -> Left e
                    Right t -> Right (k, t)
      (errors, successes) = partitionEithers (map f (Map.toList constraints))
  in if null errors then Right (Map.fromList successes) else Left errors
  where
    -- Each constraint represents a set of allowed types.
    -- The variable's type is the intersection of all such sets.
    unifyVar :: String -> [RDFType] -> Either TypeError RDFType
    unifyVar name types =
      case map toSet (filter (/= TUnknown) types) of
        [] -> Right TUnknown
        sets -> case foldr1 intersect sets of
          [] -> Left (TypeConflict name (nub (concat sets)))
          (t:_) -> Right t

toSet :: RDFType -> [RDFType]
toSet (TOr ts) = ts
toSet t = [t]


mergeConstraints :: Constraints -> Constraints -> Constraints
mergeConstraints = Map.unionWith (++)

mergeAll :: [Constraints] -> Constraints
mergeAll = foldr mergeConstraints Map.empty

collectConstraints :: [Query] -> Constraints
collectConstraints = mergeAll . map collect
  where
    collect :: Query -> Constraints
    collect (Query pattern whereClause) =
      mergeAll $ typeWhereClause whereClause : map typePatternMatch pattern

typePatternMatch :: PatternMatch -> Constraints
typePatternMatch (PMatch s p o) =
    mergeAll [inferNS s TUri, inferNS p TUri, inferOS o TUnknown]
    where
        inferNS (NSVar name) rdfType = Map.singleton name [rdfType]
        inferNS _ _ = Map.empty
        inferOS (OSVar name) rdfType = Map.singleton name [rdfType]
        inferOS _ _ = Map.empty

typeWhereClause :: WhereClause -> Constraints
typeWhereClause (WhereClause element opsOnOutput) = mergeAll $ map typeWhereElement element ++ map typeOperationOnOutput opsOnOutput

typeWhereElement :: WhereElement -> Constraints
typeWhereElement (WEClause (GPM _ pm) opsGraph) = mergeAll $ typePatternMatch pm : map typeOperationOnGraph opsGraph
typeWhereElement (WEGraphExpr graphExpr) = typeGraphExpr graphExpr

typeGraphExpr :: GraphExpr -> Constraints
typeGraphExpr (GraphAtom (SubBlock element opsOnGraph)) = mergeAll $ map typeWhereElement element ++ map typeOperationOnGraph opsOnGraph
typeGraphExpr (GraphUnion graphExpr1 graphExpr2) = mergeAll $ [typeGraphExpr graphExpr1, typeGraphExpr graphExpr2]
typeGraphExpr (GraphIntersect graphExpr1 graphExpr2) = mergeAll $ [typeGraphExpr graphExpr1, typeGraphExpr graphExpr2]
typeGraphExpr (GraphExcept graphExpr1 graphExpr2) = mergeAll $ [typeGraphExpr graphExpr1, typeGraphExpr graphExpr2]
typeGraphExpr (GraphOptional graphExpr) = typeGraphExpr graphExpr


typeOperationOnOutput :: OperationOnOutput -> Constraints
typeOperationOnOutput (OpOutHaving (HavingOp varName opOnGraph)) = mergeAll [Map.singleton varName [returnType opOnGraph], typeOperationOnGraph opOnGraph]
typeOperationOnOutput _ = Map.empty

typeOperationOnGraph :: OperationOnGraph -> Constraints
typeOperationOnGraph (OpGraphAvg s) = Map.singleton s [TInt]
typeOperationOnGraph (OpGraphMax s) = Map.singleton s [TInt]
typeOperationOnGraph (OpGraphMin s) = Map.singleton s [TInt]
typeOperationOnGraph (OpGraphSum s) = Map.singleton s [TInt]
typeOperationOnGraph (OpGraphCount _) = Map.empty
typeOperationOnGraph (OpGraphTypeIs _ _) = Map.empty
typeOperationOnGraph (OpGraphRegex _ _) = Map.empty
typeOperationOnGraph (OpGraphFilter b) = typeBoolExpr b

returnType :: OperationOnGraph -> RDFType
returnType (OpGraphAvg _) = TInt
returnType (OpGraphMax _) = TInt
returnType (OpGraphMin _) = TInt
returnType (OpGraphSum _) = TInt
returnType (OpGraphCount _) = TInt
returnType (OpGraphFilter _) = TUnknown  -- boolean result
returnType _ = TUnknown

typeBoolExpr :: BoolExpr -> Constraints
typeBoolExpr (BoolOr x y) =
  Map.intersectionWith combine (typeBoolExpr x) (typeBoolExpr y)
  where
    combine a b = [ TOr (nub (concatMap toSet (a ++ b))) ]
typeBoolExpr (BoolAnd x y) = mergeAll [typeBoolExpr x, typeBoolExpr y]
typeBoolExpr (BoolNot x)= typeBoolExpr x
typeBoolExpr (BoolComp comp) = typeComparison comp

typeComparison :: Comparison -> Constraints
typeComparison (Comp lhs _ rhs) =
  -- because we don't know the concrete side
  mergeAll [inferVar lhs rhs, inferVar rhs lhs, arithConstraints lhs, arithConstraints rhs]
  where
    inferVar :: ComparableExpr -> ComparableExpr -> Constraints
    inferVar varSide concreteSide =
      case (varOfCmp varSide, typeOfCmp concreteSide) of
          (Just name, Just t) -> Map.singleton name [t]
          _ -> Map.empty  -- can't infer

    arithConstraints :: ComparableExpr -> Constraints
    arithConstraints (CmpArith (ArithVar _)) = Map.empty
    arithConstraints (CmpArith e) = varOfArith e
    arithConstraints _ = Map.empty

typeOfCmp :: ComparableExpr -> Maybe RDFType
typeOfCmp (CmpUri _) = Just TUri
typeOfCmp (CmpString _) = Just TStr
typeOfCmp (CmpArith (ArithInt _)) = Just TInt
typeOfCmp _ = Nothing  -- variable or complex expr, unknown

varOfCmp :: ComparableExpr -> Maybe String
varOfCmp (CmpArith (ArithVar s)) = Just s
varOfCmp _ = Nothing

varOfArith :: ArithExpr -> Constraints
varOfArith (ArithInt _) = Map.empty
varOfArith (ArithVar s) = Map.singleton s [TInt]
varOfArith (ArithNeg e) = varOfArith e
varOfArith (ArithAbs e) = varOfArith e
varOfArith (ArithBinOp _ e1 e2) = mergeAll [varOfArith e1, varOfArith e2]
