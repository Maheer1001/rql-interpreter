{
module Parser where

import Lexer
import ParserMonad
}

%name parse
%tokentype { PosnToken }
%errorhandlertype explist
%expect 0
%error { parseError }
%monad { E } { thenE } { returnE }

%token
    int         { PT _ (TokenInt $$) }
    string      { PT _ (TokenString $$) }
    uri         { PT _ (TokenURI $$) }
    uri_char    { PT _ (TokenURIChar $$) }
    var         { PT _ (TokenVar $$) }
    graph_var   { PT _ (TokenGraph $$) }

    ttl_file    { PT _ (TokenGraphFile $$) }

    CONSTRUCT   { PT _ TokenConstruct }
    WHERE       { PT _ TokenWhere }
    UNION       { PT _ TokenUnion }
    INTERSECT   { PT _ TokenIntersect }
    EXCEPT      { PT _ TokenExcept }
    OPTIONAL    { PT _ TokenOptional }
    FILTER      { PT _ TokenFilter }
    LET         { PT _ TokenLet }

    GROUP_BY    { PT _ TokenGroupBy }
    HAVING      { PT _ TokenHaving }
    COUNT       { PT _ TokenCount }
    MAX         { PT _ TokenMax }
    MIN         { PT _ TokenMin }
    AVG         { PT _ TokenAvg }
    SUM         { PT _ TokenSum }
    ABS         { PT _ TokenAbs }
    ORDER_BY    { PT _ TokenOrderBy }
    ASC         { PT _ TokenAsc }
    DESC        { PT _ TokenDesc }
    DISTINCT    { PT _ TokenDistinct }
    REGEX       { PT _ TokenRegex }
    INT_T       { PT _ TokenIntType }
    STRING_T    { PT _ TokenStringType }
    URI_T       { PT _ TokenUriType }
    TYPE        { PT _ TokenType }
    IF          { PT _ TokenIf }
    THEN        { PT _ TokenThen }
    ELSE        { PT _ TokenElse }

    FIRST       { PT _ TokenFirst }
    LAST        { PT _ TokenLast }

    '||'        { PT _ TokenOr }
    '&&'        { PT _ TokenAnd }
    '!'         { PT _ TokenNot }

    '=='        { PT _ TokenEqEq }
    '!='        { PT _ TokenNeq }
    '>='        { PT _ TokenGte }
    '<='        { PT _ TokenLte }
    '<'         { PT _ TokenLAngle }
    '>'         { PT _ TokenRAngle }
    '='         { PT _ TokenEq }

    '+'         { PT _ TokenPlus }
    '-'         { PT _ TokenMinus }
    '*'         { PT _ TokenStar }
    '/'         { PT _ TokenDiv }
    '%'         { PT _ TokenMod }

    '('         { PT _ TokenLParen }
    ')'         { PT _ TokenRParen }
    '{'         { PT _ TokenLBrace }
    '}'         { PT _ TokenRBrace }
    -- '['         { PT _ TokenLBracket }
    -- ']'         { PT _ TokenRBracket }

    '.'         { PT _ TokenDot }
    ','         { PT _ TokenComma }
    -- ';'         { PT _ TokenSemicolon }
    '_'         { PT _ TokenUnderscore }

%%

-- Top-Level Program

Program
    : Bindings Query                        { Program $1 [$2] }
    | Program Query                         { programAppend $1 $2 }

Bindings
    : LetBinding                            { [$1] }
    | LetBinding Bindings                   { $1 : $2 }

LetBinding
    : LET graph_var '=' ttl_file            { GBind $2 $4 }
    | LET graph_var '=' uri                 { PBind $2 $4 }

Query
    : CONSTRUCT ConstructTemplate WhereClause   { Query $2 $3 }

-- Where Clause

WhereClause
    : WHERE '{' WhereBody '}'                   { WhereClause $3 [] }
    | WHERE '{' WhereBody '}' OutputOps         { WhereClause $3 $5 }

WhereBody
    : WhereItem                             { [$1] }
    | WhereItem WhereBody                   { $1 : $2 }

WhereItem
    : Clause                                { $1 }
    | GraphExpr                             { WEGraphExpr $1 }

-- One or more graph pattern matches

Clause
    : graph_var PatternMatch                    { WEClause (GPM $1 $2) [] }
    | graph_var PatternMatch GraphOps           { WEClause (GPM $1 $2) $3 }

-- Graph set expressions with explicit precedence.

GraphExpr
    : UnionExpr                             { $1 }

UnionExpr
    : ExceptExpr UNION UnionExpr            { GraphUnion $1 $3 }
    | ExceptExpr                            { $1 }

ExceptExpr
    : IntersectExpr EXCEPT ExceptExpr       { GraphExcept $1 $3 }
    | IntersectExpr                         { $1 }

IntersectExpr
    : GraphAtom INTERSECT IntersectExpr     { GraphIntersect $1 $3 }
    | GraphAtom                             { $1 }

GraphAtom
    : SubBlock                              { GraphAtom $1 }
    | OPTIONAL SubBlock                     { GraphOptional (GraphAtom $2) }

SubBlock
    : '{' BlockContent '}'                  { SubBlock $2 [] }
    | '{' BlockContent '}' GraphOps         { SubBlock $2 $4 }

-- Inside a sub-block: clauses or nested unions

BlockContent
    : WhereItem                             { [$1] }
    | WhereItem BlockContent                { $1 : $2 }

-- Operations

OutputOps
    : OperationOnOutput                     { [$1] }
    | OperationOnOutput OutputOps           { $1 : $2 }

GraphOps
    : OperationOnGraph                      { [$1] }
    | OperationOnGraph GraphOps             { $1 : $2 }

OperationOnOutput
    : GROUP_BY '(' GroupVars ')'                            { OpOutGroup (GroupByVars $3) }
    | GROUP_BY '(' uri ')'                                  { OpOutGroup (GroupByUri $3) }
    | HAVING '(' var '=' OperationOnGraph ')'               { OpOutHaving (HavingOp $3 $5) }
    | ORDER_BY SortConditions                               { OpOutOrderBy $2 }
    | FIRST '(' int ')'                                     { OpOutFirst $3 }
    | LAST '(' int ')'                                      { OpOutLast $3 }
    | DISTINCT                                              { OpOutDistinct }

GroupVars
    : var                                                   { [$1] }
    | var GroupVars                                         { $1 : $2 }

SortConditions
    : SortCondition                                         { [$1] }
    | SortCondition SortConditions                          { $1 : $2 }

SortCondition
    : ASC '(' var ')'                                       { SortAsc $3 }
    | DESC '(' var ')'                                      { SortDesc $3 }
    | var                                                   { SortAsc $1 }

OperationOnGraph
    : FILTER '(' BooleanEquation ')'                        { OpGraphFilter $3 }
    | REGEX '(' var ',' string ')'                          { OpGraphRegex $3 $5 }
    | TYPE '(' var ')' '=' TypeName                         { OpGraphTypeIs $3 $6 }
    | AVG '(' var ')'                                       { OpGraphAvg $3 }
    | MAX '(' var ')'                                       { OpGraphMax $3 }
    | MIN '(' var ')'                                       { OpGraphMin $3 }
    | SUM '(' var ')'                                       { OpGraphSum $3 }
    | COUNT '(' var ')'                                     { OpGraphCount (CountVar $3) }
    | COUNT '(' uri ')'                                     { OpGraphCount (CountUri $3) }

-- Boolean Logic

BooleanEquation
    : AndExpr '||' BooleanEquation          { BoolOr $1 $3 }
    | AndExpr                               { $1 }

AndExpr
    : PrimaryExpr '&&' AndExpr              { BoolAnd $1 $3 }
    | PrimaryExpr                           { $1 }

PrimaryExpr
    : Comparison                            { BoolComp $1 }
    | '(' BooleanEquation ')'               { $2 }
    | '!' '(' BooleanEquation ')'           { BoolNot $3 }

Comparison
    : ComparableExpr ComparisonOperator ComparableExpr  { Comp $1 $2 $3 }

ComparisonOperator
    : '=='                                  { OpEqEq }
    | '>='                                  { OpGte }
    | '<='                                  { OpLte }
    | '<'                                   { OpLt }
    | '>'                                   { OpGt }
    | '!='                                  { OpNeq }

ComparableExpr
    : ArithmeticExpression                  { CmpArith $1 }
    | uri                                   { CmpUri (UriExprUri $1) }
    | graph_var uri_char                    { CmpUri (UriExprVar $1 $2) }
    | string                                { CmpString $1 }
    | IF '(' BooleanEquation ')' THEN ComparableExpr ELSE ComparableExpr
                                            { CmpIf $3 $6 $8 }

-- Pattern Matching

PatternMatch
    : '{' NodeSymbol NodeSymbol ObjectSymbol '}'
                                            { PMatch $2 $3 $4 }

NodeSymbol
    : uri                                   { NSUri (UriExprUri $1) }
    | graph_var uri_char                    { NSUri (UriExprVar $1 $2) }
    | var                                   { NSVar $1 }
    | '_'                                   { NSWildcard }

ObjectSymbol
    : uri                                   { OSUri (UriExprUri $1) }
    | graph_var uri_char                    { OSUri (UriExprVar $1 $2) }
    | var                                   { OSVar $1 }
    | int                                   { OSLiteral (LitInt $1) }
    | string                                { OSLiteral (LitString $1) }
    | '_'                                   { OSWildcard }

-- CONSTRUCT supports multiple template triples: { ... } . { ... } ...

ConstructTemplate
    : PatternMatch                          { [$1] }
    | PatternMatch '.' ConstructTemplate    { $1 : $3 }
    | PatternMatch '.'                      { [$1] }

-- Arithmetic

ArithmeticExpression
    : Term                                  { $1 }
    | ArithmeticExpression AddOp Term       { ArithBinOp $2 $1 $3 }

Term
    : Factor                                { $1 }
    | Term MulOp Factor                     { ArithBinOp $2 $1 $3 }

Factor
    : int                                   { ArithInt $1 }
    | '-' Factor                            { ArithNeg $2 }
    | var                                   { ArithVar $1 }
    | ABS '(' ArithmeticExpression ')'      { ArithAbs $3 }
    | '(' ArithmeticExpression ')'          { $2 }

TypeName
    : INT_T                                 { TypeInt }
    | STRING_T                              { TypeString }
    | URI_T                                 { TypeUri }

AddOp
    : '+'                                   { OpPlus }
    | '-'                                   { OpMinus }

MulOp
    : '*'                                   { OpMul }
    | '/'                                   { OpDiv }
    | '%'                                   { OpMod }

{

parseError :: ([PosnToken],[String]) -> E a
parseError ([] , _) = failE (PT (AlexPn 0 0 0) TokenAnd) [] "Parse error at end of file"
parseError ( (t@(PT _ (TokenError _)) : _), expected ) = failE t expected "Lexical Error"
parseError ((t : _), expected) = failE t expected "Syntax Error"

programAppend :: Program -> Query -> Program
programAppend (Program bs qs) q = Program bs (qs ++ [q])

-- AST Data Types

data Program = Program [LetBinding] [Query]
    deriving (Show, Eq)

data LetBinding
    = GBind String FilePath      -- LET @graph = <xxx.ttl>
    | PBind String String        -- LET @prefix = <uri>
    deriving (Show, Eq)

data Query = Query [PatternMatch] WhereClause
    deriving (Show, Eq)

data WhereClause = WhereClause [WhereElement] [OperationOnOutput]
    deriving (Show, Eq)

data WhereElement
    = WEClause GPM [OperationOnGraph]
    | WEGraphExpr GraphExpr
    deriving (Show, Eq)

data SubBlock = SubBlock [WhereElement] [OperationOnGraph]
    deriving (Show, Eq)

data GraphExpr
    = GraphAtom SubBlock
    | GraphUnion GraphExpr GraphExpr
    | GraphIntersect GraphExpr GraphExpr
    | GraphExcept GraphExpr GraphExpr
    | GraphOptional GraphExpr
    deriving (Show, Eq)

data GPM = GPM String PatternMatch
    deriving (Show, Eq)

data PatternMatch = PMatch NodeSymbol NodeSymbol ObjectSymbol
    deriving (Show, Eq)

data NodeSymbol
    = NSUri UriExpression
    | NSVar String
    | NSWildcard
    deriving (Show, Eq)

data ObjectSymbol
    = OSUri UriExpression
    | OSVar String
    | OSLiteral LiteralValue
    | OSWildcard
    deriving (Show, Eq)

data LiteralValue
    = LitInt Int
    | LitString String
    deriving (Show, Eq)

data UriExpression 
    = UriExprUri String          -- <uri>
    | UriExprVar String String   -- @graph:localname
    deriving (Show, Eq)

data OperationOnOutput 
    = OpOutGroup GroupBy
    | OpOutHaving Having
    | OpOutOrderBy [SortCondition]
    | OpOutFirst Int
    | OpOutLast Int
    | OpOutDistinct
    deriving (Show, Eq)

data SortCondition = SortAsc String | SortDesc String
    deriving (Show, Eq)

data OperationOnGraph
    = OpGraphFilter BoolExpr
    | OpGraphRegex String String
    | OpGraphTypeIs String TypeName
    | OpGraphAvg String
    | OpGraphMax String
    | OpGraphMin String
    | OpGraphSum String
    | OpGraphCount CountTarget
    deriving (Show, Eq)

data GroupBy = GroupByVars [String] | GroupByUri String
    deriving (Show, Eq)

data Having = HavingOp String OperationOnGraph
    deriving (Show, Eq)

data CountTarget = CountVar String | CountUri String
    deriving (Show, Eq)

data BoolExpr 
    = BoolOr BoolExpr BoolExpr
    | BoolAnd BoolExpr BoolExpr
    | BoolNot BoolExpr
    | BoolComp Comparison
    deriving (Show, Eq)

data Comparison = Comp ComparableExpr CompOp ComparableExpr
    deriving (Show, Eq)

data CompOp = OpEqEq | OpNeq | OpGte | OpLte | OpLt | OpGt
    deriving (Show, Eq)

data ComparableExpr
    = CmpUri UriExpression
    | CmpString String
    | CmpArith ArithExpr
    | CmpIf BoolExpr ComparableExpr ComparableExpr
    deriving (Show, Eq)

data ArithExpr 
    = ArithInt Int
    | ArithVar String
    | ArithAbs ArithExpr
    | ArithNeg ArithExpr
    | ArithBinOp ArithOp ArithExpr ArithExpr
    deriving (Show, Eq)

data ArithOp = OpPlus | OpMinus | OpMul | OpDiv | OpMod
    deriving (Show, Eq)

data TypeName = TypeInt | TypeString | TypeUri
    deriving (Show, Eq)
}
