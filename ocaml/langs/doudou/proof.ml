open Parser
open Pprinter
open Doudou
open Printf
(*
  This is an attempt to have a facility for step by step proof 
*)

(*
  first we have the hypothesis 
  of the form prf * lemma 
  all terms type under the same context ctxt/defs such that
  ctxt |- prf :: lemma :: Type

  It means basically that the proof/type of hypothesis does not depends on other hypothesis
*)
type hypothesis = term * term

(*
  BEFORE: for now we just store them into a map from name to hypothesis
  
  the hypothesis are stored by their categorie: a string representing their types
  see the following function for the mapping
*)
let term2category (te: term) : string =
  match te with
    | Type _ -> "Type"
    | Cste (s, _) | App (Cste (s, _), _, _) -> symbol2string s
    | TVar _ -> "Var"
    | Impl _ -> "(->)"
    (* other term should not be hypothesis (that we consider in normal formal form (== beta reduced)) *)
    | _ -> "??"

module NameMap = Map.Make(
  struct
    type t = string
    let compare x y = compare x y
  end
);;

(* the first level represent category, the second names of the hypothesis *)
type hypothesises = (hypothesis NameMap.t) NameMap.t

(*
  few helper functions on hypothesis
*)

(* shifting of hypothesises, all hypothesises which cannot be shifted (due to negative shifting) *)
let shift_hypothesises (hyps: hypothesises) (level: int) =
  NameMap.fold (fun category hyps acc ->
    NameMap.add category (
      NameMap.fold (fun name (prf, lemma) acc ->
	try 
	  NameMap.add name (shift_term prf level, shift_term lemma level) acc
	with
	  | DoudouException (Unshiftable_term _) -> acc
      ) hyps NameMap.empty
    ) acc
  ) hyps NameMap.empty

(* a function that check that all hypothesis are well typed *)
let check_hypothesis (defs: defs) (ctxt: context) (hyps: hypothesises) : unit =
  NameMap.iter (fun category hyps -> 
    NameMap.iter (fun name (prf, lemma) -> 
      ignore(typecheck defs (ref ctxt) lemma (Type nopos));
      ignore(typecheck defs (ref ctxt) prf lemma)
    ) hyps
  ) hyps

(* hypothesis2 token *)
let hypothesises2token (ctxt: context) (hyps: hypothesises) : token =
  Box (
    NameMap.fold (fun category hyps acc ->
      acc @ (NameMap.fold (fun key (prf, lemma) acc ->
	acc @ [Box [Verbatim key; Space 1; Verbatim "::"; Space 1; term2token ctxt lemma Alone]; Newline]
      ) hyps [])
    ) hyps []
  )

(* input an hypothesis in a proof_context *)
let input_hypothesis (hyp: hypothesis) ?(name: string = "H") (hyps: hypothesises) : hypothesises =
  (* grab the proof and the lemma *)
  let prf, lemma = hyp in
  (* find the category (create an empty map of hypothesises if it does not exists) *)
  let category = term2category lemma in
  let category_hyps = try NameMap.find category hyps with | Not_found -> NameMap.empty in
  (* grab the names of this category hypothesis, and generate a fresh name from the given one *)
  let category_hyps_names = NameMap.fold (fun k _ acc -> NameSet.add k acc) category_hyps NameSet.empty in
  let name = String.concat "." [category; name] in
  let name = fresh_name ~basename:name category_hyps_names in
  (* and finally update the map of hypothesis *)
  (* please note that we do not check for duplicate *)
  let category_hyps = NameMap.add name hyp category_hyps in
  NameMap.add category category_hyps hyps

(*
  this is the proof context

  defs: the global definitions under which all Cste types
  ctxt: the global context under which all Variables types
  hyps: the current set of hypothesis (valid under defs, ctxt)

*)

type proof_context = {
  defs: defs;
  ctxt: context;
  hyps: hypothesises;
}

(*
  pretty print of a proof_context
*)
let proof_context2token (ctxt: proof_context) : token =
  Bar (true,
    Bar (true, Verbatim " ",
	 Bar 
	   (false,
	    Bar (true, 
		 Box [Verbatim "   DEFINITIONS:";
		      Newline; 
		      Verbatim "-----------------";
		      Newline; 
		      defs2token ctxt.defs], 
		 Box [Verbatim "   CONTEXT:";
			Newline; 
			Verbatim "--------------";
			Newline; 
			context2token ctxt.ctxt]),
	    Box [Verbatim "   HYPOTHESIS:"; 
		 Newline; 
		 Verbatim "-----------------"; 
		 Newline; 
		 hypothesises2token ctxt.ctxt ctxt.hyps])	   
    ), Verbatim " ")

let proof_context2string (ctxt: proof_context) : string =
  let token = proof_context2token ctxt in
  let box = token2box token 100 2 in
  box2string box

let proof_state2token (ctxt: proof_context) (goal: term) : token =
  Bar (true,
    Bar (true, Verbatim " ",
	 Bar 
	   (false,
	    Bar (true, 
		 Box [Verbatim "   DEFINITIONS:";
		      Newline; 
		      Verbatim "-----------------";
		      Newline; 
		      defs2token ctxt.defs], 
		 Box [Verbatim "   CONTEXT:";
			Newline; 
			Verbatim "--------------";
			Newline; 
			context2token ctxt.ctxt]),
	    Box [Verbatim "   HYPOTHESIS:"; 
		 Newline; 
		 Verbatim "-----------------"; 
		 Newline; 
		 hypothesises2token ctxt.ctxt ctxt.hyps])	   
    ), Box [Verbatim "goal:"; Newline; ISpace 4; term2token ctxt.ctxt goal Alone])

let proof_state2string (ctxt: proof_context) (goal: term) : string =
  let token = proof_state2token ctxt goal in
  let box = token2box token 100 2 in
  box2string box

(*
  the empty proof_context
*)

let empty_proof_context (defs: defs) = {
  defs = defs;
  ctxt = empty_context;
  hyps = NameMap.empty;
}

(*
  a flag that check whenever needed that a proof_context and the goals are valid
*)

let force_check = ref true

(*
  an exception when a goal cannot be solved
*)
exception CannotSolveGoal

(*
  checking a proof context and goals
*)
let check_proof_context (ctxt: proof_context) (goals: (term * term) list) : unit =
  ignore(check_hypothesis ctxt.defs ctxt.ctxt ctxt.hyps);
  ignore(List.iter (fun (prf, goal) -> 
    ignore(typecheck ctxt.defs (ref ctxt.ctxt) goal (Type nopos));
    ignore(typecheck ctxt.defs (ref ctxt.ctxt) prf goal);
  ) goals)

(*
  push/pop a quantification in a proof_context
*)
let push_quantification (ctxt: proof_context) (q : symbol * term * nature * pos) : proof_context =
  (* we compute the new context *)
  let ctxt' = let ctxt = ref ctxt.ctxt in push_quantification q ctxt; !ctxt in
  (* we compute the new hypothesises *)
  let hyps' = shift_hypothesises ctxt.hyps 1 in
  {ctxt with ctxt = ctxt'; hyps = hyps'}

let pop_quantification (ctxt: proof_context) (prf: term) : proof_context * (symbol * term * nature * pos) * term =
  let ctxt', q, prf = 
    let ctxt = ref ctxt.ctxt in 
    let q, [prf] = pop_quantification ctxt [prf] in 
    !ctxt, q, prf
  in
  let hyps' = shift_hypothesises ctxt.hyps (-1) in
  {ctxt with ctxt = ctxt'; hyps = hyps'}, q, prf

(*
  a proof_solver: a function that takes a proof_context and a goal and returns a proof_context together with a proof of the goal
*)
type proof_solver = proof_context -> term -> proof_context * term

(*
  a proof_context_transformer: a function that modifies the proof_context (such that it stay valid)
*)

type proof_context_transformer = proof_context -> proof_context

(*
  a goal_transformer: a function that modifies the goal (such that it stay valid under the proof_context)
*)

type goal_transformer = proof_context -> term -> term

(*
  for witenessing a term we might split a goal in different subgoals which need all to be proved

  prfctxt: the original proof_context
  goals: a list of sub-goals together with thir solver function
  merge: a function that merges goals together

  the proof is sequential, in order, the context is shared/extends

*)
let split_goal_allneeded (ctxt: proof_context) (goals: (term * proof_solver) list) (merge: term list -> term) : proof_context * term =
  (* we traverse the goals and their provers *)
  let ctxt, rev_prfs = List.fold_left (fun (ctxt, prfs) (goal, solver) ->
    let ctxt, prf = solver ctxt goal in
    if !force_check then check_proof_context ctxt [prf, goal];
    ctxt, prf::prfs 
  ) (ctxt, []) goals in
  (* we merge the proofs in the right order *)
  let prf = merge (List.rev rev_prfs) in
  (* checking if we wish to *)
  if !force_check then check_proof_context ctxt [];
  (* returning the result*)
  ctxt, prf

(*
  for witenessing a term we might split a goal in different possible subgoals of which only one need to be solved

  prfctxt: the original proof_context
  goals: a list of sub-goals together with their solver function and the function to rebuild the proof

  the contexts are not shared

*)
let split_goal_oneneeded (ctxt: proof_context) (goals: (term * proof_solver * (term -> term)) list) : proof_context * term =
  (* we try all the goals *)
  let res = fold_stop (fun () (goal, solver, prf_builder) ->
    try
      let ctxt, prf = solver ctxt goal in
      if !force_check then check_proof_context ctxt [prf, goal];
      let prf = prf_builder prf in
      Right (ctxt, prf)
    with
      | CannotSolveGoal -> Left ()
  ) () goals in
  match res with
    (* we cannot find any proof for the goals *)
    | Left () ->
      raise CannotSolveGoal
    | Right res -> res

(*
  when the goal is an Impl, we might want to introduce the quantification, 
  prove the goal and quantify it by a Lambda
*)
let introduce_impl (ctxt: proof_context) (goal: term) (solver: proof_solver) : proof_context * term =
  match goal with
    (* an implication, we can do a introduction *)
    | Impl (q, body, pos) ->
      (* quantifying the Impl *)
      let ctxt = push_quantification ctxt q in
      (* try to solve the goal *)
      let ctxt, prf = solver ctxt body in
      (* do a check *)
      if !force_check then check_proof_context ctxt [prf, body];
      (* pop the quantification *)
      let ctxt, q, prf = pop_quantification ctxt prf in
      (* rebuilt the proof *)
      let prf = Lambda (q, prf, nopos) in
      (* do a check *)
      if !force_check then check_proof_context ctxt [prf, goal];
      (* return the result *)
      ctxt, prf
    (* not an implication, cannot introduce  *)
    | _ -> raise CannotSolveGoal

(*
  tactic: an ast which semantics is a proof_solver
*)

type tactic = Fail
	      | Msg of string * tactic
	      | ShowGoal of tactic 

	      | Exact of term

	      | Apply of term

	      | NYD 

(* helper functions *)

(* this function apply to a term a free variable for each of its remaining arguments *)
let rec complete_explicit_arguments (ctxt: context ref) (te: term) (ty: term) : term =
  match ty with
    | Impl ((_, _, nature, _), ty, _) ->
      let fvty = add_fvar ctxt (Type nopos) in
      let fvte = add_fvar ctxt (TVar (fvty, nopos)) in
      complete_explicit_arguments ctxt (App (te, [TVar (fvte, nopos), nature], nopos)) ty
    | _ -> te  

(* the semantics *)

let rec tactic_semantics (t: tactic) : proof_solver = 
  match t with
    | Fail -> raise CannotSolveGoal

    | Msg (s, t) -> printf "%s\n" s; tactic_semantics t

    | ShowGoal t -> (
      fun ctxt goal ->
	printf "%s\n\n\n" (proof_state2string ctxt goal); tactic_semantics t ctxt goal
    )

    | Exact prf -> (
      fun ctxt goal ->
	let prf, _ = 
	  try 
	    typecheck ctxt.defs (ref ctxt.ctxt) prf goal
	  with
	    | DoudouException err ->
	      printf "%s\n" (error2string err);
	      raise CannotSolveGoal
	in
	ctxt, prf	
    )

    | Apply prf -> (fun ctxt goal ->
      (* first we typeinfer the term *)
      let ctxt' = ref ctxt.ctxt in
      let prf, ty = typeinfer ctxt.defs ctxt' prf in
      printf "infered apply: %s :: %s\n" (term2string !ctxt' prf) (term2string !ctxt' ty);
      let prf' = complete_explicit_arguments ctxt' prf ty in
      printf "completed term: %s\n" (term2string !ctxt' prf');
      (* we typecheck against the goal to infer the free variables type *)
      let prf', _ = typecheck ctxt.defs ctxt' prf' goal in
      IndexSet.iter (fun var ->
	printf "need to find a goal of type: %s\n" (term2string !ctxt' (fvar_type !ctxt' var))
      ) (fv_term prf');
      raise CannotSolveGoal
    )
    | _ -> raise Exit


