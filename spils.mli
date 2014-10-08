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
(* The documentation text is adapted from comments in the Sundials     *)
(* header files by Scott D. Cohen, Alan C. Hindmarsh and Radu Serban   *)
(* at the Center for Applied Scientific Computing, Lawrence Livermore  *)
(* National Laboratory.                                                *)
(***********************************************************************)

(** Scaled Preconditioned Iterative Linear Solvers (SPILS) routines.

    @version VERSION()
    @author Timothy Bourke (Inria)
    @author Jun Inoue (Inria)
    @author Marc Pouzet (LIENS)
    @cvode <node9#s:spils>  The SPILS Modules *)

(** {2 Types} *)

(** The type of Gram-Schmidt orthogonalization in SPGMR linear solvers.

    @cvode <node9#ss:spgmr> ModifiedGS/ClassicalGS *)
type gramschmidt_type =
  | ModifiedGS   (** Modified Gram-Schmidt orthogonalization (MODIFIED_GS) *)
  | ClassicalGS  (** Classical Gram Schmidt orthogonalization (CLASSICAL_GS) *)

(** The type of preconditioning in Krylov solvers.

    @cvode <node3#s:preconditioning> Preconditioning
    @cvode <node5#sss:lin_solv_init> CVSpgmr/CVSpbcg/CVSptfqrm *)
type preconditioning_type =
  | PrecNone    (** No preconditioning *)
  | PrecLeft    (** {% $(P^{-1}A)x = P^{-1}b$ %} *)
  | PrecRight   (** {% $(AP^{-1})Px = b$ %} *)
  | PrecBoth    (** {% $(P_L^{-1}AP_R^{-1})P_Rx = P_L^{-1}b)$ %} *)

(**
  The type of a function [f v z] that calculates [z = A v] using an internal
  representation of [A]. The vector [v] must not be changed. Results are stored
  in [z]. The {!Sundials.RecoverableFailure} exception can be raised to indicate
  a recoverable failure. Any other exception indicates an unrecoverable failure.
 *)
type 'a atimes = 'a -> 'a -> unit

(**
  The type of a fucntion [f r z lr] that solves the preconditioner equation
  [P z = r] for the vector [z]. If [lr] is true then [P] should be taken as the
  left preconditioner and otherwise as the right preconditioner. The
  {!Sundials.RecoverableFailure} exception can be raised to indicate a
  recoverable failure. Any other exception indicates an unrecoverable failure.
 *)
type 'a psolve = 'a -> 'a -> bool -> unit

(** {2 Exceptions} *)

(** Raised when a solver fails to converge.
    (SPGMR_/SPBCG_/SPTFQMR_CONVFAIL) *)
exception ConvFailure

(** Raised when QR factorization yields a singular matrix.
    (SPGMR_/SPBCG_/SPTFQMR_QRFACT_FAIL) *)
exception QRfactFailure

(** Raised when a preconditioner solver fails. The argument is [true] for a
    recoverable failure (SPGMR_/SPBCG_/SPTFQMR_PSOLVE_FAIL_REC) and [false]
    for an unrecoverable one (SPGMR_/SPBCG_/SPTFQMR_PSOLVE_FAIL_UNREC). *)
exception PSolveFailure of bool

(** Raised when an atimes function fails. The argument is [true] for a
    recoverable failure (SPGMR_/SPBCG_/SPTFQMR_ATIMES_FAIL_REC) and [false]
    for an unrecoverable one (SPGMR_/SPBCG_/SPTFQMR_ATIMES_FAIL_UNREC). *)
exception ATimesFailure of bool

(** Raised when a preconditioner setup routine fails. The argument is [true]
    for a recoverable failure (SPGMR_/SPBCG_/SPTFQMR_PSET_FAIL_REC) and
    [false] for an unrecoverable one (SPGMR_/SPBCG_/SPTFQMR_PSET_FAIL_UNREC). *)
exception PSetFailure of bool

(** Raised when a Gram-Schmidt routine fails. (SPGMR_/SPBCG_/SPTFQMR_GS_FAIL) *)
exception GSFailure

(** Raised QR solution finds a singular result.
    (SPGMR_/SPBCG_/SPTFQMR_QRSOL_FAIL) *)
exception QRSolFailure

(** {2 Basic routines} *)

(**
  [r = qr_fact n h q newjob] performs a QR factorization of the Hessenberg
  matrix [h], where
  - [n] is the problem size,
  - [h] is the [n+1] by [n] Hessenberg matrix (stored row-wise) to be factored,
  - [q] is an array of length [2*n] containing the Givens rotations    computed
    by this function. A Givens rotation has the form [| c -s; s c |]. The
    components of the Givens rotations are stored in [q] as
    [(c, s, c, s, ..., c, s)], and,
  - if [newjob] is true then a new QR factorization is performed, otherwise it
    is assumed that the first [n-1] columns of [h] have already been factored,
    and only the last column needs to be updated.

  The result, [r], is 0 if successful. If a zero is encountered on the diagonal
  of the triangular factor [R], then QRfact returns the equation number of the
  zero entry, where the equations are numbered from 1, not 0. If {!qr_sol} is
  subsequently called in this situation, it will return an error because it
  could not divide by the zero diagonal entry.                             
 *)
val qr_fact : int
              -> Sundials.RealArray2.t
              -> Sundials.RealArray.t
              -> bool
              -> int
 
(**
  [r = qr_sol n h q b] solves the linear least squares problem
  [min (b - h*x, b - h*x), x in R^n] where
  - [n] is the problem size,
  - [h] is computed by {!qr_fact} containing the upper triangular factor
    [R] of the original Hessenberg matrix,
  - [q] is the array computed by {!qr_fact} containing the Givens rotations used
    to factor [h], and,
  - [b] is the [n+1]-vector which, on successful return, will contain the
    solution [x] of the least squares problem.

  The result, [r], is 0 if successful. Otherwise, a zero was encountered on the
  diagonal of the triangular factor [R]. In this case, QRsol returns the
  equation number (numbered from 1, not 0) of the zero entry.
 *)
val qr_sol : int
             -> Sundials.RealArray2.t
             -> Sundials.RealArray.t
             -> Sundials.RealArray.t
             -> int

(**
  [new_vk_norm = modified_gs v h k p new_vk_norm] performs a modified
  Gram-Schmidt orthogonalization  of [v[k]] against the [p] unit vectors at
  [v.{k-1}], [v.{k-2}], ..., [v.{k-p}]. Its arguments are:
  - [v] an array of [k + 1] vectors assumed to have an L2-norm of 1,
  - [h] is the output [k] by [k] Hessenberg matrix of inner products.
    This matrix must be allocated row-wise so that the [(i,j)]th entry is
    [h.{i}.{j}]. The inner products [(v.{i}, v.{k})], [i=i0], [i0+1], ...,
    [k-1], are stored at [h.{i}.{k-1}] where [i0=MAX(0,k-p)],
  - [k] is the index of the vector in [v] that needs to be
    orthogonalized against previous vectors in [v],
  - [p] is the number of previous vectors in [v] against     
    which [v.{k}] is to be orthogonalized, and,
  The returned value, [new_vk_norm], is the Euclidean norm of the orthogonalized
  vector [v.{k}].
                                                                
  If [(k-p) < 0], then [modified_gs] uses [p=k]. The orthogonalized [v.{k}] is
  not normalized and is stored over the old [v.{k}]. Once the orthogonalization
  has been performed, the Euclidean norm of [v.{k}] is stored in [new_vk_norm].                           
 *)
val modified_gs : (('a, 'k) Nvector.t) array
                 -> Sundials.RealArray2.t
                 -> int
                 -> int
                 -> float

(**
  [new_vk_norm = classical_gs v h k p new_vk_norm temp s] performs a classical
  Gram-Schmidt orthogonalization  of [v[k]] against the [p] unit vectors at
  [v.{k-1}], [v.{k-2}], ..., [v.{k-p}]. Its arguments are:
  - [v] an array of [k + 1] vectors assumed to have an L2-norm of 1,
  - [h] is the output [k] by [k] Hessenberg matrix of inner products.
    This matrix must be allocated row-wise so that the [(i,j)]th entry is
    [h.{i}.{j}]. The inner products [(v.{i}, v.{k})], [i=i0], [i0+1], ...,
    [k-1], are stored at [h.{i}.{k-1}] where [i0=MAX(0,k-p)],
  - [k] is the index of the vector in [v] that needs to be
    orthogonalized against previous vectors in [v],
  - [p] is the number of previous vectors in [v] against     
    which [v.{k}] is to be orthogonalized,
  - [temp] is used as a workspace, and,
  - [s] is another workspace.
  The returned value, [new_vk_norm], is the Euclidean norm of the orthogonalized
  vector [v.{k}].

  If [(k-p) < 0], then [modifiedGS] uses [p=k]. The orthogonalized [v.{k}] is
  not normalized and is stored over the old [v.{k}]. Once the orthogonalization
  has been performed, the Euclidean norm of [v.{k}] is stored in [new_vk_norm].                           
 *)
val classical_gs : (('a, 'k) Nvector.t) array
                  -> Sundials.RealArray2.t
                  -> int
                  -> int
                  -> ('a, 'k) Nvector.t
                  -> Sundials.RealArray.t
                  -> float

(** {2 Solvers} *)

(** The Scaled Preconditioned Generalized Minimum Residual (GMRES) method. *)
module SPGMR :
  sig
    
    (**
     This type represents a solver instance returned from a call to {!make}.

    @cvode <node9#ss:spgmr> The SPGMR Module
    *)
    type 'a t

    (**
     [make lmax temp] returns a solver session, where [lmax] is the maximum
     Krylov subspace dimension that the solver will be permitted to use, and
     [temp] indirectly specifies the problem size.

     @cvode <node9#ss:spgmr> SpgmrMalloc
     @raise MemoryRequestFailure Memory could not be allocated.
     *)
    val make  : int -> ('a, 'k) Nvector.t -> 'a t

    (**
     [solved, res_norm, nli, nps = solve s x b pretype gstype delta max_restarts
     s1 s2 atimes psolve res_norm] solves the linear system [Ax = b] using the
     SPGMR iterative method where
      - [s] is a solver session (allocated with {!make}),
      - [x] is the initial guess upon entry, and the solution on return,
      - [b] is the right-hand side vector,
      - [pretype] is the type of preconditioning to use,
      - [gstype] is the type of Gram-Schmidt orthogonalization to use,
      - [delta] is the tolerance on the L2 norm of the scaled, preconditioned
        residual which will satisfy [|| s1 P1_inv (b - Ax) ||_2 <= delta] if
        [solved] is true,
      - [max_restarts] is the maximum number of allowed restarts,
      - [s1] are the optional positive scale factors for [P1-inv b] where
        [P1] is the left preconditioner,
      - [s2] are the optional positive scale factors for [P2 x] where [P2]
        is the right preconditioner,
      - [atimes] multiplies the coefficients [A] by a given vector,
      - [psolve] optionally solves the preconditioner system, and,

      The returned value, [solved], indicates whether the system converged or
      whether it only managed to reduce the norm of the residual, [res_norm] is
      the L2 norm of the scaled preconditioned residual, [|| s1 P1_inv (b - Ax)
      ||_2], [nli] indicates the number of linear iterations performed, and
      [nps] indicates the number of calls made to [psolve].

      Repeated calls can be made to [solve] with varying input arguments, but a
      new session must be created with [make] if the problem size or the maximum
      Krylov dimension changes.

      @cvode <node9#ss:spgmr> SpgmrSolve
      @raise ConvFailure Failed to converge
      @raise QRfactFailure QRfact found singular matrix
      @raise PSolveFailure psolve failed (recoverable or not)
      @raise ATimesFailure atimes failed (recoverable or not)
      @raise PSetFailure pset failed (recoverable or not)
      @raise GSFailure Gram-Schmidt routine failed.
      @raise QRSolFailure QRsol found singular R.
     *)
    val solve : 'a t
                -> ('a, 'k) Nvector.t
                -> ('a, 'k) Nvector.t
                -> preconditioning_type
                -> gramschmidt_type 
                -> float
                -> int
                -> (('a, 'k) Nvector.t) option
                -> (('a, 'k) Nvector.t) option
                -> 'a atimes
                -> ('a psolve) option
                -> bool * float * int * int
  end

(** The Scaled Preconditioned Biconjugate Gradient Stabilized (Bi-CGStab)
    method. *)
module SPBCG :
  sig
    
    (**
     This type represents a solver instance returned from a call to {!make}.

      @cvode <node9#ss:spgmr> The SPBCG Module
    *)
    type 'a t

    (**
     [make lmax temp] returns a solver session, where [lmax] is the maximum
     Krylov subspace dimension that the solver will be permitted to use, and
     [temp] indirectly specifies the problem size.

     @cvode <node9#ss:spbcg> SpbcgMalloc
     @raise MemoryRequestFailure Memory could not be allocated.
     *)
    val make  : int -> ('a, 'k) Nvector.t -> 'a t

    (**
     [solved, res_norm, nli, nps = solve s x b pretype delta sx sb atimes
     psolve] solves the linear system [Ax = b] using the SPBCG iterative method
     where
      - [s] is a solver session (allocated with {!make}),
      - [x] is the initial guess upon entry, and the solution on return,
      - [b] is the right-hand side vector,
      - [pretype] is the type of preconditioning to use,
      - [delta] is the tolerance on the L2 norm of the scaled, preconditioned
        residual which will satisfy [||sb*P1_inv*(b-Ax)||_L2 <= delta] if
        [solved] is true,
      - [sx] are the optional positive scaling factors for [x],
      - [sb] are the optional positive scaling factors for [b],
      - [atimes] multiplies the coefficients [A] by a given vector,
      - [psolve] optionally solves the preconditioner system, and,

      The returned value, [solved], indicates whether the system converged or
      whether it only managed to reduce the norm of the residual, [res_norm] is
      used for returning the L2 norm of the scaled preconditioned residual,
      [||sb*P1_inv*(b-Ax)||_L2], [nli] indicates the number of linear iterations
      performed, and [nps] indicates the number of calls made to [psolve].

      Repeated calls can be made to [solve] with varying input arguments, but a
      new session must be created with [make] if the problem size or the maximum
      Krylov dimension changes.

      @cvode <node9#ss:spbcg> SpbcgSolve
      @raise ConvFailure Failed to converge
      @raise PSolveFailure psolve failed (recoverable or not)
      @raise ATimesFailure atimes failed (recoverable or not)
      @raise PSetFailure pset failed (recoverable or not)
     *)
    val solve : 'a t
                -> ('a, 'k) Nvector.t
                -> ('a, 'k) Nvector.t
                -> preconditioning_type
                -> float
                -> (('a, 'k) Nvector.t) option
                -> (('a, 'k) Nvector.t) option
                -> 'a atimes
                -> ('a psolve) option
                -> bool * float * int * int

 end


(** The Scaled Preconditioned Transpose-Free Quasi-Minimal Residual
    (SPTFQMR) method *)
module SPTFQMR :
  sig
    
    (**
     This type represents a solver instance returned from a call to {!make}.

     @cvode <node9#ss:sptfqmr> The SPTFQMR Module
    *)
    type 'a t

    (**
     [make lmax temp] returns a solver session, where [lmax] is the maximum
     Krylov subspace dimension that the solver will be permitted to use, and
     [temp] indirectly specifies the problem size.

     @cvode <node9#ss:sptfqmr> SptfqmrMalloc
     @raise MemoryRequestFailure Memory could not be allocated.
     *)
    val make  : int -> ('a, 'k) Nvector.t -> 'a t

    (**
     [solved, res_norm, nli, nps = solve s x b pretype delta sx sb atimes
     psolve] solves the linear system [Ax = b] using the SPTFQMR iterative
     method where
      - [s] is a solver session (allocated with {!make}),
      - [x] is the initial guess upon entry, and the solution on return,
      - [b] is the right-hand side vector,
      - [pretype] is the type of preconditioning to use,
      - [delta] is the tolerance on the L2 norm of the scaled, preconditioned
        residual which will satisfy [||sb*P1_inv*(b-Ax)||_L2 <= delta] if
        [solved] is true,
      - [sx] are the optional positive scaling factors for [x],
      - [sb] are the optional positive scaling factors for [b],
      - [atimes] multiplies the coefficients [A] by a given vector,
      - [psolve] optionally solves the preconditioner system, and,

      The value returned by this function, [solved], indicates whether the
      system converged or whether it only managed to reduce the norm of the
      residual, [res_norm] is used for returning the L2 norm of the scaled
      preconditioned residual, [||sb*P1_inv*(b-Ax)||_L2], [nli] indicates the
      number of linear iterations performed, and [nps] indicates the number of
      calls made to [psolve].

      Repeated calls can be made to [solve] with varying input arguments, but a
      new session must be created with [make] if the problem size or the maximum
      Krylov dimension changes.

      @cvode <node9#ss:sptfqmr> SptfqmrSolve
      @raise ConvFailure Failed to converge
      @raise PSolveFailure psolve failed (recoverable or not)
      @raise ATimesFailure atimes failed (recoverable or not)
      @raise PSetFailure pset failed (recoverable or not)
     *)
    val solve : 'a t
                -> ('a, 'k) Nvector.t
                -> ('a, 'k) Nvector.t
                -> preconditioning_type
                -> float
                -> (('a, 'k) Nvector.t) option
                -> (('a, 'k) Nvector.t) option
                -> 'a atimes
                -> ('a psolve) option
                -> bool * float * int * int

 end

