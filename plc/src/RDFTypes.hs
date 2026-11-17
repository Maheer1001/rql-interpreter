module RDFTypes ( 
  URI, Object(..), Triple(..), Graph
) where

type URI = String
data Object = Resource URI | LitStr String | LitInt Int
  deriving (Eq, Show, Ord)
data Triple = Triple URI URI Object
  deriving (Eq, Show, Ord)
type Graph = [Triple]
