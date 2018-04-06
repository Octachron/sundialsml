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

module Klu = struct

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
end

module Superlumt = struct

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
end

module Direct = struct

  type _ solver =
    | Dense       : Matrix.Dense.t solver
    | LapackDense : Matrix.Dense.t solver
    | Band        : Matrix.Band.t  solver
    | LapackBand  : Matrix.Band.t  solver
    | Klu         : Klu.info       -> 's Matrix.Sparse.t solver
    | Superlumt   : Superlumt.info -> 's Matrix.Sparse.t solver

  type cptr

  type ('m, 'nd, 'nk) t = {
    rawptr : cptr;
    solver : 'm solver;
  }
end

module Iterative = struct

  (* Must correspond with lsolver_ml.h:lsolver_gramschmidt_type_tag *)
  type gramschmidt_type = Spils.gramschmidt_type =
    | ModifiedGS
    | ClassicalGS

  (* Must correspond with lsolver_ml.h:lsolver_preconditioning_type_tag *)
  type preconditioning_type = Spils.preconditioning_type =
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
  type solver =
    | Spbcgs
    | Spfgmr
    | Spgmr
    | Sptfqmr
    | Pcg

  type cptr

  type ('nd, 'nk, 'f) t = {
    rawptr : cptr;
    solver : solver;
    compat : info;
  }

  external c_set_prec_type : cptr -> solver -> preconditioning_type -> unit
    = "ml_lsolvers_set_prec_type"

end

