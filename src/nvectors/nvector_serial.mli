(***********************************************************************)
(*                                                                     *)
(*                   OCaml interface to Sundials                       *)
(*                                                                     *)
(*             Timothy Bourke, Jun Inoue, and Marc Pouzet              *)
(*             (Inria/ENS)     (Inria/ENS)    (UPMC/ENS/Inria)         *)
(*                                                                     *)
(*  Copyright 2014 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under a New BSD License, refer to the file LICENSE.                *)
(*                                                                     *)
(***********************************************************************)

(** The standard serial nvectors of 

    @version VERSION()
    @author Timothy Bourke (Inria/ENS)
    @author Jun Inoue (Inria/ENS)
    @author Marc Pouzet (UPMC/ENS/Inria)
    @cvode <node7#ss:nvec_ser> NVECTOR_SERIAL *)

open Sundials

(** Serial nvectors are based on
    {{:OCAML_DOC_ROOT(Bigarray.Array1.html)} bigarrays} of floats. *)
type data = RealArray.t

(** Represents any nvector that can be treated as a serial nvector. That is,
    any nvector whose underlying elements can be accessed as an array
    locally. *)
type kind = [`Serial]

(** The type of serial nvectors. *)
type t = (data, kind) Nvector.t

(** The type of any nvector that can be used as a serial nvector. *)
type 'k any = (data, [>kind] as 'k) Nvector.t

(** [make n iv] creates a new serial nvector with [n] elements, each initialized
    to [iv]. *)
val make : int -> float -> t

(** [wrap a] creates a new serial nvector over the elements of [a]. *)
val wrap : RealArray.t -> t

(** Aliases {!Nvector.unwrap}. *)
val unwrap : t -> RealArray.t

(* TOPLEVEL-PRINTER: Nvector_serial.pp *)
(** Pretty-print a serial nvector using the
    {{:OCAML_DOC_ROOT(Format.html)} Format} module. *)
val pp : Format.formatter -> t -> unit

(** Underlying nvector operations on serial nvectors. *)
module Ops : Nvector.NVECTOR_OPS with type t = t

(** Nvector operations on {{!Sundials.RealArray}RealArray}s implemented in OCaml. *)
module DataOps : Nvector.NVECTOR_OPS with type t = RealArray.t

