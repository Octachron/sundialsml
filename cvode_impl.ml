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

(* Types shared between Cvode, Cvodes, Cvode_bbd, and Cvodes_bbd.  *)

(* This module's purpose is just to define types shared between Cvode,
   Cvodes, Cvode_bbd, and Cvode_bbds.  However, the session and
   linear_solver types must have their implementation exposed to all
   four modules yet be abstract to code that lives outside of the
   sundialsml library.

   To satisfy this requirement, we define the type in a separate
   module - this module - that exports everything, then omit
   Cvode_impl.cmi during installation.  This way, the compiled library
   doesn't divulge implementation details.

   Unfortunately, session depends on 90% of all data types used in
   those modules, so we are forced to declare almost all types here.
   To avoid repeating the types' definitions in Cvode, Cvodes,
   Cvode_bbd, and Cvodes_bbd, we "include Cvode_impl" from each
   module.  However, some submodules' types clash (for example
   Cvode.Spils.prec_solve_fn and Cvodes.Adjoint.Spils.prec_solve_fn),
   so we need to reproduce to some extent the submodules present in
   Cvode and Cvodes.  Hence the behemoth you see below.

 *)

(*
 * NB: The order of variant constructors and record fields is important!
 *     If these types are changed or augmented, the corresponding declarations
 *     in cvode_ml.h (and code in cvode_ml.c) must also be updated.
 *)

type ('data, 'kind) nvector = ('data, 'kind) Sundials.nvector
module RealArray = Sundials.RealArray

type 'a single_tmp = 'a
type 'a triple_tmp = 'a * 'a * 'a

type ('t, 'a) jacobian_arg =
  {
    jac_t   : float;
    jac_y   : 'a;
    jac_fy  : 'a;
    jac_tmp : 't
  }

type bandrange = { mupper : int; mlower : int; }

module DlsTypes = struct
  type dense_jac_fn =
    (RealArray.t triple_tmp, RealArray.t) jacobian_arg
    -> Dls.DenseMatrix.t
    -> unit

  type band_jac_fn =
    bandrange
    -> (RealArray.t triple_tmp, RealArray.t) jacobian_arg
    -> Dls.BandMatrix.t
    -> unit
end

module SpilsCommonTypes = struct
  (* Types that don't depend on jacobian_arg.  *)

  type 'a prec_solve_arg =
    {
      rhs   : 'a;
      gamma : float;
      delta : float;
      left  : bool;
    }

  type gramschmidt_type = Spils.gramschmidt_type =
    | ModifiedGS
    | ClassicalGS
end

module SpilsTypes = struct
  include SpilsCommonTypes

  type 'a prec_solve_fn =
    ('a single_tmp, 'a) jacobian_arg
    -> 'a prec_solve_arg
    -> 'a
    -> unit

  type 'a prec_setup_fn =
    ('a triple_tmp, 'a) jacobian_arg
    -> bool
    -> float
    -> bool

  type 'a jac_times_vec_fn =
    ('a single_tmp, 'a) jacobian_arg
    -> 'a (* v *)
    -> 'a (* Jv *)
    -> unit

  type 'a user_callbacks =
    {
      prec_solve_fn : 'a prec_solve_fn;
      prec_setup_fn : 'a prec_setup_fn option;
      jac_times_vec_fn : 'a jac_times_vec_fn option;
    }

  type (_,_) callbacks =
    | User : 'a prec_solve_fn
             * 'a prec_setup_fn option
             * 'a jac_times_vec_fn option
      -> ('a, 'k) callbacks
    | Banded : bandrange * RealArray.t jac_times_vec_fn option ->
      (Nvector_serial.data, Nvector_serial.kind) callbacks

  type serial_callbacks =
    (Nvector_serial.data, Nvector_serial.kind) callbacks

  type 'callbacks with_preconditioning_type =
    | PrecNone
    | PrecLeft of 'callbacks
    | PrecRight of 'callbacks
    | PrecBoth of 'callbacks

  type ('a, 'k) preconditioner = ('a, 'k) callbacks with_preconditioning_type

  type preconditioning_type = unit with_preconditioning_type

  type serial_preconditioner =
    (Nvector_serial.data, Nvector_serial.kind) preconditioner
end

module AlternateTypes' = struct
  type conv_fail =
    | NoFailures
    | FailBadJ
    | FailOther
end

module CvodeBbdParamTypes = struct
  type 'a local_fn = float -> 'a -> 'a -> unit
  type 'a comm_fn = float -> 'a -> unit
  type 'a callbacks =
    {
      local_fn : 'a local_fn;
      comm_fn  : 'a comm_fn option;
    }
end

module CvodeBbdTypes = struct
  type bandwidths =
    {
      mudq    : int;
      mldq    : int;
      mukeep  : int;
      mlkeep  : int;
    }
end

(* Sensitivity *)

module QuadratureTypes = struct
  type 'a quadrhsfn = float -> 'a -> 'a -> unit
end

module SensitivityTypes = struct
  type 'a sensrhsfn_all =
    float
    -> 'a
    -> 'a
    -> 'a array
    -> 'a array
    -> 'a
    -> 'a
    -> unit

  type 'a sensrhsfn1 =
    float
    -> 'a
    -> 'a
    -> int
    -> 'a
    -> 'a
    -> 'a
    -> 'a
    -> unit

  type 'a sensrhsfn =
      AllAtOnce of 'a sensrhsfn_all option
    | OneByOne of 'a sensrhsfn1 option

  module QuadratureTypes = struct
    type 'a quadsensrhsfn =
      float
      -> 'a
      -> 'a array
      -> 'a
      -> 'a array
      -> 'a
      -> 'a
      -> unit
  end
end

module AdjointTypes' = struct
  type 'a brhsfn_no_sens = float -> 'a -> 'a -> 'a -> unit
  type 'a brhsfn_with_sens = float -> 'a -> 'a array -> 'a -> 'a -> unit

  type 'a brhsfn =
      NoSens of 'a brhsfn_no_sens
    | WithSens of 'a brhsfn_with_sens

  module QuadratureTypes = struct
    type 'a bquadrhsfn_no_sens = float -> 'a -> 'a -> 'a -> unit
    type 'a bquadrhsfn_with_sens = float -> 'a -> 'a array -> 'a -> 'a -> unit
    type 'a bquadrhsfn =
        NoSens of 'a bquadrhsfn_no_sens
      | WithSens of 'a bquadrhsfn_with_sens
  end

  type ('t, 'a) jacobian_arg =
    {
      jac_t   : float;
      jac_y   : 'a;
      jac_yb  : 'a;
      jac_fyb : 'a;
      jac_tmp : 't
    }

  (* This is NOT the same as DlsTypes defined above.  This version
     refers to a different jacobian_arg, the one that was just
     defined.  *)
  module DlsTypes = struct
    type dense_jac_fn =
      (RealArray.t triple_tmp, RealArray.t) jacobian_arg
      -> Dls.DenseMatrix.t
      -> unit

    type band_jac_fn =
      bandrange
      -> (RealArray.t triple_tmp, RealArray.t) jacobian_arg
      -> Dls.BandMatrix.t
      -> unit
  end

  (* Ditto. *)
  module SpilsTypes = struct
    include SpilsCommonTypes

    type 'a prec_solve_fn =
      ('a single_tmp, 'a) jacobian_arg
      -> 'a prec_solve_arg
      -> 'a
      -> unit

    type 'a prec_setup_fn =
      ('a triple_tmp, 'a) jacobian_arg
      -> bool
      -> float
      -> bool

    type 'a jac_times_vec_fn =
      ('a single_tmp, 'a) jacobian_arg
      -> 'a (* v *)
      -> 'a (* Jv *)
      -> unit

    type 'a user_callbacks =
      {
        prec_solve_fn : 'a prec_solve_fn;
        prec_setup_fn : 'a prec_setup_fn option;
        jac_times_vec_fn : 'a jac_times_vec_fn option;
      }

    type (_,_) callbacks =
      | User : 'a prec_solve_fn
               * 'a prec_setup_fn option
               * 'a jac_times_vec_fn option
        -> ('a, 'k) callbacks
      | Banded : bandrange * RealArray.t jac_times_vec_fn option ->
        (Nvector_serial.data, Nvector_serial.kind) callbacks

    type serial_callbacks =
      (Nvector_serial.data, Nvector_serial.kind) callbacks

    type 'callbacks with_preconditioning_type =
      | PrecNone
      | PrecLeft of 'callbacks
      | PrecRight of 'callbacks
      | PrecBoth of 'callbacks

    type ('a, 'k) preconditioner = ('a, 'k) callbacks with_preconditioning_type

    type preconditioning_type = unit with_preconditioning_type

    type serial_preconditioner =
      (Nvector_serial.data, Nvector_serial.kind) preconditioner
  end
end

module CvodesBbdParamTypes = struct
  type 'a local_fn = float -> 'a -> 'a -> 'a -> unit
  type 'a comm_fn = float -> 'a -> 'a -> unit
  type 'a callbacks =
    {
      local_fn : 'a local_fn;
      comm_fn  : 'a comm_fn option;
    }
end
module CvodesBbdTypes = CvodeBbdTypes

type cvode_mem
type cvode_file
type c_weak_ref

type 'a rhsfn = float -> 'a -> 'a -> unit
type 'a rootsfn = float -> 'a -> Sundials.Roots.val_array -> unit
type errh = Sundials.error_details -> unit
type 'a errw = 'a -> 'a -> unit

(* Session: here comes the big blob.  These mutually recursive types
   cannot be handed out separately to modules without menial
   repetition, so we'll just have them all here, at the top of the
   Types module.  *)

type ('a, 'kind) session = {
  cvode      : cvode_mem;
  backref    : c_weak_ref;
  nroots     : int;
  err_file   : cvode_file;

  mutable exn_temp     : exn option;

  mutable rhsfn        : 'a rhsfn;
  mutable rootsfn      : 'a rootsfn;
  mutable errh         : errh;
  mutable errw         : 'a errw;

  mutable ls_callbacks : ('a, 'kind) linsolv_callbacks;

  mutable sensext      : ('a, 'kind) sensext (* Used by Cvodes *)
}

and (_, _) linsolv_callbacks =
  | NoCallbacks : ('a, 'k) linsolv_callbacks

  | DenseCallback :
      DlsTypes.dense_jac_fn
      -> (Nvector_serial.data, Nvector_serial.kind) linsolv_callbacks
  | BandCallback :
      DlsTypes.band_jac_fn
      -> (Nvector_serial.data, Nvector_serial.kind) linsolv_callbacks
  | SpilsCallback :
      'a SpilsTypes.user_callbacks
      -> ('a, 'k) linsolv_callbacks
  | SpilsBandedCallback :
      RealArray.t SpilsTypes.jac_times_vec_fn option ->
      (Nvector_serial.data, Nvector_serial.kind) linsolv_callbacks
  | BBDCallback :
      'a CvodeBbdParamTypes.callbacks
      -> ('a, 'k) linsolv_callbacks

  | AlternateCallback :
      ('a, 'k) alternate_linsolv
      -> ('a, 'k) linsolv_callbacks

  | BDenseCallback :
      AdjointTypes'.DlsTypes.dense_jac_fn
      -> (Nvector_serial.data, Nvector_serial.kind) linsolv_callbacks
  | BBandCallback :
      AdjointTypes'.DlsTypes.band_jac_fn
      -> (Nvector_serial.data, Nvector_serial.kind) linsolv_callbacks
  | BSpilsCallback :
      'a AdjointTypes'.SpilsTypes.user_callbacks
      -> ('a, 'k) linsolv_callbacks
  | BSpilsBandedCallback :
      RealArray.t AdjointTypes'.SpilsTypes.jac_times_vec_fn option
      -> (Nvector_serial.data, Nvector_serial.kind) linsolv_callbacks
  | BBBDCallback :
      'a CvodesBbdParamTypes.callbacks
      -> ('a, 'k) linsolv_callbacks

and ('a, 'kind) sensext =
    NoSensExt
  | FwdSensExt of ('a, 'kind) fsensext
  | BwdSensExt of ('a, 'kind) bsensext

and ('a, 'kind) fsensext = {
  (* Quadrature *)
  mutable quadrhsfn       : 'a QuadratureTypes.quadrhsfn;

  (* Sensitivity *)
  mutable num_sensitivities : int;
  mutable sensarray1        : 'a array;
  mutable sensarray2        : 'a array;
  mutable senspvals         : RealArray.t option;
  (* keep a reference to prevent garbage collection *)

  mutable sensrhsfn         : 'a SensitivityTypes.sensrhsfn_all;
  mutable sensrhsfn1        : 'a SensitivityTypes.sensrhsfn1;
  mutable quadsensrhsfn     : 'a SensitivityTypes.QuadratureTypes.quadsensrhsfn;

  (* Adjoint *)
  mutable bsessions         : ('a, 'kind) session list;
  (* hold references to prevent garbage collection
     of backward sessions which are needed for
     callbacks. *)
}

and ('a, 'kind) bsensext = {
  (* Adjoint *)
  parent                : ('a, 'kind) session ;
  which                 : int;

  bnum_sensitivities    : int;
  bsensarray            : 'a array;

  mutable brhsfn        : 'a AdjointTypes'.brhsfn_no_sens;
  mutable brhsfn1       : 'a AdjointTypes'.brhsfn_with_sens;
  mutable bquadrhsfn    : 'a AdjointTypes'.QuadratureTypes.bquadrhsfn_no_sens;
  mutable bquadrhsfn1   : 'a AdjointTypes'.QuadratureTypes.bquadrhsfn_with_sens;
}

and ('data, 'kind) alternate_linsolv =
  {
    linit  : ('data, 'kind) linit' option;
    lsetup : ('data, 'kind) lsetup' option;
    lsolve : ('data, 'kind) lsolve';
  }
and ('data, 'kind) linit' = ('data, 'kind) session -> unit
and ('data, 'kind) lsetup' =
  ('data, 'kind) session
  -> AlternateTypes'.conv_fail
  -> 'data
  -> 'data
  -> 'data triple_tmp
  -> bool
and ('data, 'kind) lsolve' =
  ('data, 'kind) session
  -> 'data
  -> 'data
  -> 'data
  -> 'data
  -> unit

(* Types that depend on session *)

type serial_session = (Nvector_serial.data, Nvector_serial.kind) session

type ('data, 'kind) linear_solver =
  ('data, 'kind) session
  -> ('data, 'kind) nvector
  -> unit

type serial_linear_solver =
  (Nvector_serial.data, Nvector_serial.kind) linear_solver

module AlternateTypes = struct
  include AlternateTypes'
  type ('data, 'kind) callbacks = ('data, 'kind) alternate_linsolv =
    {
      linit  : ('data, 'kind) linit option;
      lsetup : ('data, 'kind) lsetup option;
      lsolve : ('data, 'kind) lsolve;
    }
  and ('data, 'kind) linit = ('data, 'kind) linit'
  and ('data, 'kind) lsetup = ('data, 'kind) lsetup'
  and ('data, 'kind) lsolve = ('data, 'kind) lsolve'
end

module AdjointTypes = struct
  include AdjointTypes'
  (* Backwards session. *)
  type ('a, 'k) bsession = Bsession of ('a, 'k) session
  type serial_bsession = (Nvector_serial.data, Nvector_serial.kind) bsession
  let tosession (Bsession s) = s

  type ('data, 'kind) linear_solver =
    ('data, 'kind) bsession
    -> ('data, 'kind) nvector
    -> unit
  type serial_linear_solver =
    (Nvector_serial.data, Nvector_serial.kind) linear_solver
end

let read_weak_ref x : ('a, 'kind) session =
  match Weak.get x 0 with
  | Some y -> y
  | None -> raise (Failure "Internal error: weak reference is dead")

let adjust_retcode = fun session check_recoverable f x ->
  try f x; 0
  with
  | Sundials.RecoverableFailure when check_recoverable -> 1
  | e -> (session.exn_temp <- Some e; -1)

let adjust_retcode_and_bool = fun session f x ->
  try (f x, 0)
  with
  | Sundials.RecoverableFailure -> (false, 1)
  | e -> (session.exn_temp <- Some e; (false, -1))

(* Dummy callbacks.  These dummies getting called indicates a fatal
   bug.  Rather than raise an exception (which may or may not get
   propagated properly depending on the context), we immediately abort
   the program. *)
external crash : string -> unit = "sundials_crash"
let dummy_rhsfn _ _ _ =
  crash "Internal error: dummy_resfn called\n"
let dummy_rootsfn _ _ _ =
  crash "Internal error: dummy_rootsfn called\n"
let dummy_errh _ =
  crash "Internal error: dummy_errh called\n"
let dummy_errw _ _ =
  crash "Internal error: dummy_errw called\n"
let dummy_brhsfn _ _ _ _ =
  crash "Internal error: dummy_brhsfn called\n"
let dummy_brhsfn1 _ _ _ _ _ =
  crash "Internal error: dummy_brhsfn1 called\n"
let dummy_bquadrhsfn _ _ _ _ =
  crash "Internal error: dummy_bquadrhsfn called\n"
let dummy_bquadrhsfn1 _ _ _ _ _ =
  crash "Internal error: dummy_bquadrhsfn1 called\n"
let dummy_quadrhsfn _ _ _ =
  crash "Internal error: dummy_quadrhsfn called\n"
let dummy_sensrhsfn _ _ _ _ _ _ _ =
  crash "Internal error: dummy_sensresfn called\n"
let dummy_sensrhsfn1 _ _ _ _ _ _ _ _ =
  crash "Internal error: dummy_sensresfn called\n"
let dummy_quadsensrhsfn _ _ _ _ _ _ _ =
  crash "Internal error: dummy_quadsensrhsfn called\n"
