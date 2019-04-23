{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Stlc.AlgorithmM where

-- This is a context-sensitive top-down approach to type checking
-- The pros are that:
--     1. It terminates much earlier than AlgorithmW if the term is illtyped
--     2. error messages are more legible and can pin point the "real" problem
--        in the expression
-- The cons are:
--     1. We would need give a top level binding for the expression that
--        sources to be the expected type of of the expression
--        (or just give a TVar type and unify will take care of it)
-- References:
--     1. Proofs about a folklore let-polymorphic type inference algorithm
--        https://dl.acm.org/citation.cfm?id=291892


import Stlc.Language
import Stlc.Util


import qualified Data.Map as Map
import qualified Data.Set as Set

import Data.Map (Map)
import Data.Set (Set)

import Control.Monad (liftM2)
import Debug.Trace (traceM)

-- Unify is a function that tries to unify 2 types or returns an error
-- The goal will be to convert left Type into a right Type
-- so that substitute t1 (unify (ty1, ty2)) = ty2 if unify returns a Right _
-- we need to update the state i.e. subs tcm and return a ()
unify :: Type ->  Type -> TCM Substitution
unify t1@(TArrSp a b) t2@(TArrSp c d) = TCM (\tcs -> do -- traceM ("DEBUG (unify t1 t2)\n\t" ++ show t1 ++ "\n\t" ++ show t2)
                                                    (_, tcs') <- (runTCM $ unify a c) tcs
                                                    -- traceM ("DEBUG (unify a c): " ++  show tcs')
                                                    let s = subs tcs'
                                                    (_, tcs'') <- (runTCM $ unify (substitute s b) (substitute s d)) tcs'
                                                    -- traceM ("DEBUG (unify b d): " ++  show tcs'')
                                                    return (subs tcs'', tcs'')
                                        )

unify t1@(TArrSh a b) t2@(TArrSh c d) = TCM (\tcs -> do -- traceM ("DEBUG (unify t1 t2)\n\t" ++ show t1 ++ "\n\t" ++ show t2)
                                                    (_, tcs') <- (runTCM $ unify a c) tcs
                                                    -- traceM ("DEBUG (unify a c): " ++  show tcs')
                                                    let s = subs tcs'
                                                    (_, tcs'') <- (runTCM $ unify (substitute s b) (substitute s d)) tcs'
                                                    -- traceM ("DEBUG (unify b d): " ++  show tcs'')
                                                    return (subs tcs'', tcs'')
                                        )

unify (TVar a) x@(TVar b)         | (a == b) = return (Subt Map.empty)
                                  | otherwise =  TCM (\tcs ->
                                                        return ((subs tcs) `mappend` (sub a x)
                                                               ,tcs {subs = (subs tcs) `mappend` (sub a x)}))
unify (TVar a) x          = do if (a `elem` fvs x)
                               then typeError
                                    $ "unification of "
                                    ++ (a) ++ " and " ++ (ppr x)
                                    ++ " will lead to infinite type"
                               else TCM (\tcs ->
                                            return ((subs tcs) `mappend` (sub a x)
                                                   , tcs { subs = (subs tcs) `mappend` (sub a x)}))
unify x (TVar a)          = do if (a `elem` fvs x)
                               then typeError
                                    $ "unification of "
                                    ++ (a) ++ " and " ++ (ppr x)
                                    ++ " will lead to infinite type"
                               else TCM (\tcs ->
                                            return ((subs tcs) `mappend` (sub a x)
                                                   , tcs { subs = (subs tcs) `mappend` (sub a x)}))
unify (TConst a) (TConst b) | (a == b)  = return (Subt Map.empty)
                            | otherwise = typeError
                                    $ "Cannot unify " ++ (ppr a) ++ " and " ++ ppr b

unify (TConst a)  b         = typeError
                                $ "Cannot unify " ++ (ppr a) ++ " with " ++ ppr b

unify a b                   = typeError $ "Cannot unify "
                                ++ (ppr a) ++ " and " ++ ppr b

-- This algorithm takes in the context, expression and
-- the expected type (or type constraint) of the expression and returns the
-- substitution that satisfies the type constraint
-- It is different from algoW:
--    1. it does not return type and substitution.
--    2. It expects a type to be given for which a substitution is returned.
--    3. Unify is called at for Literal, Variable and Lambda (as opposed to Application call in algorithmW)

algoM :: Context -> Exp -> Type -> TCM Substitution
-- patten match on all the expression constructs


{-
   The first rule is for the literals,
   literals have a constant type. eg. True: Bool 0: Int
   and require no substitution

  -------------------------------------------[Lit]
               Γ ⊢ True : TBool

  -------------------------------------------[Lit]
               Γ ⊢ 3 : TInt

  unify is called here so as to fix the type of the literal
-}
algoM _ (ELit x) expty = case x of
  LitB _ -> unify (TConst TBool) expty
  LitI _ -> unify (TConst TInt) expty

{-
   The second rule is for the variable
      x : σ ϵ Γ            τ = instantiate(σ)
   -------------------------------------------[Var]
               Γ ⊢ x : τ

  search if the variable x exists in the context Γ and instantiate it.
  returns a unification of expected type and instantiated type
  or an error if no such variable exists.

-}
algoM gamma (EVar x) expty = do (sig, _) <- lookupVar gamma x     -- x : σ ϵ Γ
                                tau <- instantiate sig            -- τ = inst(σ)
                                updateUsed x
                                unify tau expty                   -- τ

{-
  This rule types lambda expression.
          Γ, x:T ⊢ e :T'
   -------------------------- [Lam]
       Γ ⊢ λx. e : T -> T'

  2 new fresh type variables are introduced, for x and e. They are unifed with
  the expected type. The new type variable for x is used to extend the context
  and the expression e is checked to return the final substition
  with extended context with substituions applied.

-}
algoM gamma (ELamSp x e) expty = do b1 <- fresh 'x'
                                    b2 <- fresh 'e'
                                    s  <- unify (TArrSp b1 b2) expty
                                    let gamma' = extendContext gamma x (scheme b1) (Set.singleton x)
                                    s' <- algoM (substitute s gamma') e (substitute s b2)
                                    return (substitute s' s)

algoM gamma (ELamSh x e) expty = do b1 <- fresh 'x'
                                    b2 <- fresh 'e'
                                    s  <- unify (TArrSh b1 b2) expty
                                    let shinfo = getvars gamma
                                    let gamma' = extendContext (updateShInfo gamma x) x (scheme b1) shinfo
                                    s' <- algoM (substitute s gamma') e (substitute s b2)
                                    return (substitute s' s)

{-
   rule for application goes as follows:
   if we have an expression e e'
   then if the second expression e is well typed to T
   and the first expression should be of the form T -> T'
   then complete expression is of type T'


      Γ ⊢ e : T -> T'    Γ ⊢ e' :T
   --------------------------------------- [App]
                 Γ ⊢ e e' : T'


  The interesting bit here is we have to introduce a new
  type variable as the return type of the first expression.
  Then e is checked against the TArrSp b expected type
  to obtain a substitution for b. Then e' is checked for sanity
-}

-- FIX THIS
-- We have to split the gamma into 2 disjoint sets of e and e' to introduce TArrSp
-- Or we have to show that we have complete overlap of gamma for e and e' to introduce TArrSh
-- Else we fail
algoM gamma (EApp e e') expty = do (original_state:: TcState) <- gets
                                   b <- fresh 'e'
                                   -- First assume that e e' are separate and get the used variables
                                   traceM ("\tDEBUG: Checking for Separation")
                                   let (orig_used::Set Id) = used original_state
                                   s_sep <- algoM gamma e (TArrSp b expty)
                                   (used_sep::Set Id) <- getUsed

                                   let gamma' = substitute s_sep gamma
                                   let b' = substitute s_sep b
                                   resetUsed orig_used
                                   sep_s' <- algoM gamma' e' b'
                                   used_sep_e' <- getUsed
                                   traceM ("\tDEBUG: " ++ (show used_sep) ++ " used in e")
                                   traceM ("\tDEBUG: " ++ (show used_sep_e') ++ " used in e'")
                                   -- check if the used variables are separate
                                   if (used_sep_e' `Set.disjoint` used_sep)
                                     then return (substitute sep_s' s_sep)
                                     else
                                     do traceM ("DEBUG: Checking for sharing")
                                        sets original_state
                                        -- now assume that e e' are shared and get the used variables
                                        s_sh <- algoM gamma e (TArrSh b expty)
                                        (used_sh::Set Id)  <- getUsed
                                        -- Check if the used variables are in sharing
                                        let gamma'' = substitute s_sh gamma
                                        let b'' = substitute s_sh b
                                        resetUsed used_sh
                                        sh_s' <- algoM gamma'' e' b''
                                        used_sh_e' <- getUsed
                                        if used_sh == used_sh_e'
                                          then return (substitute sh_s' s_sh)
                                          else typeError "Could not prove sharing or separation"
                                   -- return (substitute sep_s' s_sep)
{-
    Let bindings introduce variable names and associated types
    into the context Γ.

    The procedure for this rule is:
    Obtain the type of e and bind it to x
    then type check e' with the updated context

       Γ ⊢ e : T    sig = gen(Γ,T)    Γ, x: sig ⊢ e' :T'
   -------------------------------------------------------- [Let]
                  Γ ⊢ let x = e in e' : T'

-}

-- FIXME
-- algoM gamma (ELet x e e') expty = do b <- fresh 'e'
--                                      s <- algoM gamma e b
--                                      sig <- generalize gamma (substitute b s)
--                                      let gamma' = updateContext gamma x sig
--                                      s' <- algoM (substitute gamma' s) e' (substitute expty s)
--                                      return (substitute s s')

-- FIXME
-- algoM gamma (EFix f'@(EVar f) l@(ELamSp x e)) expty = do b <- fresh 'f'
--                                                        let gamma' = updateContext gamma f (scheme b)
--                                                        algoM gamma' l expty

-- algoM _ _ _ = typeError "Cannot typecheck current expression"
