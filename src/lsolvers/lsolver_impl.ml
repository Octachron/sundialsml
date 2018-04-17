(***********************************************************************)
(*                                                                     *)
(*                   OCaml interface to Sundials                       *)
(*                                                                     *)
(*  Timothy Bourke (Inria), Jun Inoue (Inria), and Marc Pouzet (LIENS) *)
(*                                                                     *)
(*  Copyright 2018 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under a New BSD License, refer to the file LICENSE.                *)
(*                                                                     *)
(***********************************************************************)

(* Types underlying Lsolver.  *)

(* This module defines the lsolver types which are manipulated (abstractly)
   via the Lsolver module. They are declared here so that they can also be
   used (concretely) from the <solver> modules. To ensure that this type will
   be opaque outside of Sundials/ML, we simply do not install the
   lsolver_impl.cmi file. *)

exception SolverInUse

module Klu = struct (* {{{ *)

  type tag = [`Klu]

  (* Must correspond with lsolver_ml.h:lsolver_klu_ordering_tag *)
  type ordering =
    Amd
  | ColAmd
  | Natural

  type info = {
    mutable ordering : ordering option;

    mutable reinit : int -> int option -> unit;
    mutable set_ordering : ordering -> unit;
  }

  let info = {
    ordering     = None;
    reinit       = (fun _ _ -> ());
    set_ordering = (fun _ -> ());
  }

end (* }}} *)

module Superlumt = struct (* {{{ *)

  type tag = [`Superlumt]

  (* Must correspond with lsolver_ml.h:lsolver_superlumt_ordering_tag *)
  type ordering =
    Natural
  | MinDegreeProd
  | MinDegreeSum
  | ColAmd

  type info = {
    mutable ordering     : ordering option;
    mutable set_ordering : ordering -> unit;
    num_threads          : int;
  }

  let info num_threads = {
    ordering     = None;
    set_ordering = (fun _ -> ());
    num_threads  = num_threads;
  }

end (* }}} *)

module Custom = struct (* {{{ *)

  type 'lsolver tag = [`Custom of 'lsolver]

  type ('data, 'kind) atimes_with_data

  external call_atimes
    : ('data, 'kind) atimes_with_data
      -> ('data, 'kind) Nvector.t
      -> ('data, 'kind) Nvector.t
      -> unit
    = "ml_lsolver_call_atimes"

  type ('data, 'kind) precond_with_data

  external call_psetup : ('data, 'kind) precond_with_data -> unit
    = "ml_lsolver_call_psetup"

  external call_psolve
    : ('data, 'kind) precond_with_data
      -> ('data, 'kind) Nvector.t
      -> ('data, 'kind) Nvector.t
      -> float
      -> bool
      -> unit
    = "ml_lsolver_call_psolve"

  (* The fields and their order must match lsolver_ml.h:lsolver_ops_index *)
  type ('matrix, 'data, 'kind) ops = {
    init : unit -> unit;

    setup : 'matrix -> unit;

    solve :
      'matrix
      -> ('data, 'kind) Nvector.t
      -> ('data, 'kind) Nvector.t
      -> float
      -> unit;

    set_atimes : ('data, 'kind) atimes_with_data -> unit;

    set_preconditioner :
      ('data, 'kind) precond_with_data -> bool -> bool -> unit;

    set_scaling_vectors :
      ('data, 'kind) Nvector.t option
      -> ('data, 'kind) Nvector.t option
      -> unit;

    get_num_iters : unit -> int;

    get_res_norm : unit -> float;

    get_res_id : unit -> ('data, 'kind) Nvector.t;

    get_work_space : unit -> int * int
  }

  (* The fields and their order must match lsolver_ml.h:lsolver_hasops_index *)
  type has_ops = {
    has_set_atimes          : bool;
    has_set_preconditioner  : bool;
    has_set_scaling_vectors : bool;
    has_get_num_iters       : bool;
    has_get_res_norm        : bool;
    has_get_res_id          : bool;
    has_get_work_space      : bool;
  }

end (* }}} *)

module Direct = struct (* {{{ *)

  type tag = [`Basic]

  type ('m, 'nd, 'nk, 't) solver =
    | Dense       : (Matrix.Dense.t, 'nd, 'nk, tag) solver
    | LapackDense : (Matrix.Dense.t, 'nd, 'nk, tag) solver
    | Band        : (Matrix.Band.t,  'nd, 'nk, tag) solver
    | LapackBand  : (Matrix.Band.t,  'nd, 'nk, tag) solver
    | Klu         : Klu.info
                    -> ('s Matrix.Sparse.t, 'nd, 'nk, [>Klu.tag]) solver
    | Superlumt   : Superlumt.info
                    -> ('s Matrix.Sparse.t, 'nd, 'nk, [>Superlumt.tag]) solver
    | Custom      : 'lsolver * ('m, 'nd, 'nk) Custom.ops
                     -> ('m, 'nd, 'nk, 'lsolver Custom.tag) solver

  type ('m, 'nd, 'nk) cptr

  let only_ops = Custom.({
      has_set_atimes          = false;
      has_set_preconditioner  = false;
      has_set_scaling_vectors = false;
      has_get_num_iters       = false;
      has_get_res_norm        = false;
      has_get_res_id          = false;
      has_get_work_space      = false;
    })

  external c_make_custom
    : int -> ('m, 'nd, 'nk) Custom.ops -> Custom.has_ops -> ('m, 'nd, 'nk) cptr
    = "ml_lsolver_make_custom"

  type ('m, 'nd, 'nk, 't) t = {
    rawptr : ('m, 'nd, 'nk) cptr;
    solver : ('m, 'nd, 'nk, 't) solver;
    mutable attached : bool;
  }

  let attach ({ attached } as s) =
    if attached then raise SolverInUse;
    s.attached <- true

end (* }}} *)

module Iterative = struct (* {{{ *)

  (* Must correspond with lsolver_ml.h:lsolver_gramschmidt_type_tag *)
  type gramschmidt_type =
    | ModifiedGS
    | ClassicalGS

  (* Must correspond with lsolver_ml.h:lsolver_preconditioning_type_tag *)
  type preconditioning_type =
    | PrecNone
    | PrecLeft
    | PrecRight
    | PrecBoth

  type info = {
    mutable maxl             : int;
    mutable gs_type          : gramschmidt_type option;

    mutable set_maxl         : int -> unit;
    mutable set_gs_type      : gramschmidt_type -> unit;
    mutable set_prec_type    : preconditioning_type -> unit;
  }

  let info = {
    maxl             = 0;
    gs_type          = None;

    set_maxl         = (fun _ -> ());
    set_gs_type      = (fun _ -> ());
    set_prec_type    = (fun _ -> ());
  }

  (* Must correspond with lsolver_ml.h:lsolver_iterative_solver_tag *)
  type ('nd, 'nk, 'lsolver) solver =
    | Spbcgs  : ('nd, 'nk, [`Spbcgs]) solver
    | Spfgmr  : ('nd, 'nk, [`Spfgmr]) solver
    | Spgmr   : ('nd, 'nk, [`Spgmr])  solver
    | Sptfqmr : ('nd, 'nk, [`Sptfqmr]) solver
    | Pcg     : ('nd, 'nk, [`Pcg])    solver
    | Custom  : 'lsolver * (unit, 'nd, 'nk) Custom.ops
                -> ('nd, 'nk, 'lsolver Custom.tag) solver

  type ('nd, 'nk) cptr

  external c_make_custom
    : int -> (unit, 'nd, 'nk) Custom.ops -> Custom.has_ops -> ('nd, 'nk) cptr
    = "ml_lsolver_make_custom"

  type ('nd, 'nk, 't) t = {
    rawptr : ('nd, 'nk) cptr;
    solver : ('nd, 'nk, 't) solver;
    compat : info;
    mutable check_prec_type : preconditioning_type -> bool;
    mutable attached : bool;
  }

  let attach ({ attached } as s) =
    if attached then raise SolverInUse;
    s.attached <- true

  external c_set_prec_type
    : ('nd, 'nk) cptr -> ('nd, 'nk, 't) solver -> preconditioning_type -> unit
    = "ml_lsolvers_set_prec_type"

end (* }}} *)

(* Used by the solver implementations to 'hold' a linear solver so that it
   is not garbage collected while still required (i.e., while a pointer is
   still held in an underlying C data structure. *)
type solver =
  | NoSolver
  | DirectSolver : ('m, 'nd, 'nk, 't) Direct.t -> solver
  | IterativeSolver : ('nd, 'nk, 't) Iterative.t -> solver

