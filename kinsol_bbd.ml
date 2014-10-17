(***********************************************************************)
(*                                                                     *)
(*                   OCaml interface to Sundials                       *)
(*                                                                     *)
(*  Timothy Bourke (Inria), Jun Inoue (Inria), and Marc Pouzet (LIENS) *)
(*                                                                     *)
(*  Copyright 2014 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under a BSD 2-Clause License, refer to the file LICENSE.           *)
(*                                                                     *)
(***********************************************************************)

include Kinsol_impl
include KinsolBbdTypes

type parallel_session =
      (Nvector_parallel.data, Nvector_parallel.kind) Kinsol.session
type parallel_preconditioner =
      (Nvector_parallel.data, Nvector_parallel.kind) Kinsol.Spils.preconditioner

module Impl = KinsolBbdParamTypes
type local_fn = Nvector_parallel.data Impl.local_fn
type comm_fn = Nvector_parallel.data Impl.comm_fn
type callbacks =
  {
    local_fn : local_fn;
    comm_fn  : comm_fn option;
  }

let bbd_callbacks { local_fn; comm_fn } =
  { Impl.local_fn = local_fn; Impl.comm_fn = comm_fn }

external c_bbd_prec_init
    : parallel_session -> int -> bandwidths -> float -> bool -> unit
    = "c_kinsol_bbd_prec_init"

let init_preconditioner dqrely bandwidths callbacks session onv =
  (* FIXME: is it really legitimate to pass 0?  If so, why not always
     do that?  *)
  let localn =
    match onv with
    | None -> 0
    | Some nv -> let ba, _, _ = Nvector.unwrap nv in
                 Sundials.RealArray.length ba
  in
  c_bbd_prec_init session localn bandwidths dqrely (callbacks.comm_fn <> None);
  session.ls_callbacks <- BBDCallback (bbd_callbacks callbacks)

let prec_right ?(dqrely=0.0) bandwidths ?comm_fn local_fn =
  SpilsTypes.InternalPrecRight
    (init_preconditioner dqrely bandwidths { local_fn; comm_fn })

external get_work_space : parallel_session -> int * int
    = "c_kinsol_bbd_get_work_space"

external get_num_gfn_evals : parallel_session -> int
    = "c_kinsol_bbd_get_num_gfn_evals"
