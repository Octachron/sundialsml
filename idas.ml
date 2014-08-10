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

include Ida_impl
type serial_session = (real_array, Nvector_serial.kind) session

external c_alloc_nvector_array : int -> 'a array
    = "c_idas_alloc_nvector_array"

let add_fwdsensext s =
  match s.sensext with
  | FwdSensExt se -> ()
  | BwdSensExt _ -> failwith "Quadrature.add_fwdsensext: internal error"
  | NoSensExt ->
      s.sensext <- FwdSensExt {
        num_sensitivities = 0;
        sensarray1      = c_alloc_nvector_array 0;
        sensarray2      = c_alloc_nvector_array 0;
        sensarray3      = c_alloc_nvector_array 0;
        quadrhsfn       = (fun _ _ _ _ -> ());
        senspvals       = None;
        sensresfn       = (fun _ _ _ _ _ _ _ _ _ _ -> ());
        quadsensrhsfn   = (fun _ _ _ _ _ _ _ -> ());
        bsessions       = [];
      }

let num_sensitivities s =
  match s.sensext with
  | FwdSensExt se -> se.num_sensitivities
  (*| BwdSensExt se -> se.bnum_sensitivities*)
  | _ -> 0

let read_weak_ref x : ('a, 'kind) session =
  match Weak.get x 0 with
  | Some y -> y
  | None -> raise (Failure "Internal error: weak reference is dead")

let read_weak_fwd_ref x =
  let y = read_weak_ref x in
  match y.sensext with
  | FwdSensExt se -> (y, se)
  | _ -> raise (Failure "Internal error: not forward extension")

let read_weak_bwd_ref x =
  let y = read_weak_ref x in
  match y.sensext with
  (*| BwdSensExt se -> (y, se)*)
  | _ -> raise (Failure "Internal error: not backward extension")

let adjust_retcode = fun session f x ->
  try f x; 0
  with
  | Sundials.RecoverableFailure _ -> 1
  | e -> (session.exn_temp <- Some e; -1)

let adjust_retcode_and_bool = fun session f x ->
  try (f x, 0)
  with
  | Sundials.RecoverableFailure r -> (r, 1)
  | e -> (session.exn_temp <- Some e; (false, -1))

let call_quadrhsfn session t y y' rhsQ =
  let (session, fwdsensext) = read_weak_fwd_ref session in
  adjust_retcode session (fwdsensext.quadrhsfn t y y') rhsQ

(* fwdsensext.sensrhsfn is called directly from C *)

let _ =
  Callback.register "c_idas_call_quadrhsfn"     call_quadrhsfn;
(*
  Callback.register "c_idas_call_brhsfn"        call_brhsfn;
  Callback.register "c_idas_call_bquadrhsfn"    call_bquadrhsfn;
  Callback.register "c_idas_call_bprecsetupfn"  call_bprecsetupfn;
  Callback.register "c_idas_call_bprecsolvefn"  call_bprecsolvefn;
  Callback.register "c_idas_call_bjactimesfn"   call_bjactimesfn;
  Callback.register "c_idas_call_bjacfn"        call_bjacfn;
  Callback.register "c_idas_call_bbandjacfn"    call_bbandjacfn
*)

module Quadrature =
  struct
    exception QuadNotInitialized
    exception QuadRhsFuncFailure
    exception FirstQuadRhsFuncErr
    exception RepeatedQuadRhsFuncErr
    exception UnrecoverableQuadRhsFuncErr

    let _ = List.iter (fun (nm, ex) -> Callback.register_exception nm ex)
      [
        ("idas_QuadNotInitialized",           QuadNotInitialized);
        ("idas_QuadRhsFuncFailure",           QuadRhsFuncFailure);
        ("idas_FirstQuadRhsFuncErr",          FirstQuadRhsFuncErr);
        ("idas_RepeatedQuadRhsFuncErr",       RepeatedQuadRhsFuncErr);
        ("idas_UnrecoverableQuadRhsFuncErr",  UnrecoverableQuadRhsFuncErr);
      ]

    let fwdsensext s =
      match s.sensext with
      | FwdSensExt se -> se
      | _ -> raise QuadNotInitialized

    type 'a quadrhsfn = float -> 'a -> 'a -> unit

    external c_quad_init : ('a, 'k) session -> ('a, 'k) nvector -> unit
        = "c_idas_quad_init"

    let init session f yQ0 =
      add_fwdsensext session;
      let s = fwdsensext session in
      s.quadrhsfn <- f;
      c_quad_init session yQ0

    external reinit : ('a, 'k) session -> ('a, 'k) nvector -> unit
      = "c_idas_quad_reinit"

    external set_err_con    : ('a, 'k) session -> bool -> unit
        = "c_idas_quad_set_err_con"
    external sv_tolerances
        : ('a, 'k) session -> float -> ('a, 'k) nvector -> unit
        = "c_idas_quad_sv_tolerances"
    external ss_tolerances  : ('a, 'k) session -> float -> float -> unit
        = "c_idas_quad_ss_tolerances"

    type ('a, 'k) tolerance =
        NoStepSizeControl
      | SStolerances of float * float
      | SVtolerances of float * ('a, 'k) nvector

    let set_tolerances s tol =
      match tol with
      | NoStepSizeControl -> set_err_con s false
      | SStolerances (rel, abs) -> (ss_tolerances s rel abs;
                                    set_err_con s true)
      | SVtolerances (rel, abs) -> (sv_tolerances s rel abs;
                                    set_err_con s true)

    external get : ('a, 'k) session -> ('a, 'k) nvector -> float
        = "c_idas_quad_get"

    external get_dky
        : ('a, 'k) session -> float -> int -> ('a, 'k) nvector -> unit
        = "c_idas_quad_get_dky"

    external get_num_rhs_evals       : ('a, 'k) session -> int
        = "c_idas_quad_get_num_rhs_evals"

    external get_num_err_test_fails  : ('a, 'k) session -> int
        = "c_idas_quad_get_num_err_test_fails"

    external get_err_weights : ('a, 'k) session -> ('a, 'k) nvector -> unit
        = "c_idas_quad_get_err_weights"

    external get_stats : ('a, 'k) session -> int * int
        = "c_idas_quad_get_stats"

  end

module Sensitivity =
  struct
    type ('a, 'k) tolerance =
        SStolerances of float * Sundials.RealArray.t
      | SVtolerances of float * ('a, 'k) nvector array
      | EEtolerances

    external set_err_con : ('a, 'k) session -> bool -> unit
        = "c_idas_sens_set_err_con"

    external ss_tolerances
        : ('a, 'k) session -> float -> Sundials.RealArray.t -> unit
        = "c_idas_sens_ss_tolerances"

    external ee_tolerances  : ('a, 'k) session -> unit
        = "c_idas_sens_ee_tolerances"

    external sv_tolerances
        : ('a, 'k) session -> float -> ('a, 'k) nvector array -> unit
        = "c_idas_sens_sv_tolerances"

    let set_tolerances s tol =
      let ns = num_sensitivities s in
      match tol with
      | SStolerances (rel, abs) -> begin
            if Bigarray.Array1.dim abs <> ns
            then invalid_arg "set_tolerances: abstol has the wrong length";
            ss_tolerances s rel abs
          end
      | SVtolerances (rel, abs) -> begin
            if Array.length abs <> ns
            then invalid_arg "set_tolerances: abstol has the wrong length";
            sv_tolerances s rel abs
          end
      | EEtolerances -> ee_tolerances s

    exception SensNotInitialized
    exception SensResFuncFailure
    exception FirstSensRhsFuncErr
    exception RepeatedSensRhsFuncErr
    exception UnrecoverableSensRhsFuncErr
    exception BadIS

    let _ = List.iter (fun (nm, ex) -> Callback.register_exception nm ex)
      [
        ("idas_SensNotInitialized",           SensNotInitialized);
        ("idas_SensResFuncFailure",           SensResFuncFailure);
        ("idas_FirstSensRhsFuncErr",          FirstSensRhsFuncErr);
        ("idas_RepeatedSensRhsFuncErr",       RepeatedSensRhsFuncErr);
        ("idas_UnrecoverableSensRhsFuncErr",  UnrecoverableSensRhsFuncErr);
        ("idas_BadIS",                        BadIS);
      ]

    let fwdsensext s =
      match s.sensext with
      | FwdSensExt se -> se
      | _ -> raise SensNotInitialized

    type sens_method =
        Simultaneous
      | Staggered
      | Staggered1

    type 'a sensresfn = 'a Ida_impl.sensresfn

    type sens_params = {
        pvals  : Sundials.RealArray.t option;
        pbar   : Sundials.RealArray.t option;
        plist  : int array option;
      }

    let no_sens_params = { pvals = None; pbar = None; plist = None }

    external c_sens_init : ('a, 'k) session -> sens_method -> bool
                           -> ('a, 'k) nvector array
                           -> ('a, 'k) nvector array -> unit
      = "c_idas_sens_init"

    external c_set_params : ('a, 'k) session -> sens_params -> unit
        = "c_idas_sens_set_params"

    let set_params s ({pvals; pbar; plist} as ps) =
      let ns = num_sensitivities s in
      let np = match pvals with None -> 0 | Some p -> Bigarray.Array1.dim p in
      let check_pi v =
        if v < 0 || v >= np
        then invalid_arg "set_params: plist has an invalid entry" in
      (match pbar with
       | None -> ()
       | Some p -> if Bigarray.Array1.dim p <> ns
                   then invalid_arg "set_params: pbar has the wrong length");
      (match plist with
       | None -> ()
       | Some p -> if Array.length p <> ns
         then invalid_arg "set_params: plist has the wrong length"
         else Array.iter check_pi p);
      c_set_params s ps


    let init s tol fmethod sparams sensresfn y0 y'0 =
      add_fwdsensext s;
      let se = fwdsensext s in
      let ns = Array.length y0 in
      if ns <> Array.length y'0 then
        invalid_arg "init: y0 and y'0 have inconsistent lengths";
      c_sens_init s fmethod (sensresfn <> None) y0 y'0;
      (match sensresfn with
       | Some f -> se.sensresfn <- f
       | None -> ());
      se.num_sensitivities <- ns;
      se.senspvals <- sparams.pvals;
      se.sensarray1 <- c_alloc_nvector_array ns;
      se.sensarray2 <- c_alloc_nvector_array ns;
      se.sensarray3 <- c_alloc_nvector_array ns;
      set_params s sparams;
      set_tolerances s tol


    external c_reinit
      : ('a, 'k) session -> sens_method
        -> ('a, 'k) nvector array -> ('a, 'k) nvector array -> unit
      = "c_idas_sens_reinit"

    let reinit s sm s0 =
      if Array.length s0 <> num_sensitivities s
      then invalid_arg "reinit: wrong number of sensitivity vectors";
      c_reinit s sm s0

    external toggle_off : ('a, 'k) session -> unit
      = "c_idas_sens_toggle_off"

    external c_get : ('a, 'k) session -> ('a, 'k) nvector array -> float
      = "c_idas_sens_get"

    let get s ys =
      if Array.length ys <> num_sensitivities s
      then invalid_arg "get: wrong number of sensitivity vectors";
      c_get s ys

    external c_get_dky
      : ('a, 'k) session -> float -> int -> ('a, 'k) nvector array -> unit
      = "c_idas_sens_get_dky"

    let get_dky s t k dkys =
      if Array.length dkys <> num_sensitivities s
      then invalid_arg "get_dky: wrong number of sensitivity vectors";
      c_get_dky s t k dkys

    external get1 : ('a, 'k) session -> int -> ('a, 'k) nvector -> float
      = "c_idas_sens_get1"

    external get_dky1
      : ('a, 'k) session -> float -> int -> int -> ('a, 'k) nvector -> unit
      = "c_idas_sens_get_dky1"

    type dq_method = DQCentered | DQForward

    external set_dq_method : ('a, 'k) session -> dq_method -> float -> unit
      = "c_idas_sens_set_dq_method"

    external set_max_nonlin_iters : ('a, 'k) session -> int -> unit
      = "c_idas_sens_set_max_nonlin_iters"

    external get_num_res_evals : ('a, 'k) session -> int
      = "c_idas_sens_get_num_res_evals"

    external get_num_res_evals_sens : ('a, 'k) session -> int
      = "c_idas_sens_get_num_res_evals_sens"

    external get_num_err_test_fails : ('a, 'k) session -> int
      = "c_idas_sens_get_num_err_test_fails"

    external get_num_lin_solv_setups : ('a, 'k) session -> int
      = "c_idas_sens_get_num_lin_solv_setups"

    type sensitivity_stats = {
      num_res_evals : int;
      num_sens_evals :int;
      num_err_test_fails : int;
      num_lin_solv_setups :int;
    }

    external get_stats : ('a, 'k) session -> sensitivity_stats
      = "c_idas_sens_get_stats"

    external c_get_err_weights
      : ('a, 'k) session -> ('a, 'k) nvector array -> unit
      = "c_idas_sens_get_err_weights"

    let get_err_weights s esweight =
      if Array.length esweight <> num_sensitivities s
      then invalid_arg "get_err_weights: wrong number of vectors";
      c_get_err_weights s esweight

    external c_sens_calc_ic_ya_yd' :
      ('a,'k) session
      -> ('a,'k) nvector option
      -> ('a,'k) nvector option
      -> ('a,'k) nvector array option
      -> ('a,'k) nvector array option
      -> ('a,'k) nvector -> float -> unit
      = "c_ida_sens_calc_ic_ya_ydp_byte"
        "c_ida_sens_calc_ic_ya_ydp"

    external c_sens_calc_ic_y :
      ('a,'k) session
      -> ('a,'k) nvector option
      -> ('a,'k) nvector option
      -> float -> unit
      = "c_ida_sens_calc_ic_y"

    let calc_ic_ya_yd' session ?y ?y' ?ys ?y's id tout1 =
      c_sens_calc_ic_ya_yd' session y y' ys y's id tout1

    (* Note: my understanding is that CalcIC with IDA_Y_INIT corrects
       the non-derivatives of the sensitivity variables while holding
       the derivatives constant, so there's no point querying the
       values of the corrected derivatives.  *)
    let calc_ic_y session ?y ?ys tout1 =
      c_sens_calc_ic_y session y ys tout1

    external get_num_nonlin_solv_iters : ('a, 'k) session -> int
      = "c_idas_sens_get_num_nonlin_solv_iters"

    external get_num_nonlin_solv_conv_fails : ('a, 'k) session -> int
      = "c_idas_sens_get_num_nonlin_solv_conv_fails"

    external get_nonlin_solv_stats : ('a, 'k) session -> int * int
      = "c_idas_sens_get_nonlin_solv_stats"

    module Quadrature =
    struct

      exception QuadSensNotInitialized
      exception QuadSensRhsFuncFailure
      exception FirstQuadSensRhsFuncErr
      exception RepeatedQuadSensRhsFuncErr
      exception UnrecoverableQuadSensRhsFuncErr

      let _ = List.iter (fun (nm, ex) -> Callback.register_exception nm ex)
          [
            ("ida_QuadSensNotInitialized",     QuadSensNotInitialized);
            ("ida_QuadSensRhsFuncFailure",     QuadSensRhsFuncFailure);
            ("ida_FirstQuadSensRhsFuncErr",    FirstQuadSensRhsFuncErr);
            ("ida_RepeatedQuadSensRhsFuncErr", RepeatedQuadSensRhsFuncErr);
            ("ida_UnrecoverableQuadSensRhsFuncErr",
             UnrecoverableQuadSensRhsFuncErr);
          ]

      type 'a quadsensrhsfn =
        float          (* t *)
        -> 'a          (* y *)
        -> 'a          (* y' *)
        -> 'a array    (* yS *)
        -> 'a array    (* y'S *)
        -> 'a          (* rrQ *)
        -> 'a array    (* rhsvalQs *)
        -> 'a          (* tmp1 *)
        -> 'a          (* tmp2 *)
        -> 'a          (* tmp3 *)
        -> unit

      external c_quadsens_init
        : ('a, 'k) session -> bool -> ('a, 'k) nvector array -> unit
        = "c_idas_quadsens_init"

      let init s f v0 =
        let se = fwdsensext s in
        let ns = num_sensitivities s in
        if Array.length v0 <> ns
        then invalid_arg "init: wrong number of vectors";
        match f with
        | Some f -> se.quadsensrhsfn <- f;
                    c_quadsens_init s true v0
        | None -> c_quadsens_init s false v0

      external c_reinit : ('a, 'k) session -> ('a, 'k) nvector array -> unit
        = "c_idas_quadsens_reinit"

      let reinit s v =
        let ns = num_sensitivities s in
        if Array.length v <> ns
        then invalid_arg "reinit: wrong number of vectors";
        c_reinit s v

      type ('a, 'k) tolerance =
          NoStepSizeControl
        | SStolerances of float * Sundials.RealArray.t
        | SVtolerances of float * ('a, 'k) nvector array
        | EEtolerances

      external set_err_con : ('a, 'k) session -> bool -> unit
        = "c_idas_quadsens_set_err_con"

      external ss_tolerances
        : ('a, 'k) session -> float -> Sundials.RealArray.t -> unit
        = "c_idas_quadsens_ss_tolerances"

      external sv_tolerances
        : ('a, 'k) session -> float -> ('a, 'k) nvector array -> unit
        = "c_idas_quadsens_sv_tolerances"

      external ee_tolerances  : ('a, 'k) session -> unit
        = "c_idas_quadsens_ee_tolerances"

      let set_tolerances s tol =
        let ns = num_sensitivities s in
        match tol with
        | NoStepSizeControl -> set_err_con s false
        | SStolerances (rel, abs) -> begin
            if Bigarray.Array1.dim abs <> ns
            then invalid_arg "set_tolerances: abstol has the wrong length";
            ss_tolerances s rel abs;
            set_err_con s true
          end
        | SVtolerances (rel, abs) -> begin
            if Array.length abs <> ns
            then invalid_arg "set_tolerances: abstol has the wrong length";
            sv_tolerances s rel abs;
            set_err_con s true
          end
        | EEtolerances -> (ee_tolerances s;
                           set_err_con s true)

      external c_get : ('a, 'k) session -> ('a, 'k) nvector array -> float
        = "c_idas_quadsens_get"

      let get s ys =
        let ns = num_sensitivities s in
        if Array.length ys <> ns
        then invalid_arg "get: wrong number of vectors";
        c_get s ys

      external get1 : ('a, 'k) session -> int -> ('a, 'k) nvector -> float
        = "c_idas_quadsens_get1"

      external c_get_dky
        : ('a, 'k) session -> float -> int -> ('a, 'k) nvector array -> unit
        = "c_idas_quadsens_get_dky"

      let get_dky s t k ys =
        let ns = num_sensitivities s in
        if Array.length ys <> ns
        then invalid_arg "get_dky: wrong number of vectors";
        c_get_dky s t k ys

      external get_dky1 : ('a, 'k) session -> float -> int -> int
        -> ('a, 'k) nvector -> unit
        = "c_idas_quadsens_get_dky1"

      external get_num_rhs_evals       : ('a, 'k) session -> int
        = "c_idas_quadsens_get_num_rhs_evals"

      external get_num_err_test_fails  : ('a, 'k) session -> int
        = "c_idas_quadsens_get_num_err_test_fails"

      external c_get_err_weights
        : ('a, 'k) session -> ('a, 'k) nvector array -> unit
        = "c_idas_quadsens_get_err_weights"

      let get_err_weights s esweight =
        let ns = num_sensitivities s in
        if Array.length esweight <> ns
        then invalid_arg "get_err_weights: wrong number of vectors";
        c_get_err_weights s esweight

      external get_stats : ('a, 'k) session -> int * int
        = "c_idas_quadsens_get_stats"
    end
  end

module Adjoint =
  struct
    exception AdjointNotInitialized
    exception NoForwardCall
    exception ForwardReinitializationFailed
    exception ForwardFailed
    exception NoBackwardProblem
    exception BadFinalTime
    exception BadOutputTime

    let _ = List.iter (fun (nm, ex) -> Callback.register_exception nm ex)
      [
        ("idas_AdjointNotInitialized",         AdjointNotInitialized);
        ("idas_NoForwardCall",                 NoForwardCall);
        ("idas_ForwardReinitializationFailed", ForwardReinitializationFailed);
        ("idas_ForwardFailed",                 ForwardFailed);
        ("idas_NoBackwardProblem",             NoBackwardProblem);
        ("idas_BadFinalTime",                  BadFinalTime);
        ("idas_BadOutputTime",                 BadOutputTime);
      ]


    type interpolation = IPolynomial | IHermite

    external c_init : ('a, 'k) session -> int -> interpolation -> unit
        = "c_idas_adj_init"

    let init s nd interptype =
      add_fwdsensext s;
      c_init s nd interptype

    let fwdsensext s =
      match s.sensext with
      | FwdSensExt se -> se
      | _ -> raise AdjointNotInitialized

    external forward_normal : ('a, 'k) session -> float
                              -> ('a, 'k) nvector -> ('a, 'k) nvector
                              -> float * int * Sundials.solver_result
        = "c_idas_adj_forward_normal"

    external forward_one_step : ('a, 'k) session -> float
                                -> ('a, 'k) nvector -> ('a, 'k) nvector
                                -> float * int * Sundials.solver_result
        = "c_idas_adj_forward_one_step"

    type 'a bresfn = 'a B.bresfn =
      Basic of 'a B.resfnb
    | WithSens of 'a B.resfnbs

    type 'a single_tmp = 'a
    type 'a triple_tmp = 'a * 'a * 'a

    type ('t, 'a) jacobian_arg = ('t, 'a) B.jacobian_arg =
      {
        jac_t   : float;
        jac_y   : 'a;
        jac_y'  : 'a;
        jac_yb  : 'a;
        jac_y'b : 'a;
        jac_resb : 'a;
        jac_coef : float;
        jac_tmp : 't
      }

    type bandrange = Cvode_impl.bandrange = { mupper : int; mlower : int; }

    type ('a, 'k) bsession = ('a, 'k) Cvode_impl.bsession
    type serial_bsession = (real_array, Nvector_serial.kind) bsession

    type ('data, 'kind) linear_solver = ('data, 'kind) Cvode_impl.blinear_solver

    type serial_linear_solver = (real_array, Nvector_serial.kind) linear_solver

    type ('data, 'kind) iter =
      | Newton of ('data, 'kind) linear_solver
      | Functional

    let parent_and_which s =
      match (tosession s).sensext with
      | BwdSensExt se -> (se.parent, se.which)
      | _ -> failwith "Internal error: bsession invalid"

    type ('a, 'k) tolerance =
      | SStolerances of float * float
      | SVtolerances of float * ('a, 'k) nvector

    external ss_tolerances
        : ('a, 'k) session -> int -> float -> float -> unit
        = "c_idas_adj_ss_tolerances"

    external sv_tolerances
        : ('a, 'k) session -> int -> float -> ('a, 'k) nvector -> unit
        = "c_idas_adj_sv_tolerances"

    let set_tolerances bs tol =
      let parent, which = parent_and_which bs in
      match tol with
      | SStolerances (rel, abs) -> ss_tolerances parent which rel abs
      | SVtolerances (rel, abs) -> sv_tolerances parent which rel abs

    let bwdsensext = function (Bsession bs) ->
      match bs.sensext with
      | BwdSensExt se -> se
      | _ -> raise AdjointNotInitialized

    let set_linear_solver bs solver nv nv' =
      (tosession bs).ls_callbacks <- NoCallbacks;
      solver bs nv nv'

    external bsession_finalize : ('a, 'k) session -> unit
        = "c_idas_adj_bsession_finalize"

    external c_init_backward
        : ('a, 'k) session -> ('a, 'k) session Weak.t
          -> float
          -> ('a, 'k) nvector
          -> ('a, 'k) nvector
          -> bool
          -> (ida_mem * int * c_weak_ref * ida_file)
        = "c_idas_adj_init_backward_byte"
          "c_idas_adj_init_backward"

    let init_backward s linsolv tol mf t0 y0 y'0 =
      let { bsessions } as se = fwdsensext s in
      let ns = num_sensitivities s in
      let weakref = Weak.create 1 in
      let ida_mem, which, backref, err_file =
        match mf with
        | Basic _ -> c_init_backward s weakref t0 y0 y'0 false
        | WithSens _ -> c_init_backward s weakref t0 y0 y'0 true
      in
      (* ida_mem and backref have to be immediately captured in a session and
         associated with the finalizer before we do anything else.  *)
      let bs = Bsession {
              ida          = ida_mem;
              backref      = backref;
              nroots       = 0;
              err_file     = err_file;

              exn_temp     = None;

              resfn        = (fun _ _ _ _ -> ());
              rootsfn      = (fun _ _ _ _ -> ());
              errh         = (fun _ -> ());
              errw         = (fun _ _ -> ());
              ls_callbacks = NoCallbacks;

              safety_check_flags = 0;

              sensext    = BwdSensExt {
                parent   = s;
                which    = which;

                bnum_sensitivities = ns;
                bsensarray1 = c_alloc_nvector_array ns;
                bsensarray2 = c_alloc_nvector_array ns;

                resfnb      = (match mf with
                               | Basic f -> f
                               | _ -> (fun _ _ _ _ _ _ -> ()));

                resfnbs     = (match mf with
                               | WithSens f -> f
                               | _ -> (fun _ _ _ _ _ _ _ _ -> ()));

                bquadrhsfn  = (fun _ _ _ _ -> ());
                bquadrhsfn1 = (fun _ _ _ _ _ -> ());
              };
            } in
      Gc.finalise bsession_finalize (tosession bs);
      Weak.set weakref 0 (Some (tosession bs));
      (* Now the session is safe to use.  If any of the following fails and
         raises an exception, the GC will take care of freeing ida_mem and
         backref. *)
      set_linear_solver bs linsolv y0 y'0;
      set_tolerances bs tol;
      se.bsessions <- (tosession bs) :: bsessions;
      bs

    external c_reinit
        : ('a, 'k) session -> int -> float -> ('a, 'k) nvector -> unit
        = "c_idas_adj_reinit"

    let reinit bs tb0 yb0 =
      let parent, which = parent_and_which bs in
      c_reinit parent which tb0 yb0

    external backward_normal : ('a, 'k) session -> float -> unit
        = "c_idas_adj_backward_normal"

    external backward_one_step : ('a, 'k) session -> float -> unit
        = "c_idas_adj_backward_one_step"

    external c_get : ('a, 'k) session -> int
                     -> ('a, 'k) nvector -> ('a, 'k) nvector -> float
        = "c_idas_adj_get"

    let get bs yb ypb =
      let parent, which = parent_and_which bs in
      c_get parent which yb ypb

    let get_dky bs = Ida.get_dky (tosession bs)

    external c_set_max_ord : ('a, 'k) session -> int -> int -> unit
        = "c_idas_adj_set_max_ord"

    let set_max_ord bs maxordb =
      let parent, which = parent_and_which bs in
      c_set_max_ord parent which maxordb

    external c_set_max_num_steps : ('a, 'k) session -> int -> int -> unit
        = "c_idas_adj_set_max_num_steps"

    let set_max_num_steps bs mxstepsb =
      let parent, which = parent_and_which bs in
      c_set_max_num_steps parent which mxstepsb 

    external c_set_init_step : ('a, 'k) session -> int -> float -> unit
        = "c_idas_adj_set_init_step"

    let set_init_step bs hinb =
      let parent, which = parent_and_which bs in
      c_set_init_step parent which hinb 

    external c_set_max_step : ('a, 'k) session -> int -> float -> unit
        = "c_idas_adj_set_max_step"

    let set_max_step bs hmaxb =
      let parent, which = parent_and_which bs in
      c_set_max_step parent which hmaxb 

    module Dls =
      struct
        type dense_jac_fn = (real_array triple_tmp, real_array) jacobian_arg
                                -> Dls.DenseMatrix.t -> unit

        type band_jac_fn = bandrange
                            -> (real_array triple_tmp, real_array) jacobian_arg
                            -> Dls.BandMatrix.t -> unit

        external c_dls_dense : serial_session -> int -> int -> bool -> unit
          = "c_idas_adj_dls_dense"

        external c_dls_band
          : (serial_session * int) -> int -> int -> int -> bool -> unit
          = "c_idas_adj_dls_band"

        let dense jac bs nv nv' =
          let parent, which = parent_and_which bs in
          let neqs = Sundials.RealArray.length (Sundials.unvec nv) in
          c_dls_dense parent which neqs (jac <> None);
          (tosession bs).ls_callbacks <- match jac with
                                         | None -> NoCallbacks
                                         | Some f -> BDenseCallback f

        (* Sundials 2.5.0 doesn't support Lapack for IDA adjoint.  *)
        (*
        let lapack_dense jac bs nv =
          let parent, which = parent_and_which bs in
          let neqs = Sundials.RealArray.length (Sundials.unvec nv) in
          c_dls_lapack_dense parent which neqs (jac <> None);
          (tosession bs).ls_callbacks <- match jac with
                                         | None -> NoCallbacks
                                         | Some f -> BDenseCallback f
         *)

        type ('data, 'kind) linear_solver =
          ('data, 'kind) bsession -> ('data, 'kind) nvector -> unit

        let band p jac bs nv nv' =
          let parent, which = parent_and_which bs in
          let neqs = Sundials.RealArray.length (Sundials.unvec nv) in
          c_dls_band (parent, which) neqs p.mupper p.mlower (jac <> None);
          (tosession bs).ls_callbacks <- match jac with
                                         | None -> NoCallbacks
                                         | Some f -> BBandCallback f

        (* Sundials 2.5.0 doesn't support Lapack for IDA adjoint.  *)
        (*
        let lapack_band p jac bs nv =
          let parent, which = parent_and_which bs in
          let neqs = Sundials.RealArray.length (Sundials.unvec nv) in
          c_dls_lapack_band (parent,which) neqs p.mupper p.mlower (jac <> None);
          (tosession bs).ls_callbacks <- match jac with
                                         | None -> NoCallbacks
                                         | Some f -> BBandCallback f
         *)
      end

    module Spils =
      struct
        type gramschmidt_type = Spils.gramschmidt_type =
          | ModifiedGS
          | ClassicalGS

        type preconditioning_type = Spils.preconditioning_type =
          | PrecNone
          | PrecLeft
          | PrecRight
          | PrecBoth

        type 'a callbacks = 'a B.spils_callbacks =
          {
            prec_solve_fn : (('a single_tmp, 'a) jacobian_arg
                             -> 'a -> 'a -> float -> unit) option;

            prec_setup_fn : (('a triple_tmp, 'a) jacobian_arg -> unit) option;

            jac_times_vec_fn : (('a single_tmp, 'a) jacobian_arg -> 'a -> 'a
                                -> unit) option;
          }

        let no_precond = {
          prec_solve_fn = None;
          prec_setup_fn = None;
          jac_times_vec_fn = None;
        }

        external c_spils_set_preconditioner
          : ('a, 'k) session -> int -> bool -> bool -> unit
          = "c_idas_adj_spils_set_preconditioner"

        external c_spils_spgmr
          : ('a, 'k) session -> int -> int -> unit
          = "c_idas_adj_spils_spgmr"

        external c_spils_spbcg
          : ('a, 'k) session -> int -> int -> unit
          = "c_idas_adj_spils_spbcg"

        external c_spils_sptfqmr
          : ('a, 'k) session -> int -> int -> unit
          = "c_idas_adj_spils_sptfqmr"

        let set_precond bs parent which cb =
          match cb.prec_solve_fn with
          | None -> ()                  (* FIXME: is this right? *)
          | Some solve_fn ->
            c_spils_set_preconditioner parent which
              (cb.prec_setup_fn <> None)
              (cb.jac_times_vec_fn <> None);
            (tosession bs).ls_callbacks <- BSpilsCallback cb

        let spgmr maxl cb bs _ =
          let parent, which = parent_and_which bs in
          let maxl = match maxl with None -> 0 | Some ml -> ml in
          c_spils_spgmr parent which maxl;
          set_precond bs parent which cb

        let spbcg maxl cb bs _ =
          let parent, which = parent_and_which bs in
          let maxl = match maxl with None -> 0 | Some ml -> ml in
          c_spils_spbcg parent which maxl;
          set_precond bs parent which cb

        let sptfqmr maxl cb bs _ =
          let parent, which = parent_and_which bs in
          let maxl = match maxl with None -> 0 | Some ml -> ml in
          c_spils_sptfqmr parent which maxl;
          set_precond bs parent which cb

        external set_gs_type
            : ('a, 'k) bsession -> Spils.gramschmidt_type -> unit
            = "c_idas_adj_spils_set_gs_type"

        external set_eps_lin : ('a, 'k) bsession -> float -> unit
            = "c_idas_adj_spils_set_eps_lin"

        external c_set_maxl : ('a, 'k) bsession -> int -> unit
            = "c_idas_adj_spils_set_maxl"

        let set_maxl bs omaxl =
          c_set_maxl bs (match omaxl with None -> 0 | Some x -> x)

        let get_work_space bs =
          Ida.Spils.get_work_space (tosession bs)

        let get_num_lin_iters bs =
          Ida.Spils.get_num_lin_iters (tosession bs)

        let get_num_conv_fails bs =
          Ida.Spils.get_num_conv_fails (tosession bs)

        let get_num_prec_evals bs =
          Ida.Spils.get_num_prec_evals (tosession bs)

        let get_num_prec_solves bs =
          Ida.Spils.get_num_prec_solves (tosession bs)

        let get_num_jtimes_evals bs =
          Ida.Spils.get_num_jtimes_evals (tosession bs)

        let get_num_res_evals bs =
          Ida.Spils.get_num_res_evals (tosession bs)
      end

    let get_work_space bs = Ida.get_work_space (tosession bs)

    let get_num_steps bs = Ida.get_num_steps (tosession bs)

    let get_num_res_evals bs = Ida.get_num_res_evals (tosession bs)

    let get_num_lin_solv_setups bs =
      Ida.get_num_lin_solv_setups (tosession bs)

    let get_num_err_test_fails bs =
      Ida.get_num_err_test_fails (tosession bs)

    let get_last_order bs = Ida.get_last_order (tosession bs)

    let get_current_order bs = Ida.get_current_order (tosession bs)

    let get_last_step bs = Ida.get_last_step (tosession bs)

    let get_current_step bs = Ida.get_current_step (tosession bs)

    let get_actual_init_step bs =
      Ida.get_actual_init_step (tosession bs)

    let get_current_time bs = Ida.get_current_time (tosession bs)

    let get_tol_scale_factor bs =
      Ida.get_tol_scale_factor (tosession bs)

    let get_err_weights bs = Ida.get_err_weights (tosession bs)
    let get_est_local_errors bs =
      Ida.get_est_local_errors (tosession bs)

    let get_integrator_stats bs =
      Ida.get_integrator_stats (tosession bs)

    let print_integrator_stats bs =
      Ida.print_integrator_stats (tosession bs)

    let get_num_nonlin_solv_iters bs =
      Ida.get_num_nonlin_solv_iters (tosession bs)

    let get_num_nonlin_solv_conv_fails bs =
      Ida.get_num_nonlin_solv_conv_fails (tosession bs)

    let get_nonlin_solv_stats bs =
      Ida.get_nonlin_solv_stats (tosession bs)

    module Quadrature =
      struct
        type 'a bquadrhsfn = 'a B.bquadrhsfn =
            Basic of (float -> 'a -> 'a -> 'a -> unit)
          | WithSens of (float -> 'a -> 'a array -> 'a -> 'a -> unit)

        external c_quad_initb
            : ('a, 'k) session -> int -> ('a, 'k) nvector -> unit
            = "c_idas_adjquad_initb"
        external c_quad_initbs
            : ('a, 'k) session -> int -> ('a, 'k) nvector -> unit
            = "c_idas_adjquad_initbs"

        let init bs mf y0 =
          let parent, which = parent_and_which bs in
          let se = bwdsensext bs in
          match mf with
           | Basic f -> (se.bquadrhsfn <- f;
                         c_quad_initb parent which y0)
           | WithSens f -> (se.bquadrhsfn1 <- f;
                            c_quad_initbs parent which y0)

        external c_reinit : ('a, 'k) session -> int -> ('a, 'k) nvector -> unit
            = "c_idas_adjquad_reinit"

        let reinit bs yqb0 =
          let parent, which = parent_and_which bs in
          c_reinit parent which yqb0

        external c_get : ('a, 'k) session -> int -> ('a, 'k) nvector -> float
            = "c_idas_adjquad_get"

        let get bs yqb =
          let parent, which = parent_and_which bs in
          c_get parent which yqb

        type ('a, 'k) tolerance =
            NoStepSizeControl
          | SStolerances of float * float
          | SVtolerances of float * ('a, 'k) nvector

        external set_err_con : ('a, 'k) session -> int -> bool -> unit
            = "c_idas_adjquad_set_err_con"

        external sv_tolerances
            : ('a, 'k) session -> int -> float -> ('a, 'k) nvector -> unit
            = "c_idas_adjquad_sv_tolerances"

        external ss_tolerances
            : ('a, 'k) session -> int -> float -> float -> unit
            = "c_idas_adjquad_ss_tolerances"

        let set_tolerances bs tol =
          let parent, which = parent_and_which bs in
          match tol with
          | NoStepSizeControl -> set_err_con parent which false
          | SStolerances (rel, abs) -> (ss_tolerances parent which rel abs;
                                        set_err_con parent which true)
          | SVtolerances (rel, abs) -> (sv_tolerances parent which rel abs;
                                        set_err_con parent which true)

        let get_num_rhs_evals bs =
          Quadrature.get_num_rhs_evals (tosession bs)

        let get_num_err_test_fails bs =
          Quadrature.get_num_err_test_fails (tosession bs)

        let get_err_weights bs =
          Quadrature.get_err_weights (tosession bs)

        let get_stats bs = Quadrature.get_stats (tosession bs)
      end
  end

