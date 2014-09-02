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

(** Interface to Parallel NVectors manipulated by the standard operations
    provided by Sundials. Requires MPI.
 
    @cvode <node7#ss:nvec_par> NVECTOR_PARALLEL *)
type kind

(** (local array, global length, MPI communicator) *)
type data = Sundials.RealArray.t * int * Mpi.communicator
type t = (data, kind) Sundials.nvector

(** Raised by make if the given global length is not consistent with the sum of
    local lengths across all parallel instances. *)
exception IncorrectGlobalSize

(** [make nl ng c iv] creates a new parallel nvector with [nl] local elements,
    that is part of a global array with [ng] elements. The local elements are
    initialized to [iv], and communications occur on [c]. *)
val make : int -> int -> Mpi.communicator -> float -> t

(** Create an nvector with a distinct underlying array but that shares the
    original global size and communicator. *)
val clone : t -> t

(** [unwrap nv] returns the local data [a] underlying the parallel nvector
    [nv]. *)
val unwrap : t -> Sundials.RealArray.t

(** Returns the number of global elements for a parallel nvector. *)
val global_length : t -> int

(** Returns the communicator used for by the parallel nvector. *)
val communicator : t -> Mpi.communicator

module MakeOps : functor (A : sig
      type local_data
      val get       : local_data -> int -> float
      val set       : local_data -> int -> float -> unit
      val fill      : local_data -> float -> unit
      val make      : int -> float -> local_data
      val clone     : local_data -> local_data
      val length    : local_data -> int
    end) -> Nvector.NVECTOR_OPS
            with type t = A.local_data * int * Mpi.communicator

module Ops : Nvector.NVECTOR_OPS with type t = t
module DataOps : Nvector.NVECTOR_OPS with type t = data

