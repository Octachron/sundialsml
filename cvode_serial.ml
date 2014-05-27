(***********************************************************************)
(*                                                                     *)
(*               OCaml interface to (serial) Sundials                  *)
(*                                                                     *)
(*  Timothy Bourke (Inria), Jun Inoue (Inria), and Marc Pouzet (LIENS) *)
(*                                                                     *)
(*  Copyright 2014 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under a BSD 2-Clause License, refer to the file LICENSE.           *)
(*                                                                     *)
(***********************************************************************)

include Cvode_session_serial

let spils_no_precond = { prec_solve_fn = None;
                         prec_setup_fn = None;
                         jac_times_vec_fn = None; }

let read_weak_ref x : session =
  match Weak.get x 0 with
  | Some y -> y
  | None -> raise (Failure "Internal error: weak reference is dead")

let adjust_retcode = fun session check_recoverable f x ->
  try f x; 0
  with
  | Sundials.RecoverableFailure when check_recoverable -> 1
  | e -> (session.exn_temp <- Some e; -1)

let call_rhsfn session t y y' =
  let session = read_weak_ref session in
  adjust_retcode session true (session.rhsfn t y) y'

let call_errw session y ewt =
  let session = read_weak_ref session in
  adjust_retcode session false (session.errw y) ewt

let call_errh session details =
  let session = read_weak_ref session in
  try session.errh details
  with e ->
    prerr_endline ("Warning: error handler function raised an exception.  " ^
                   "This exception will not be propagated.")

let call_jacfn session jac j =
  let session = read_weak_ref session in
  adjust_retcode session true (session.jacfn jac) j

let call_bandjacfn session jac mupper mlower j =
  let session = read_weak_ref session in
  adjust_retcode session true (session.bandjacfn jac mupper mlower) j

let call_presolvefn session jac r z =
  let session = read_weak_ref session in
  adjust_retcode session true (session.presolvefn jac r) z

let call_jactimesfn session jac v jv =
  let session = read_weak_ref session in
  adjust_retcode session true (session.jactimesfn jac v) jv

let _ =
  Callback.register "c_ba_cvode_call_rhsfn"         call_rhsfn;
  Callback.register "c_ba_cvode_call_errh"          call_errh;
  Callback.register "c_ba_cvode_call_errw"          call_errw;
  Callback.register "c_ba_cvode_call_jacfn"         call_jacfn;
  Callback.register "c_ba_cvode_call_bandjacfn"     call_bandjacfn;
  Callback.register "c_ba_cvode_call_presolvefn"    call_presolvefn;
  Callback.register "c_ba_cvode_call_jactimesfn"    call_jactimesfn;

external session_finalize : session -> unit
    = "c_cvode_session_finalize"

external c_init
    : session Weak.t -> lmm -> iter -> nvec -> float
      -> (cvode_mem * c_weak_ref * cvode_file)
    = "c_ba_cvode_init"

external c_root_init : session -> int -> unit
    = "c_ba_cvode_root_init"

let root_init session (nroots, rootsfn) =
  c_root_init session nroots;
  session.rootsfn <- rootsfn

external c_dls_dense : session -> bool -> unit
  = "c_ba_cvode_dls_dense"

external c_dls_lapack_dense : session -> bool -> unit
  = "c_ba_cvode_dls_lapack_dense"

external c_dls_band : session -> int -> int -> bool -> unit
  = "c_ba_cvode_dls_band"

external c_dls_lapack_band : session -> int -> int -> bool -> unit
  = "c_ba_cvode_dls_lapack_band"

external c_diag : session -> unit
  = "c_cvode_diag"

external c_spils_set_preconditioner
  : session -> bool -> bool -> unit
  = "c_ba_cvode_spils_set_preconditioner"

external c_spils_spgmr
  : session -> int -> Spils.preconditioning_type -> unit
  = "c_cvode_spils_spgmr"

external c_spils_spbcg
  : session -> int -> Spils.preconditioning_type -> unit
  = "c_cvode_spils_spbcg"

external c_spils_sptfqmr
  : session -> int -> Spils.preconditioning_type -> unit
  = "c_cvode_spils_sptfqmr"

external c_spils_banded_spgmr
  : session -> int -> int -> int -> Spils.preconditioning_type -> unit
  = "c_ba_cvode_spils_banded_spgmr"

external c_spils_banded_spbcg
  : session -> int -> int -> int -> Spils.preconditioning_type -> unit
  = "c_ba_cvode_spils_banded_spbcg"

external c_spils_banded_sptfqmr
  : session -> int -> int -> int -> Spils.preconditioning_type -> unit
  = "c_ba_cvode_spils_banded_sptfqmr"

external c_set_functional : session -> unit
  = "c_cvode_set_functional"

let set_iter_type session iter =
  let optionally f = function
    | None -> ()
    | Some x -> f x
  in
  let set_precond prec_type cb =
    match prec_type with
    | Spils.PrecNone -> ()
    | Spils.PrecLeft | Spils.PrecRight | Spils.PrecBoth ->
      match cb.prec_solve_fn with
      | None -> invalid_arg "preconditioning type is not PrecNone, but no \
                             solve function given"
      | Some solve_fn ->
        c_spils_set_preconditioner session
          (cb.prec_setup_fn <> None)
          (cb.jac_times_vec_fn <> None);
        session.presolvefn <- solve_fn;
        optionally (fun f -> session.presetupfn <- f) cb.prec_setup_fn;
        optionally (fun f -> session.jactimesfn <- f) cb.jac_times_vec_fn
  in
  (* Release references to all linear solver-related callbacks.  *)
  session.jacfn      <- dummy_dense_jac;
  session.bandjacfn  <- dummy_band_jac;
  session.presetupfn <- dummy_prec_setup;
  session.presolvefn <- dummy_prec_solve;
  session.jactimesfn <- dummy_jac_times_vec;
  match iter with
  | Functional -> c_set_functional session
  | Newton linsolv ->
    (* Iter type will be set to CV_NEWTON in the functions that set the linear
       solver.  *)
    match linsolv with
    | Dense jac ->
      c_dls_dense session (jac <> None);
      optionally (fun f -> session.jacfn <- f) jac
    | LapackDense jac ->
      c_dls_lapack_dense session (jac <> None);
      optionally (fun f -> session.jacfn <- f) jac
    | Band (p, jac) ->
      c_dls_band session p.mupper p.mlower (jac <> None);
      optionally (fun f -> session.bandjacfn <- f) jac
    | LapackBand (p, jac) ->
      c_dls_lapack_band session p.mupper p.mlower (jac <> None);
      optionally (fun f -> session.bandjacfn <- f) jac
    | Diag -> c_diag session
    | Spgmr (par, cb) ->
        let maxl = match par.maxl with None -> 0 | Some ml -> ml in
        c_spils_spgmr session maxl par.prec_type;
        set_precond par.prec_type cb
    | Spbcg (par, cb) ->
        let maxl = match par.maxl with None -> 0 | Some ml -> ml in
        c_spils_spbcg session maxl par.prec_type;
        set_precond par.prec_type cb
    | Sptfqmr (par, cb) ->
        let maxl = match par.maxl with None -> 0 | Some ml -> ml in
        c_spils_sptfqmr session maxl par.prec_type;
        set_precond par.prec_type cb
    | BandedSpgmr (sp, br) ->
        let maxl = match sp.maxl with None -> 0 | Some ml -> ml in
        c_spils_banded_spgmr session br.mupper br.mlower maxl sp.prec_type
    | BandedSpbcg (sp, br) ->
        let maxl = match sp.maxl with None -> 0 | Some ml -> ml in
        c_spils_banded_spbcg session br.mupper br.mlower maxl sp.prec_type
    | BandedSptfqmr (sp, br) ->
        let maxl = match sp.maxl with None -> 0 | Some ml -> ml in
        c_spils_banded_sptfqmr session br.mupper br.mlower maxl sp.prec_type

external sv_tolerances  : session -> float -> nvec -> unit
    = "c_ba_cvode_sv_tolerances"
external ss_tolerances  : session -> float -> float -> unit
    = "c_cvode_ss_tolerances"
external wf_tolerances  : session -> unit
    = "c_ba_cvode_wf_tolerances"

type tolerance =
  | SSTolerances of float * float
  | SVTolerances of float * nvec
  | WFTolerances of (val_array -> val_array -> unit)

let default_tolerances = SSTolerances (1.0e-4, 1.0e-8)

let set_tolerances s tol =
  match tol with
  | SSTolerances (rel, abs) -> ss_tolerances s rel abs
  | SVTolerances (rel, abs) -> sv_tolerances s rel abs
  | WFTolerances ferrw -> (s.errw <- ferrw; wf_tolerances s)

let init lmm iter tol f ?(roots=no_roots) ?(t0=0.) y0 =
  let (nroots, roots) = roots in
  if nroots < 0 then
    raise (Invalid_argument "number of root functions is negative");
  let neqs    = Carray.length y0 in
  let weakref = Weak.create 1 in
  let cvode_mem, backref, err_file = c_init weakref lmm iter y0 t0 in
  (* cvode_mem and backref have to be immediately captured in a session and
     associated with the finalizer before we do anything else.  *)
  let session = {
          cvode      = cvode_mem;
          backref    = backref;
          neqs       = neqs;
          nroots     = nroots;
          err_file   = err_file;

          exn_temp   = None;

          rhsfn      = f;
          rootsfn    = roots;
          errh       = (fun _ -> ());
          errw       = (fun _ _ -> ());
          jacfn      = dummy_dense_jac;
          bandjacfn  = dummy_band_jac;
          presetupfn = dummy_prec_setup;
          presolvefn = dummy_prec_solve;
          jactimesfn = dummy_jac_times_vec;

          sensext    = NoSensExt;
        } in
  Gc.finalise session_finalize session;
  Weak.set weakref 0 (Some session);
  (* Now the session is safe to use.  If any of the following fails and raises
     an exception, the GC will take care of freeing cvode_mem and backref.  *)
  if nroots > 0 then
    c_root_init session nroots;
  set_iter_type session iter;
  set_tolerances session tol;
  session

let nroots { nroots } = nroots
let neqs { neqs } = neqs

external c_reinit
    : session -> float -> val_array -> unit
    = "c_ba_cvode_reinit"
let reinit session ?iter_type ?roots t0 y0 =
  c_reinit session t0 y0;
  (match iter_type with
   | None -> ()
   | Some iter_type -> set_iter_type session iter_type);
  (match roots with
   | None -> ()
   | Some roots -> root_init session roots)

external get_root_info  : session -> root_array -> unit
    = "c_cvode_get_root_info"

external solve_normal
    : session -> float -> val_array -> float * solver_result
    = "c_ba_cvode_solve_normal"

external solve_one_step
    : session -> float -> val_array -> float * solver_result
    = "c_ba_cvode_solve_one_step"

external get_dky
    : session -> float -> int -> nvec -> unit
    = "c_ba_cvode_get_dky"

external get_integrator_stats   : session -> integrator_stats
    = "c_cvode_get_integrator_stats"

external get_work_space         : session -> int * int
    = "c_cvode_get_work_space"

external get_num_steps          : session -> int
    = "c_cvode_get_num_steps"

external get_num_rhs_evals      : session -> int
    = "c_cvode_get_num_rhs_evals"

external get_num_lin_solv_setups : session -> int
    = "c_cvode_get_num_lin_solv_setups"

external get_num_err_test_fails : session -> int
    = "c_cvode_get_num_err_test_fails"

external get_last_order         : session -> int
    = "c_cvode_get_last_order"

external get_current_order      : session -> int
    = "c_cvode_get_current_order"

external get_actual_init_step   : session -> float
    = "c_cvode_get_actual_init_step"

external get_last_step          : session -> float
    = "c_cvode_get_last_step"

external get_current_step       : session -> float
    = "c_cvode_get_current_step"

external get_current_time       : session -> float
    = "c_cvode_get_current_time"

let print_integrator_stats s =
  let stats = get_integrator_stats s
  in
    Printf.printf "num_steps = %d\n"           stats.num_steps;
    Printf.printf "num_rhs_evals = %d\n"       stats.num_rhs_evals;
    Printf.printf "num_lin_solv_setups = %d\n" stats.num_lin_solv_setups;
    Printf.printf "num_err_test_fails = %d\n"  stats.num_err_test_fails;
    Printf.printf "last_order = %d\n"          stats.last_order;
    Printf.printf "current_order = %d\n"       stats.current_order;
    Printf.printf "actual_init_step = %e\n"    stats.actual_init_step;
    Printf.printf "last_step = %e\n"           stats.last_step;
    Printf.printf "current_step = %e\n"        stats.current_step;
    Printf.printf "current_time = %e\n"        stats.current_time;

external set_error_file : session -> string -> bool -> unit
    = "c_cvode_set_error_file"

external set_err_handler_fn  : session -> unit
    = "c_ba_cvode_set_err_handler_fn"

let set_err_handler_fn s ferrh =
  s.errh <- ferrh;
  set_err_handler_fn s

external clear_err_handler_fn  : session -> unit
    = "c_ba_cvode_clear_err_handler_fn"

let clear_err_handler_fn s =
  s.errh <- (fun _ -> ());
  clear_err_handler_fn s

external set_max_ord            : session -> int -> unit
    = "c_cvode_set_max_ord"
external set_max_num_steps      : session -> int -> unit
    = "c_cvode_set_max_num_steps"
external set_max_hnil_warns     : session -> int -> unit
    = "c_cvode_set_max_hnil_warns"
external set_stab_lim_det       : session -> bool -> unit
    = "c_cvode_set_stab_lim_det"
external set_init_step          : session -> float -> unit
    = "c_cvode_set_init_step"
external set_min_step           : session -> float -> unit
    = "c_cvode_set_min_step"
external set_max_step           : session -> float -> unit
    = "c_cvode_set_max_step"
external set_stop_time          : session -> float -> unit
    = "c_cvode_set_stop_time"
external set_max_err_test_fails : session -> int -> unit
    = "c_cvode_set_max_err_test_fails"
external set_max_nonlin_iters   : session -> int -> unit
    = "c_cvode_set_max_nonlin_iters"
external set_max_conv_fails     : session -> int -> unit
    = "c_cvode_set_max_conv_fails"
external set_nonlin_conv_coef   : session -> float -> unit
    = "c_cvode_set_nonlin_conv_coef"

external set_root_direction'    : session -> RootDirs.t -> unit
    = "c_cvode_set_root_direction"

let set_root_direction s rda = 
  set_root_direction' s (RootDirs.copy_n (nroots s) rda)

let set_all_root_directions s rd =
  set_root_direction' s (RootDirs.make (nroots s) rd)

external set_no_inactive_root_warn      : session -> unit
    = "c_cvode_set_no_inactive_root_warn"

external get_num_stab_lim_order_reds    : session -> int
    = "c_cvode_get_num_stab_lim_order_reds"

external get_tol_scale_factor           : session -> float
    = "c_cvode_get_tol_scale_factor"

external get_err_weights                : session -> nvec -> unit
    = "c_ba_cvode_get_err_weights"

external get_est_local_errors           : session -> nvec -> unit
    = "c_ba_cvode_get_est_local_errors"

external get_num_nonlin_solv_iters      : session -> int
    = "c_cvode_get_num_nonlin_solv_iters"

external get_num_nonlin_solv_conv_fails : session -> int
    = "c_cvode_get_num_nonlin_solv_conv_fails"

external get_num_g_evals                : session -> int
    = "c_cvode_get_num_g_evals"

module Dls =
  struct
    external set_dense_jac_fn  : session -> unit
        = "c_ba_cvode_dls_set_dense_jac_fn"

    let set_dense_jac_fn s fjacfn =
      s.jacfn <- fjacfn;
      set_dense_jac_fn s

    external clear_dense_jac_fn : session -> unit
        = "c_ba_cvode_dls_clear_dense_jac_fn"

    let clear_dense_jac_fn s =
      s.jacfn <- dummy_dense_jac;
      clear_dense_jac_fn s

    external set_band_jac_fn   : session -> unit
        = "c_ba_cvode_dls_set_band_jac_fn"

    let set_band_jac_fn s fbandjacfn =
      s.bandjacfn <- fbandjacfn;
      set_band_jac_fn s

    external clear_band_jac_fn : session -> unit
        = "c_ba_cvode_dls_clear_band_jac_fn"

    let clear_band_jac_fn s =
      s.bandjacfn <- dummy_band_jac;
      clear_band_jac_fn s

    external get_work_space : session -> int * int
        = "c_cvode_dls_get_work_space"

    external get_num_jac_evals    : session -> int
        = "c_cvode_dls_get_num_jac_evals"

    external get_num_rhs_evals    : session -> int
        = "c_cvode_dls_get_num_rhs_evals"
  end

module Diag =
  struct
    external get_work_space       : session -> int * int
        = "c_cvode_diag_get_work_space"

    external get_num_rhs_evals    : session -> int
        = "c_cvode_diag_get_num_rhs_evals"
  end

module BandPrec =
  struct
    external get_work_space : session -> int * int
        = "c_cvode_bandprec_get_work_space"

    external get_num_rhs_evals    : session -> int
        = "c_cvode_bandprec_get_num_rhs_evals"
  end

module Spils =
  struct
    type solve_arg = prec_solve_arg =
      {
        rhs   : val_array;
        gamma : float;
        delta : float;
        left  : bool;
      }

    external set_preconditioner  : session -> unit
        = "c_nvec_cvode_set_preconditioner"

    let set_preconditioner s fpresetupfn fpresolvefn =
      s.presetupfn <- fpresetupfn;
      s.presolvefn <- fpresolvefn;
      set_preconditioner s

    external set_jac_times_vec_fn : session -> unit
        = "c_nvec_cvode_set_jac_times_vec_fn"

    let set_jac_times_vec_fn s fjactimesfn =
      s.jactimesfn <- fjactimesfn;
      set_jac_times_vec_fn s

    external clear_jac_times_vec_fn : session -> unit
        = "c_nvec_cvode_clear_jac_times_vec_fn"

    let clear_jac_times_vec_fn s =
      s.jactimesfn <- (fun _ _ _ -> ());
      clear_jac_times_vec_fn s

    external set_prec_type : session -> Spils.preconditioning_type -> unit
        = "c_cvode_set_prec_type"

    external set_gs_type : session -> Spils.gramschmidt_type -> unit
        = "c_cvode_set_gs_type"

    external set_eps_lin            : session -> float -> unit
        = "c_cvode_set_eps_lin"

    external set_maxl               : session -> int -> unit
        = "c_cvode_set_maxl"

    external get_num_lin_iters      : session -> int
        = "c_cvode_spils_get_num_lin_iters"

    external get_num_conv_fails     : session -> int
        = "c_cvode_spils_get_num_conv_fails"

    external get_work_space         : session -> int * int
        = "c_cvode_spils_get_work_space"

    external get_num_prec_evals     : session -> int
        = "c_cvode_spils_get_num_prec_evals"

    external get_num_prec_solves    : session -> int
        = "c_cvode_spils_get_num_prec_solves"

    external get_num_jtimes_evals   : session -> int
        = "c_cvode_spils_get_num_jtimes_evals"

    external get_num_rhs_evals      : session -> int
        = "c_cvode_spils_get_num_rhs_evals"

  end

