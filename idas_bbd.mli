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
(*               User Documentation for IDA v1.1.0                     *)
(*                Alan C. Hindmarsh and Radu Serban                    *)
(*              Center for Applied Scientific Computing                *)
(*              Lawrence Livermore National Laboratory                 *)
(*                                                                     *)
(***********************************************************************)

(** Interface to the IDAS Adjoint Parallel Band-Block-Diagonal preconditioner.

    @version VERSION()
    @author Timothy Bourke (Inria)
    @author Jun Inoue (Inria)
    @author Marc Pouzet (LIENS)
    @idas <node7#SECTION00742000000000000000> Using the band-block-diagonal preconditioner IDABBDPRE
 *)
type data = Nvector_parallel.data
type kind = Nvector_parallel.kind
type parallel_bsession = (data, kind) Idas.Adjoint.bsession
type parallel_linear_solver = (data, kind) Idas.Adjoint.linear_solver

type bandwidths = Ida_bbd.bandwidths =
  {
    mudq    : int; (** Upper half-bandwidth to be used in the difference
                       quotient Jacobian approximation. *)
    mldq    : int; (** Lower half-bandwidth to be used in the difference
                       quotient Jacobian approximation. *)
    mukeep  : int; (** Upper half-bandwidth of the retained banded approximate
                       Jacobian block. *)
    mlkeep  : int; (** Lower half-bandwidth of the retained banded approximate
                       Jacobian block. *)
  }

(** User-supplied functions for the BBD preconditioner.

    @idas <node7#SECTION00742200000000000000> IDABBDLocalFnB
    @idas <node7#SECTION00742200000000000000> IDABBDCommFnB *)
type callbacks =
  {
    local_fn : float -> data -> data -> data -> data -> data -> unit;
      (** [gloc t y yb gb] computes [g(t, y)] into [gb] from the value of the
          independent variable [t], the current forward solution vector [y], and
          the current value of the backward dependent variable vector. This
          function should raise {!Sundials.RecoverableFailure} on a recoverable
          error, any other exception is treated as an unrecoverable error. *)

    comm_fn  : (float -> data -> data -> data -> data -> unit) option;

      (** [cfn t y yb] performs all interprocess communication necessary for the
          execution of [local_fn] using the forward solution vector [y] and the
          backward dependent variable vector [yb]. This function should raise
          {!Sundials.RecoverableFailure} on a recoverable error, any other
          exception is treated as an unrecoverable error. *)
  }

(** Same as {!Idas.Adjoint.Spils.spgmr} but with the Parallel
    Band-Block-Diagonal preconditioner.  Called like [spgmr ~maxl:maxl
    ~max_restarts:maxr ~dqrely:dqrely bandwidths cbs], where:

    - [~maxl] is the maximum dimension of the Krylov subspace.
      Defaults to [5].
    - [~max_restarts] is the maximum number of restarts.  Defaults to [5].
      Passing [0] disables restarts.
    - [~dqrely] is the relative increment in components of [y] used in
      the difference quotient approximations.  Defaults to [sqrt
      unit_roundoff].
    - [bandwidths] give the bandwidths of the preconditioning matrix.
    - [cbs] is a set of {!callbacks}.

    @idas <node7#sss:lin_solv_b> IDASpgmrB
    @idas <node7#SECTION00742100000000000000> IDABBDPrecInitB *)
val spgmr : ?maxl:int -> ?max_restarts:int -> ?dqrely:float
          -> Ida_bbd.bandwidths -> callbacks -> parallel_linear_solver

(** Same as {!Idas.Adjoint.Spils.spbcg} but with the Parallel
    Band-Block-Diagonal preconditioner. The arguments are the same as for
    {!spgmr}.

    @idas <node7#sss:lin_solv_b> IDASpbcgB
    @idas <node7#SECTION00742100000000000000> IDABBDPrecInitB *)
val spbcg : ?maxl:int -> ?dqrely:float -> Ida_bbd.bandwidths
          -> callbacks -> parallel_linear_solver

(** Same as {!Idas.Adjoint.Spils.sptfqmr} but with the Parallel
    Band-Block-Diagonal preconditioner. The arguments are the same as for
    {!spgmr}.

    @idas <node7#sss:lin_solv_b> IDASptfqmrB
    @idas <node7#SECTION00742100000000000000> IDABBDPrecInitB *)
val sptfqmr : ?maxl:int -> ?dqrely:float -> Ida_bbd.bandwidths
            -> callbacks -> parallel_linear_solver

(** [reinit s mudq mldq dqrely] reinitializes the BBD preconditioner
    with upper ([mudq]) and lower ([mldq]) half-bandwidths to be used in the
    difference quotient Jacobian approximation, and an optional relative
    increment in components of [y] (passing [None] uses the default value [sqrt
    unit_roundoff]).

    @idas <node7#SECTION00742000000000000000> IDABBDPrecReInitB *)
val reinit : parallel_bsession -> ?dqrely:float -> int -> int -> unit

(** {4 Optional output functions} *)

(** Returns the sizes of the real and integer workspaces used by the
    band-block-diagonal preconditioner module.

    @ida <node7#SECTION00742000000000000000> IDABBDPrecGetWorkSpace
    @return ([real_size], [integer_size]) *)
val get_work_space : parallel_bsession -> int * int

(** Returns the number of calls made to the user-supplied right-hand
    side function due to finite difference banded Jacobian approximation in the
    preconditioner setup function.

    @ida <node7#SECTION00742000000000000000> IDABBDPrecGetNumGfnEvals *)
val get_num_gfn_evals : parallel_bsession -> int

