{ 
module Turtle.Parser where 
import Turtle.Lexer
import Data.List (isInfixOf)
}

%name parseTurtle           -- the name of parse function
%tokentype { PosnToken }    -- set the type of token
%error { parseError }       -- error handling function

-- Maps between terminal symbols in Grammar and Token type in Lexer
%token
  BASE          { PT _ TokenBase } 
  PREFIX        { PT _ TokenPrefix } 
  URI           { PT _ (TokenURI $$) } 
  PREFIXEDNAME  { PT _ (TokenPrefixedName $$) } 
  PREFIXLABEL   { PT _ (TokenPrefixLabel $$) } 
  LITSTR        { PT _ (TokenLitStr $$) } 
  LITINT        { PT _ (TokenLitInt $$) }
  ':'           { PT _ TokenColon }
  ';'           { PT _ TokenSemicolon }
  ','           { PT _ TokenComma }
  '.'           { PT _ TokenDot }

-- Grammar rules
%% 
TurtleDoc  :: { TurtleDoc }
TurtleDoc  : Statements             { $1 }
Statements :: { [Statement] }
Statements :                        { [] }
           | Statement Statements   { $1 : $2 }

Statement  :: { Statement }
Statement  : Directive                                { SDirective $1 }
           | Triples                                  { STriples $1 }

Directive  :: { Directive }
Directive  : BASE URI '.'                             { Base (getAbsURI $2) }
           | PREFIX PREFIXLABEL ':' URI '.'           { Prefix $2 (getAbsURI $4) }
Triples    :: { [Triple] }
Triples    : Subject PredObjList '.'                  { [ Triple $1 p o | (p, os) <- $2, o <- os ] }

PredObjList :: { [(Predicate, [Object])] }
PredObjList : PredObjects                             { [$1] }
            | PredObjects ';' PredObjList             { $1 : $3 }
PredObjects :: { (Predicate, [Object]) }
PredObjects : Predicate ObjectList                    { ($1, $2) }
ObjectList  :: { [Object] }
ObjectList  : Object                                  { [$1] }
            | Object ',' ObjectList                   { $1 : $3 }

Subject   :: { Subject }
Subject   : URI                                       { Subject (RUri (buildURI $1)) }
          | PREFIXEDNAME                              { Subject (RPrefixedName (buildPrefixedName $1)) }

Predicate :: { Predicate }
Predicate : URI                                       { Predicate (RUri (buildURI $1)) }
          | PREFIXEDNAME                              { Predicate (RPrefixedName (buildPrefixedName $1)) }

Object    :: { Object }
Object    : URI                                       { OUri (buildURI $1) }
          | PREFIXEDNAME                              { OPrefixedName (buildPrefixedName $1) }
          | LITSTR                                    { OLitStr $1 }
          | LITINT                                    { OLitInt $1 }

{ 
-- Error handler
parseError :: [PosnToken] -> a
parseError [] = error "Parse error at end of input"
parseError tokens = error $ "Parse error at line " ++ (show line) ++ " column " ++ (show col)
  where
    PT p t = head tokens
    AlexPn _ line col = p


-- AST types

type TurtleDoc = [Statement]
-- A statement is either a directive or a list of triples (might contain a predicate/object list)
data Statement = SDirective Directive | STriples [Triple] 
  deriving (Eq, Show)

data URI = AbsURI String | RelURI String
  deriving (Eq, Show)
data PrefixedName = PrefixedName {
  prefixLabel :: String,
  local :: String
} deriving (Eq, Show)
data Resource = RUri URI | RPrefixedName PrefixedName
  deriving (Eq, Show)

data Directive = Base URI | Prefix String URI
  deriving (Eq, Show)
data Triple = Triple Subject Predicate Object
  deriving (Eq, Show)

newtype Subject = Subject Resource
  deriving (Eq, Show)
newtype Predicate = Predicate Resource
  deriving (Eq, Show)
data Object = OUri URI | OPrefixedName PrefixedName | OLitStr String | OLitInt Int
  deriving (Eq, Show)


-- helper functions

buildURI :: String -> URI
buildURI str
  | isAbsURI str = AbsURI str
  | otherwise = RelURI str
  where
    isAbsURI :: String -> Bool
    isAbsURI = isInfixOf "://"

getAbsURI :: String -> URI
getAbsURI str = case buildURI str of
  abs@(AbsURI _) -> abs
  RelURI _ -> error $ "Directive requires absolute URI, got: " ++ str

buildPrefixedName :: String -> PrefixedName
buildPrefixedName str = PrefixedName { prefixLabel = p, local = l }
  where
    -- break (== ':') "ont:name" => ("ont", ":name")
    (p, _:l) = break (== ':') str

}
