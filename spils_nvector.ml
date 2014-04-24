(***********************************************************************)
(*                                                                     *)
(*     OCaml interface to Sundials (serial) CVODE and IDA solvers      *)
(*                                                                     *)
(*  Timothy Bourke (Inria), Jun Inoue (Inria), and Marc Pouzet (LIENS) *)
(*                                                                     *)
(*  Copyright 2013 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under a BSD 2-Clause License, refer to the file LICENSE.           *)
(*                                                                     *)
(***********************************************************************)

type 'a nvector = 'a Nvector.nvector

type 'a atimes = 'a nvector -> 'a nvector -> int

type 'a psolve = 'a nvector -> 'a nvector -> bool -> int

external modified_gs : ('a nvector) array
                       -> Sundials.Realarray2.t
                       -> int
                       -> int
                       -> float
    = "c_nvec_spils_modified_gs"

external classical_gs' : ('a nvector) array
                         * Sundials.Realarray2.t
                         * int
                         * int
                         * 'a nvector
                         * Sundials.real_array
                         -> float
    = "c_nvec_spils_classical_gs"

let classical_gs v h k p temp s = classical_gs' (v, h, k, p, temp, s)

module SPGMR =
  struct
    type 'a t

    type 'a nvector = 'a Nvector.nvector

    external make  : int -> 'a nvector -> 'a t
        = "c_nvec_spils_spgmr_make"

    external solve' : 'a t                            (*  0 *)
                      * 'a nvector                    (*  1 *)
                      * 'a nvector                    (*  2 *)
                      * Spils.preconditioning_type    (*  3 *)
                      * Spils.gramschmidt_type        (*  4 *)
                      * float                         (*  5 *)
                      * int                           (*  6 *)
                      * ('a nvector) option           (*  7 *)
                      * ('a nvector) option           (*  8 *)
                      * 'a atimes                     (*  9 *)
                      * ('a psolve) option            (* 10 *)
                      -> bool * float * int * int
        = "c_nvec_spils_spgmr_solve"

    let solve s x b pretype gstype delta max_restarts s1 s2 atimes psolve
        = solve' (s, x, b, pretype, gstype, delta, max_restarts, s1, s2,
                  atimes, psolve)

  end

module SPBCG =
  struct
    type 'a t

    type 'a nvector = 'a Nvector.nvector

    external make  : int -> 'a nvector -> 'a t
        = "c_nvec_spils_spbcg_make"

    external solve' : 'a t
                      * 'a nvector
                      * 'a nvector
                      * Spils.preconditioning_type
                      * float
                      * ('a nvector) option
                      * ('a nvector) option
                      * 'a atimes
                      * ('a psolve) option
                      -> bool * float * int * int
        = "c_nvec_spils_spbcg_solve"
    let solve s x b pretype delta sx sb atimes psolve =
      solve' (s, x, b, pretype, delta, sx, sb, atimes, psolve)
 end

module SPTFQMR =
  struct
    
    type 'a t

    type 'a nvector = 'a Nvector.nvector

    external make  : int -> 'a nvector -> 'a t
        = "c_nvec_spils_sptfqmr_make"

    external solve' : 'a t
                      * 'a nvector
                      * 'a nvector
                      * Spils.preconditioning_type
                      * float
                      * ('a nvector) option
                      * ('a nvector) option
                      * 'a atimes
                      * ('a psolve) option
                      -> bool * float * int * int
        = "c_nvec_spils_sptfqmr_solve"
    let solve s x b pretype delta sx sb atimes psolve =
      solve' (s, x, b, pretype, delta, sx, sb, atimes, psolve)

 end

