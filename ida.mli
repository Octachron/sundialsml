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
(*               User Documentation for IDA v2.7.0                     *)
(*         Alan C. Hindmarsh, Radu Serban, and Aaron Collier           *)
(*              Center for Applied Scientific Computing                *)
(*              Lawrence Livermore National Laboratory                 *)
(*                                                                     *)
(***********************************************************************)

(** IDA solves DAE initial value problems using a variable-step solver with
    zero-crossing detection (root finding).

 @version VERSION()
 @author Timothy Bourke (Inria)
 @author Jun Inoue (Inria)
 @author Marc Pouzet (LIENS)
 *)

(** {2:exceptions Exceptions} *)

(** @ida <node5#sss:ida> IDA_ILL_INPUT *)
exception IllInput

(** @ida <node5#sss:ida> IDA_TOO_CLOSE *)
exception TooClose

(** @ida <node5#sss:ida> IDA_TOO_MUCH_WORK *)
exception TooMuchWork

(** @ida <node5#sss:ida> IDA_TOO_MUCH_ACC *)
exception TooMuchAccuracy

(** @ida <node5#sss:ida> IDA_ERR_FAIL *)
exception ErrFailure                

(** @ida <node5#sss:ida> IDA_CONV_FAIL *)
exception ConvergenceFailure        

(** @ida <node5#sss:ida> IDA_LINIT_FAIL *)
exception LinearInitFailure         

(** @ida <node5#sss:ida> IDA_LSETUP_FAIL *)
exception LinearSetupFailure        

(** @ida <node5#sss:ida> IDA_LSOLVE_FAIL *)
exception LinearSolveFailure        

(** @ida <node5#sss:ida> IDA_RES_FAIL *)
exception ResFuncFailure

(** @ida <node5#sss:ida> IDA_FIRST_RES_FAIL *)
exception FirstResFuncFailure       

(** @ida <node5#sss:ida> IDA_REP_RES_ERR *)
exception RepeatedResFuncErr        

(** @ida <node5#sss:ida> IDA_RTFUNC_FAIL *)
exception RootFuncFailure           

exception BadK      (** k is not in the range 0, 1, ..., q_u (IDA_BAD_K)
                        @ida <node5#ss:optional_dky> IDAGetDky *)

exception BadT      (** t is not in the interval
                        \[t_n - h_u, t_n\] (IDA_BAD_T)
                        @ida <node5#ss:optional_dky> IDAGetDky *)
exception BadDky    (** invalid dky argument (IDA_BAD_DKY)
                        @ida <node5#ss:optional_dky> IDAGetDky *)

(** This type represents a session with the IDA solver.

    A skeleton of the main program:
    + {b Set vector of initial values}
    {[let y = Nvector_array.wrap [| 0.0; 0.0; 0.0 |] ]}
    The length of this vector determines the problem size.
    + {b Create and initialize a solver session}
    {[let s = Ida.init (Ida.Spgmr spils_no_precond) tols f ~roots:(2, g) (3, y)]}
    This will initialize a specific linear solver and the root-finding
    mechanism, if necessary.
    + {b Specify integration tolerances (optional)}, e.g.
    {[set_tolerances s SStolerances (reltol, abstol)]}
    + {b Set optional inputs}, e.g.
    {[set_stop_time s 10.0; ...]}
    Call any of the [set_*] functions to change solver parameters from their
    defaults.
    + {b Advance solution in time}, e.g.
    {[let (t', result) = Ida.solve_normal s !t y in
...
t := t' + 0.1]}
    Repeatedly call either [solve_normal] or [solve_one_step] to advance the
    simulation.
    + {b Get optional outputs}
    {[let stats = get_integrator_stats s in ...]}
    Call any of the [get_*] functions to examine solver statistics.

    @ida <node5#ss:skeleton_sim> Skeleton of main program
 *)
type ('a, 'k) session = ('a, 'k) Ida_impl.session

type real_array = Sundials.RealArray.t
type serial_session = (real_array, Nvector_serial.kind) session

(** The type of vectors passed to the solver. *)
type ('data, 'kind) nvector = ('data, 'kind) Sundials.nvector

(** {2 Linear Solvers} *)

(** Specify a linear solver.

    @ida <node5#sss:lin_solv_init> Linear Solver Specification Functions *)
type ('data, 'kind) linear_solver = ('data, 'kind) Ida_impl.linear_solver
type serial_linear_solver = (real_array, Nvector_serial.kind) linear_solver


type 'a single_tmp = 'a
type 'a double_tmp = 'a * 'a
type 'a triple_tmp = 'a * 'a * 'a

(**
  Arguments common to all Jacobian callback functions.    
 
  @ida <node5#ss:djacFn> Dense Jacobian function
  @ida <node5#ss:bjacFn> Banded Jacobian function
  @ida <node5#ss:jtimesFn> Jacobian-times-vector function
  @ida <node5#ss:psolveFn> Linear preconditioning function
  @ida <node5#ss:precondFn> Jacobian preconditioning function
  @ida <node3#ss:ivp_sol> IVP solution
 *)
type ('t, 'a) jacobian_arg =
  {
    jac_t    : float;        (** The independent variable. *)
    jac_y    : 'a;           (** The dependent variable vector. *)
    jac_y'   : 'a;           (** The derivative vector (i.e. dy/dt). *)
    jac_res  : 'a;           (** The current value of the residual vector. *)
    jac_coef : float;        (** The coefficient [a] in the system Jacobian
                                   [J = dF/dy + a*dF/d(y')],
                                 where [F] is the residual function and
                                 d denotes partial differentiation.
                                 See the IVP solution section linked below.  *)
    jac_tmp  : 't            (** Workspace data, either {!single_tmp},
                                 {!double_tmp}, or {!triple_tmp}. *)
  }

(** {3 Direct Linear Solvers (DLS)} *)

(** The range of nonzero entries in a band matrix.  *)
type bandrange = { mupper : int; (** The upper half-bandwidth.  *)
                   mlower : int; (** The lower half-bandwidth.  *) }

(** Get optional outputs for the Direct Linear Solvers that operate on dense
    and banded matrices.

    @ida <node5#sss:optin_dls> Direct linear solvers optional input functions
    @ida <node5#sss:optout_dls> Direct linear solvers optional output functions
  *)
module Dls :
  sig
    (** Direct Linear Solvers operating on dense and banded matrices.
        
        @ida <node5#sss:optin_dls> Direct linear solvers optional input functions
        @ida <node5#sss:optout_dls> Direct linear solvers optional output functions
        @ida <node5#ss:djacFn> Dense Jacobian function
      *)

    (** The type of a user-supplied callback function that computes an
        approximation to the Jacobian matrix for the {!dense} and
        {!lapack_dense} {!linear_solver}s.

        The function is called like [dense_jac_fn arg jac] where:
        - [arg] is the standard {!jacobian_arg} with three work vectors.
        - [jac] is the matrix in which to store the computed Jacobian.

        The function should load the ({i i,j}) entry of the Jacobian
        with {i dFi/dyj + c*dFi/dy'j}, i.e. the partial derivative of
        the {i i}-th equation with respect to the {i j}-th variable,
        evaluated at the values of ({i t,y,y'}) that can be obtained
        from [arg].  Note that in IDA, we have two terms due to the
        chain rule: one differentiated by the {i j}-th component of
        the non-derivative vector and the other by the {i j}-th
        component of the derivative vector.  The coefficient {i c} is
        the [jac_coef] field of the record [arg] (see
        {!jacobian_arg}).

        Only nonzero elements need to be loaded into [jac] because
        [jac] is set to the zero matrix before the call to the
        Jacobian function.

        If the user-supplied Jacobian function uses difference
        quotient approximations, then it may need to access quantities
        not in the argument list.  These include the current step
        size, the error weights, etc. To obtain these values, use the
        [get_*] functions defined in this module. The unit roundoff
        can be accessed as {!Sundials.unit_roundoff}.

        {b NB:} The elements of [arg] and [jac] must no longer be
        accessed after this function has returned.  If their values
        are needed outside of the function call, then they must be
        copied to separate physical structures.

        @ida <node5#sss:optin_dls> IDADlsSetDenseJacFn
        @ida <node5#ss:djacFn> Dense Jacobian function
        @ida <node3#ss:ivp_soln> IVP solution
    *)
    type dense_jac_fn = (real_array triple_tmp, real_array) jacobian_arg
                         -> Dls.DenseMatrix.t -> unit

    (** Direct linear solver with dense matrix.  The optional argument
        specifies a callback function that computes an approximation
        to the Jacobian matrix J(t, y).  If the argument is [None],
        then IDA uses a default implementation based on difference
        quotients.  [Dense None] can be passed into {!reinit} to
        disable any user-supplied Jacobian function that was
        previously active.

      @ida <node5#sss:lin_solve_init> IDADense
      @ida <node5#sss:optin_dls> IDADlsSetDenseJacFn
      @ida <node5#ss:djacFn> Dense Jacobian function
      @ida <node3#ss:ivp_soln> IVP solution  *)
    val dense : dense_jac_fn option -> serial_linear_solver

    (** Direct linear solver with dense matrix, using LAPACK.  The
        argument is the same as [Dense].

        @ida <node5#sss:lin_solve_init> IDALapackDense
        @ida <node5#sss:optin_dls> IDADlsSetDenseJacFn
        @ida <node5#ss:djacFn> Dense Jacobian function
        @ida <node3#ss:ivp_soln> IVP solution  *)
    val lapack_dense : dense_jac_fn option -> serial_linear_solver

    (** The type of a user-supplied callback function that computes an
        approximation to the Jacobian matrix for the {!band} and
        {!lapack_band} {!linear_solver}s.

        A user-supplied Jacobian function takes four arguments, in this
        order:
        - [bandrange] the bandwidth of the Jacobian (see {!bandrange}).
        - [arg] a {!jacobian_arg} with three work vectors.
        - [jac] the matrix to fill in with the values of the Jacobian.

        The function should load the ({i i,j}) entry of the Jacobian
        with {i dFi/dyj + c*dFi/dy'j}, i.e. the partial derivative of
        the {i i}-th equation with respect to the {i j}-th variable,
        evaluated at the values of ({i t,y,y'}) that can be obtained
        from [arg].  Note that in IDA, we have two terms due to the
        chain rule: one differentiated by the {i j}-th component of
        the non-derivative vector and the other by the {i j}-th
        component of the derivative vector.  The coefficient {i c} is
        the [jac_coef] field of the record [arg] (see
        {!jacobian_arg}).

        Only nonzero elements need to be loaded into [jac] because
        [jac] is set to the zero matrix before the call to the
        Jacobian function.

        If the user-supplied Jacobian function uses difference
        quotient approximations, then it may need to access quantities
        not in the argument list.  These include the current step
        size, the error weights, etc. To obtain these values, use the
        [get_*] functions defined in this module. The unit roundoff
        can be accessed as {!Sundials.unit_roundoff}.

        {b NB:} The elements of [arg] and [jac] must no longer be
        accessed after this function has returned.  If their values
        are needed outside of the function call, then they must be
        copied to separate physical structures.

        @ida <node5#sss:optin_dls> IDADlsSetBandJacFn
        @ida <node5#ss:bjacFn> Banded Jacobian function
        @ida <node3#ss:ivp_soln> IVP solution
    *)
    type band_jac_fn = bandrange
                        -> (real_array triple_tmp, real_array) jacobian_arg
                        -> Dls.BandMatrix.t -> unit

    (** Direct linear solver with banded matrix.  The arguments
        specify the width of the band ({!bandrange}) and an optional
        Jacobian function ({!band_jac_fn}).  If the Jacobian function
        is [None], IDA uses an internal implementation based on
        difference quotients.

        @ida <node5#sss:lin_solve_init> IDABand
        @ida <node5#sss:optin_dls> IDADlsSetBandJacFn
        @ida <node5#ss:bjacFn> Banded Jacobian function
        @ida <node3#ss:ivp_soln> IVP solution *)
    val band : bandrange -> band_jac_fn option -> serial_linear_solver

    (** Direct linear solver with banded matrix using LAPACK.  The
        arguments are the same as {!band}.

        @ida <node5#sss:lin_solve_init> IDALapackBand
        @ida <node5#sss:optin_dls> IDADlsSetBandJacFn
        @ida <node5#ss:bjacFn> Banded Jacobian function
        @ida <node3#ss:ivp_soln> IVP solution *)
    val lapack_band : bandrange -> band_jac_fn option -> serial_linear_solver


    (** {4 Low-level solver manipulation} *)

    (** Change the dense Jacobian function.  It may be unsafe to use
        this function without a {!reinit}.  Users are encouraged to
        use the [linsolv] parameter of {!reinit} instead, unless they
        are desperate for performance.

        @ida <node5#sss:optin_dls> IDADlsSetDenseJacFn
        @ida <node5#ss:djacFn> Dense Jacobian function
        @ida <node3#ss:ivp_soln> IVP solution
      *)
    val set_dense_jac_fn : serial_session -> dense_jac_fn -> unit

    (** Remove the user-supplied dense Jacobian function, if any, and
        fall back to IDA's internal implementation.  This is the same
        as calling IDADlsSetDenseJacFn with an argument of [NULL].

        It may be unsafe to use this function without a {!reinit}.
        Users are encouraged to use the [linsolv] parameter of
        {!reinit} instead, unless they are desperate for performance.

        @ida <node5#sss:optin_dls> IDADlsSetDenseJacFn
        @ida <node5#ss:djacFn> Dense Jacobian function
     *)
    val clear_dense_jac_fn : serial_session -> unit

    (** Change the banded Jacobian function.  It may be unsafe to use
        this function without a {!reinit}.  Users are encouraged to
        use the [linsolv] parameter of {!reinit} instead, unless they
        are desperate for performance.

        @ida <node5#sss:optin_dls> IDADlsSetBandJacFn
        @ida <node5#ss:bjacFn> Banded Jacobian function
      *)
    val set_band_jac_fn : serial_session -> band_jac_fn -> unit

    (** Remove the user-supplied banded Jacobian function, if any, and
        fall back to IDA's internal implementation.  It may be unsafe
        to use this function without a {!reinit}.  Users are
        encouraged to use the [linsolv] parameter of {!reinit}
        instead, unless they are desperate for performance.

        @ida <node5#sss:optin_dls> IDADlsSetBandJacFn
        @ida <node5#ss:bjacFn> Banded Jacobian function
      *)
    val clear_band_jac_fn : serial_session -> unit


    (** {4 Optional output functions} *)

    (** Returns the sizes of the real and integer workspaces used by
        the Dense or Band direct linear solver.

        @ida <node5#sss:optout_dls> IDADlsGetWorkSpace
        @return ([real_size], [integer_size])
     *)
    val get_work_space : serial_session -> int * int


    (** Returns the number of calls made to the Dense and Band direct
        linear solvers Jacobian approximation function.

      @ida <node5#sss:optout_dls> IDADlsGetNumJacEvals
    *)
    val get_num_jac_evals : serial_session -> int

    (** Returns the number of calls made to the user-supplied residual
        function due to the finite difference (Dense or Band) Jacobian
        approximation.

        @ida <node5#sss:optout_dls> IDADlsGetNumResEvals
    *)
    val get_num_res_evals : serial_session -> int
  end

(** {3 Scaled Preconditioned Iterative Linear Solvers (SPILS)} *)

module Spils :
  sig
    (** Scaled Preconditioned Iterative Linear Solvers (SPILS)

        @ida <node5#sss:optin_spils> Iterative linear solvers optional input
                                     functions.
        @ida <node5#sss:optout_spils> Iterative linear solvers optional output
                                      functions.
        @ida <node5#ss:psolveFn> Linear preconditioning function
        @ida <node5#ss:precondFn> Jacobian preconditioning function
    *)

    type gramschmidt_type = Spils.gramschmidt_type =
      | ModifiedGS
      | ClassicalGS

    (** Initialization parameters and callbacks for Krylov iterative
        {!linear_solver}s.  If you don't want any preconditioning, you
        should use {!spils_no_precond}.  *)
    type 'a callbacks = {

      prec_solve_fn : (('a single_tmp, 'a) jacobian_arg -> 'a -> 'a -> float
                       -> unit) option;
      (** Called like [prec_solve_fn arg r z delta] to solve the
          linear system {i P}[z] = [r], where {i P} is the (left)
          preconditioner matrix.
          - [arg] supplies the basic problem data as a {!jacobian_arg}.
          - [r] is the right-hand side vector.
          - [z] is the vector in which the result must be stored.
          - [delta] is an input tolerance.

          If set to [None] then no preconditioning is performed, and
          [prec_setup_fn] and [jac_times_vec_fn] are ignored.

          {i P} should approximate, at least crudely, the system
          Jacobian matrix {i J = dF/dy + c * dF/dy'} where {i
          F} is the residual function and {i c} is [arg.jac_coef].

          [delta] is an input tolerance to be used if an iterative method is
          employed in the solution.  In that case, the residual vector res = [r]
          - {i P} [z] of the system should be made less than [delta] in weighted
          l2 norm, i.e. [sqrt (sum over i ((res.{i} * ewt.{i})^2)) < delta],
          where the vector ewt can be obtained through {!get_err_weights}.

          This function can raise {!Sundials.RecoverableFailure} to instruct the
          integrator to retry with a different step size.  Raising any other
          kind of exception aborts the integrator.

          {b NB:} [r], [z], and the elements of [arg] must no longer be accessed
                  after [prec_solve_fn] has returned, i.e. if their values are
                  needed outside of the function call, then they must be copied
                  to separate physical structures.

          @ida <node5#sss:optin_spils> IDASpilsSetPreconditioner
          @ida <node5#ss:psolveFn> Linear preconditioning function
          @ida <node5#ss:precondFn> Jacobian preconditioning function
      *)

      prec_setup_fn : (('a triple_tmp, 'a) jacobian_arg -> unit) option;
      (** A function that preprocesses and/or evaluates any
          Jacobian-related data needed by [prec_solve_fn] above.  When
          [prec_solve_fn] doesn't need any such data, this field can
          be [None].

          The sole argument to this function specifies the basic
          problem data as a {!jacobian_arg}.

          Note that unlike in CVODE, whatever data this function
          computes has to be recomputed every time it is called.

          This function can raise {!Sundials.RecoverableFailure} to
          instruct the integrator to retry with a different step size.
          Raising any other kind of exception aborts the integrator.

          {b NB:} The elements of [jac] must no longer be accessed
                  after [psetup] has returned a result, i.e. if their
                  values are needed outside of the function call, then
                  they must be copied to a separate physical
                  structure.

          The operations performed by this function might include
          forming a crude approximate Jacobian, and performing an LU
          factorization on the resulting approximation.

          Each call to the preconditioner setup function is preceded
          by a call to the user-supplied residual function (see
          {!init}) with the same (tt, yy, yp) arguments. Thus the
          preconditioner setup function can use any auxiliary data
          that is computed and saved during the evaluation of the DAE
          residual.

          This function is not called in advance of every call to the
          preconditioner solve function, but rather is called only as
          often as needed to achieve convergence in the Newton
          iteration.

          If this function uses difference quotient approximations, it
          may need to access quantities not in the argument.  These
          include the current step size, the error weights, etc.  To
          obtain these, use the [get_*] functions defined in this
          module.

          @ida <node5#sss:optin_spils> IDASpilsSetPreconditioner
          @ida <node5#ss:psolveFn> Linear preconditioning function
          @ida <node5#ss:precondFn> Jacobian preconditioning function
      *)

      jac_times_vec_fn : (('a double_tmp, 'a) jacobian_arg -> 'a -> 'a -> unit)
          option;
      (**

         Specifies a Jacobian-times-vector function.  When this field is [None],
         IDA uses a default implementation based on difference quotients.

         [jac_times_vec_fn arg v jv] should compute the matrix-vector product {i
         J}[v], where {i J} is the system Jacobian.
         - [arg] provides the data necessary to compute the Jacobian.
         - [v] is the vector by which the Jacobian must be multiplied.
         - [jv] is the vector in which the result must be stored.

         The Jacobian {i J} (which is not explicitly constructed) has ({i i,j})
         entry {i dFi/dyj + c*dFi/dy'j} where {i F} is the residual function,
         i.e. the partial derivative of the [i]-th equation with respect to the
         [j]-th component of the non-derivative vector.  [c] is the [jac_coef]
         field of [arg] (see {!jacobian_arg}).  See the [Dense] {!linear_solver}
         for a more detailed explanation.

         {b NB:} The elements of [jac], [v], and [Jv] must no longer be accessed
                 after [psolve] has returned a result, i.e. if their values are
                 needed outside of the function call, then they must be copied to
                 separate physical structures.

         Raising any kind of exception (including {!Sundials.RecoverableFailure})
         from this function results in the integrator being aborted.

         @ida <node5#sss:optin_spils> IDASpilsSetJacTimesVecFn
         @ida <node5#ss:jtimesFn> Jacobian-times-vector function
      *)
    }

    val no_precond : 'a callbacks

    (** Krylov iterative linear solver with the scaled preconditioned GMRES
        method.  See {!callbacks} for what the argument should contain.

        @ida <node5#sss:lin_solve_init> IDASpgmr
        @ida <node5#sss:optin_spils> IDASpilsSetPreconditioner
        @ida <node5#ss:psolveFn> Linear preconditioning function
        @ida <node5#ss:precondFn> Jacobian preconditioning function
    *)
    val spgmr : int option -> 'data callbacks -> ('data,'kind) linear_solver

    (** Krylov iterative linear solver with the scaled preconditioned
        Bi-CGStab method.  See {!callbacks} for what the argument
        should contain.

        @ida <node5#sss:lin_solve_init> IDASpbcg
        @ida <node5#sss:optin_spils> IDASpilsSetPreconditioner
        @ida <node5#ss:psolveFn> Linear preconditioning function
        @ida <node5#ss:precondFn> Jacobian preconditioning function
    *)
    val spbcg : int option -> 'data callbacks -> ('data,'kind) linear_solver

    (** Krylov iterative linear solver with the scaled preconditioned
        TFQMR method.  See {!callbacks} for what the argument should
        contain.

        @ida <node5#sss:lin_solve_init> IDASptfqmr
        @ida <node5#sss:optin_spils> IDASpilsSetPreconditioner
        @ida <node5#ss:psolveFn> Linear preconditioning function
        @ida <node5#ss:precondFn> Jacobian preconditioning function
    *)
    val sptfqmr : int option -> 'data callbacks -> ('data,'kind) linear_solver


    (** {4 Low-level solver manipulation} *)

    (** Set preconditioning functions (see {!callbacks}).  It may be
        unsafe to use this function without a {!reinit}.  Users are
        encouraged to use the [linsolv] parameter of {!reinit}
        instead, unless they are desperate for performance.

        @ida <node5#sss:optin_spils> IDASpilsSetPreconditioner
        @ida <node5#ss:psolveFn> Linear preconditioning function
      *)
     val set_preconditioner :
       ('a,'k) session
       -> (('a triple_tmp, 'a) jacobian_arg -> unit) option
       -> (('a single_tmp, 'a) jacobian_arg -> 'a -> 'a -> float -> unit)
       -> unit

    (** Set the Jacobian-times-vector function (see {!callbacks}).  It
        may be unsafe to use this function without a {!reinit}.  Users
        are encouraged to use the [linsolv] parameter of {!reinit}
        instead, unless they are desperate for performance.

        @ida <node5#sss:optin_spils> IDASpilsSetJacTimesVecFn
        @ida <node5#ss:jtimesFn> Jacobian-times-vector function
      *)
    val set_jac_times_vec_fn :
      ('a,'k) session
      -> (('a double_tmp, 'a) jacobian_arg
          -> 'a (* v *)
          -> 'a (* Jv *)
          -> unit)
      -> unit

    (** This function disables the user-supplied Jacobian-vector function, and
        switches back to the default internal difference quotient approximation
        (see {!spils_params}).  It is equivalent to calling
        IDASpilsSetJacTimesVecFn with an argument of [NULL].

        It may be unsafe to use this function without a {!reinit}.  Users are
        encouraged to use the [iter_type] parameter of {!reinit} instead, unless
        they are desperate for performance.

        @ida <node5#sss:optin_spils> IDASpilsSetJacTimesVecFn
        @ida <node5#ss:jtimesFn> Jacobian-times-vector function
    *)
    val clear_jac_times_vec_fn : ('a, 'k) session -> unit


    (** {4 Optional output functions} *)

    (** Sets the Gram-Schmidt orthogonalization to be used with the [Spgmr]
        {!linear_solver}.

      @ida <node5#sss:optin_spils> IDASpilsSetGSType
    *)
    val set_gs_type : ('a, 'k) session -> Spils.gramschmidt_type -> unit

    (**
      [set_eps_lin eplifac] sets the factor by which the Krylov linear solver's
      convergence test constant is reduced from the Newton iteration test
      constant. [eplifac]  must be >= 0. Passing a value of 0 specifies the
      default (which is 0.05).

      @ida <node5#sss:optin_spils> IDASpilsSetEpsLin
    *)
    val set_eps_lin : ('a, 'k) session -> float -> unit

    (**
      [set_maxl maxl] resets the maximum Krylov subspace dimension for the
      Bi-CGStab or TFQMR methods. [maxl] is the maximum dimension of the Krylov
      subspace, a value of [maxl] <= 0 specifies the default (which is 5.0).

      @ida <node5#sss:optin_spils> IDASpilsSetMaxl
    *)
    val set_maxl : ('a, 'k) session -> int -> unit

    (** {4 Optional input functions} *)

    (**
      Returns the sizes of the real and integer workspaces used by the SPGMR
      linear solver.

      @ida <node5#sss:optout_spils> IDASpilsGetWorkSpace
      @return ([real_size], [integer_size])
    *)
    val get_work_space       : ('a, 'k) session -> int * int

    (**
      Returns the cumulative number of linear iterations.

      @ida <node5#sss:optout_spils> IDASpilsGetNumLinIters
    *)
    val get_num_lin_iters    : ('a, 'k) session -> int

    (**
      Returns the cumulative number of linear convergence failures.

      @ida <node5#sss:optout_spils> IDASpilsGetNumConvFails
    *)
    val get_num_conv_fails   : ('a, 'k) session -> int

    (**
      Returns the number of preconditioner evaluations, i.e., the number of
      calls made to [prec_setup_fn] (see {!spils_params}).

      @ida <node5#sss:optout_spils> IDASpilsGetNumPrecEvals
    *)
    val get_num_prec_evals   : ('a, 'k) session -> int

    (**
      Returns the cumulative number of calls made to the preconditioner solve
      function, [prec_solve_fn] (see {!spils_params}).

      @ida <node5#sss:optout_spils> IDASpilsGetNumPrecSolves
    *)
    val get_num_prec_solves  : ('a, 'k) session -> int

    (**
      Returns the cumulative number of calls made to [jac_times_vec_fn]
      (see {!spils_params}).

      @ida <node5#sss:optout_spils> IDASpilsGetNumJtimesEvals
    *)
    val get_num_jtimes_evals : ('a, 'k) session -> int

    (**
      Returns the number of calls to the user right-hand side function for
      finite difference Jacobian-vector product approximation. This counter is
      only updated if the default difference quotient function is used.

      @ida <node5#sss:optout_spils> IDASpilsGetNumResEvals
    *)
    val get_num_res_evals    : ('a, 'k) session -> int
  end
(*
module Alternate :
  sig
    (** Alternate Linear Solvers

        @cvode <node8#s:new_linsolv> Providing Alternate Linear Solver Modules *)

    (** A flag that indicates any problems that occured during the solution of
        the nonlinear equation on the current time step for which the linear
        solver is being used. This flag can be used to help decide whether the
        Jacobian data kept by a linear solver needs to be updated or not. *)
    type conv_fail =
      | NoFailures
          (** Passed on the first call for a step, or if the lcoal error test
              failed on the previous attempt at this setup but the Newton
              iteration converged. *)
      | FailBadJ
          (**  Passed if
               - the previous Newton corrector iteration did not converge and
                 the linear solver's setup routine indicated that its
                 Jacobian-related data is not current, or,

               - during the previous Newton corrector iteration, the linear
                 solver's {!solve} routine failed in a recoverable manner and
                 the linear solver's setup routine indicated that its
                 Jacobian-related data is not current. *)
      | FailOther
          (** Passed if the previous Newton iteration failed to converge even
              though the linear solver was using current Jacobian-related
              data. *)

    type 'data callbacks =
      {
        linit   : (unit -> bool) option;
          (** Complete initializations for a specific linear solver, such as
              counters and statistics. Returns [true] if successful.

              @cvode <node8#SECTION00810000000000000000> linit *)

        lsetup : (conv_fail -> 'data -> 'data -> 'data triple_tmp -> bool)
                 option;
          (** [jcur = lsetup convfail ypred fpred tmp] prepares the linear
              solver for subsequent calls to {!lsolve}. Its arguments are:
              - [convfail], indicating any problem that occurred during the
                 solution of the nonlinear equation on the current time step,
              - [ypred], the predicted [y] vector for the current internal
                step,
              - [fpred], the value of the right-hand side at [ypred], and,
              - [tmp], temporary variables for use by the routine.
           
              This function must return [true] if the Jacobian-related data is
              current after the call, or [false] otherwise. It may raise a
              {!Sundials.RecoverableFailure} exception to indicate that a
              recoverable error has occurred. Any other exception is treated as
              an unrecoverable error.
           
              @cvode <node8#SECTION00820000000000000000> lsetup *)
           
        lsolve : 'data -> 'data -> 'data -> 'data -> unit;
          (** [lsolve b weight ycur fcur] must solve the linear equation given:
              - [b], is the vector into which the solution is to be calculated,
              - [weight] contains the error weights,
              - [ycur] contains the solvers current approximation to [y], and,
              - [fcur] is a vector that contains [f(tn, ycur)].
              
              This function may raise a {!Sundials.RecoverableFailure} exception
              to indicate that a recoverable error has occurred. Any other
              exception is treated as an unrecoverable error.
          
              @cvode <node8#SECTION00830000000000000000> lsolve *)

        lfree  : (unit -> unit) option;
          (** This function is called once a problem has been completed and the
              linear solver is no longer needed.

              @cvode <node8#SECTION00840000000000000000> lfree *)
      }

    (** Create a linear solver from a function returning a set of callback
        functions *)
    val make_solver :
          (('data, 'kind) session -> ('data, 'kind) nvector -> 'data callbacks)
          -> ('data, 'kind) linear_solver
  end
*)

(** {2 Tolerances} *)

type ('data, 'kind) tolerance =
  | SStolerances of float * float
    (** [(rel, abs)] : scalar relative and absolute tolerances. *)
  | SVtolerances of float * ('data, 'kind) nvector
    (** [(rel, abs)] : scalar relative and vector absolute tolerances. *)
  | WFtolerances of ('data -> 'data -> unit)
    (** Specifies a function [efun y ewt] that sets the multiplicative
        error weights Wi for use in the weighted RMS norm. The function is
        passed the dependent variable vector [y] and is expected to set the
        values inside the error-weight vector [ewt].

        The error weight vector must have all components positive.  It
        is the user's responsibility to perform this test in [efun]
        and throw a {!Sundials.NonPositiveEwt} exception.

        If [efun] throws any other kind of exception, it will be
        recorded in the session and propagated on the first chance to
        do so.  But note this chance may or may not come promptly, as
        sundials doesn't allow [efun] to immediately abort the solver.
        It's best to avoid raising any exceptions (besides
        [NonPositiveEwt]) in [efun].  *)

(** A default relative tolerance of 1.0e-4 and absolute tolerance of 1.0e-8. *)
val default_tolerances : ('data, 'kind) tolerance

(** {2 Initialization} *)

(** [init linsolv tol f ~roots:(nroots, g) ~t0:t0 y0 y'0] initializes
    the IDA solver to solve the DAE f t y y' = 0 and returns a
    {!session}.

    - [linsolv] is the linear solver to attach to this session,
    - [tol]     specifies the integration tolerances,
    - [f]       is the residual function (see below),
    - [nroots]  specifies the number of root functions (zero-crossings),
    - [g]       calculates the values of the root functions,
    - [t0]      is the initial value of the independent variable t, which
                defaults to 0,
    - [y0]      is a vector of initial values for the dependent-variable vector
                [y].  This vector's size determines the number of equations
                in the session, see {!Sundials.RealArray.t}, and,
    - [y'0]     is a vector of initial values for [y'], i.e. the derivative
                of [y] with respect to t.  This vector's size must match the
                size of [y0].

    This function calls IDACreate, IDAInit, IDARootInit, an
    appropriate linear solver function, and one of IDASStolerances,
    IDASVtolerances, or IDAWFtolerances. It does everything necessary
    to initialize an IDA session; the {!solve_normal} or
    {!solve_one_step} functions can be called directly afterward.

    The residual function [f] is called by the solver like [f t y y' r] to
    compute the problem residual, where:
    - [t] is the current value of the independent variable,
          i.e., the simulation time.
    - [y] is a vector of dependent-variable values, i.e. y(t).
    - [y'] is the derivative of [y] with respect to [t], i.e. dy/dt.
    - [r] is the output vector to fill in with the value of the residual
          function for the given values of t, y, and y'.
    The residual function should return normally if successful, raise
    {!Sundials.RecoverableFailure} if a recoverable error occurred (e.g. [y] has
    an illegal value), or raise some other exception if a nonrecoverable error
    occurred.  If a recoverable error occurred, the integrator will attempt to
    correct and retry.  If a nonrecoverable error occurred, the integrator will
    halt and propagate the exception to the caller.

    {b NB:} [y], [y'], and [r] must no longer be accessed after [f] has
            returned a result, i.e. if their values are needed outside of
            the function call, then they must be copied to separate physical
            structures.

    The roots function [g], if supplied, is called by the solver to calculate
    the values of root functions (zero-crossing expressions) which are used to
    detect significant events.  It is passed four arguments [t], [y], [y'], and
    [gout]:
    - [t], [y], [y'] are as for [f].
    - [gout] is a vector for storing the values of g(t, y, y').
    If the labeled argument ~roots is omitted, then no root finding is
    performed.  If the root function raises an exception, the integrator will
    halt immediately and propagate the exception to the caller.

    {b NB:} [y] and [gout] must no longer be accessed after [g] has returned
            a result, i.e. if their values are needed outside of the function
            call, then they must be copied to separate physical structures.

    @ida <node5#sss:idainit>       IDACreate/IDAInit
    @ida <node5#ss:resFn>          DAE residual function
    @ida <node5#ss:idarootinit>    IDARootInit
    @ida <node5#ss:rootFn>         Rootfinding function
    @ida <node5#sss:lin_solv_init> Linear solvers
    @ida <node5#sss:idatolerances> IDASStolerances
    @ida <node5#sss:idatolerances> IDASVtolerances
    @ida <node5#sss:idatolerances> IDAWFtolerances
    @ida <node5#ss:ewtsetFn> Error weight function
 *)
val init :
    ('a, 'kind) linear_solver
    -> ('a, 'kind) tolerance
    -> (float -> 'a -> 'a -> 'a -> unit)
    -> ?roots:(int * (float -> 'a -> 'a -> Sundials.Roots.val_array -> unit))
    -> ?t0:float
    -> ('a, 'kind) nvector
    -> ('a, 'kind) nvector
    -> ('a, 'kind) session

(** This is a convenience value for signalling that there are no
    roots (zero-crossings) to monitor. *)
val no_roots : (int * (float -> 'a -> 'a -> Sundials.Roots.val_array -> unit))

(** Return the number of root functions. *)
val nroots : ('a, 'k) session -> int

(** {3 Initial Value Calculation} *)

(** Symbolic names for variable type classifications needed to
    calculate initial values (see {!calc_ic_ya_yd'}) or to suppress
    local error tests on some variables (see {!suppress_alg}).

    Those functions require you to pass in an nvector populated with
    magic constants specifying each variable as algebraic or
    differential.  This module gives symbolic names to those
    constants, for your convenience.

    Note: variable type classification is called "id" in the C
    interface, e.g. [IDASetId].

    @ida <node5#sss:idasetid> IDASetId
    @ida <node5#sss:optin_main> IDASetSuppressAlg
 *)
module VarType :
  sig
    (** A symbolic name for the magic floating-point constant [0.0]. *)
    val algebraic : float
    (** A symbolic name for the magic floating-point constant [1.0]. *)
    val differential : float

    (** An ADT representation of the magic constants specifying
        variable types, useful for pattern-matching.  *)
    type t =
    | Algebraic    (** Algebraic variable; residual function must not depend
                       on this component's derivative.  Corresponds to
                       numerical value 0.0.  *)
    | Differential (** Differential variable; residual function can depend on
                       this component's derivative.  Corresponds to numerical
                       value 1.0.  *)

    (** Encode an [Algebraic] / [Differential] into the corresponding
        magic floating-point constant.  *)
    val to_float : t -> float

    (** Decode a magic float-point constant into an [Algebraic] /
        [Differential] specification.  Raises [Invalid_argument] if
        the given floating point value is not a legal variable type
        specification.  *)
    val of_float : float -> t

    (** Maps [algebraic -> "Algebraic"] and [differential ->
        "Differential"].  Raises [Invalid_argument] if the given
        floating point value is not a legal variable type
        specification.  *)
    val string_of_float : float -> string

    (** Returns ["Algebraic"] or ["Differential"].  *)
    val string_of_var_type : t -> string
  end

(** Specify which variables are algebraic and which variables are
    differential, needed for {!set_suppress_alg}.  This function must
    not be called if you already called {!calc_ic_ya_yd'}.

    The SUNDIALS manual is not clear about whether it's safe to change the
    variable types after you've already set it.

    [set_var_types] corresponds to [IDASetId] in the C interface, and an alias
    {!set_id} is also available in this binding.  We prefer the more
    descriptive name {!set_var_types}, however.

    @ida <node5#sss:optin_main> IDASetId
 *)
val set_var_types : ('a, 'k) session -> ('a,'k) nvector -> unit

(** An unpreferred alias for {!set_var_types}.  SUNDIALS calls variable types
    by the cryptic name "Id", and this OCaml binding preserves this alternative
    naming to help users transition from the C interface.

    @ida <node5#sss:optin_main> IDASetId
  *)
val set_id : ('a, 'k) session -> ('a,'k) nvector -> unit

(** Indicate whether or not to ignore algebraic variables in the local
    error test.  This is set to [false] by default.  Before you can
    set it to [true], you must specify which variables are algebraic
    through {!calc_ic_ya_yd'} or {!set_var_types}, but not both.

    Exactly one of these functions should be called, exactly once,
    before the first call to {!solve_normal}, {!solve_one_step}, or
    {!calc_ic_ya_yd'}.  Forgetting to do so will cause an
    {!Ida.IllInput} exception.

    Note: {!set_var_types} is the preferred alias to {!set_id}, which
    corresponds to [IDASetId] in the C interface.

    In general, suppressing local error tests for algebraic variables
    is {i discouraged} when solving DAE systems of index 1, whereas it
    is generally {i encouraged} for systems of index 2 or more.  See
    pp. 146-147 of the following reference for more on this issue:

    K. E. Brenan, S. L. Campbell, and L. R. Petzold.  Numerical
    Solution of Initial-Value Problems in Differential-Algebraic
    Equations.  SIAM, Philadelphia, Pa, 1996.

    @ida <node5#sss:optin_main> IDASetId
    @ida <node5#sss:optin_main> IDASetSuppressAlg
 *)
val set_suppress_alg : ('a, 'k) session -> bool -> unit

(** [calc_ic_y ida ~y:yvar tout1] corrects the initial values y0 at
    time t0, using the initial values of the derivatives y'0.  That
    is, if the {i t0,y0,y'0} that were given to {!init} or {!reinit}
    does not satisfy {i f(t0,y0,y'0) = 0}, where {i f} is the residual
    function, then [calc_ic_y] will modify {i y'0} so that this
    equation holds.  If {i f(t0,y0,y'0) = 0} is already true, a call
    to [calc_ic_y] is unnecessary.  [calc_ic_y] must not be called
    after any calls to {!solve_normal} or {!solve_one_step} without a
    {!reinit} in between.

    The optional parameter [~y], if given, will receive the corrected
    {i y} vector.  [tout1] is the first value of {i t} at which a
    solution will be requested (using {!solve_normal} or
    {!solve_one_step}). This value is needed here only to determine
    the direction of integration and rough scale in the independent
    variable {i t}.

    [calc_ic_y] differs from {!calc_ic_ya_yd'} in that,
    {!calc_ic_ya_yd'} computes parts of y and y' using parts of y as
    input, whereas [calc_ic_y] computes all of y using all of y' as
    input.  Here, y means the vector formed by collecting scalar
    variables that appear in the mathematical description of the DAE
    system, and y' is its derivative.  This is not to be confused with
    the labeled argument whose name is [~y]: y and y' are mathematical
    objects whereas [~y] is a programming construct.

    IDA's initial value correction works for certain index-one
    problems including a class of systems of semi-implicit form, and
    uses Newton iteration combined with a linesearch algorithm.  See
    Section 2.1 of the IDA User Guide and the following reference for
    more information:

    P. N. Brown, A. C. Hindmarsh, and L. R. Petzold. Consistent Initial Condition Calculation for Differential-Algebraic Systems. SIAM J. Sci. Comput., 19:1495-1512, 1998.

    @ida <node5#ss:idacalcic> IDACalcIC
    @ida <node5#sss:optout_iccalc> IDAGetConsistentIC
 *)
val calc_ic_y : ('a, 'k) session -> ?y:('a, 'k) nvector -> float -> unit

(** [calc_ic_ya_yd' ida ~y:yvar ~y':y'var vartypes tout1] corrects the
    initial values y0 and y0' at time t0.  That is, if the {i
    t0,y0,y'0} that were given to {!init} or {!reinit} does not
    satisfy {i f(t0,y0,y'0) = 0}, where {i f} is the residual
    function, then [calc_ic_ya_yd'] will modify parts of {i y0} and {i
    y'0} so that this equation holds.  If {i f(t0,y0,y'0) = 0} is
    already true, a call to [calc_ic_ya_yd'] is unnecessary.
    [calc_ic_ya_yd'] must not be called after any calls to
    {!solve_normal} or {!solve_one_step} without a {!reinit} in
    between.

    The optional parameters [~y] and [~y'], if given, will receive the
    corrected vectors.  [tout1] is the first value of t at which a
    solution will be requested (using {!solve_normal} or
    {!solve_one_step}), and is needed here only to determine the
    direction of integration and rough scale in the independent
    variable t.

    {!calc_ic_y} differs from [calc_ic_ya_yd'] in that,
    [calc_ic_ya_yd'] computes parts of y and y' using parts of y as
    input, whereas {!calc_ic_y} computes all of y using all of y' as
    input.  Here, y means the vector formed by collecting scalar
    variables that appear in the mathematical description of the DAE
    system, and y' means its derivative.  These are not to be confused
    with the labeled arguments whose names are [~y] and [~y']: y and
    y' are mathematical objects whereas [~y] and [~y'] are programming
    constructs.

    The non-optional nvector argument, named [vartypes] at the
    beginning, specifies some components of y as algebraic (i.e. their
    derivatives do not appear in the DAE) and others as differential
    (i.e. their derivatives appear in the DAE).  [calc_ic_ya_yd']
    modifies the algebraic components of y and differential components
    of y', using the differential components of y as input.  So if we
    let Ia be the set of indices at which [vartypes] is [Algebraic]
    and Id be the set of indices at which [vartypes] is
    [Differential], then y and y' are each partitioned into two
    sub-vectors (we use OCaml's array-indexing notation to denote
    subscripting):

      - y  splits into A  = \{ y.(i)  | i in Ia \} and D  = \{ y.(i)  | i in Id \}
      - y' splits into A' = \{ y'.(i) | i in Ia \} and D' = \{ y'.(i) | i in Id \}

    The residual function must be such that it ignores all values in
    A'.  [calc_ic_ya_yd'] computes (i.e. modifies) A and D' while
    treating D as read-only and ignoring A'.

      input:   D
      output:  A, D'
      ignored: A'

    Note: [vartypes] is called "id" in the C interface, e.g. [IDASetId].

    [calc_ic_ya_yd'] sets the variable types that {!set_suppress_alg}
    uses, so you do not need to set it again with {!set_var_types} (or
    its alias {!set_id}) before calling {!set_suppress_alg}.

    Note: the nvector interface gives no way of checking that the [~y]
    and [~y'] vectors have the right sizes.  Passing incorrectly sized
    vectors leads to memory corruption, so beware!  It's a good idea
    to always reuse the nvectors you gave to {!init} or {!reinit}.

    @ida <node5#ss:idacalcic> IDACalcIC
    @ida <node5#sss:optin_main> IDASetId
    @ida <node5#sss:optout_iccalc> IDAGetConsistentIC
 *)
val calc_ic_ya_yd' :
  ('a, 'k) session
  -> ?y:('a, 'k) nvector
  -> ?y':('a, 'k) nvector
  -> ('a, 'k) nvector
  -> float
  -> unit

(** [get_num_backtrack_ops ida] gets the number of backtrack operations done in
    the linesearch algorithm in {!calc_ic_ya_yd'} or {!calc_ic_y}.
    @ida <node5#sss:optout_iccalc> IDAGetNumBcktrackOps
 *)
val get_num_backtrack_ops : ('a, 'k) session -> int

(** {2 Solver functions } *)

(** [(tret, r) = solve_normal s tout yout y'out] integrates the DAE
    over an interval in t.

   The arguments are:
   - [s] a session with the solver.
   - [tout] the next time at which a computed solution is desired.
   - [yout] a vector to store the computed solution. The same vector that was
            passed to {!init} can be (but does not have to be) reused for this
            argument.
   - [y'out] a vector to store the computed solution's derivative.
             The same vector that was passed to {!init} can be (but
             does not have to be) reused for this argument.

   Two values are returned:
    - [tret] the time reached by the solver, which will be equal to [tout] if
      no errors occur.
    - [r] indicates whether roots were found, or whether an optional stop time,
          set by {!set_stop_time}, was reached; see {!Sundials.solver_result}.

   This routine will throw one of the solver {!exceptions} if an error
   occurs.

   Note: the nvector interface gives no way of checking that the
   [yout] and [y'out] vectors have the right sizes.  Passing
   incorrectly sized vectors leads to memory corruption, so beware!
   It's a good idea to always reuse the nvectors you gave to {!init}
   or {!reinit}.

   @ida <node5#sss:idasolve> IDASolve (IDA_NORMAL)
 *)
val solve_normal : ('a, 'k) session -> float
                   -> ('a, 'k) nvector -> ('a, 'k) nvector
                   -> float * Sundials.solver_result

(** This function is identical to {!solve_normal}, except that it
    returns after one internal solver step.

    @ida <node5#sss:idasolve> IDASolve (IDA_ONE_STEP)
 *)
val solve_one_step : ('a, 'k) session -> float
                     -> ('a, 'k) nvector -> ('a, 'k) nvector
                     -> float * Sundials.solver_result


(** {2 Main optional functions} *)

(** {3 Input} *)

(** Set the integration tolerances.

    @ida <node5#sss:idatolerances> IDASStolerances
    @ida <node5#sss:idatolerances> IDASVtolerances
    @ida <node5#sss:idatolerances> IDAWFtolerances
    @ida <node5#ss:ewtsetFn> Error weight function
 *)
val set_tolerances : ('a, 'k) session -> ('a, 'k) tolerance -> unit

(** [set_error_file s fname trunc] opens the file named [fname] and to
    which all messages from the default error handler are then
    directed.  If the file already exists it is either trunctated
    ([trunc] = [true]) or appended to ([trunc] = [false]).

    The error file is closed if set_error_file is called again, or
    otherwise when the session is garbage collected.

    @ida <node5#sss:optin_main> IDASetErrFile
 *)
val set_error_file : ('a, 'k) session -> string -> bool -> unit

(** [set_err_handler_fn s efun] specifies a custom function [efun] for
    handling error messages.  The error handler function must not fail
    -- any exceptions raised from it will be captured and silently
    discarded.

    @ida <node5#sss:optin_main> IDASetErrHandlerFn
    @ida <node5#ss:ehFn> Error message handler function
 *)
val set_err_handler_fn : ('a, 'k) session -> (Sundials.error_details -> unit)
                         -> unit

(** This function restores the default error handling function. It is
    equivalent to calling IDASetErrHandlerFn with an argument of [NULL].

    @ida <node5#sss:optin_main> IDASetErrHandlerFn *)
val clear_err_handler_fn : ('a, 'k) session -> unit

(** Specifies the maximum order of the linear multistep method.

    @ida <node5#sss:optin_main> IDASetMaxOrd
 *)
val set_max_ord : ('a, 'k) session -> int -> unit

(** Specifies the maximum number of steps to be taken by the solver in
    its attempt to reach the next output time.

    @ida <node5#sss:optin_main> IDASetMaxNumSteps
 *)
val set_max_num_steps : ('a, 'k) session -> int -> unit

(** Specifies the initial step size.

    @ida <node5#sss:optin_main> IDASetInitStep
 *)
val set_init_step : ('a, 'k) session -> float -> unit

(** Specifies an upper bound on the magnitude of the step size.

    @ida <node5#sss:optin_main> IDASetMaxStep
 *)
val set_max_step : ('a, 'k) session -> float -> unit

(** Specifies the value of the independent variable t past which the
    solution is not to proceed.  The default, if this routine is not
    called, is that no stop time is imposed.

    @ida <node5#sss:optin_main> IDASetStopTime
 *)
val set_stop_time : ('a, 'k) session -> float -> unit

(** Specifies the maximum number of error test failures permitted in
    attempting one step.

    @ida <node5#sss:optin_main> IDASetMaxErrTestFails
 *)
val set_max_err_test_fails : ('a, 'k) session -> int -> unit

(** Specifies the maximum number of nonlinear solver iterations
    permitted per step.

    @ida <node5#sss:optin_main> IDASetMaxNonlinIters
 *)
val set_max_nonlin_iters : ('a, 'k) session -> int -> unit

(** Specifies the maximum number of nonlinear solver convergence
    failures permitted during one step.

    @ida <node5#sss:optin_main> IDASetMaxConvFails
 *)
val set_max_conv_fails : ('a, 'k) session -> int -> unit

(** Specifies the safety factor used in the nonlinear convergence test.

    @ida <node5#sss:optin_main> IDASetNonlinConvCoef
    @ida <node3#ss:ivp_sol> IVP Solution
 *)
val set_nonlin_conv_coef : ('a, 'k) session -> float -> unit

(** Symbolic names for inequality constraints on variables, used for
    {!set_constraints}.  This function requires you to pass in an
    nvector populated with magic constants specifying each variable as
    positive, non-positive, negative, non-negative, or unconstrained.
    This module gives symbolic names to those constants, for your
    convenience.

    @ida <node5#sss:optin_main> IDASetConstraints
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
        point value is not a legal variable type specification.  *)
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

(** Set inequality constraints on variables.

    @ida <node5#sss:optin_main> IDASetConstraints
 *)
val set_constraints : ('a, 'k) session -> ('a, 'k) nvector -> unit

(** {3 Output } *)

(** Returns the real and integer workspace sizes.

    @ida <node5#sss:optout_main> IDAGetWorkSpace
    @return ([real_size], [integer_size])
 *)
val get_work_space          : ('a, 'k) session -> int * int

(** Returns the cumulative number of internal steps taken by the
    solver.

    @ida <node5#sss:optout_main> IDAGetNumSteps
 *)
val get_num_steps           : ('a, 'k) session -> int

(** Returns the number of calls to the user's right-hand side
    function.

    @ida <node5#sss:optout_main> IDAGetNumResEvals
 *)
val get_num_res_evals       : ('a, 'k) session -> int

(** Returns the number of calls made to the linear solver's setup
    function.

    @ida <node5#sss:optout_main> IDAGetNumLinSolvSetups
 *)
val get_num_lin_solv_setups : ('a, 'k) session -> int

(** Returns the number of local error test failures that have
    occurred.

    @ida <node5#sss:optout_main> IDAGetNumErrTestFails
 *)
val get_num_err_test_fails  : ('a, 'k) session -> int

(** Returns the integration method order used during the last internal
    step.

    @ida <node5#sss:optout_main> IDAGetLastOrder
 *)
val get_last_order          : ('a, 'k) session -> int

(** Returns the integration method order to be used on the next
    internal step.

    @ida <node5#sss:optout_main> IDAGetCurrentOrder
 *)
val get_current_order       : ('a, 'k) session -> int

(** Returns the integration step size taken on the last internal step.

    @ida <node5#sss:optout_main> IDAGetLastStep
 *)
val get_last_step           : ('a, 'k) session -> float

(** Returns the integration step size to be attempted on the next
    internal step.

    @ida <node5#sss:optout_main> IDAGetCurrentStep
 *)
val get_current_step        : ('a, 'k) session -> float

(** Returns the the value of the integration step size used on the
    first step.

    @ida <node5#sss:optout_main> IDAGetActualInitStep
 *)
val get_actual_init_step    : ('a, 'k) session -> float

(** Returns the the current internal time reached by the solver.

    @ida <node5#sss:optout_main> IDAGetCurrentTime
 *)
val get_current_time        : ('a, 'k) session -> float

(* IDAGetNumStabLimOrderReds appears in the sundials 2.5.0 manual on
   p.52 but there's no such function in the implementation.  It's
   probably a leftover from earlier versions or something.

(** Returns the number of order reductions dictated by the BDF
    stability limit detection algorithm.

    @ida <node5#sss:optout_main> IDAGetNumStabLimOrderReds
    @ida <node3#s:bdf_stab> BDF stability limit detection
 *)
val get_num_stab_lim_order_reds : session -> int
 *)

(** Returns a suggested factor by which the user's tolerances should
    be scaled when too much accuracy has been requested for some
    internal step.

    @ida <node5#sss:optout_main> IDAGetTolScaleFactor
 *)
val get_tol_scale_factor : ('a, 'k) session -> float

(** Returns the solution error weights at the current time.

    @ida <node5#sss:optout_main> IDAGetErrWeights
    @ida <node3#ss:ivp_sol> IVP solution (W_i)
 *)
val get_err_weights : ('a, 'k) session -> ('a, 'k) nvector -> unit

(** Returns the vector of estimated local errors.

    @ida <node5#sss:optout_main> IDAGetEstLocalErrors
 *)
val get_est_local_errors : ('a, 'k) session -> ('a, 'k) nvector -> unit

(**
 Aggregated integrator statistics.
 @ida <node5#sss:optout_main> IDAGetIntegratorStats
 *)
type integrator_stats = {
    num_steps : int;
    num_res_evals : int;
    num_lin_solv_setups : int;
    num_err_test_fails : int;
    last_order : int;
    current_order : int;
    actual_init_step : float;
    last_step : float;
    current_step : float;
    current_time : float
  }

(** Returns the integrator statistics as a group.

    @ida <node5#sss:optout_main> IDAGetIntegratorStats
 *)
val get_integrator_stats    : ('a, 'k) session -> integrator_stats

(** Convenience function that calls get_integrator_stats and prints
    the results to stdout.

    @ida <node5#sss:optout_main> IDAGetIntegratorStats
 *)
val print_integrator_stats  : ('a, 'k) session -> unit


(** Returns the number of nonlinear (functional or Newton) iterations
    performed.

    @ida <node5#sss:optout_main> IDAGetNumNonlinSolvIters
 *)
val get_num_nonlin_solv_iters : ('a, 'k) session -> int

(** Returns the number of nonlinear convergence failures that have
    occurred.

    @ida <node5#sss:optout_main> IDAGetNumNonlinSolvConvFails
 *)
val get_num_nonlin_solv_conv_fails : ('a, 'k) session -> int

(** [nniters, nncfails = get_nonlin_solv_stats s] obtains both the numbers of
    nonlinear iterations performed [nniters] and of nonlinear convergence
    failures that have occurred [nncfails].

    @ida <node5#sss:optout_main> IDAGetNonlinSolvStats *)
val get_nonlin_solv_stats : ('a, 'k) session -> int *int




(** {2 Root finding optional functions} *)

(** {3 Input} *)

(**
 Values for root directions.
 @ida <node5#sss:optin_root> IDASetRootDirection
 *)
type root_direction = Sundials.RootDirs.root_direction

(** [set_root_direction s dir] specifies the direction of
    zero-crossings to be located and returned. [dir] may contain one
    entry of type {!Ida.root_direction} for each root function.

    @ida <node5#sss:optin_root> IDASetRootDirection
 *)
val set_root_direction : ('a, 'k) session -> root_direction array -> unit

(** Like {!set_root_direction} but specifies a single direction of
    type {!Ida.root_direction} for all root functions.

  @ida <node5#sss:optin_root> IDASetRootDirection
 *)
val set_all_root_directions : ('a, 'k) session -> root_direction -> unit

(**
  Disables issuing a warning if some root function appears to be identically
  zero at the beginning of the integration.

  @ida <node5#sss:optin_root> IDASetNoInactiveRootWarn
 *)
val set_no_inactive_root_warn : ('a, 'k) session -> unit

(** {3 Output} *)

(**
  Fills an array showing which functions were found to have a root.

  @ida <node5#sss:optout_root> IDAGetRootInfo
 *)
val get_root_info : ('a, 'k) session -> Sundials.Roots.t -> unit

(** Returns the cumulative number of calls made to the user-supplied
    root function g.

    @ida <node5#sss:optout_root> IDAGetNumGEvals
 *)
val get_num_g_evals : ('a, 'k) session -> int

(** {2 Interpolated output function } *)

(**
  [get_dky s t k dky] computes the [k]th derivative of the function y at time
  [t], i.e. d(k)y/dt(k)(t). The function requires that tn - hu <= [t] <=
  tn, where tn denotes the current internal time reached, and hu is the last
  internal step size successfully used by the solver.
  The user may request [k] = 0, 1,..., qu, where qu is the current order.

  This function may only be called after a successful return from either
  {!solve_normal} or {!solve_one_step}.

  Values for the limits may be obtained:
    - tn = {!get_current_time}
    - qu = {!get_last_order}
    - hu = {!get_last_step}

  @ida <node5#sss:optin_root> IDAGetDky
 *)
val get_dky : ('a, 'k) session -> float -> int -> ('a, 'k) nvector -> unit

(** {2 Reinitialization} *)

(** [reinit s ~linsolv:linsolv ~roots:(nroots, g) t0 y0 y'0]
    reinitializes the solver session [s] with a new time [t0] and new
    values for the variables [y0].  There are two optional arguments
    to change the linear solver and the set of root functions.

    The optional argument [linsolv] sets the linear solver.  If
    omitted, the current linear solver will be kept.  If a session is
    created with, say, [Dense (Some f)], and then reinitialized with
    [Dense None], then the linear solver is reset and [f] is removed
    from the session.  The same goes for all other optional callbacks.

    The optional argument [roots] sets the root functions; see {!init}
    for what each component does.  {!Ida.no_roots} may be passed in to
    turn off root finding.  If omitted, the current root functions
    will be kept.

    @ida <node5#sss:cvreinit> IDAReInit
 *)
val reinit :
  ('a, 'k) session
  -> ?linsolv:('a, 'k) linear_solver
  -> ?roots:(int * (float -> 'a -> 'a -> Sundials.Roots.val_array -> unit))
  -> float
  -> ('a, 'k) nvector
  -> ('a, 'k) nvector
  -> unit
