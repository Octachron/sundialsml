(***********************************************************************)
(*                                                                     *)
(*              Ocaml interface to Sundials CVODE solver               *)
(*                                                                     *)
(*           Timothy Bourke (INRIA) and Marc Pouzet (LIENS)            *)
(*                                                                     *)
(*  Copyright 2013 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file LICENSE.        *)
(*                                                                     *)
(***********************************************************************)

(***********************************************************************)
(* Much of the comment text is taken directly from:                    *)
(*                                                                     *)
(*               User Documentation for IDA v2.7.0                     *)
(*         Alan C. Hindmarsh, Radu Serban, and Aaron Collier           *)
(*              Center for Applied Scientific Computing                *)
(*              Lawrence Livermore National Laboratory                 *)
(*                                                                     *)
(***********************************************************************)

include module type of Ida
  with type Roots.t = Ida.Roots.t
  and type RootDirs.t = Ida.RootDirs.t
  and type linear_solver = Ida.linear_solver

(*STARTINTRO*)
(** Serial nvector interface to the IDA solver.
 
  Serial vectors are passed between Sundials and Ocaml programs as
  Bigarrays.
  These vectors are manipulated within the solver using the original low-level
  vector operations (cloning, linear sums, adding constants, and etcetera).
  While direct interfaces to these operations are not provided, there are
  equivalent implementations written in Ocaml for arrays of floats
  ({! Nvector_array}) and bigarrays ({! Nvector_array.Bigarray}) of floats.

  @version VERSION()
  @author Timothy Bourke (INRIA)
  @author Marc Pouzet (LIENS)
 *)

(**
    This type represents a session with the IDA solver using serial nvectors
    accessed as {{:OCAML_DOC_ROOT(Bigarray.Array1)} Bigarray.Array1}s.

    A skeleton of the main program:
    + {b Set vector of initial values}
    {[let y = Ida.Carray.of_array [| 0.0; 0.0; 0.0 |] ]}
    The length of this vector determines the problem size.    
    + {b Create and initialize a solver session}
    {[let s = Ida.init Ida.Adams Ida.Functional f (2, g) y]}
    This will initialize a specific linear solver and the root-finding
    mechanism, if necessary.
    + {b Specify integration tolerances (optional)}, e.g.
    {[ss_tolerances s reltol abstol]}
    + {b Set optional inputs}, e.g.
    {[set_stop_time s 10.0; ...]}
    Call any of the [set_*] functions to change solver parameters from their
    defaults.
    + {b Advance solution in time}, e.g.
    {[let (t', result) = Ida.normal s !t y in
...
t := t' + 0.1]}
    Repeatedly call either [normal] or [one_step] to advance the simulation.
    + {b Get optional outputs}
    {[let stats = get_integrator_stats s in ...]}
    Call any of the [get_*] functions to examine solver statistics.

    @ida <node5#ss:skeleton_sim> Skeleton of main program
 *)
(*ENDINTRO*)
type session

(** The type of vectors passed to the solver. *)
type nvec = Sundials.Carray.t

(** The type of vectors containing dependent variable values, passed from the
   solver to callback functions. *)
type val_array = Sundials.Carray.t

(** The type of vectors containing derivative values, passed from the
   solver to callback functions. *)
type der_array = Sundials.Carray.t

(** The type of vectors containing detected roots (zero-crossings). *)
type root_array = Sundials.Roots.t

(** The type of vectors containing the values of root functions
   (zero-crossings). *)
type root_val_array = Sundials.Roots.val_array

(** {2 Initialization} *)

(**
    [init linsolv f (nroots, g) y0 y'0] initializes the IDA solver to solve
    the DAE f t y y' = 0 and returns a {!session}.
    - [linsolv] is the linear solver to attach to this solver.
    - [f]       is the residual function.
    - [nroots]  specifies the number of root functions (zero-crossings).
    - [g]       calculates the values of the root functions.
    - [y0]      is a vector of initial values for the dependent-variable vector
                [y].  This vector's size determines the number of equations
                in the session, see {!Sundials.Carray.t}.
    - [y'0]     is a vector of initial values for [y'], i.e. the derivative
                of [y] with respect to t.  This vector's size must match the
                size of [y0].

    The start time defaults to 0. It can be set manually by instead using
    {!init'}.

    This function calls IDACreate, IDAInit, IDARootInit, an appropriate
    linear solver function, and IDASStolerances (with default values for
    relative tolerance of 1.0e-4 and absolute tolerance as 1.0e-8; these can be
    changed with {!ss_tolerances}, {!sv_tolerances}, or {!wf_tolerances}).
    It does everything necessary to initialize an IDA session; the {!normal} or
    {!one_step} functions can be called directly afterward.

    The residual function [f] is called by the solver to compute the problem
    residual, given [t], [y], [y'], and [r], where:
    - [t] is the current value of the independent variable,
          i.e., the simulation time.
    - [y] is a vector of dependent-variable values, i.e. y(t).
    - [y'] is the derivative of [y] with respect to [t], i.e. dy/dt.
    - [r] is the output vector to fill in with the value of the residual
          function for the given values of t, y, and y'.

    {b NB:} [y], [y'], and [r] must no longer be accessed after [f] has
            returned a result, i.e. if their values are needed outside of
            the function call, then they must be copied to separate physical
            structures.

    The roots function [g] is called by the solver to calculate the values of
    root functions (zero-crossing expressions) which are used to detect
    significant events.  It is passed four arguments [t], [y], [y'], and [gout]:
    - [t], [y], [y'] are as for [f].
    - [gout] is a vector for storing the values of g(t, y, y').
    The {!Ida.no_roots} value can be passed for the [(nroots, g)] argument if
    root functions are not required.

    {b NB:} [y] and [gout] must no longer be accessed after [g] has returned
            a result, i.e. if their values are needed outside of the function
            call, then they must be copied to separate physical structures.

    @ida <node5#sss:idamalloc>     IDACreate/IDAInit
    @ida <node5#ss:resFn>          ODE right-hand side function
    @ida <node5#ss:idarootinit>    IDARootInit
    @ida <node5#ss:rootFn>         Rootfinding function
    @ida <node5#sss:lin_solv_init> Linear solvers
    @ida <node5#sss:idatolerances> IDASStolerances
 *)
val init :
    linear_solver
    -> (float -> val_array -> der_array -> val_array -> unit)
    -> (int * (float -> val_array -> der_array -> root_val_array -> unit))
    -> nvec
    -> nvec
    -> session

(**
  [init' linsolv roots y0 y'0 t0] is the same as init except that a start time,
  [t0], can be given explicitly.
 *)
val init' :
    linear_solver
    -> (float -> val_array -> der_array -> val_array -> unit)
    -> (int * (float -> val_array -> der_array -> root_val_array -> unit))
    -> nvec
    -> nvec
    -> float (* start time *)
    -> session

(** Return the number of root functions. *)
val nroots : session -> int

(** Return the number of equations. *)
val neqs : session -> int

(** {2 Tolerance specification} *)

(**
    [ss_tolerances s reltol abstol] sets the relative and absolute
    tolerances using scalar values.

    @ida <node5#sss:cvtolerances> IDASStolerances
 *)
val ss_tolerances : session -> float -> float -> unit

(**
    [sv_tolerances s reltol abstol] sets the relative tolerance using a scalar
    value, and the absolute tolerance as a vector.

    @ida <node5#sss:cvtolerances> IDASVtolerances
 *)
val sv_tolerances : session -> float -> nvec -> unit

(**
    [wf_tolerances s efun] specifies a function [efun] that sets the multiplicative
    error weights Wi for use in the weighted RMS norm.

    [efun y ewt] is passed the dependent variable vector [y] and is expected to
    set the values inside the error-weight vector [ewt].

    @ida <node5#sss:cvtolerances> IDAWFtolerances
    @ida <node5#ss:ewtsetFn> Error weight function
 *)
val wf_tolerances : session -> (val_array -> val_array -> unit) -> unit

(** {2 Solver functions } *)

(**
   [(tret, r) = normal s tout yout y'out] integrates the DAE over an interval
   in t.

   The arguments are:
   - [s] a session with the solver.
   - [tout] the next time at which a computed solution is desired.
   - [yout] a vector to store the computed solution. The same vector as was
   - [y'out] a vector to store the computed solution's derivative. The same
   vector as was passed to {!init} can (but does not have to) be used again
   for this argument.

   Two values are returned:
    - [tret] the time reached by the solver, which will be equal to [tout] if
      no errors occur.
    - [r] indicates whether roots were found, or whether an optional stop time,
   set by {!set_stop_time}, was reached; see {!Ida.solver_result}.

   This routine will throw one of the solver {!Ida.exceptions} if an error
   occurs.

   @ida <node5#sss:ida> IDA (IDA_NORMAL)
 *)
val normal :
  session -> float -> val_array -> der_array -> float * solver_result

(**
   This function is identical to {!normal}, except that it returns after one
   internal solver step.

   @ida <node5#sss:ida> IDA (IDA_ONE_STEP)
 *)
val one_step :
  session -> float -> val_array -> der_array -> float * solver_result

(** {2 Main optional functions} *)

(** {3 Input} *)

(**
  [set_error_file s fname trunc] opens the file named [fname] and to which all
  messages from the default error handler are then directed.
  If the file already exists it is either trunctated ([trunc] = [true]) or
  appended to ([trunc] = [false]).

  The error file is closed if set_error_file is called again, or otherwise when
  the session is garbage collected.
   
  @ida <node5#sss:optin_main> IDASetErrFile
 *)
val set_error_file : session -> string -> bool -> unit

(**
  [set_err_handler_fn s efun] specifies a custom function [efun] for handling
  error messages.

  @ida <node5#sss:optin_main> IDASetErrHandlerFn
  @ida <node5#ss:ehFn> Error message handler function
 *)
val set_err_handler_fn : session -> (error_details -> unit) -> unit

(**
  This function restores the default error handling function. It is equivalent
  to calling IDASetErrHandlerFn with an argument of [NULL].

  @ida <node5#sss:optin_main> IDASetErrHandlerFn
 *)
val clear_err_handler_fn : session -> unit

(**
  Specifies the maximum order of the linear multistep method.

  @ida <node5#sss:optin_main> IDASetMaxOrd
 *)
val set_max_ord : session -> int -> unit

(**
  Specifies the maximum number of steps to be taken by the solver in its attempt
  to reach the next output time.

  @ida <node5#sss:optin_main> IDASetMaxNumSteps
 *)
val set_max_num_steps : session -> int -> unit

(**
  Specifies the initial step size.

  @ida <node5#sss:optin_main> IDASetInitStep
 *)
val set_init_step : session -> float -> unit

(**
  Specifies an upper bound on the magnitude of the step size.

  @ida <node5#sss:optin_main> IDASetMaxStep
 *)
val set_max_step : session -> float -> unit

(**
  Specifies the value of the independent variable t past which the solution is
  not to proceed.
  The default, if this routine is not called, is that no stop time is imposed.

  @ida <node5#sss:optin_main> IDASetStopTime
 *)
val set_stop_time : session -> float -> unit

(**
  Specifies the maximum number of error test failures permitted in attempting
  one step.

  @ida <node5#sss:optin_main> IDASetMaxErrTestFails
 *)
val set_max_err_test_fails : session -> int -> unit

(**
  Specifies the maximum number of nonlinear solver iterations permitted per
  step.

  @ida <node5#sss:optin_main> IDASetMaxNonlinIters
 *)
val set_max_nonlin_iters : session -> int -> unit

(**
  Specifies the maximum number of nonlinear solver convergence failures
  permitted during one step.

  @ida <node5#sss:optin_main> IDASetMaxConvFails
 *)
val set_max_conv_fails : session -> int -> unit

(**
  Specifies the safety factor used in the nonlinear convergence test.

  @ida <node5#sss:optin_main> IDASetNonlinConvCoef
  @ida <node3#ss:ivp_sol> IVP Solution
 *)
val set_nonlin_conv_coef : session -> float -> unit

(** {3 Output } *)

(**
  Returns the real and integer workspace sizes.

  @ida <node5#sss:optout_main> IDAGetWorkSpace
  @return ([real_size], [integer_size])
 *)
val get_work_space          : session -> int * int

(**
  Returns the cumulative number of internal steps taken by the solver.

  @ida <node5#sss:optout_main> IDAGetNumSteps
 *)
val get_num_steps           : session -> int

(**
  Returns the number of calls to the user's right-hand side function.

  @ida <node5#sss:optout_main> IDAGetNumResEvals
 *)
val get_num_res_evals       : session -> int

(**
  Returns the number of calls made to the linear solver's setup function.

  @ida <node5#sss:optout_main> IDAGetNumLinSolvSetups
 *)
val get_num_lin_solv_setups : session -> int

(**
  Returns the number of local error test failures that have occurred.

  @ida <node5#sss:optout_main> IDAGetNumErrTestFails
 *)
val get_num_err_test_fails  : session -> int

(**
  Returns the integration method order used during the last internal step.

  @ida <node5#sss:optout_main> IDAGetLastOrder
 *)
val get_last_order          : session -> int

(**
  Returns the integration method order to be used on the next internal step.

  @ida <node5#sss:optout_main> IDAGetCurrentOrder
 *)
val get_current_order       : session -> int

(**
  Returns the integration step size taken on the last internal step.

  @ida <node5#sss:optout_main> IDAGetLastStep
 *)
val get_last_step           : session -> float

(**
  Returns the integration step size to be attempted on the next internal step.

  @ida <node5#sss:optout_main> IDAGetCurrentStep
 *)
val get_current_step        : session -> float

(**
  Returns the the value of the integration step size used on the first step.

  @ida <node5#sss:optout_main> IDAGetActualInitStep
 *)
val get_actual_init_step    : session -> float

(**
  Returns the the current internal time reached by the solver.

  @ida <node5#sss:optout_main> IDAGetCurrentTime
 *)
val get_current_time        : session -> float

(* IDAGetNumStabLimOrderReds appears in the sundials manual on p.52 but there's
   no such function in the implementation.  It's probably a typo or a leftover
   from earlier versions.

(**
   Returns the number of order reductions dictated by the BDF stability limit
   detection algorithm.

   @ida <node5#sss:optout_main> IDAGetNumStabLimOrderReds
   @ida <node3#s:bdf_stab> BDF stability limit detection
 *)
val get_num_stab_lim_order_reds : session -> int
 *)

(**
  Returns a suggested factor by which the user's tolerances should be scaled
  when too much accuracy has been requested for some internal step.

  @ida <node5#sss:optout_main> IDAGetTolScaleFactor
 *)
val get_tol_scale_factor : session -> float

(**
  Returns the solution error weights at the current time.

  @ida <node5#sss:optout_main> IDAGetErrWeights
  @ida <node3#ss:ivp_sol> IVP solution (W_i)
 *)
val get_err_weights : session -> nvec -> unit

(**
  Returns the vector of estimated local errors.

  @ida <node5#sss:optout_main> IDAGetEstLocalErrors
 *)
val get_est_local_errors : session -> nvec -> unit

(**
  Returns the integrator statistics as a group.

  @ida <node5#sss:optout_main> IDAGetIntegratorStats
 *)
val get_integrator_stats    : session -> Ida.integrator_stats

(**
  Convenience function that calls get_integrator_stats and prints the results to
  stdout.

  @ida <node5#sss:optout_main> IDAGetIntegratorStats
 *)
val print_integrator_stats  : session -> unit


(**
  Returns the number of nonlinear (functional or Newton) iterations performed.

  @ida <node5#sss:optout_main> IDAGetNumNonlinSolvIters
 *)
val get_num_nonlin_solv_iters : session -> int

(**
  Returns the number of nonlinear convergence failures that have occurred.

  @ida <node5#sss:optout_main> IDAGetNumNonlinSolvConvFails
 *)
val get_num_nonlin_solv_conv_fails : session -> int

(** {2 Root finding optional functions} *)

(** {3 Input} *)

(**
  [set_root_direction s dir] specifies the direction of zero-crossings to be
  located and returned. [dir] may contain one entry of type
  {!Ida.root_direction} for each root function.

  @ida <node5#sss:optin_root> IDASetRootDirection
 *)
val set_root_direction : session -> root_direction array -> unit

(**
  Like {!set_root_direction} but specifies a single direction of type
  {!Ida.root_direction} for all root
  functions.

  @ida <node5#sss:optin_root> IDASetRootDirection
 *)
val set_all_root_directions : session -> root_direction -> unit

(**
  Disables issuing a warning if some root function appears to be identically
  zero at the beginning of the integration.

  @ida <node5#sss:optin_root> IDASetNoInactiveRootWarn
 *)
val set_no_inactive_root_warn : session -> unit

(** {3 Output} *)

(**
  Fills an array showing which functions were found to have a root.

  @ida <node5#sss:optout_root> IDAGetRootInfo
 *)
val get_root_info : session -> root_array -> unit

(**
  Returns the cumulative number of calls made to the user-supplied root function g.

  @ida <node5#sss:optout_root> IDAGetNumGEvals
 *)
val get_num_g_evals : session -> int

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

  @ida <node5#sss:optin_root> IDAGetDky
 *)
val get_dky : session -> float -> int -> nvec -> unit

(** {2 Reinitialization} *)

(**
  [reinit s t0 y0] reinitializes the solver session [s] with a new time [t0] and
  new values for the variables [y0].

  @ida <node5#sss:cvreinit> IDAReInit
 *)
val reinit : session -> float -> val_array -> der_array -> unit


(** {2 Linear Solvers} *)

type single_tmp = val_array
type triple_tmp = val_array * val_array * val_array

(**
  Arguments common to all Jacobian callback functions.    
 
  @ida <node5#ss:djacFn> Dense Jacobian function
  @ida <node5#ss:bjacFn> Banded Jacobian function
  @ida <node5#ss:jtimesFn> Product Jacobian function
  @ida <node5#ss:psolveFn> Linear preconditioning function
  @ida <node5#ss:precondFn> Jacobian preconditioning function
 *)
type 't jacobian_arg =
  {
    jac_t    : float;        (** The independent variable. *)
    jac_coef : float;        (** The coefficient [a] in the system Jacobian
                                 to compute,
                                   [J = dF/dy + a*dF/d(y')]
                                 where [F(t,y,y')] is the residual vector.
                                 See Eq (2.5) of IDA's user documentation.  *)
    jac_y    : val_array;    (** The dependent variable vector. *)
    jac_y'   : der_array;    (** The derivative vector (i.e. dy/dt). *)
    jac_res  : val_array;    (** The current value of the residual vector. *)
    jac_tmp  : 't            (** Workspace data,
                                either {!single_tmp} or {!triple_tmp}. *)
  }

(** {3 Direct Linear Solvers (DLS)} *)

(** Control callbacks and get optional outputs for the Direct Linear Solvers
    that operate on dense and banded matrices.
    
    @ida <node5#sss:optin_dls> Direct linear solvers optional input functions
    @ida <node5#sss:optout_dls> Direct linear solvers optional output functions
    @ida <node5#ss:djacFn> Dense Jacobian function
  *)
module Dls :
  sig
    (** {4 Callback functions} *)
    (**
     Specify a callback function that computes an approximation to the Jacobian
     matrix J(t, y) for the Dense and Lapackdense {!Ida.linear_solver}s.

     The callback function takes the {!jacobian_arg} as an input and must store
     the computed Jacobian as a {!Ida.Densematrix.t}.

     {b NB:} the elements of the Jacobian argument and the output matrix must no
     longer be accessed after callback function has returned a result, i.e. if
     their values are needed outside of the function call, then they must be
     copied to separate physical structures.
     
     @ida <node5#sss:optin_dls> IDADlsSetDenseJacFn
     @ida <node5#ss:djacFn> Dense Jacobian function
     *)
    val set_dense_jac_fn :
         session
      -> (triple_tmp jacobian_arg -> Densematrix.t -> unit)
      -> unit

    (**
      This function disables the user-supplied dense Jacobian function, and
      switches back to the default internal difference quotient approximation
      that comes with the Dense and Lapackdense {!Ida.linear_solver}s. It is
      equivalent to calling IDASetDenseJacFn with an argument of [NULL].

      @ida <node5#ss:djacFn> Dense Jacobian function
    *)
    val clear_dense_jac_fn : session -> unit

    (**
     Specify a callback function that computes an approximation to the Jacobian
     matrix J(t, y) for the Band and Lapackband {!Ida.linear_solver}s.

     The callback function takes three input arguments:
     - [jac] the standard {!jacobian_arg} with three work vectors.
     - [mupper] the upper half-bandwidth of the Jacobian.
     - [mlower] the lower half-bandwidth of the Jacobian.
     and it must store the computed Jacobian as a {!Ida.Bandmatrix.t}.

    {b NB:} [jac] and the computed Jacobian must no longer be accessed after the
            calback function has returned a result, i.e. if their values are
            needed outside of the function call, then they must be copied to
            separate physical structures.

     @ida <node5#sss:optin_dls> IDADlsSetBandJacFn
     @ida <node5#ss:bjacFn> Banded Jacobian function
     *)
    val set_band_jac_fn :
         session
      -> (triple_tmp jacobian_arg -> int -> int -> Bandmatrix.t -> unit)
      -> unit

    (**
      This function disables the user-supplied band Jacobian function, and
      switches back to the default internal difference quotient approximation
      that comes with the Band and Lapackband {!Ida.linear_solver}s. It is
      equivalent to calling IDASetBandJacFn with an argument of [NULL].

      @ida <node5#ss:bjacFn> Banded Jacobian function
    *)
    val clear_band_jac_fn : session -> unit

    (** {4 Optional input functions} *)

    (**
      Returns the sizes of the real and integer workspaces used by the Dense and
      Band direct linear solvers .

      @ida <node5#sss:optout_dls> IDADlsGetWorkSpace
      @return ([real_size], [integer_size])
     *)
    val get_work_space : session -> int * int


    (**
      Returns the number of calls made to the Dense and Band direct linear
      solvers Jacobian approximation function.

      @ida <node5#sss:optout_dls> IDADlsGetNumJacEvals
    *)
    val get_num_jac_evals : session -> int

    (**
      Returns the number of calls made to the user-supplied right-hand side
      function due to the finite difference (Dense or Band) Jacobian
      approximation.

      @ida <node5#sss:optout_dls> IDADlsGetNumResEvals
    *)
    val get_num_res_evals : session -> int
  end

(** {3 Diagonal approximation} *)
(*
(** Get optional inputs for the linear solver that gives diagonal approximations
    of the Jacobian matrix.
    @ida <node5#sss:optout_diag> Diagonal linear solver optional output functions
  *)
module Diag :
  sig
    (** {4 Optional input functions} *)

    (**
      Returns the sizes of the real and integer workspaces used by the Diagonal
      linear solver.

      @ida <node5#sss:optout_diag> IDADiagGetWorkSpace
      @return ([real_size], [integer_size])
     *)
    val get_work_space : session -> int * int

    (**
      Returns the number of calls made to the user-supplied right-hand side
      function due to finite difference Jacobian approximation in the Diagonal
      linear solver.

      @ida <node5#sss:optout_diag> IDADiagGetNumResEvals
    *)
    val get_num_res_evals : session -> int
  end
(*

(** {3 Scaled Preconditioned Iterative Linear Solvers (SPILS)} *)

(** Set callback functions, set optional outputs, and get optional inputs for
    the Scaled Preconditioned Iterative Linear Solvers: SPGMR, SPBCG, SPTFQMR.
    @ida <node5#sss:optin_spils> Iterative linear solvers optional input functions.
    @ida <node5#sss:optout_spils> Iterative linear solvers optional output functions.
    @ida <node5#ss:psolveFn> Linear preconditioning function
    @ida <node5#ss:precondFn> Jacobian preconditioning function
 *)
module Spils :
  sig
    (** {4 Callback functions} *)

    (**
      Arguments passed to the preconditioner solve callback function.

      @ida <node5#ss:psolveFn> IDASpilsPrecSolveFn
     *)
    type solve_arg =
      {
        res   : val_array;  (** The right-hand side vector, {i r}, of the
                                linear system. *)
        gamma : float;      (** The scalar {i g} appearing in the Newton
                                matrix given by M = I - {i g}J. *)
        delta : float;      (** Input tolerance to be used if an
                                iterative method is employed in the
                                solution. *)
        left  : bool;       (** [true] (1) if the left preconditioner
                                is to be used and [false] (2) if the
                                right preconditioner is to be used. *)
      }

    (**
      Setup preconditioning for any of the SPILS linear solvers. Two functions
      are required: [psetup] and [psolve].

      [psetup jac jok gamma] preprocesses and/or evaluates any Jacobian-related
      data needed by the preconditioner. It takes three inputs:
        - [jac] supplies the basic problem data as a {!jacobian_arg}.
        - [jok] indicates whether any saved Jacobian-related data can be reused.
        If [false] any such data must be recomputed from scratch, otherwise, if
        [true], any such data saved from a previous call to the function can
        be reused, with the current value of [gamma]. A call with [jok] =
        [true] can only happen after an earlier call with [jok] = [false].
        - [gamma] is the scalar {i g} appearing in the Newton matrix given
        by M = I - {i g}J.

      {b NB:} The elements of [jac] must no longer be accessed after [psetup]
              has returned a result, i.e. if their values are needed outside
              of the function call, then they must be copied to a separate
              physical structure.

      It must return [true] if the Jacobian-related data was updated, or
      [false] otherwise, i.e. if the saved data was reused.

      [psolve jac arg z] is called to solve the linear system
      {i P}[z] = [jac.res], where {i P} may be either a left or right
      preconditioner matrix. {i P} should approximate, however crudely, the
      Newton matrix M = I - [jac.gamma] J, where J = delr(f) / delr(y).
      - [jac] supplies the basic problem data as a {!jacobian_arg}.
      - [arg] specifies the linear system as a {!solve_arg}.
      - [z] is the vector in which the result must be stored.

      {b NB:} The elements of [jac], [arg], and [z] must no longer be accessed
              after [psolve] has returned a result, i.e. if their values are
              needed outside of the function call, then they must be copied
              to separate physical structures.

      @ida <node5#sss:optin_spils> IDASpilsSetPreconditioner
      @ida <node5#ss:psolveFn> Linear preconditioning function
      @ida <node5#ss:precondFn> Jacobian preconditioning function
    *)
    val set_preconditioner :
      session
      -> (triple_tmp jacobian_arg -> bool -> float -> bool)
      -> (single_tmp jacobian_arg -> solve_arg -> nvec -> unit)
      -> unit

    (**
      Specifies a Jacobian-vector function.

      The function given, [jactimes jac v Jv], computes the matrix-vector
      product {i J}[v].
      - [v] is the vector by which the Jacobian must be multiplied.
      - [Jv] is the vector in which the result must be stored.

      {b NB:} The elements of [jac], [v], and [Jv] must no longer be accessed
              after [psolve] has returned a result, i.e. if their values are
              needed outside of the function call, then they must be copied
              to separate physical structures.

      @ida <node5#sss:optin_spils> IDASpilsSetJacTimesVecFn
      @ida <node5#ss:jtimesFn> Product Jacobian function
    *)
    val set_jac_times_vec_fn :
      session
      -> (single_tmp jacobian_arg
          -> val_array (* v *)
          -> val_array (* Jv *)
          -> unit)
      -> unit

    (**
      This function disables the user-supplied Jacobian-vector function, and
      switches back to the default internal difference quotient approximation.
      It is equivalent to calling IDASpilsSetJacTimesVecFn with an argument of
      [NULL].

      @ida <node5#sss:optin_spils> IDASpilsSetJacTimesVecFn
      @ida <node5#ss:jtimesFn> Product Jacobian function
    *)
    val clear_jac_times_vec_fn : session -> unit

    (** {4 Optional output functions} *)

    (**
      This function resets the type of preconditioning to be used using a value
      of type {!Ida.preconditioning_type}.

      @ida <node5#sss:optin_spils> IDASpilsSetPrecType
    *)
    val set_prec_type : session -> preconditioning_type -> unit

    (** Constants representing the types of Gram-Schmidt orthogonalization
        possible for the Spgmr {Ida.linear_solver}. *)
    type gramschmidt_type =
      | ModifiedGS
            (** Modified Gram-Schmidt orthogonalization (MODIFIED_GS) *)
      | ClassicalGS
            (** Classical Gram Schmidt orthogonalization (CLASSICAL_GS) *)

    (**
      Sets the Gram-Schmidt orthogonalization to be used with the
      Spgmr {!Ida.linear_solver}.

      @ida <node5#sss:optin_spils> IDASpilsSetGSType
    *)
    val set_gs_type : session -> gramschmidt_type -> unit

    (**
      [set_eps_lin eplifac] sets the factor by which the Krylov linear solver's
      convergence test constant is reduced from the Newton iteration test
      constant. [eplifac]  must be >= 0. Passing a value of 0 specifies the
      default (which is 0.05).

      @ida <node5#sss:optin_spils> IDASpilsSetEpsLin
    *)
    val set_eps_lin : session -> float -> unit

    (**
      [set_maxl maxl] resets the maximum Krylov subspace dimension for the
      Bi-CGStab or TFQMR methods. [maxl] is the maximum dimension of the Krylov
      subspace, a value of [maxl] <= 0 specifies the default (which is 5.0).

      @ida <node5#sss:optin_spils> IDASpilsSetMaxl
    *)
    val set_maxl : session -> int -> unit

    (** {4 Optional input functions} *)

    (**
      Returns the sizes of the real and integer workspaces used by the SPGMR
      linear solver.

      @ida <node5#sss:optout_spils> IDASpilsGetWorkSpace
      @return ([real_size], [integer_size])
    *)
    val get_work_space       : session -> int * int

    (**
      Returns the cumulative number of linear iterations.

      @ida <node5#sss:optout_spils> IDASpilsGetNumLinIters
    *)
    val get_num_lin_iters    : session -> int

    (**
      Returns the cumulative number of linear convergence failures.

      @ida <node5#sss:optout_spils> IDASpilsGetNumConvFails
    *)
    val get_num_conv_fails   : session -> int

    (**
      Returns the number of preconditioner evaluations, i.e., the number of
      calls made to psetup with jok = [false] (see {!set_preconditioner}).

      @ida <node5#sss:optout_spils> IDASpilsGetNumPrecEvals
    *)
    val get_num_prec_evals   : session -> int

    (**
      Returns the cumulative number of calls made to the preconditioner solve
      function, psolve (see {!set_preconditioner}).

      @ida <node5#sss:optout_spils> IDASpilsGetNumPrecSolves
    *)
    val get_num_prec_solves  : session -> int

    (**
      Returns the cumulative number of calls made to the Jacobian-vector
      function, jtimes (see {! set_jac_times_vec_fn}).

      @ida <node5#sss:optout_spils> IDASpilsGetNumJtimesEvals
    *)
    val get_num_jtimes_evals : session -> int

    (**
      Returns the number of calls to the user right-hand side function for
      finite difference Jacobian-vector product approximation. This counter is
      only updated if the default difference quotient function is used.

      @ida <node5#sss:optout_spils> IDASpilsGetNumResEvals
    *)
    val get_num_res_evals    : session -> int
  end

(** {3 Banded preconditioner} *)

(** Get optional outputs for the banded preconditioner module of the
    Scaled Preconditioned Iterative Linear Solvers:
      SPGMR, SPBCG, SPTFQMR.
    @ida <node5#sss:cvbandpre> Serial banded preconditioner module
  *)
module BandPrec :
  sig
    (** {4 Optional input functions} *)

    (**
      Returns the sizes of the real and integer workspaces used by the serial
      banded preconditioner module.

      @ida <node5#sss:cvbandpre> IDABandPrecGetWorkSpace
      @return ([real_size], [integer_size])
     *)
    val get_work_space : session -> int * int

    (**
      Returns the number of calls made to the user-supplied right-hand side
      function due to finite difference banded Jacobian approximation in the
      banded preconditioner setup function.

      @ida <node5#sss:cvbandpre> IDABandPrecGetNumResEvals
    *)
    val get_num_res_evals : session -> int
  end

 *)
 *)

(** Inequality constraints on variables.

 @ida <node5#sss:idasetconstraints> IDASetConstraints
 *)
module Constraints :
  sig
    (** An abstract array type, whose i-th component specifies that the i-th
        component of the dependent variable vector y should be:

        NonNegative  i.e. >= 0, or
        NonPositive  i.e. <= 0, or
        Positive     i.e. > 0, or
        Negative     i.e. < 0, or
        Unconstrained
     *)
    type t
    type constraint_type =
    | Unconstrained
    | NonNegative
    | NonPositive
    | Positive
    | Negative

    (** [create n] returns an array with [n] elements, each set to
        Unconstrained.  *)
    val create : int -> t

    (** Returns the length of an array *)
    val length : t -> int

    (** [get c i] returns the constraint on the i-th variable in the DAE.  *)
    val get : t -> int -> constraint_type

    (** [set c i x] sets the constraint on the i-th variable in the DAE to
        [x].  *)
    val set : t -> int -> constraint_type -> unit

    (** [fill c x] fills the array so that all variables will have constraint
        [x].  *)
    val fill : t -> constraint_type -> unit

    (** [blit a b] copies the contents of [a] to [b].  *)
    val blit : t -> t -> unit
  end

(** Variable classification that needs to be specified for computing consistent
 initial values.

 @ida <node5#sss:idasetid> IDASetId
 *)
module Id :
  sig
    (** An abstract array type, whose i-th component specifies whether the i-th
        component of the dependent variable vector y is an algebraic or
        differential variable, for each i.  *)
    type t
    type component_type =
    | Algebraic    (** Algebraic variable; residual function must not depend
                       on this component's derivative.  *)
    | Differential (** Differential variable; residual function can depend on
                       this component's derivative.  *)

    (** [create n] returns an array with [n] elements, each set to
        Algebraic.  *)
    val create : int -> t

    (** Returns the length of an array *)
    val length : t -> int

    (** [get c i] returns the component type of the i-th variable in the
        DAE.  *)
    val get : t -> int -> component_type

    (** [set c i x] sets the component type of the i-th variable in the DAE to
        [x].  *)
    val set : t -> int -> component_type -> unit

    (** [fill c x] fills the array so that all variables will have component
        type [x].  *)
    val fill : t -> component_type -> unit

    (** [blit a b] copies the contents of [a] to [b].  *)
    val blit : t -> t -> unit
  end

val set_constraints : session -> Constraints.t -> unit

(** [calc_ic_y_init ida tout1] corrects the initial values y0 at time t0.  All
    components of y are computed, using all components of y' as input.

    [tout1] is the first value of t at which a solution will be requested (from
    IDASolve). This value is needed here only to determine the direction of
    integration and rough scale in the independent variable t.

    @ida <node#sss:idacalcic> IDACalcIC
 *)
val calc_ic_y_init : session -> float -> unit

(** [calc_ic_ya_yd'_init ida id tout1] corrects the initial values y0 and y0'
    at time t0.  [id] specifies some components of y0 (and y0') as
    differential, and other components as algebraic.  This function computes
    the algebraic components of y and differential components of y, given the
    differential components of y.

    If the i-th component of [id] is Algebraic (or Differential), then the i-th
    components of y0 and y0' are both treated as algebraic (respectively,
    differential).

    [tout1] is the first value of t at which a solution will be requested (from
    IDASolve). This value is needed here only to determine the direction of
    integration and rough scale in the independent variable t.

    @ida <node#sss:idacalcic> IDACalcIC
    @ida <node#sss:idasetid> IDASetId
 *)
val calc_ic_ya_yd'_init : session -> Id.t -> float -> unit
