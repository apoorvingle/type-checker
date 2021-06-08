module Main where

import Stlc.Language
import Stlc.AlgorithmM
import Stlc.Util
import Stlc.Freshen

import Data.Map as Map
import Data.Set as Set
import Control.Monad.State
import Debug.Trace

scheme1 :: Scheme
scheme1 = Forall (Set.fromList ["b"]) (TArr (TVar "a") (TVar "b"))

gamma :: Context
gamma = Context (Map.fromList [ (unique 0 "add",
                       Forall (Set.fromList ["a"])
                                  (TArr (TArr (TVar "a") (TVar "a")) (TVar "a")))
                              , (unique 0 "id", Forall (Set.empty)
                                         (TArr (TVar "b") (TVar "b")))
                     ])
sub1 :: Substitution
sub1 = Subt (Map.singleton "a" (TVar "b"))

sub2 :: Substitution
sub2 = Subt (Map.singleton "b" (TVar "c"))


runPipeline e ty= do (fe, _) <- runStateT (freshen e) initFnS
                     runStateT (algoM globalCtx fe ty) initTcS
                     


main :: IO ()
main = do
  putStrLn $ show $ substitute sub1 sub2

  putStr $ "+ should succeed:\n\t"
  putStrLn $ show $ (execStateT $ (unify (TConst TBool) (TConst TBool))) (TcState mempty 0)
  putStr $ "+ should fail:\n\t"
  putStrLn $ show $ (execStateT $ (unify (TConst TBool) (TArr (TVar "a") (TVar "b")))) (TcState mempty 0)
  putStr $ "+ should fail:\n\t"
  putStrLn $ show $ (execStateT $ (unify (TVar "a") (TArr (TVar "a") (TVar "b")))) (TcState mempty 0)
  putStr $ "+ should succeed:\n\t"
  putStrLn $ show $ (execStateT $ (unify (TArr (TVar "a") (TVar "b"))
                                     (TArr (TVar "a") (TVar "b"))))
                              (TcState mempty 0)
  putStr $ "+ should succeed:\n\t"
  putStrLn $ show $ (execStateT $ (unify (TVar "a")
                                     (TArr (TVar "b") (TVar "c"))))
                            (TcState mempty 0)
  putStr $ "+ should fail:\n\t -- (y: Bool) |- x\n\t"
  putStrLn $ show $ (execStateT $ algoM (Context $ Map.singleton (mkUnique "y") (Forall (Set.fromList []) $ TConst TBool))
                     (EVar $ mkUnique "x") (TVar "a"))
                            initTcS
  putStr $ "+ should succeed:\n\t"
  putStrLn $ show $ (execStateT $ algoM (Context $ Map.singleton (mkUnique "x") (Forall (Set.fromList []) $ TConst TBool))
                     (EVar $ mkUnique "x") (TVar "a"))
                            initTcS
  putStr $ "+ should succeed:\n\t"
  putStrLn $ show $ runPipeline (ELam "x" (ELit $ LitB True)) (TArr (TVar "a") (TConst TBool))

  putStr $ "+ should succeed:\n\t"
  putStrLn $ show $ runPipeline  (ELam "x" (ELit $ LitB True)) (TVar "a")

  putStr $ "+ should succeed:\n\t |- (\\x. \\y. True)\n\t" 
  putStrLn $ show $ runPipeline (ELam "x" (ELam "y" $ ELit $ LitB True)) (TArr (TVar "a") (TArr (TVar "b") (TConst TBool)))

  putStr $ "+ should succeed:\n\t |- (\\x.x) False a\n\t"
  putStrLn $ show $ runPipeline (EApp (ELam "x" (EVar "x")) (ELit $ LitB False)) (TVar "a")

  putStr $ "+ should succeed:\n\t -- |- (\\x.x) (\\y.y) a\n\t"
  putStrLn $ show $ runPipeline (EApp (ELam "x" (EVar "x")) (ELam "y" (EVar "y"))) (TArr (TVar "a") (TVar "a"))

  putStr $ "+ should fail:\n\t -- (\\x.x)(False)(\\x.x)\n\t"
  putStrLn $ show $ runPipeline
                     (EApp (EApp (ELam "x" (EVar "x")) (ELit $ LitB False))
                           (ELam "x" (EVar "x")))
                       (TConst TBool)

  putStr $ "+ should succeed:\n\t -- (let id = \\x -> x in (id False))\n\t"
  putStrLn $ show $ runPipeline
                     (ELet "id" (ELam "x" (EVar "x"))
                       (EApp (EVar "id") (ELit $ LitB False)))
                       (TConst TBool)


