(*
  This file is part of Mymms.

  Mymms is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Mymms is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Mymms.  If not, see <http://www.gnu.org/licenses/>.

  Copyright (C) 2008 Nicolas Marti
*)

open Varset;;
open Output;;
open Printf;;

type var = String
;;

type nexpr =
    | Nvar of string
    | Ncons of int
    | Nplus of nexpr * nexpr
    | Nminus of nexpr * nexpr
    | Nmult of nexpr * nexpr
;;

let rec rewrite_nexpr e x y =
  match e with
    | Nvar v ->	if (v = x) then y else e
    | Ncons _ -> e
    | Nplus (e1, e2) -> Nplus (rewrite_nexpr e1 x y, rewrite_nexpr e2 x y)
    | Nminus (e1, e2) -> Nminus (rewrite_nexpr e1 x y, rewrite_nexpr e2 x y)
    | Nmult (e1, e2) -> Nmult (rewrite_nexpr e1 x y, rewrite_nexpr e2 x y)
;;

let rec print_nexpr e = 
  match e with
    | Nvar s -> printf "%s" s
    | Ncons v -> printf "%d" v
    | Nplus (e1, e2) -> print_nexpr e1; printf " + "; print_nexpr e2;
    | Nminus (e1, e2) -> print_nexpr e1; printf " - "; print_nexpr e2;
    | Nmult (e1, e2) -> print_nexpr e1; printf " * "; print_nexpr e2;
;;

type bexpr =
    | BTrue
    | BFalse
    | Beq of nexpr * nexpr
    | Blt of nexpr * nexpr
    | Ble of nexpr * nexpr
    | Bgt of nexpr * nexpr
    | Bge of nexpr * nexpr
    | Bneg of bexpr
    | Band of bexpr * bexpr
    | Bor of bexpr * bexpr
;;

let rec rewrite_bexpr b x y =
  match b with
    | Beq (e1, e2) -> Beq (rewrite_nexpr e1 x y, rewrite_nexpr e2 x y)
    | Blt (e1, e2) -> Blt (rewrite_nexpr e1 x y, rewrite_nexpr e2 x y)
    | Ble (e1, e2) -> Ble (rewrite_nexpr e1 x y, rewrite_nexpr e2 x y)
    | Bgt (e1, e2) -> Bgt (rewrite_nexpr e1 x y, rewrite_nexpr e2 x y)
    | Bge (e1, e2) -> Bge (rewrite_nexpr e1 x y, rewrite_nexpr e2 x y)
    | Bneg b1 -> Bneg (rewrite_bexpr b1 x y)
    | Band (e1, e2) -> Band (rewrite_bexpr e1 x y, rewrite_bexpr e2 x y)
    | Bor (e1, e2) -> Bor (rewrite_bexpr e1 x y, rewrite_bexpr e2 x y)
    | _ -> b
;;

let bimpl b1 b2 = Bor (Bneg b1, b2);;
(** val nexpr_var : nexpr -> var list **)

let rec print_bexpr b =
  match b with
    | BTrue -> printf "True"
    | BFalse -> printf "False"
    | Beq (e1, e2) -> print_nexpr e1; printf " == "; print_nexpr e2;
    | Blt (e1, e2) -> print_nexpr e1; printf " < "; print_nexpr e2;
    | Ble (e1, e2) -> print_nexpr e1; printf " <= "; print_nexpr e2;
    | Bgt (e1, e2) -> print_nexpr e1; printf " > "; print_nexpr e2;
    | Bge (e1, e2) -> print_nexpr e1; printf " >= "; print_nexpr e2;
    | Bneg b1 -> printf "!( "; print_bexpr b1; printf " )";
    | Band (b1, b2) -> printf "( "; print_bexpr b1; printf " ) /\\ ("; print_bexpr b2; printf " )";
    | Bor (b1, b2) ->
        match b1 with
          | Bneg b1' ->
              printf "( "; print_bexpr b1'; printf " ) -> ("; print_bexpr b2; printf " )";
          | _ ->
              printf "( "; print_bexpr b1; printf " ) \\/ ("; print_bexpr b2; printf " )";
;;

let rec simpl_bexpr b =
  match b with
    | Bneg b -> (
        match (simpl_bexpr b) with
          | BTrue -> BFalse
          | BFalse -> BTrue
          | b' -> Bneg b'
      )        
    | Bor (b1, b2) -> (
        match (simpl_bexpr b1, simpl_bexpr b2) with
          | (BTrue, _) -> BTrue
          | (_, BTrue) -> BTrue
          | (BFalse, b2') -> b2'
          | (b1', BFalse) -> b1'
          | (b1', b2') -> Bor (b1', b2')
      )
    | Band (b1, b2) -> (
        match (simpl_bexpr b1, simpl_bexpr b2) with
          | (BFalse, _) -> BFalse
          | (_, BFalse) -> BFalse
          | (BTrue, b2') -> b2'
          | (b1', BTrue) -> b1'
          | (b1', b2') -> Band (b1', b2')
      )
    | _ -> b
;;

let rec nexpr_var = function
  | Nvar x -> VarSet.singleton x
  | Ncons z0 -> VarSet.empty
  | Nplus (e1, e2) -> (nexpr_var e1) +++ (nexpr_var e2)
  | Nminus (e1, e2) -> (nexpr_var e1) +++ (nexpr_var e2) 
  | Nmult (e1, e2) -> (nexpr_var e1) +++ (nexpr_var e2)

(** val neg_propagate : bexpr -> bool -> bexpr **)

let rec neg_propagate b n =
  match b with
    | BTrue -> 
        if n then BFalse else BTrue
    | BFalse -> 
        if n then BTrue else BFalse
    | Beq (n0, n1) -> (match n with
        | true -> Bneg b
        | false -> b)
    | Blt (n0, n1) -> (match n with
        | true -> Bneg b
        | false -> b)
    | Ble (n0, n1) -> (match n with
        | true -> Bneg b
        | false -> b)
    | Bgt (n0, n1) -> (match n with
        | true -> Bneg b
        | false -> b)
    | Bge (n0, n1) -> (match n with
        | true -> Bneg b
        | false -> b)
    | Bneg b1 -> neg_propagate b1 (not n)
    | Band (b1, b2) ->
        (match n with
          | true -> Bor ((neg_propagate b1 true), (neg_propagate b2 true))
          | false -> Band ((neg_propagate b1 false),
                          (neg_propagate b2 false)))
    | Bor (b1, b2) ->
        (match n with
          | true -> Band ((neg_propagate b1 true), (neg_propagate b2 true))
          | false -> Bor ((neg_propagate b1 false),
                         (neg_propagate b2 false)))


type constraint0 = nexpr

let print_cons c =
  printf "0 >= "; print_nexpr c;;

type andlist = constraint0 list

let rec print_andlist l =
  match l with
    | [] -> printf "True"; printf ") ";
    | hd::tl ->
        print_cons hd; printf " /\\ "; print_andlist tl
;;

(** val andlist_plus_andlist : andlist -> andlist -> andlist **)

let andlist_plus_andlist c1 c2 =
  c1 @ c2

type orlist = andlist list


let rec print_orlist l =
  match l with
    | [] -> printf "False"; 
    | hd::tl ->
        printf "( "; print_andlist hd; printf "\\/\n"; print_orlist tl;
;;

(** val orlist_plus_orlist : orlist -> orlist -> orlist **)

let orlist_plus_orlist d1 d2 =
  d1 @ d2


(** val andlist_mult_orlist : andlist -> orlist -> orlist **)

let rec andlist_mult_orlist c = function
  | [] -> []
  | (hd :: tl) ->
      orlist_plus_orlist ((andlist_plus_andlist c hd) :: [])
        (andlist_mult_orlist c tl)


(** val orlist_mult_orlist : orlist -> orlist -> orlist **)

let rec orlist_mult_orlist d1 d2 =
  match d1 with
    | [] -> []
    | (hd :: tl) ->
        orlist_plus_orlist (andlist_mult_orlist hd d2)
          (orlist_mult_orlist tl d2)

(** val disj_nf : bexpr -> orlist **)

let rec disj_nf = function
  | BTrue -> ((Ncons 0)::[]) :: []
  | BFalse -> ((Ncons 1) :: []) :: []
  | Beq (e1, e2) -> ((((Nminus (e1, e2)) :: (((Nminus (e2, e1))::
                                                 [])))) :: [])
  | Blt (e1, e2) -> ((((Nminus ((Nplus (e1, (Ncons 1))), 
                               e2)):: [])):: [])
  | Ble (e1, e2) -> ((((Nminus (e1, e2)) :: [])) :: [])
  | Bgt (e1, e2) -> ((((Nminus ((Nplus (e2, (Ncons 1))),
                               e1)) :: []))::[])
  | Bge (e1, e2) -> ((((Nminus (e2, e1))::[]))::[])
  | Bneg b1 ->
      (match b1 with
        | Beq (e1, e2) -> ((((Nminus ((Nplus (e1, (Ncons 1))), e2))::[])):: (((((Nminus ((Nplus (e2, (Ncons
                                                                                                         1))), e1))::[]))::[])))
        | Blt (e1, e2) -> ((((Nminus (e2, e1))::[]))::[])
        | Ble (e1, e2) -> ((((Nminus ((Nplus (e2, (Ncons 1))), e1))::[]))::[])
        | Bgt (e1, e2) -> ((((Nminus (e1, e2))::[]))::[])
        | Bge (e1, e2) -> ((((Nminus ((Nplus (e1, (Ncons 1))), e2))::[]))::[])
        | Bneg b0 -> []
        | Band (b0, b2) -> []
        | Bor (b0, b2) -> []
        | BTrue -> ((Ncons 1) :: []) :: []
        | BFalse -> ((Ncons 0) :: []) :: []
      )
  | Band (e1, e2) -> orlist_mult_orlist (disj_nf e1) (disj_nf e2)
  | Bor (e1, e2) -> orlist_plus_orlist (disj_nf e1) (disj_nf e2)

(** val expr_b2constraints : bexpr -> orlist **)

let expr_b2constraints b =
  disj_nf (neg_propagate b false)

(** val nexpr_compute : nexpr -> z option **)

let rec nexpr_compute = function
  | Nvar x -> None
  | Ncons x -> Some x
  | Nplus (e1, e2) ->
      (match nexpr_compute e1 with
        | Some e1' ->
            (match nexpr_compute e2 with
              | Some e2' -> Some (e1' + e2')
              | None -> None)
        | None -> None)
  | Nminus (e1, e2) ->
      (match nexpr_compute e1 with
        | Some e1' ->
            (match nexpr_compute e2 with
              | Some e2' -> Some (e1' - e2')
              | None -> None)
        | None -> None)
  | Nmult (e1, e2) ->
      (match nexpr_compute e1 with
        | Some e1' -> (
            if (e1' = 0) then
              Some 0
            else
              (match nexpr_compute e2 with
                | Some e2' -> Some (e1' * e2')
                | None -> None)
          )      
        | None ->      
            (match nexpr_compute e2 with
              | Some e2' ->
                  (match e2' = 0 with
                    | true -> Some 0
                    | false -> None)
              | None -> None
            )
      )
;;



(** val simpl_nexpr : nexpr -> nexpr **)

let rec simpl_nexpr = function
  | Nvar v -> Nvar v
  | Ncons z0 -> Ncons z0
  | Nplus (e1, e2) ->
      let e1' = simpl_nexpr e1 in
      let e2' = simpl_nexpr e2 in
        (match nexpr_compute e1' with
          | Some z1 ->
              (match nexpr_compute e2' with
                | Some z2 -> Ncons (z1 + z2)
                | None ->
                    (match z1 = 0 with
                      | true -> e2'
                      | false -> Nplus ((Ncons z1), e2')))
          | None ->
              (match nexpr_compute e2' with
                | Some z2 ->
                    (match z2 = 0 with
                      | true -> e1'
                      | false -> Nplus (e1', (Ncons z2)))
                | None -> Nplus (e1', e2')))
  | Nminus (e1, e2) ->
      let e1' = simpl_nexpr e1 in
      let e2' = simpl_nexpr e2 in
        (match nexpr_compute e1' with
          | Some z1 ->
              (match nexpr_compute e2' with
                | Some z2 -> Ncons (z1 - z2)
                | None -> Nminus ((Ncons z1), e2'))
          | None ->
              (match nexpr_compute e2' with
                | Some z2 ->
                    (match z2 = 0 with
                      | true -> e1'
                      | false -> Nminus (e1', (Ncons z2)))
                | None -> Nminus (e1', e2')))
  | Nmult (e1, e2) ->
      let e1' = simpl_nexpr e1 in
      let e2' = simpl_nexpr e2 in
        (match nexpr_compute e1' with
          | Some z1 ->
              (match nexpr_compute e2' with
                | Some z2 -> Ncons (z1 * z2)
                | None ->
                    (match z1 = 0 with
                      | true -> Ncons 0
                      | false ->
                          (match z1 = 1 with
                            | true -> e2'
                            | false -> Nmult ((Ncons z1), e2'))))
          | None ->
              (match nexpr_compute e2' with
                | Some z2 ->
                    (match z2 = 0 with
                      | true -> Ncons 0
                      | false ->
                          (match z2 = 1 with
                            | true -> e1'
                            | false -> Nmult (e1', (Ncons z2))))
                | None -> Nmult (e1', e2')))



(** val nexpr_var_fact : nexpr -> nat -> (nexpr, nexpr) prod **)

let rec nexpr_var_fact e v =
  match e with
    | Nvar x ->
        (match String.compare x v with
          | 0 -> ((Ncons 1), (Ncons 0))
          | _ -> ((Ncons 0), (Nvar x)))
    | Ncons z0 -> ((Ncons 0), (Ncons z0))
    | Nplus (e1, e2) ->
        let (e11, e12) = nexpr_var_fact e1 v in
        let (e21, e22) = nexpr_var_fact e2 v in
          ((Nplus (e11, e21)), (Nplus (e12, e22)))
    | Nminus (e1, e2) ->
        let (e11, e12) = nexpr_var_fact e1 v in
        let (e21, e22) = nexpr_var_fact e2 v in
          ((Nminus (e11, e21)), (Nminus (e12, e22)))
    | Nmult (e1, e2) ->
        let (e11, e12) = nexpr_var_fact e1 v in
        let (e21, e22) = nexpr_var_fact e2 v in
          ((Nplus ((Nplus ((Nmult (e11, e22)), (Nmult (e21, e12)))),
                  (Nmult ((Nvar v), (Nmult (e11, e21)))))), (Nmult (e12, e22)))


(** val nexpr_simpl_var_fact : nexpr -> nat -> (nexpr, nexpr) prod **)

let nexpr_simpl_var_fact n v =
  let (e1, e2) = nexpr_var_fact n v in
    ((simpl_nexpr e1), (simpl_nexpr e2))

(** val elim_var_constraint : constraint0 -> constraint0 -> constraint0 ->
    constraint0 -> nat -> constraint0 option **)

let elim_var_constraint e11 e12 e21 e22 v =
  match nexpr_compute (simpl_nexpr e11) with
    | Some e11' ->
        (match nexpr_compute (simpl_nexpr e21) with
          | Some e21' ->
              (match match 0 < e11' with
                | true -> e21' < 0
                | false -> false
                with
                  | true -> Some (Nminus ((Nmult ((Ncons e11'), e22)), (Nmult
                                                                           ((Ncons e21'), e12))))
                  | false ->
                      (match 
                          match 0 < e21' with
                            | true -> e11' < 0
                            | false -> false
                        with
                          | true -> Some (Nminus ((Nmult ((Ncons e21'), e12)),
                                                 (Nmult ((Ncons e11'), e22))))
                          | false -> None))
          | None -> None)
    | None -> None


(** val elim_var_constraint_andlist : constraint0 -> constraint0 -> andlist
    -> nat -> andlist **)

let rec elim_var_constraint_andlist e11 e12 l v =
  match l with
    | [] -> []
    | (hd:: tl) ->
        let (e21, e22) = nexpr_simpl_var_fact hd v in        
          (match elim_var_constraint e11 e12 e21 e22 v with
            | Some hd' -> (hd'::[])
            | None -> []) @ (elim_var_constraint_andlist e11 e12 tl v)

(** val elim_var_andlist : andlist -> nat -> andlist **)

let rec elim_var_andlist l v =
  match l with
    | [] -> []
    | (hd:: tl) ->
        let (e11, e12) = nexpr_simpl_var_fact hd v in
          (match nexpr_compute (simpl_nexpr e11) with
            | Some e11' ->
                (match e11' = 0 with
                  | true -> 
                      ((simpl_nexpr (Nplus ((Nmult ((Nvar v), e11)), e12)))::[])
                  | false -> elim_var_constraint_andlist e11 e12 tl v)
            | None -> 
                ((simpl_nexpr (Nplus ((Nmult ((Nvar v), e11)), e12)))::[])) @
            (elim_var_andlist tl v)


(** val elim_listvar_andlist : andlist -> nat list -> andlist **)

let rec elim_listvar_andlist l = function
  | [] -> l
  | (hd:: tl) -> elim_listvar_andlist (elim_var_andlist l hd) tl

(** val andlist_var : andlist -> var list **)

let rec andlist_var = function
  | [] -> VarSet.empty
  | (hd:: tl) -> (nexpr_var hd) +++ (andlist_var tl)

(** val elim_allvar_andlist : andlist -> andlist **)

let elim_allvar_andlist l =
  elim_listvar_andlist l (VarSet.elements (andlist_var l))

(** val elim_allvar_orlist : orlist -> orlist **)

let rec elim_allvar_orlist = function
  | [] -> []
  | (hd:: tl) -> ((elim_allvar_andlist hd) :: (elim_allvar_orlist tl))


(** val neval_constraint : constraint0 -> bool option **)

let neval_constraint c =
  match nexpr_compute c with
    | Some z0 -> Some
        (match z0 <= 0 with
          | true -> true
          | false -> false)
    | None -> None

(** val neval_andlist' : andlist -> bool option **)

let rec neval_andlist' = function
  | [] -> Some true
  | (hd:: tl) ->
      (match neval_constraint hd with
        | Some b ->
            (match b with
              | true ->
                  (match neval_andlist' tl with
                    | Some b0 ->
                        (match b0 with
                          | true ->
                              (match neval_constraint hd with
                                | Some a' -> Some a'
                                | None -> None)
                          | false -> Some false)
                    | None -> None)
              | false -> Some false)
        | None ->
            (match neval_andlist' tl with
              | Some b ->
                  (match b with
                    | true ->
                        (match neval_constraint hd with
                          | Some a' -> Some a'
                          | None -> None)
                    | false -> Some false)
              | None -> None))

(** val neval_andlist : andlist -> bool option **)

let neval_andlist a =
  match (List.length a) = 0 with
    | true -> None
    | false -> neval_andlist' a

(** val neval_orlist' : orlist -> bool option **)

let rec neval_orlist' = function
  | [] -> Some false
  | (hd:: tl) ->
      (match neval_andlist hd with
        | Some a' ->
            (match neval_orlist' tl with
              | Some b' -> Some
                  (match a' with
                    | true -> true
                    | false -> b')
              | None -> None)
        | None -> None)

(** val neval_orlist : orlist -> bool option **)

let neval_orlist a =
  match (List.length a) = 0 with
    | true -> None
    | false -> neval_orlist' a

(** val fm_dp : bexpr -> bool **)

let fm_dp b =
  let b1 = (expr_b2constraints (simpl_bexpr (Bneg b))) in
  let b2 = (elim_allvar_orlist b1) in
    match neval_orlist b2 with
      | Some res -> 
	  (*
	  (
            match (res) with
            | true -> 
	        printf "arith false:\n"; 
                print_bexpr b; printf "\n\n";
                print_orlist b1; printf "\n\n";
                print_orlist b2; printf "\n\n";
		
            | _ -> ();
        ); *)
	  not res
      | None -> 
	  (*
          printf "cannot evaluate:\n"; 
          print_orlist b1; printf "\n\n";
          print_orlist b2; printf "\n\n";
	  *)
          false

