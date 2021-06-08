{-# Language InstanceSigs #-}
module Stlc.Util where

import Stlc.Language

import Control.Applicative (liftA2)
import Control.Monad (liftM2)
import Control.Monad.State
import qualified Data.Map as Map
import Data.Map (Map)
import qualified Data.Set as Set
import Data.Set (Set, (\\))
import qualified Data.Hashable as H (hash)

------------------------
-- Freshening Utils  ---
------------------------

data FnState = FnS {
  seed :: Int -- threaded state seed
                   }
  deriving (Show)
               
initFnS = FnS {seed = 0}

incFnS :: FnState -> FnState
incFnS (FnS {seed = s}) = FnS {seed = s + 1}

type FnM a = StateT FnState (Either String) a

unique :: FnState -> String -> Unique
unique s n = Unique { value = n, hash = H.hash n, scope = seed s}


-------------------------
-- Type checking Utils --
-------------------------

-- Convinence function to return an error
typeError :: String -> TCM a
typeError err = StateT (\_ ->  Left err)

-- Looks up a variable and returns the scheme if it exists in the
-- context
lookupVar :: Context -> Id -> TCM Scheme
lookupVar (Context c) i = case (Map.lookup i c) of
  Just x -> return x
  Nothing -> typeError $ "Variable " ++ i ++ " not in context"

-- concretizes a scheme to specific type
-- ie. takes all the quantified variables creates new type variables for them
-- and applies all of them to the type
instantiate :: Scheme -> TCM Type
instantiate (Forall q ty) = do q' <- mapM (const $ fresh 't') (Set.toList $ q)
                               let s = Subt (Map.fromList $ zip (Set.toList q) q')
                               return (substitute ty s)

-- creates a scheme given a context and a type
-- the free variables in the generated scheme
-- are the (free variables in the type) - (free variables in context)
generalize :: Context -> Type -> TCM Scheme
generalize gamma ty = return $ Forall qs ty
  where qs = fvs ty \\ fvs gamma

-- Generate unique type variable for a new term
fresh :: Char -> TCM Type
fresh c = StateT (\(TcState s i) -> return (TVar (c:'`':(suffixGen !! i))
                                           , TcState s (i + 1)))
  where
    suffixGen = liftA2 (\i -> \pre -> [pre] ++ show i)  [ (1::Integer) .. ]  ['a' .. 'z']

-- Typechecker state holds the substitutions that we would use
-- in order to typecheck the term and a term number that will be used
-- to create unique fresh type variables.
data TcState = TcState { subs :: Substitution
                       , tno  :: Int } deriving (Show, Eq)

type TCM a = StateT TcState  (Either String) a


