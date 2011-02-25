(***********************************************************************)
(*                                                                     *)
(*              Ocaml interface to Sundials CVODE solver               *)
(*                                                                     *)
(*       Timothy Bourke (INRIA Rennes) and Marc Pouzet (LIENS)         *)
(*                                                                     *)
(*  Copyright 2011 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file LICENSE.        *)
(*                                                                     *)
(***********************************************************************)

(***********************************************************************)
(* Much of the comment text is taken directly from:                    *)
(*                                                                     *)
(*               User Documentation for CVODE v2.6.0                   *)
(*                Alan C. Hindmarsh and Radu Serban                    *)
(*              Center for Applied Scientific Computing                *)
(*              Lawrence Livermore National Laboratory                 *)
(*                                                                     *)
(***********************************************************************)

(** Abstract nvector interface to the CVODE Solver

 @version VERSION()
 @author Timothy Bourke (INRIA)
 @author Marc Pouzet (LIENS)
 *)

include module type of Cvode

(**
    This type represents a 'a session with the CVODE solver using serial 'a nvectortors
    accessed as {{:OCAML_DOC_ROOT(Bigarray.Array1)} Bigarray.Array1}s.

    TODO: write out a sketch of the user's main program in Ocaml.

    @cvode <node5#ss:skeleton_sim> Skeleton of main program
 *)
type 'a session

type 'a nvector = 'a Nvector.nvector

type root_array = Sundials.Roots.t
type root_val_array = Sundials.Roots.val_array

(** {2 Initialization} *)

(**
    TODO: EXPLAIN HOW THIS WORKS.

    The start time defaults to 0. It can be set manually by instead using
    {!init'}.

    @cvode <node5#sss:cvodemalloc>   CVodeCreate/CVodeInit
    @cvode <node5#sss:lin_solv_init> Linear solvers
    @cvode <node5#ss:cvrootinit>     Root initialisation
 *)
val init :
    lmm
    -> iter
    -> (float -> 'a -> 'a -> unit)
    -> (int * (float -> 'a -> root_val_array -> unit))
    -> 'a nvector
    -> 'a session

(**
  The same as init' except that the start time is given explicitly.
 *)
val init' :
    lmm
    -> iter
    -> (float -> 'a -> 'a -> unit)
    -> (int * (float -> 'a -> root_val_array -> unit))
    -> 'a nvector
    -> float (* start time *)
    -> 'a session

(** Return the number of root functions. *)
val nroots : 'a session -> int

(** Return the number of equations. *)
val neqs : 'a session -> int

(** {2 Tolerance specification} *)

(**
    [ss_tolerances s reltol abstol] sets the relative and absolute
    tolerances using scalar values.

    @cvode <node5#sss:cvtolerances> CVodeSStolerances
 *)
val ss_tolerances : 'a session -> float -> float -> unit

(**
    [sv_tolerances s reltol abstol] sets the relative tolerance using a scalar
    value, and the absolute tolerance as a vector.

    @cvode <node5#sss:cvtolerances> CVodeSVtolerances
 *)
val sv_tolerances : 'a session -> float -> 'a nvector -> unit

(**
    [wf_tolerances s efun] specifies a function [efun] that sets the multiplicative
    error weights Wi for use in the weighted RMS norm.

    [efun y ewt] is passed the dependent variable vector [y] and is expected to
    set the values inside the error-weight vector [ewt].

    @cvode <node5#sss:cvtolerances> CVodeWFtolerances
    @cvode <node5#ss:ewtsetFn> Error weight function
 *)
val wf_tolerances : 'a session -> ('a -> 'a -> unit) -> unit

(** {2 Solver functions } *)

(**
    TODO: write this description.

    @cvode <node5#sss:cvode> CVode (CV_NORMAL)
 *)
val normal : 'a session -> float -> 'a nvector -> float * solver_result

(**
    TODO: write this description.

    @cvode <node5#sss:cvode> CVode (CV_ONE_STEP)
 *)
val one_step : 'a session -> float -> 'a nvector -> float * solver_result

(** {2 Main optional functions} *)

(** {3 Input} *)

(**
  [set_error_file s fname trunc] opens the file named [fname] and to which all
  messages from the default error handler are then directed.
  If the file already exists it is either trunctated ([trunc] = [true]) or
  appended to ([trunc] = [false]).

  The error file is closed if set_error_file is called again, or otherwise when
  the 'a session is garbage collected.
   
  @cvode <node5#sss:optin_main> CVodeSetErrFile
 *)
val set_error_file : 'a session -> string -> bool -> unit

(**
  [set_err_handler_fn s efun] specifies a custom function [efun] for handling
  error messages.

  @cvode <node5#sss:optin_main> CVodeSetErrHandlerFn
  @cvode <node5#ss:ehFn> Error message handler function
 *)
val set_err_handler_fn : 'a session -> (error_details -> unit) -> unit

(**
  This function restores the default error handling function. It is equivalent
  to calling CVodeSetErrHandlerFn with an argument of [NULL].

  @cvode <node5#sss:optin_main> CVodeSetErrHandlerFn
 *)
val clear_err_handler_fn : 'a session -> unit

(**
  Specifies the maximum order of the linear multistep method.

  @cvode <node5#sss:optin_main> CVodeSetMaxOrd
 *)
val set_max_ord : 'a session -> int -> unit

(**
  Specifies the maximum number of steps to be taken by the solver in its attempt
  to reach the next output time.

  @cvode <node5#sss:optin_main> CVodeSetMaxNumSteps
 *)
val set_max_num_steps : 'a session -> int -> unit

(**
  Specifies the maximum number of messages issued by the solver warning that t +
  h = t on the next internal step.

  @cvode <node5#sss:optin_main> CVodeSetMaxHnilWarns
 *)
val set_max_hnil_warns : 'a session -> int -> unit

(**
  Indicates whether the BDF stability limit detection algorithm should be used.

  @cvode <node5#sss:optin_main> CVodeSetStabLimDet
  @cvode <node3#s:bdf_stab> BDF Stability Limit Detection
 *)
val set_stab_lim_det : 'a session -> bool -> unit

(**
  Specifies the initial step size.

  @cvode <node5#sss:optin_main> CVodeSetInitStep
 *)
val set_init_step : 'a session -> float -> unit

(**
  Specifies a lower bound on the magnitude of the step size.

  @cvode <node5#sss:optin_main> CVodeSetMinStep
 *)
val set_min_step : 'a session -> float -> unit

(**
  Specifies an upper bound on the magnitude of the step size.

  @cvode <node5#sss:optin_main> CVodeSetMaxStep
 *)
val set_max_step : 'a session -> float -> unit

(**
  Specifies the value of the independent variable t past which the solution is
  not to proceed.
  The default, if this routine is not called, is that no stop time is imposed.

  @cvode <node5#sss:optin_main> CVodeSetStopTime
 *)
val set_stop_time : 'a session -> float -> unit

(**
  Specifies the maximum number of error test failures permitted in attempting
  one step.

  @cvode <node5#sss:optin_main> CVodeSetMaxErrTestFails
 *)
val set_max_err_test_fails : 'a session -> int -> unit

(**
  Specifies the maximum number of nonlinear solver iterations permitted per
  step.

  @cvode <node5#sss:optin_main> CVodeSetMaxNonlinIters
 *)
val set_max_nonlin_iters : 'a session -> int -> unit

(**
  Specifies the maximum number of nonlinear solver convergence failures
  permitted during one step.

  @cvode <node5#sss:optin_main> CVodeSetMaxConvFails
 *)
val set_max_conv_fails : 'a session -> int -> unit

(**
  Specifies the safety factor used in the nonlinear convergence test.

  @cvode <node5#sss:optin_main> CVodeSetNonlinConvCoef
  @cvode <node3#ss:ivp_sol> IVP Solution
 *)
val set_nonlin_conv_coef : 'a session -> float -> unit

(**
  [set_iter_type s iter] resets the nonlinear solver iteration type to [iter].
  TODO: describe what happens internally.

  @cvode <node5#sss:optin_main> CVodeSetIterType
 *)
val set_iter_type : 'a session -> iter -> unit

(** {3 Output } *)

(**
  Returns the real and integer workspace sizes.

  @cvode <node5#sss:optout_main> CVodeGetWorkSpace
  @return ([lenrw], [leniw])
 *)
val get_work_space          : 'a session -> int * int

(**
  Returns the cumulative number of internal steps taken by the solver.

  @cvode <node5#sss:optout_main> CVodeGetNumSteps
 *)
val get_num_steps           : 'a session -> int

(**
  Returns the number of calls to the user's right-hand side function.

  @cvode <node5#sss:optout_main> CVodeGetNumRhsEvals
 *)
val get_num_rhs_evals       : 'a session -> int

(**
  Returns the number of calls made to the linear solver's setup function.

  @cvode <node5#sss:optout_main> CVodeGetNumLinSolvSetups
 *)
val get_num_lin_solv_setups : 'a session -> int

(**
  Returns the number of local error test failures that have occurred.

  @cvode <node5#sss:optout_main> CVodeGetNumErrTestFails
 *)
val get_num_err_test_fails  : 'a session -> int

(**
  Returns the integration method order used during the last internal step.

  @cvode <node5#sss:optout_main> CVodeGetLastOrder
 *)
val get_last_order          : 'a session -> int

(**
  Returns the integration method order to be used on the next internal step.

  @cvode <node5#sss:optout_main> CVodeGetCurrentOrder
 *)
val get_current_order       : 'a session -> int

(**
  Returns the integration step size taken on the last internal step.

  @cvode <node5#sss:optout_main> CVodeGetLastStep
 *)
val get_last_step           : 'a session -> float

(**
  Returns the integration step size to be attempted on the next internal step.

  @cvode <node5#sss:optout_main> CVodeGetCurrentStep
 *)
val get_current_step        : 'a session -> float

(**
  Returns the the value of the integration step size used on the first step.

  @cvode <node5#sss:optout_main> CVodeGetActualInitStep
 *)
val get_actual_init_step    : 'a session -> float

(**
  Returns the the current internal time reached by the solver.

  @cvode <node5#sss:optout_main> CVodeGetCurrentTime
 *)
val get_current_time        : 'a session -> float

(**
  Returns the number of order reductions dictated by the BDF stability limit
  detection algorithm.

  @cvode <node5#sss:optout_main> CVodeGetNumStabLimOrderReds
  @cvode <node3#s:bdf_stab> BDF stability limit detection
 *)
val get_num_stab_lim_order_reds : 'a session -> int

(**
  Returns a suggested factor by which the user's tolerances should be scaled
  when too much accuracy has been requested for some internal step.

  @cvode <node5#sss:optout_main> CVodeGetTolScaleFactor
 *)
val get_tol_scale_factor : 'a session -> float

(**
  Returns the solution error weights at the current time.

  @cvode <node5#sss:optout_main> CVodeGetErrWeights
  @cvode <node3#ss:ivp_sol> IVP solution (W_i)
 *)
val get_err_weights : 'a session -> 'a nvector -> unit

(**
  Returns the vector of estimated local errors.

  @cvode <node5#sss:optout_main> CVodeGetEstLocalErrors
 *)
val get_est_local_errors : 'a session -> 'a nvector -> unit

(**
  Returns the integrator statistics as a group.

  @cvode <node5#sss:optout_main> CVodeGetIntegratorStats
 *)
val get_integrator_stats    : 'a session -> Cvode.integrator_stats

(**
  Convenience function that calls get_integrator_stats and prints the results to
  stdout.

  @cvode <node5#sss:optout_main> CVodeGetIntegratorStats
 *)
val print_integrator_stats  : 'a session -> unit


(**
  Returns the number of nonlinear (functional or Newton) iterations performed.

  @cvode <node5#sss:optout_main> CVodeGetNumNonlinSolvIters
 *)
val get_num_nonlin_solv_iters : 'a session -> int

(**
  Returns the number of nonlinear convergence failures that have occurred.

  @cvode <node5#sss:optout_main> CVodeGetNumNonlinSolvConvFails
 *)
val get_num_nonlin_solv_conv_fails : 'a session -> int

(** {2 Root finding optional functions} *)

(** {3 Input} *)

(**
  [set_root_direction s dir] specifies the direction of zero-crossings to be
  located and returned. [dir] may contain one entry for each root function.

  @cvode <node5#sss:optin_root> CVodeSetRootDirection
 *)
val set_root_direction : 'a session -> root_direction array -> unit

(**
  Like {!set_root_direction} but specifies a single direction for all root
  functions.

  @cvode <node5#sss:optin_root> CVodeSetRootDirection
 *)
val set_all_root_directions : 'a session -> root_direction -> unit

(**
  Disables issuing a warning if some root function appears to be identically
  zero at the beginning of the integration.

  @cvode <node5#sss:optin_root> CVodeSetNoInactiveRootWarn
 *)
val set_no_inactive_root_warn : 'a session -> unit

(** {3 Output} *)

(**
  Fills an array showing which functions were found to have a root.

  @cvode <node5#sss:optout_root> CVodeGetRootInfo
 *)
val get_root_info : 'a session -> root_array -> unit

(**
  Returns the cumulative number of calls made to the user-supplied root function g.

  @cvode <node5#sss:optout_root> CVodeGetNumGEvals
 *)
val get_num_g_evals : 'a session -> int

(** {2 Interpolated output function } *)

(**
  [get_dky s t k dky] computes the [k]th derivative of the function y at time
  [t], i.e. d(k)y/dt(k)(t). The function requires that tn - hu <= [t] <=
  tn, where tn denotes the current internal time reached, and hu is the last
  internal step size successfully used by the solver.
  The user may request [k] = 0, 1,..., qu, where qu is the current order.

  This function may only be called after a successful return from either
  {!normal} or {!one_step}.

  Values for the limits may be obtained:
    - tn = {!get_current_time}
    - qu = {!get_last_order}
    - hu = {!get_last_step}

  @cvode <node5#sss:optin_root> CVodeGetDky
 *)
val get_dky : 'a session -> float -> int -> 'a nvector -> unit

(** {2 Reinitialization} *)

(**
  [reinit s t0 y0] reinitializes the solver 'a session [s] with a new time [t0] and
  new values for the variables [y0].

  @cvode <node5#sss:cvreinit> CVodeReInit
 *)
val reinit : 'a session -> float -> 'a nvector -> unit


(** {2 Linear Solvers} *)

(** TODO *)
type ('t, 'a) jacobian_arg =
  {
    jac_t   : float;
    jac_y   : 'a;
    jac_fy  : 'a;
    jac_tmp : 't
  }

type 'a triple_tmp = 'a * 'a * 'a

(** {3 Direct Linear Solvers (DLS)} *)

module Dls :
  sig
    val set_dense_jac_fn :
         'a session
      -> (('a triple_tmp, 'a) jacobian_arg -> Densematrix.t -> unit)
      -> unit

    val clear_dense_jac_fn : 'a session -> unit

    val set_band_jac_fn :
         'a session
      -> (('a triple_tmp, 'a) jacobian_arg -> int -> int -> Bandmatrix.t -> unit)
      -> unit

    val clear_band_jac_fn : 'a session -> unit

    val get_work_space : 'a session -> int * int

    (* No. of Jacobian evaluations *)
    val get_num_jac_evals : 'a session -> int

    (* No. of r.h.s. calls for finite diff. Jacobian evals. *)
    val get_num_rhs_evals : 'a session -> int
  end

(** {3 Diagonal approximation} *)

module Diag :
  sig
    val get_work_space : 'a session -> int * int

    (* No. of r.h.s. calls for finite diff. Jacobian evals. *)
    val get_num_rhs_evals : 'a session -> int
  end

(** {3 Banded preconditioning} *)

module BandPrec :
  sig
    val get_work_space : 'a session -> int * int

    (* No. of r.h.s. calls for finite diff. banded Jacobian evals. *)
    val get_num_rhs_evals : 'a session -> int
  end

(** {3 Scaled Preconditioned Iterative Linear Solvers (SPILS)} *)

module Spils :
  sig
    type 'a solve_arg =
      {
        rhs   : 'a;
        gamma : float;
        delta : float;
        left  : bool; (* true: left, false: right *)
      }

    type 'a single_tmp = 'a nvector

    type gramschmidt_type =
      | ModifiedGS
      | ClassicalGS

    val set_preconditioner :
      'a session
      -> (('a triple_tmp, 'a) jacobian_arg -> bool -> float -> bool)
      -> (('a single_tmp, 'a) jacobian_arg -> 'a solve_arg -> 'a nvector -> unit)
      -> unit

    val set_jac_times_vec_fn :
      'a session
      -> (('a single_tmp, 'a) jacobian_arg
          -> 'a (* v *)
          -> 'a (* Jv *)
          -> unit)
      -> unit
    val clear_jac_times_vec_fn : 'a session -> unit

    val set_prec_type : 'a session -> preconditioning_type -> unit

    val set_gs_type :
      'a session -> gramschmidt_type -> unit

    val set_eps_lin : 'a session -> float -> unit

    val set_maxl : 'a session -> int -> unit

    val get_work_space       : 'a session -> int * int
    val get_num_prec_evals   : 'a session -> int
    val get_num_prec_solves  : 'a session -> int
    val get_num_lin_iters    : 'a session -> int
    val get_num_conv_fails   : 'a session -> int
    val get_num_jtimes_evals : 'a session -> int
    val get_num_rhs_evals    : 'a session -> int
  end

