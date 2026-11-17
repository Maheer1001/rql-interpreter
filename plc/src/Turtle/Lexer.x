{ 
module Turtle.Lexer( 
  alexScanTokens, AlexPosn(..), PosnToken(..), Token(..),
  showPosn, getTokens
) where 
}

%wrapper "posn" 
$digit = 0-9
$alpha = [a-zA-Z]
$urichar = [a-zA-Z0-9 \: \/ \? \# \[ \] \@ \! \$ \& \' \( \) \* \+ \, \; \- \. \_ \~ \%]
$pnchar = [a-zA-Z0-9\_\-]

tokens :-
  $white+                                 ; 
  "#".*                                   ; 
  "@base"                                 { \p _ -> PT p TokenBase } 
  "@prefix"                               { \p _ -> PT p TokenPrefix }
  $alpha $pnchar* ":" $alpha $pnchar*     { \p s -> PT p (TokenPrefixedName s) }
  $alpha $pnchar*                         { \p s -> PT p (TokenPrefixLabel s) }
  "<" $urichar+ ">"                       { \p s -> PT p (TokenURI (tail (init s))) }
  \" [^\"\n]* \"                          { \p s -> PT p (TokenLitStr (tail (init s))) }
  $digit+                                 { \p s -> PT p (TokenLitInt (read s)) }
  ":"                                     { \p _ -> PT p TokenColon }
  ";"                                     { \p _ -> PT p TokenSemicolon }
  ","                                     { \p _ -> PT p TokenComma }
  "."                                     { \p _ -> PT p TokenDot }

{
data PosnToken = PT AlexPosn Token deriving (Eq, Show)
-- helper that shows the posn information of each token
showPosn :: PosnToken -> String
showPosn (PT (AlexPn _ line col) _) = show line ++ ":" ++ show col

getTokens :: [PosnToken] -> [Token]
getTokens = map (\(PT _ token) -> token)

data Token = 
    TokenBase
  | TokenPrefix
  | TokenURI String
  | TokenPrefixedName String    -- e.g. "ont:name"
  | TokenPrefixLabel String     -- e.g. "ont"
  | TokenLitStr String
  | TokenLitInt Int
  | TokenColon                  -- for prefixed name
  | TokenSemicolon              -- for predicate list
  | TokenComma                  -- for object list
  | TokenDot                    -- end of directives and triples
  deriving (Eq,Show)
}
