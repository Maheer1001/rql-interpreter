{
module Lexer (
  alexScanTokens, AlexPosn(..), PosnToken(..), Token(..),
  showPosn, getTokens
) where
}

%wrapper "posn"

-- Character classes
$digit     = 0-9
$alpha     = [a-zA-Z]
$urichar   = [a-zA-Z0-9 \: \/ \? \# \[ \] \@ \! \$ \& \' \( \) \* \+ \, \; \- \. \_ \~ \%]
$localchar = [a-zA-Z0-9 \_ \-]

tokens :-

-- Whitespace and comments
$white+                         ;
"--".*                          ;

-- Literals
\< $urichar+ ".ttl" \>          { \p s -> PT p (TokenGraphFile (init (tail s))) }
\< $urichar+ \>                 { \p s -> PT p (TokenURI (init (tail s))) }
\" [^\"]* \"                    { \p s -> PT p (TokenString (init (tail s))) }
$digit+                         { \p s -> PT p (TokenInt (read s)) }

-- Variables
\? $alpha [$alpha $digit \_]*   { \p s -> PT p (TokenVar (tail s)) }
\@ $alpha [$alpha $digit \_]*   { \p s -> PT p (TokenGraph (tail s)) }

-- Binding
LET                             { \p _ -> PT p TokenLet }

-- Graph operations
CONSTRUCT                       { \p _ -> PT p TokenConstruct }
WHERE                           { \p _ -> PT p TokenWhere }
UNION                           { \p _ -> PT p TokenUnion }
INTERSECT                       { \p _ -> PT p TokenIntersect }
EXCEPT                          { \p _ -> PT p TokenExcept }
OPTIONAL                        { \p _ -> PT p TokenOptional }
FILTER                          { \p _ -> PT p TokenFilter }

-- Aggregates
GROUP $white+ BY                { \p _ -> PT p TokenGroupBy }
HAVING                          { \p _ -> PT p TokenHaving }
COUNT                           { \p _ -> PT p TokenCount }
MAX                             { \p _ -> PT p TokenMax }
MIN                             { \p _ -> PT p TokenMin }
AVG                             { \p _ -> PT p TokenAvg }
SUM                             { \p _ -> PT p TokenSum }

-- Numeric functions
ABS                             { \p _ -> PT p TokenAbs }

-- Ordering and pagination
ORDER $white+ BY                { \p _ -> PT p TokenOrderBy }
ASC                             { \p _ -> PT p TokenAsc }
DESC                            { \p _ -> PT p TokenDesc }
FIRST                           { \p _ -> PT p TokenFirst }
LAST                            { \p _ -> PT p TokenLast }
DISTINCT                        { \p _ -> PT p TokenDistinct }

-- Conditionals
IF                              { \p _ -> PT p TokenIf }
THEN                            { \p _ -> PT p TokenThen }
ELSE                            { \p _ -> PT p TokenElse }

-- String and type operations
REGEX                           { \p _ -> PT p TokenRegex }
TYPE                            { \p _ -> PT p TokenType }
INT                             { \p _ -> PT p TokenIntType }
STRING                          { \p _ -> PT p TokenStringType }
URI                             { \p _ -> PT p TokenUriType }

-- Boolean operators
"||"                            { \p _ -> PT p TokenOr }
"&&"                            { \p _ -> PT p TokenAnd }
"!"                             { \p _ -> PT p TokenNot }

-- Comparison operators
"=="                            { \p _ -> PT p TokenEqEq }
"!="                            { \p _ -> PT p TokenNeq }
">="                            { \p _ -> PT p TokenGte }
"<="                            { \p _ -> PT p TokenLte }
\<                              { \p _ -> PT p TokenLAngle }
\>                              { \p _ -> PT p TokenRAngle }
\=                              { \p _ -> PT p TokenEq }

-- Arithmetic operators
\+                              { \p _ -> PT p TokenPlus }
\-                              { \p _ -> PT p TokenMinus }
\*                              { \p _ -> PT p TokenStar }
\/                              { \p _ -> PT p TokenDiv }
\%                              { \p _ -> PT p TokenMod }

-- Delimiters
\(                              { \p _ -> PT p TokenLParen }
\)                              { \p _ -> PT p TokenRParen }
\{                              { \p _ -> PT p TokenLBrace }
\}                              { \p _ -> PT p TokenRBrace }

-- Punctuation
\.                              { \p _ -> PT p TokenDot }
\,                              { \p _ -> PT p TokenComma }
\_                              { \p _ -> PT p TokenUnderscore }

-- Local name (e.g. :has, :name) -- must come after all keyword rules
\: $localchar+                  { \p s -> PT p (TokenURIChar (tail s)) }

-- Error
.                               { \p s -> PT p (TokenError s) }

{
data PosnToken = PT AlexPosn Token deriving (Eq, Show)

showPosn :: PosnToken -> String
showPosn (PT (AlexPn _ line col) _) = show line ++ ":" ++ show col

getTokens :: [PosnToken] -> [Token]
getTokens = map (\(PT _ token) -> token)

data Token
    = TokenInt Int
    | TokenString String
    | TokenURIChar String
    | TokenGraphFile String
    | TokenURI String
    | TokenVar String
    | TokenGraph String
    | TokenConstruct
    | TokenWhere
    | TokenUnion
    | TokenIntersect
    | TokenExcept
    | TokenOptional
    | TokenFilter
    | TokenLet
    | TokenGroupBy
    | TokenHaving
    | TokenCount
    | TokenMax
    | TokenMin
    | TokenAvg
    | TokenSum
    | TokenAbs
    | TokenOrderBy
    | TokenAsc
    | TokenDesc
    | TokenFirst
    | TokenLast
    | TokenDistinct
    | TokenRegex
    | TokenIntType
    | TokenStringType
    | TokenUriType
    | TokenType
    | TokenIf
    | TokenThen
    | TokenElse
    | TokenOr
    | TokenAnd
    | TokenNot
    | TokenEqEq
    | TokenNeq
    | TokenGte
    | TokenLte
    | TokenLAngle
    | TokenRAngle
    | TokenEq
    | TokenPlus
    | TokenMinus
    | TokenStar
    | TokenDiv
    | TokenMod
    | TokenLParen
    | TokenRParen
    | TokenLBrace
    | TokenRBrace
    | TokenDot
    | TokenComma
    | TokenUnderscore
    | TokenError String
    deriving (Eq, Show)
}
