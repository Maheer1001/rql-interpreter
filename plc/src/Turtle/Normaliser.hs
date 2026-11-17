module Turtle.Normaliser (
  normaliseTurtle, showTriples, showTriple, showObject, module RDFTypes
) where

import RDFTypes
import qualified Turtle.Parser as Parser
import Data.List (nub)
import Data.Map (Map)
import qualified Data.Map as Map

-- Environment to store base and prefix directives
data Environment = Environment {
  baseURI :: Maybe String,
  prefixes :: Map String String   -- key-value pairs: prefix labels -> their absolute URIs
}
emptyTurtleEnv :: Environment
emptyTurtleEnv = Environment { baseURI = Nothing, prefixes = Map.empty }


-- Convert a list of statements to a list of normalised triples
normaliseTurtle :: Parser.TurtleDoc -> [Triple]
normaliseTurtle stmts = nub (normaliseTurtle' stmts emptyTurtleEnv)
  where
    normaliseTurtle' :: [Parser.Statement] -> Environment -> [Triple]
    normaliseTurtle' [] _ = []
    normaliseTurtle' (Parser.SDirective d : ss) env = normaliseTurtle' ss (updateEnvironment d env)
    normaliseTurtle' (Parser.STriples ts : ss) env = map (normaliseTriple env) ts ++ normaliseTurtle' ss env

    updateEnvironment :: Parser.Directive -> Environment -> Environment
    updateEnvironment (Parser.Base absURI) env
      | Nothing <- baseURI env = env { baseURI = Just (extractURI absURI) }
      | otherwise = error "Multiple base directives are not allowed in the same document"
    updateEnvironment (Parser.Prefix label absURI) env = env { prefixes = Map.insert label (extractURI absURI) (prefixes env) }

    extractURI :: Parser.URI -> String
    extractURI (Parser.AbsURI s) = s
    extractURI (Parser.RelURI s) = s

-- Convert a triple to a normalised triple with the given environment(directives)
normaliseTriple :: Environment -> Parser.Triple -> Triple
normaliseTriple env (Parser.Triple s p o) = Triple (expandSubject s env) (expandPredicate p env) (expandObject o env)

expandSubject :: Parser.Subject -> Environment -> URI
expandSubject (Parser.Subject r) env = normaliseResource r env
expandPredicate :: Parser.Predicate -> Environment -> URI
expandPredicate (Parser.Predicate r) env = normaliseResource r env
expandObject :: Parser.Object -> Environment -> Object
expandObject (Parser.OUri uri) env = Resource (expandURI uri env)
expandObject (Parser.OPrefixedName pn) env = Resource (expandPN pn env)
expandObject (Parser.OLitStr str) _ = LitStr str
expandObject (Parser.OLitInt num) _ = LitInt num

normaliseResource :: Parser.Resource -> Environment -> URI
normaliseResource (Parser.RUri uri) env = expandURI uri env
normaliseResource (Parser.RPrefixedName pn) env = expandPN pn env

expandURI :: Parser.URI -> Environment -> URI
expandURI (Parser.AbsURI s) _ = s
expandURI (Parser.RelURI s) env =
  case baseURI env of
    Just base -> base ++ s
    Nothing -> error $ "Relative URI '<" ++ s ++ ">' with no base directive in scope"

expandPN :: Parser.PrefixedName -> Environment -> URI
expandPN (Parser.PrefixedName label loc) env =
  case Map.lookup label (prefixes env) of
    Just uri -> uri ++ loc
    Nothing -> error $ "Undefined prefix '" ++ label ++ "'"


showObject :: Object -> String
showObject (Resource uri) = "<" ++ uri ++ ">"
showObject (LitStr str) = "\"" ++ str ++ "\""
showObject (LitInt n) = show n

showTriple :: Triple -> String
showTriple (Triple s p o) = "<" ++ s ++ "> <" ++ p ++ "> " ++ showObject o ++ " ."

showTriples :: [Triple] -> String
showTriples = unlines . map showTriple
