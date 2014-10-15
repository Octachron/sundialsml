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

(***********************************************************************)
(* Much of the comment text is taken directly from:                    *)
(*                                                                     *)
(*               User Documentation for CVODE v2.6.0                   *)
(*                Alan C. Hindmarsh and Radu Serban                    *)
(*              Center for Applied Scientific Computing                *)
(*              Lawrence Livermore National Laboratory                 *)
(*                                                                     *)
(***********************************************************************)

(** Solves nonlinear systems using Newton-Krylov techniques.

    This documented interface is structured as follows.
    {ol
      {- {{:#linear}Linear solvers}}
      {- {{:#solver}Solver initialization and use}}
      {- {{:#set}Modifying the solver}}
      {- {{:#get}Querying the solver}}
      {- {{:#exceptions}Exceptions}}}

     @version VERSION()
     @author Timothy Bourke (Inria)
     @author Jun Inoue (Inria)
     @author Marc Pouzet (LIENS) *)

open Kinsol_impl
open Sundials

(** A session with the KINSOL solver.
 
    An example session with Kinsol ({openfile kinsol_skel.ml}): {[
#include "examples/ocaml/skeletons/kinsol_skel.ml"
    ]}

    @kinsol <node5#ss:skeleton_sol> Skeleton of main program *)
type ('data, 'kind) session = ('data, 'kind) Kinsol_impl.session

(** Alias for sessions based on serial nvectors. *)
type serial_session = (Nvector_serial.data, Nvector_serial.kind) session

(** {2:linear Linear Solvers} *)

(** Linear solvers used by Kinsol.

    @kinsol <node5#sss:lin_solv_init> Linear Solver Specification Functions *)
type ('data, 'kind) linear_solver = ('data, 'kind) Kinsol_impl.linear_solver

(** Alias for linear solvers that are restricted to serial nvectors. *)
type serial_linear_solver =
        (Nvector_serial.data, Nvector_serial.kind) linear_solver

(** Workspaces with two temporary vectors. *)
type 'a double = 'a * 'a

(** Arguments common to Jacobian callback functions.    
 
    @kinsol <node5#ss:djacFn> KINDlsDenseJacFn
    @kinsol <node5#ss:bjacFn> KINDlsBandJacFn
    @kinsol <node5#ss:psolveFn> KINSpilsPrecSolveFn
    @kinsol <node5#ss:precondFn> KINSpilsPrecSetupFn *)
type ('t, 'a) jacobian_arg =
  {
    jac_u   : 'a;   (** The current unscaled iterate. *)
    jac_fu  : 'a;   (** The current value of the vector F([u]). *)
    jac_tmp : 't    (** Workspace data. *)
  }

(** The range of nonzero entries in a band matrix. *)
type bandrange = Kinsol_impl.bandrange =
  { mupper : int; (** The upper half-bandwidth. *)
    mlower : int; (** The lower half-bandwidth. *) }

(** Direct Linear Solvers operating on dense and banded matrices.
    
    @kinsol <node5#sss:optin_dls> Direct linear solvers optional input functions
    @kinsol <node5#sss:optout_dls> Direct linear solvers optional output functions
    @kinsol <node5#ss:djacFn> KINDlsDenseJacFn *)
module Dls :
  sig

    (** Callback functions that compute dense approximations to a Jacobian
        matrix. In the call [dense_jac_fn arg jac], [arg] is a {!jacobian_arg}
        with two work vectors and the computed Jacobian must be stored
        in [jac].

        The callback should load the [(i,j)]th entry of [jac] with
        {% $\partial y_i/\partial y_j$%}, i.e., the partial derivative of the
        [i]th equation with respect to the [j]th variable, evaluated at the
        values of [t] and [y] obtained from [jac]. Only nonzero elements need
        be loaded into [jac].

        {warning Neither the elements of [arg] nor the matrix [jac] should
                 be accessed after the function has returned.}

        @kinsol <node5#sss:lin_solv_init> KINDense/KINLapackDense
        @kinsol <node5#sss:optin_dls> KINDlsSetDenseJacFn
        @kinsol <node5#ss:djacFn> KINDlsDenseJacFn *)
    type dense_jac_fn = (RealArray.t double, RealArray.t) jacobian_arg
                                                -> Dls.DenseMatrix.t -> unit

    (** A direct linear solver on dense matrices. The optional argument
        specifies a callback function for computing an approximation to the
        Jacobian matrix. If this argument is omitted, then a default
        implementation based on difference quotients is used.

        @kinsol <node5#sss:lin_solv_init> KINDense
        @kinsol <node5#sss:optin_dls> KINDlsSetDenseJacFn
        @kinsol <node5#ss:djacFn> KINDlsDenseJacFn *)
    val dense : dense_jac_fn option -> serial_linear_solver

    (** A direct linear solver on dense matrices using LAPACK. See {!Dense}.
        Only available if {!lapack_enabled}.

        @kinsol <node5#sss:lin_solv_init> KINLapackDense
        @kinsol <node5#sss:optin_dls> KINDlsSetDenseJacFn
        @kinsol <node5#ss:djacFn> KINDlsDenseJacFn *)
    val lapack_dense : dense_jac_fn option -> serial_linear_solver

    (** Callback functions that compute banded approximations to
        a Jacobian matrix. In the call [band_jac_fn {mupper; mlower} arg jac],
        - [mupper] is the upper half-bandwidth of the Jacobian,
        - [mlower] is the lower half-bandwidth of the Jacobian,
        - [arg] is a {!jacobian_arg} with three work vectors, and,
        - [jac] is storage for the computed Jacobian.

        The callback should load the [(i,j)]th entry of [jac] with
        {% $\partial y_i/\partial y_j$%}, i.e., the partial derivative of
        the [i]th equation with respect to the [j]th variable, evaluated
        at the values of [t] and [y] obtained from [jac]. Only nonzero
        elements need be loaded into [jac].

        {warning Neither the elements of [arg] nor the matrix [jac] should
                 be accessed after the function has returned.}

        @kinsol <node5#sss:lin_solv_init> KINBand/KINLapackBand
        @kinsol <node5#sss:optin_dls> KINDlsSetBandJacFn
        @kinsol <node5#ss:bjacFn> KINDlsBandJacFn *)
    type band_jac_fn = bandrange
                        -> (RealArray.t double, RealArray.t) jacobian_arg
                        -> Dls.BandMatrix.t -> unit

    (** A direct linear solver on banded matrices. The optional argument
        specifies a callback function for computing an approximation to the
        Jacobian matrix. If this argument is omitted, then a default
        implementation based on difference quotients is used. The other
        argument gives the width of the bandrange.

        @kinsol <node5#sss:lin_solv_init> KINBand
        @kinsol <node5#sss:optin_dls> KINDlsSetBandJacFn
        @kinsol <node5#ss:bjacFn> KINDlsBandJacFn *)
    val band : bandrange -> band_jac_fn option -> serial_linear_solver

    (** A direct linear solver on banded matrices using LAPACK. See {!band}.
        Only available if {!lapack_enabled}.

        @kinsol <node5#sss:lin_solv_init> KINLapackBand
        @kinsol <node5#sss:optin_dls> KINDlsSetBandJacFn
        @kinsol <node5#ss:bjacFn> KINDlsBandJacFn *)
    val lapack_band : bandrange -> band_jac_fn option -> serial_linear_solver

    (** {3:stats Solver statistics} *)

    (** Returns the sizes of the real and integer workspaces used by a direct
        linear solver.

        @kinsol <node5#sss:optout_dense> KINDlsGetWorkSpace
        @return ([real_size], [integer_size]) *)
    val get_work_space : serial_session -> int * int

    (** Returns the number of calls made by a direct linear solver to the
        Jacobian approximation function.

        @kinsol <node5#sss:optout_dense> KINDlsGetNumJacEvals *)
    val get_num_jac_evals : serial_session -> int

    (** Returns the number of calls made by a direct linear solver to the
        Jacobian approximation function.

        @kinsol <node5#sss:optout_dense> KINDlsGetNumFuncEvals *)
    val get_num_func_evals : serial_session -> int

    (** {3:lowlevel Low-level solver manipulation}

        The {!init} and {!reinit} functions are the preferred way to set or
        change a Jacobian function. These low-level functions are provided for
        experts who want to avoid resetting internal counters and other
        associated side-effects. *)

    (** Change the dense Jacobian function.
 
        @kinsol <node5#sss:optin_dls> KINDlsSetDenseJacFn *)
    val set_dense_jac_fn : serial_session -> dense_jac_fn -> unit

    (** Remove a dense Jacobian function and use the default
        implementation.
 
        @kinsol <node5#sss:optin_dls> KINDlsSetDenseJacFn *)
    val clear_dense_jac_fn : serial_session -> unit

    (** Change the band Jacobian function.

        @kinsol <node5#sss:optin_dls> KINDlsSetBandJacFn *)
    val set_band_jac_fn : serial_session -> band_jac_fn -> unit

    (** Remove a banded Jacobian function and use the default
        implementation.

        @kinsol <node5#sss:optin_dls> KINDlsSetBandJacFn *)
    val clear_band_jac_fn : serial_session -> unit
  end

(** Scaled Preconditioned Iterative Linear Solvers (SPILS).

    @kinsol <node5#sss:optin_spils> Iterative linear solvers optional input functions.
    @kinsol <node5#sss:optout_spils> Iterative linear solvers optional output functions.
    @kinsol <node5#ss:psolveFn> KINSpilsPrecSolveFn
    @kinsol <node5#ss:precondFn> KINSpilsPrecSetupFn *)
module Spils :
  sig
    (** {3:precond Preconditioners} *)

    (** Arguments passed to the preconditioner solver function.

        @kinsol <node5#ss:psolveFn> KINSpilsPrecSolveFn *)
    type 'data solve_arg =
      {
        uscale : 'data; (** Diagonal elements of the scaling matrix for [u]. *)
        fscale : 'data; (** Diagonal elements of the scaling matrix
                            for [fval]. *)
      }

    (** Callback functions that solve a linear system involving a
        preconditioner matrix. The call [prec_solve_fn jarg sarg v] must solve
        {% $Pz = r$%}, where [jarg] is a {!jacobian_arg} with one work vector,
        [sarg] is a {!solve_arg} giving the scaling matrices, and
        [v] is initially the right-hand side vector $r$ and is later filled
        with the computed solution $z$.
        $P$ is a preconditioner matrix that approximates the system
        Jacobian {% $J = \frac{\partial F}{\partial u}$%}.

        Raising {!Sundials.RecoverableFailure} indicates a recoverable error.
        Any other exception is treated as an unrecoverable error.

        {warning Neither the elements of [jarg] or [sarg], nor [z] should be
                 accessed after the function has returned.}

        @kinsol <node5#sss:optin_spils> KINSpilsSetPreconditioner
        @kinsol <node5#ss:psolveFn> KINSpilsPrecSolveFn *)
    and 'a prec_solve_fn =
      ('a, 'a) jacobian_arg
      -> 'a solve_arg
      -> 'a
      -> unit

    (** Callback functions that preprocess or evaluate Jacobian-related data
        need by {!prec_solve_fn}. In the call [prec_setup_fn jarg sarg],
        [jarg] is a {!jacobian_arg} with two work vectors and [sarg] is a
        {!solve_arg} giving the scaling matrices.

        The callback should raise an exception if unsuccessful.

        {warning The elements of [jarg] and [sarg] should not be accessed after
                 the function has returned.}

        @kinsol <node5#ss:precondFn> KINSpilsPrecSetupFn
        @kinsol <node5#sss:optin_spils> KINSpilsSetPreconditioner
     *)
    and 'a prec_setup_fn =
      ('a double, 'a) jacobian_arg
      -> 'a solve_arg
      -> unit


    (** Callback functions that compute (an approximation to) the Jacobian
        times a vector. In the call [jac_times_vec_fn v jv u new_u], [v] is the
        vector multiplying the Jacobian, [jv] is the vector in which to store
        the result—{% $\mathtt{jv} = J\mathtt{v}$%},—[u] is the current value of
        the dependent variable vector, and [new_u=true] indicates that
        the Jacobian data should be recomputed. Returning [false] requests an
        update of the Jacobian data at the next call.

        {warning [v], [jv], and [u] should not be accessed after the function
                 has returned.}

        @kinsol <node5#ss:jtimesFn> KINSpilsJacTimesVecFn
        @kinsol <node5#sss:optin_spils> KINSpilsSetJacTimesVecFn
     *)
    and 'data jac_times_vec_fn =
      'data      (* v *)
      -> 'data   (* jv *)
      -> 'data   (* u *)
      -> bool    (* new_u *)
      -> bool

    (** Specifies a preconditioner, including the type of preconditioning
        (none or right) and callback functions.
        The following functions and those in {!Kinsol_bbd} construct
        preconditioners.

        The {!prec_solve_fn} is usually mandatory. The {!prec_setup_fn} can be
        omitted if not needed. If the {!jac_times_vec_fn} is omitted, a
        default implementation based on difference quotients is used.

        @kinsol <node5#sss:optin_spils> KINSpilsSetPreconditioner
        @kinsol <node5#sss:optin_spils> KINSpilsSetJacTimesVecFn
        @kinsol <node5#ss:psolveFn> KINSpilsPrecSolveFn
        @kinsol <node5#ss:precondFn> KINSpilsPrecSetupFn
        @kinsol <node5#ss:jtimesFn> KINSpilsJacTimesVecFn
    *)
    type ('a, 'k) preconditioner = ('a, 'k) SpilsTypes.preconditioner

    (** No preconditioning.  *)
    val prec_none : ('a, 'k) preconditioner

    (** Right preconditioning. The {!prec_setup_fn} should compute
        the right preconditioner matrix $P$ which is used to form
        the scaled preconditioned linear system
        {% $(D_F J(u) P^{-1} D_u^{-1} \cdot (D_u P x) = * -D_F F(u)$%}.
        If a {!prec_solve_fn} is not given, a default implementation based on
        difference quotient approximation is used. *)
    val prec_right :
      ?setup:'a prec_setup_fn
      -> ?solve:'a prec_solve_fn
      -> ?jac_times_vec:'a jac_times_vec_fn
      -> unit
      -> ('a, 'k) preconditioner

    (** {3:lsolvers Solvers} *)

    (** Krylov iterative solver using the scaled preconditioned generalized
        minimum residual (GMRES) method.
        In the call [spgmr ~maxl:maxl ~max_restarts:maxr prec],
        [maxl] is the maximum dimension of the Krylov subspace (defaults to 5),
        [maxr] is the maximum number of restarts (defaults to 5; set to 0 to
        disable restarts), and [prec] is a {!preconditioner}.

        @kinsol <node5#sss:lin_solv_init> KINSpgmr
        @kinsol <node5#sss:optin_spils> KINSpilsSetPreconditioner
        @kinsol <node5#sss:optin_spils> KINSpilsSetMaxRestarts
        @kinsol <node5#ss:psolveFn> KINSpilsPrecSolveFn
        @kinsol <node5#ss:precondFn> KINSpilsPrecSetupFn *)
    val spgmr : ?maxl:int -> ?max_restarts:int -> ('a, 'k) preconditioner
                    -> ('a, 'k) linear_solver

    (** Krylov iterative solver using the scaled preconditioned biconjugate
        stabilized (Bi-CGStab) method.
        In the call [spbcg ~maxl:maxl prec], [maxl] is the maximum dimension of
        the Krylov subspace (defaults to 5), and [prec] is a {!preconditioner}.

        @kinsol <node5#sss:lin_solv_init> KINSpbcg
        @kinsol <node5#sss:optin_spils> KINSpilsSetPreconditioner
        @kinsol <node5#ss:psolveFn> KINSpilsPrecSolveFn
        @kinsol <node5#ss:precondFn> KINSpilsPrecSetupFn *)
    val spbcg : ?maxl:int -> ('a, 'k) preconditioner -> ('a, 'k) linear_solver

    (** Krylov iterative with the scaled preconditioned transpose-free
        quasi-minimal residual (SPTFQMR) method.
        In the call [sptfqmr ~maxl:maxl prec], [maxl] is the maximum dimension
        of the Krylov subspace (defaults to 5), and [prec] is a
        {!preconditioner}.

        @kinsol <node5#sss:lin_solv_init> KINSptfqmr
        @kinsol <node5#sss:optin_spils> KINSpilsSetPreconditioner
        @kinsol <node5#ss:psolveFn> KINSpilsPrecSolveFn
        @kinsol <node5#ss:precondFn> KINSpilsPrecSetupFn *)
    val sptfqmr : ?maxl:int -> ('a,'k) preconditioner -> ('a,'k) linear_solver

    (** {3:stats Solver statistics} *)

    (** Returns the sizes of the real and integer workspaces used by the spils
        linear solver.

        @kinsol <node5#sss:optout_spils> KINSpilsGetWorkSpace
        @return ([real_size], [integer_size]) *)
    val get_work_space       : ('a, 'k) session -> int * int

    (** Returns the cumulative number of linear iterations.

        @kinsol <node5#sss:optout_spils> KINSpilsGetNumLinIters *)
    val get_num_lin_iters    : ('a, 'k) session -> int

    (** Returns the cumulative number of linear convergence failures.

        @kinsol <node5#sss:optout_spils> KINSpilsGetNumConvFails *)
    val get_num_conv_fails   : ('a, 'k) session -> int

    (** Returns the cumulative number of calls to the setup function.

        @kinsol <node5#sss:optout_spils> KINSpilsGetNumPrecEvals *)
    val get_num_prec_evals   : ('a, 'k) session -> int

    (** Returns the cumulative number of calls to the preconditioner solve
        function.

        @kinsol <node5#sss:optout_spils> KINSpilsGetNumPrecSolves *)
    val get_num_prec_solves  : ('a, 'k) session -> int

    (** Returns the cumulative number of calls to the Jacobian-vector
        function.

        @kinsol <node5#sss:optout_spils> KINSpilsGetNumJtimesEvals *)
    val get_num_jtimes_evals : ('a, 'k) session -> int

    (** Returns the number of calls to the system function for finite
        difference quotient Jacobian-vector product approximations. This
        counter is only updated if the default difference quotient function
        is used.

        @kinsol <node5#sss:optout_spils> KINSpilsGetNumFuncEvals *)
    val get_num_func_evals    : ('a, 'k) session -> int

    (** {3:lowlevel Low-level solver manipulation} *)

    (** Change the preconditioner functions.

        @kinsol <node5#sss:optin_spils> KINSpilsSetPreconditioner
        @kinsol <node5#ss:precondFn> KINSpilsPrecSetupFn
        @kinsol <node5#ss:psolveFn> KINSpilsPrecSolveFn *)
    val set_preconditioner :
      ('a, 'k) session
      -> ?setup:'a prec_setup_fn
      -> ?solve:'a prec_solve_fn
      -> unit
      -> unit

    (** Change the Jacobian-times-vector function.

        @kinsol <node5#sss:optin_spils> KINSpilsSetJacTimesVecFn
        @kinsol <node5#ss:jtimesFn> KINSpilsJacTimesVecFn *)
    val set_jac_times_vec_fn :
      ('a, 'k) session
      -> 'a jac_times_vec_fn
      -> unit

    (** Remove a Jacobian-times-vector function and use the default
        implementation.

        @kinsol <node5#sss:optin_spils> KINSpilsSetJacTimesVecFn *)
    val clear_jac_times_vec_fn : ('a, 'k) session -> unit
  end

(** Alternate Linear Solvers.

    @kinsol <node8#s:new_linsolv> Providing Alternate Linear Solver Modules *)
module Alternate :
  sig
    (** Functions that initialize linear solver data, like counters and
        statistics.

        Raising any exception in this function (including
        {!Sundials.RecoverableFailure}) is treated as an unrecoverable error.

        @cvode <node8#SECTION00810000000000000000> linit *)
    type ('data, 'kind) linit = ('data, 'kind) session -> unit

    (** Functions that prepare the linear solver for subsequent calls to
        {!lsolve}. They may recompute Jacobian-related data.

        Raising any exception in this function (including
        {!Sundials.RecoverableFailure}) is treated as an unrecoverable error.

        @kinsol <node8#SECTION00820000000000000000> lsetup *)
    type ('data, 'kind) lsetup = ('data, 'kind) session -> unit

    (** Functions that solve the linear equation $Jx = b$. In the call
        [res_norm = lsolve x b], [x] is an initial guess on entry, on return
        it must contain the computed solution, and [b] is the right-hand
        side vector, set to $-F(u)$, at the current iterate.
        This function returns the {i L2} norm of the residual
        vector.
        
        Raising {!Sundials.RecoverableFailure} indicates an error where
        recovery may be possible by calling the {!lsetup} function again.
        Other exceptions are treated as unrecoverable errors.

        {warning The vectors [x] and [b] should not be accessed after the
                 function returns.}

        @kinsol <node8#SECTION00830000000000000000> lsolve *)
    type ('data, 'kind) lsolve =
      ('data, 'kind) session
      -> 'data
      -> 'data
      -> float option

    (** The callbacks needed to implement an alternate linear solver. *)
    type ('data, 'kind) callbacks =
      {
        linit  : ('data, 'kind) linit option;
        lsetup : ('data, 'kind) lsetup option;
        lsolve : ('data, 'kind) lsolve;
      }

    (** Creates a linear solver from a function returning a set of
        callbacks. The creation function is passed a session and a vector.
        The latter indicates the problem size and can, for example, be
        cloned. *)
    val make :
          (('data, 'kind) session -> ('data, 'kind) Nvector.t option
                                                  -> ('data, 'kind) callbacks)
          -> ('data, 'kind) linear_solver

    (** {3:internals Solver internals} *)

    (** Returns the internal [u] and [uscale] values. *)
    val get_u_uscale : ('data, 'kind) session -> 'data * 'data

    (** Returns the internal [f] and [fscale] values. *)
    val get_f_fscale  : ('data, 'kind) session -> 'data * 'data

    (** Sets the internal [sJpnorm] value. *)
    val set_sjpnorm   : ('data, 'kind) session -> float -> unit

    (** Sets the internal [sfdotJp] value. *)
    val set_sfdotjp   : ('data, 'kind) session -> float -> unit
  end

(** {2:solver Solver initialization and use} *)

(** System function that defines nonlinear problem. The call
    [sysfun u fval] must calculate $F(u)$ into [fval] using the current value
    vector [u].

     Raising {!Sundials.RecoverableFailure} indicates a recoverable error.
     Any other exception is treated as an unrecoverable error.

    {warning [u] and [fval] should not be accessed after the function
             returns.}

    @kinsol <node5#ss:sysFn>           Problem-defining function *)
type 'data sysfn = 'data -> 'data -> unit

(** Creates and initializes a session with the Kinsol solver. The call
    [init linsolv f tmpl] has as arguments:
     - [linsolv], the linear solver to use,
     - [f],       the system function of the nonlinear problem, and,
     - [tmpl]     a template to initialize the session (e.g., the
                  initial guess vector).

     @kinsol <node5#sss:kinmalloc>     KINCreate/KINInit
     @kinsol <node5#sss:lin_solv_init> Linear solver specification functions *)
val init : ('data, 'kind) linear_solver -> 'data sysfn
           -> ('data, 'kind) Nvector.t -> ('data, 'kind) session

type result =
  | Success           (** The scaled norm of $F(u)$ is less than [fnormtol].
                          See {!set_func_norm_tol}. {cconst KIN_SUCCESS} *)
  | InitialGuessOK    (** The initial guess already satisfies the system.
                          {cconst KIN_INITIAL_GUESS_OK} *)
  | StoppedOnStepTol  (** Stopped based on scaled step length. The
                          current iterate is an approximate solution, or the
                          algorithm stalled near an invalid solution, or
                          [scsteptol] is too large
                          (see {!set_scaled_step_tol }).
                          {cconst KIN_STEP_LT_STPTOL} *)

(** Computes an approximate solution to a nonlinear system. The call
    [solve s u linesearch u_scale f_scale] has arguments:
    - [s], a solver session,
    - [u], an initial guess that is replaced with an approximate solution
           for [F(u) = 0],
    - [linesearch], whether to use a globalization strategy (line search),
    - [u_scale], the diagonal elements of the scaling matrix $D_u$ for
                 vector [u] chosen so that all $D_u u$ all have roughly the
                 same magnitude when [u] is close to a root of $F(u)$, and,
    - [f_scale], the diagonal elements of the scaling matrix $D_f$ for
                 $F(u)$ chosen so that all $D_f F(u)$ have roughtly the same
                 magnitude when [u] is not near a root of $F(u)$.

    The function either returns a {!result} or raises one of the exceptions
    listed below.
 
    @kinsol <node5#sss:kinsol> KINSol
    @raise IllInput                     An input parameter was invalid.
    @raise LineSearchNonConvergence     Line search could not find a suitable iterate.
    @raise MaxIterationsReached         The maximum number of nonlinear iterations was reached.
    @raise MaxNewtonStepExceeded        Five consecutive steps satisfied a scaled step length test.
    @raise LineSearchBetaConditionFailure  Line search could not satisfy the beta-condition.
    @raise LinearSolverNoRecovery       The {!prec_solve_fn} callback raised {!Sundials.RecoverableFailure} but the preconditioner is already current.
    @raise LinearSolverInitFailure      Linear solver initialization failed.
    @raise LinearSetupFailure           The {!prec_setup_fn} callback failed unrecoverably.
    @raise LinearSolverFailure          Either {!prec_solve_fn} failed unrecoverably or the linear solver encountered an error condition.
    @raise SystemFunctionFailure        The {!sysfn} callback failed unrecoverably.
    @raise FirstSystemFunctionFailure   The {!sysfn} callback raised {!Sundials.RecoverableFailure} when first called.
    @raise RepeatedSystemFunctionFailure  The {!sysfn} callback raised {!Sundials.RecoverableFailure} repeatedly. *)
val solve :
    ('a, 'k) session
    -> ('a, 'k) Nvector.t
    -> bool
    -> ('a, 'k) Nvector.t
    -> ('a, 'k) Nvector.t
    -> result

(** {2:set Modifying the solver (optional input functions)} *)

(** Specifies the maximum number of nonlinear iterations allowed.

    @kinsol <node5#ss:optin_main> KINSetNumMaxIters *)
val set_num_max_iters : ('a, 'k) session -> int -> unit

(** Specifies whether an initial call to the preconditioner setup function is
    made ([false], the default) or not made ([true]).

    This function is useful when solving a sequence of problems where the final
    preconditioner values of a problem becomes the initial value for the next
    problem.

    @kinsol <node5#ss:optin_main> KINSetNoInitSetup *)
val set_no_init_setup : ('a, 'k) session -> bool -> unit

(** Controls whether the nonlinear residual monitoring scheme is used ([false],
    the default), or not ([true]) to control Jacobian updating. It only has an
    effect for the Dense and Band solvers.

    @kinsol <node5#ss:optin_main> KINSetNoResMon *)
val set_no_res_mon : serial_session -> bool -> unit

(** Specifies the maximum number of nonlinear iterations between calls to the
    preconditioner setup function. Pass [None] to set the default (10).

    @kinsol <node5#ss:optin_main> KINSetMaxSetupCalls *)
val set_max_setup_calls : ('a, 'k) session -> int option -> unit

(** Specifies the maximum number of nonlinear iterations between checks by the
    residual monitoring algorithm. Pass [None] to set the default (5). It only
    affects the Dense and Band solvers.

    @kinsol <node5#ss:optin_main> KINSetMaxSubSetupCalls *)
val set_max_sub_setup_calls : serial_session -> int option -> unit

(** The parameters {i gamma} and {i alpha} in the formula for the Eisenstat and
    Walker Choice 2 for {i eta}. Set either to [None] to specify its default
    value. The legal values are 0 < [egamma] <= 1.0 and 1 < [ealpha] <= 2.0.

    @kinsol <node3#SECTION00300900000000000000>   Stopping criteria for iterative linear solvers *)
type eta_params = {
  egamma : float option; (** default = 0.9 *)
  ealpha : float option; (** default = 2.0 *)
}

(** The choice of {i eta} used in the stopping criteria for the linear system
    solver.

    @kinsol <node3#SECTION00300900000000000000>   Stopping criteria for iterative linear solvers *)
type eta_choice =
  | EtaChoice1                   (** Eisenstat and Walker Choice 1 *)
  | EtaChoice2 of eta_params     (** Eisenstat and Walker Choice 2 *)
  | EtaConstant of float option  (** Constant (default = 0.1) *)

(** Specifies the method for computing the value of the {i eta} coefficient used
    in the calculation of the linear solver convergence tolerance.

    @kinsol <node5#ss:optin_main> KINSetEtaForm
    @kinsol <node5#ss:optin_main> KINSetEtaConstValue
    @kinsol <node5#ss:optin_main> KINSetEtaParams *)
val set_eta_choice : ('a, 'k) session -> eta_choice -> unit

(** Specifies the constant value of {i omega} when using residual monitoring.
    Pass [None] to specify the default value (0.9). The legal values are 0 <
    [omegaconst] < 1.0.

    @kinsol <node5#ss:optin_main> KINSetResMonConstValue *)
val set_res_mon_const_value : ('a, 'k) session -> float option -> unit

(** Specifies the minimum and maximum values in the formula for {i omega}.
    The legal values are
    {% $0 < \mathtt{omegamin} < \mathtt{omegamax} < 1.0$%}.

    @kinsol <node5#ss:optin_main> KINSetResMonParams
    @kinsol <node3#SECTION00300800000000000000> Residual monitoring for Modified Newton method *)
val set_res_mon_params : ('a, 'k) session
                         -> ?omegamin:float
                         -> ?omegamax:float
                         -> unit
                         -> unit

(** Specifies whether or not the value of {i epsilon}, the
    scaled linear residual tolerance, is bounded from below.

    The default value for this flag is [false] meaning that a positive minimum
    value equal to [0.01*fnormtol] is applied to {i epsilon}.

    @kinsol <node5#ss:optin_main> KINSetNoMinEps
    @kinsol <node5#ss:optin_main> KINSetFuncNormTol *)
val set_no_min_eps : ('a, 'k) session -> bool -> unit

(** Specifies the maximum allowable scaled length of the Newton step. Pass
    [None] to specify the default value {% $1000\lVert u_0 \rVert_{D_u}$%},
    otherwise the given value must be greater than zero.

    @kinsol <node5#ss:optin_main> KINSetMaxNewtonStep *)
val set_max_newton_step : ('a, 'k) session -> float option -> unit

(** Specifies the maximum number of beta-condition failures in the
    line search algorithm. Pass [None] to specify the default (10).

    @kinsol <node5#ss:optin_main> KINSetMaxBetaFails *)
val set_max_beta_fails : ('a, 'k) session -> float option -> unit

(** Specifies the relative error in computing $F(u)$, which is used in the
    difference quotient approximation of the Jacobian-vector product. Pass
    [None] to specify the default value
    ({% $\sqrt{\mathtt{unit_roundoff}}$%}).

    @kinsol <node5#ss:optin_main> KINSetRelErrFunc *)
val set_rel_err_func : ('a, 'k) session -> float option -> unit

(** Specifies the stopping tolerance on the scaled maximum norm.
    It must be greater than zero. Pass [None] to specify the default
    value ({% $\mathtt{unit_roundoff}^\frac{1}{3}$%}).

    @kinsol <node5#ss:optin_main> KINSetFuncNormTol *)
val set_func_norm_tol : ('a, 'k) session -> float option -> unit

(** Specifies the stopping tolerance on the minimum scaled step length, which
    must be greater than zero. Pass [None] to specify the default
    value ({% $\mathtt{unit_roundoff}^\frac{1}{3}$%}).

    @kinsol <node5#ss:optin_main> KINSetScaledStepTol *)
val set_scaled_step_tol : ('a, 'k) session -> float option -> unit

(** Symbolic names for inequality constraints on variables, used for
    {!set_constraints}.  This function requires you to pass in an
    nvector populated with magic constants specifying each variable as
    positive, non-positive, negative, non-negative, or unconstrained.
    This module gives symbolic names to those constants, for your
    convenience.

    @kinsol <node5#ss:optin_main> KINSetConstraints
 *)
module Constraint :
  sig
    (** A symbolic name for the magic floating-point constant [0.0]. *)
    val unconstrained : float
    (** A symbolic name for the magic floating-point constant [1.0]. *)
    val non_negative : float
    (** A symbolic name for the magic floating-point constant [-1.0]. *)
    val non_positive : float
    (** A symbolic name for the magic floating-point constant [2.0]. *)
    val positive : float
    (** A symbolic name for the magic floating-point constant [-2.0]. *)
    val non_positive : float

    (** An ADT representation of the magic constants specifying
        constraints, useful for pattern-matching.  *)
    type t =
    | Unconstrained                     (** no constraints *)
    | NonNegative                       (** >= 0 *)
    | NonPositive                       (** <= 0 *)
    | Positive                          (** > 0 *)
    | Negative                          (** < 0 *)

    (** Encode a constraint specifier into the corresponding magic
        floating-point constant.  *)
    val to_float : t -> float

    (** Decode a magic float-point constant into a constraint
        specifier.  Raises [Invalid_argument] if the given floating
        point value is not a legal constraint specification.  *)
    val of_float : float -> t

    (** Returns strings like ["NonNegative"], ["Unconstrained"], etc. *)
    val name_of_constraint : t -> string

    (** Same as {!name_of_constraint} but translates from a magic
        floating-point constant.  *)
    val name_of_float : float -> string

    (** Returns strings like [">= 0"], ["< 0"], etc.  [Unconstrained]
        is mapped to ["unconstrained"].  *)
    val string_of_constraint : t -> string

    (** Same as {!string_of_constraint} but translates from a magic
        floating-point constant.  *)
    val string_of_float : float -> string
  end

(** Specifies a vector that defines inequality constraints for each
    component of the solution vector [u].  See {!Constraint}.

    @kinsol <node5#ss:optin_main> KINSetConstraints *)
val set_constraints : ('a, 'k) session -> ('a, 'k) Nvector.t -> unit

(** Changes the linear solver. Allows consecutive solution attempts with
    different tools or parameters.

    @kinsol <node5#sss:lin_solv_init> Linear solver specification functions *)
val set_linear_solver : ('a, 'k) session -> ('a, 'k) linear_solver -> unit

(** Changes the system function. Allows solutions of several problems of the
    same size but with different functions.

    @kinsol <node5#ss:optin_main> KINSetSysFunc
    @kinsol <node5#ss:sysFn> Problem-defining function *)
val set_sys_func : ('a, 'k) session -> ('a -> 'a -> unit) -> unit

(** {3:info Logging and error handling} *)

(** Opens the named file to receive messages from the default error handler.
    If the file already exists it is either truncated ([true]) or extended
    ([false]).
    The file is closed if the function is called again or when the session is
    garbage collected.

    @kinsol <node5#ss:optin_main> KINSetErrFile *)
val set_error_file : ('a, 'k) session -> string -> bool -> unit

(** Specifies a custom function for handling error messages.
    This function must not fail: any exceptions are trapped and discarded.

    @kinsol <node5#ss:optin_main> KINSetErrHandlerFn
    @kinsol <node5#ss:ehFn> KINErrHandlerFn *)
val set_err_handler_fn : ('a, 'k) session -> (error_details -> unit) -> unit

(** Restores the default error handling function.

    @kinsol <node5#ss:optin_main> KINSetErrHandlerFn *)
val clear_err_handler_fn : ('a, 'k) session -> unit

(** Opens the named file to receive informational (non-error) messages.
    If the file already exists it is either truncated ([true]) or extended
    ([false]).
    The file is closed if {!set_info_file} is called again or when the session
    is garbage collected.
   
    @kinsol <node5#ss:optin_main> KINSetInfoFile *)
val set_info_file : ('a, 'k) session -> string -> bool -> unit

(** Specifies a custom function for handling informational (non-error) messages.
    The [error_code] field of {!error_details} is [0] for such messages.
    This function must not fail: any exceptions are trapped and discarded.

    @kinsol <node5#ss:optin_main> KINSetInfoHandlerFn
    @kinsol <node5#ss:ihFn> KINInfoHandlerFn *)
val set_info_handler_fn : ('a, 'k) session -> (error_details -> unit) -> unit

(** Restores the default information handling function.

    @kinsol <node5#ss:optin_main> KINSetErrHandlerFn *)
val clear_info_handler_fn : ('a, 'k) session -> unit

(** Increasing levels of verbosity for informational messages. *)
type print_level =
  | NoInformation     (** No information displayed. {cconst 0} *)
  | ShowScaledNorms   (** At each nonlinear iteration, display the scaled
                          Euclidean norm of the system function at the
                          current iterate, the scaled norm of the Newton step
                          (if no globalization strategy is used), and the number
                          of function evaluations performed so far.
                          {cconst 1} *)
  | ShowScaledDFNorm  (** Additionally display {% $\lVert F(u) \rVert_{DF}$%}
                          if no globalization strategy is used, and
                          {% $\lVert F(u)\rVert_{DF,\infty}$%}, otherwise.
                          {cconst 2} *)
  | ShowGlobalValues  (** Additionally display the values used by the global
                          strategy and statistical information for the linear
                          solver. {cconst 3} *)

(** Sets the level of verbosity of informational messages.

    @kinsol <node5#ss:optin_main> KINSetPrintLevel *)
val set_print_level : ('a, 'k) session -> print_level -> unit

(** {2:get Querying the solver (optional output functions)} *)

(** Returns the sizes of the real and integer workspaces.

    @kinsol <node5#sss:output_main> KINGetWorkSpace
    @return ([real_size], [integer_size]) *)
val get_work_space : ('a, 'k) session -> int * int

(** Returns the number of evaluations of the system function.

    @kinsol <node5#ss:optout_main> KINGetNumFuncEvals *)
val get_num_func_evals : ('a, 'k) session -> int

(** Returns the number of nonlinear iterations.

    @kinsol <node5#ss:optout_main> KINGetNumNonlinSolvIters *)
val get_num_nonlin_solv_iters : ('a, 'k) session -> int

(** Returns the number of beta-condition failures.

    @kinsol <node5#ss:optout_main> KINGetNumBetaCondFails *)
val get_num_beta_cond_fails : ('a, 'k) session -> int

(** Returns the number of backtrack operations (step length adjustments)
    performed by the line search algorithm.

    @kinsol <node5#ss:optout_main> KINGetNumBacktrackOps *)
val get_num_backtrack_ops : ('a, 'k) session -> int

(** Returns the scaled Euclidiean {i l2} norm of the nonlinear system function
    $F(u)$ evaluated at the current iterate.

    @kinsol <node5#ss:optout_main> KINGetFuncNorm *)
val get_func_norm : ('a, 'k) session -> float

(** Returns the scaled Euclidiean {i l2} norm of the step used during the
    previous iteration.

    @kinsol <node5#ss:optout_main> KINGetStepLength *)
val get_step_length : ('a, 'k) session -> float

(** {2:exceptions Exceptions} *)

(** An input parameter was invalid.

    @kinsol <node5#sss:kinsol> KIN_ILL_INPUT *)
exception IllInput

(** Line search could not find an iterate sufficiently distinct
    from the current one, or an iterate satisfying the sufficient decrease
    condition. The latter could mean that the current iterate is “close” to an
    approximate solution, but that the difference approximation of the
    matrix-vector product is inaccurate, or that [scsteptol]
    ({!set_scaled_step_tol}) is too large.

    @kinsol <node5#sss:kinsol> KIN_LINESEARCH_NONCONV *)
exception LineSearchNonConvergence

(** The maximum number of nonlinear iterations has been reached.
    See {!set_num_max_iters}.

    @kinsol <node5#sss:kinsol> KIN_MAXITER_REACHED *)
exception MaxIterationsReached

(** Five consecutive steps exceed the maximum newton step.
    That is, the five steps satisfy the inequality
    {% $\\|D_u p\\|_{L2} > 0.99 \mathtt{mxnewtstep}$%},
    where $p$ denotes the current step and [mxnewtstep] is a scalar
    upper bound on the scaled step length (see {!set_max_newton_step}).
    It could be that {% $\\| D_F F(u)\\|_{L2}$%} is bounded from above by
    a positive value or that [mxnewtstep] is too small.

    @kinsol <node5#sss:kinsol> KIN_MXNEWT_5X_EXCEEDED *)
exception MaxNewtonStepExceeded

(** The line search algorithm could not satisfy the “beta-condition” for
    [mxnbcf + 1] nonlinear iterations. The failures need not occur in
    consecutive iterations. They may indicate that the algorithm is making
    poor progress.

    @kinsol <node5#sss:kinsol> KIN_LINESEARCH_BCFAIL *)
exception LineSearchBetaConditionFailure

(** The {!prec_solve_fn} callback raised {!Sundials.RecoverableFailure} but
    the preconditioner is already current.

    @kinsol <node5#sss:kinsol> KIN_LINSOLV_NO_RECOVERY *)
exception LinearSolverNoRecovery

(** Linear solver initialization failed.

    @kinsol <node5#sss:kinsol> KIN_LINIT_FAIL *)
exception LinearSolverInitFailure

(** The {!prec_setup_fn} callback failed unrecoverably.

    @kinsol <node5#sss:kinsol> KIN_LSETUP_FAIL *)
exception LinearSetupFailure

(** Either {!prec_solve_fn} failed unrecoverably or the linear solver
    encountered an error condition.

    @kinsol <node5#sss:kinsol> KIN_LSOLVE_FAIL *)
exception LinearSolverFailure

(** The {!sysfn} callback failed unrecoverably.

    @kinsol <node5#sss:kinsol> KIN_SYSFUNC_FAIL *)
exception SystemFunctionFailure

(** The {!sysfn} callback raised {!Sundials.RecoverableFailure} when
    first called.

    @kinsol <node5#sss:kinsol> KIN_FIRST_SYSFUNC_FAIL *)
exception FirstSystemFunctionFailure

(** The {!sysfn} callback raised {!Sundials.RecoverableFailure} repeatedly.
    No recovery is possible.

    @kinsol <node5#sss:kinsol> KIN_REPTD_SYSFUNC_ERR *)
exception RepeatedSystemFunctionFailure

