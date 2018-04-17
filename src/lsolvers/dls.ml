(***********************************************************************)
(*                                                                     *)
(*                   OCaml interface to Sundials                       *)
(*                                                                     *)
(*  Timothy Bourke (Inria), Jun Inoue (Inria), and Marc Pouzet (LIENS) *)
(*                                                                     *)
(*  Copyright 2014 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under a New BSD License, refer to the file LICENSE.                *)
(*                                                                     *)
(***********************************************************************)

type lint_array = Sundials.LintArray.t
type real_array = Sundials.RealArray.t

(* direct linear solvers functions *)

(* note: uses DENSE_ELEM rather than the more efficient DENSE_COL. *)
module DenseMatrix =
  struct
    type dlsmat = Dls_impl.dlsmat
    include Dls_impl.DenseTypes

    exception Invalidated

    external c_create : int -> int -> t
        = "c_densematrix_new_dense_mat"

    let create i j =
      if Sundials_config.safe && (i <= 0 || j <= 0)
      then failwith "Both M and N must be positive";
      c_create i j

    (* Allowing direct access is not safe because the underlying data may
       have been invalidated. Invalidated by setting the dims of the
       bigarray to 0 is tempting but error prone and the mechanism can
       be circumvented using Bigarray.Array2.sub (see:
         https://groups.google.com/d/msg/fa.caml/ROr_PifT_44/aqQ8Z0TWzH8J). *)
    let unsafe_unwrap { payload } = payload

    let invalidate v = v.valid <- false

    external c_size : dlsmat -> (int * int)
        = "c_densematrix_size"

    let size { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_size dlsmat

    external c_print        : dlsmat -> unit
        = "c_densematrix_print_mat"

    let print { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_print dlsmat

    let pp fmt { payload=d; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      let ni, nj = Bigarray.Array2.dim2 d - 1, Bigarray.Array2.dim1 d - 1 in
      Format.pp_print_string fmt "[";
      Format.pp_open_vbox fmt 0;
      for i = 0 to ni do

        Format.pp_open_hovbox fmt 4;
        for j = 0 to nj do
          if j > 0 then (
            Format.pp_print_string fmt " ";
            Format.pp_print_cut fmt ();
          );
          Format.fprintf fmt "% -15e" d.{j, i}
        done;
        Format.pp_close_box fmt ();

        if i < ni then (
          Format.pp_print_string fmt ";";
          Format.pp_print_cut fmt ();
        );

      done;
      Format.pp_close_box fmt ();
      Format.pp_print_string fmt "]"

    let ppi ?(start="[") ?(stop="]") ?(rowsep=";") ?(indent=4) ?(sep=" ")
            ?(item=fun f->Format.fprintf f "(%2d,%2d)=% -15e")
            fmt { payload=d; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      let ni, nj = Bigarray.Array2.dim2 d - 1, Bigarray.Array2.dim1 d - 1 in
      Format.pp_print_string fmt start;
      Format.pp_open_vbox fmt 0;
      for i = 0 to ni do

        Format.pp_open_hovbox fmt indent;
        for j = 0 to nj do
          if j > 0 then (
            Format.pp_print_string fmt sep;
            Format.pp_print_cut fmt ();
          );
          item fmt i j d.{j, i}
        done;
        Format.pp_close_box fmt ();

        if i < ni then (
          Format.pp_print_string fmt rowsep;
          Format.pp_print_cut fmt ();
        );

      done;
      Format.pp_close_box fmt ();
      Format.pp_print_string fmt stop

    external c_set_to_zero  : dlsmat -> unit
        = "c_densematrix_set_to_zero"

    let set_to_zero { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_set_to_zero dlsmat

    external c_add_identity : dlsmat -> unit
        = "c_densematrix_add_identity"

    let add_identity { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_add_identity dlsmat

    external c_matvec : dlsmat -> real_array -> real_array -> unit
        = "c_densematrix_matvec"

    let matvec { dlsmat; valid } ~x ~y =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_matvec dlsmat x y

    external c_copy     : dlsmat -> dlsmat -> unit
        = "c_densematrix_copy"

    let blit { dlsmat=dlsmat1; valid=valid1 }
             { dlsmat=dlsmat2; valid=valid2 } =
      if Sundials_config.safe && not (valid1 && valid2) then raise Invalidated;
      c_copy dlsmat1 dlsmat2

    external c_scale  : float -> dlsmat -> unit
        = "c_densematrix_scale"

    let scale a { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_scale a dlsmat

    external c_getrf  : dlsmat -> lint_array -> unit
        = "c_densematrix_getrf"

    let getrf { dlsmat; valid } la =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_getrf dlsmat la

    external c_getrs  : dlsmat -> lint_array -> real_array -> unit
        = "c_densematrix_getrs"

    let getrs { dlsmat; valid } la ra =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_getrs dlsmat la ra

    external c_potrf  : dlsmat -> unit
        = "c_densematrix_potrf"

    let potrf { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_potrf dlsmat

    external c_potrs  : dlsmat -> real_array -> unit
        = "c_densematrix_potrs"

    let potrs { dlsmat; valid } ra =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_potrs dlsmat ra

    external c_geqrf  : dlsmat -> real_array -> real_array -> unit
        = "c_densematrix_geqrf"

    let geqrf { dlsmat; valid } ra1 ra2 =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_geqrf dlsmat ra1 ra2

    external c_ormqr
        : dlsmat -> (real_array * real_array * real_array * real_array) -> unit
        = "c_densematrix_ormqr"

    let ormqr ~a ~beta ~v ~w ~work =
      if Sundials_config.safe && not a.valid then raise Invalidated;
      c_ormqr a.dlsmat (beta, v, w, work)

    (*
    external c_get : dlsmat -> int -> int -> float
        = "c_densematrix_get"

    let get { dlsmat; valid } i j =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_get dlsmat i j
    *)

    let get { payload; valid } i j =
      if Sundials_config.safe && not valid then raise Invalidated;
      payload.{j, i}

    (*
    external c_set : dlsmat -> int -> int -> float -> unit
        = "c_densematrix_set"

    let set { dlsmat; valid } i j e =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_set dlsmat i j e
    *)

    let set { payload; valid } i j v =
      if Sundials_config.safe && not valid then raise Invalidated;
      payload.{j, i} <- v

    let update { payload; valid } i j f =
      if Sundials_config.safe && not valid then raise Invalidated;
      payload.{j, i} <- f payload.{j, i}

    let make m n v =
      let r = create m n in
      for i = 0 to m - 1 do
        for j = 0 to n - 1 do
          set r i j v
        done
      done;
      r

  end

module ArrayDenseMatrix =
  struct
    type t = Sundials.RealArray2.t

    let make = Sundials.RealArray2.make
    let create = Sundials.RealArray2.create
    let get = Sundials.RealArray2.get
    let set = Sundials.RealArray2.set

    let update a i j f = set a i j (f (get a i j))

    let set_to_zero x = Bigarray.Array2.fill (Sundials.RealArray2.unwrap x) 0.0

    let blit = Sundials.RealArray2.blit

    external scale : float -> t -> unit
        = "c_arraydensematrix_scale"

    external add_identity : t -> unit
        = "c_arraydensematrix_add_identity"

    external matvec' : t -> real_array -> real_array -> unit
        = "c_arraydensematrix_matvec"

    let matvec a ~x ~y = matvec' a x y

    external getrf : t -> lint_array -> unit
        = "c_arraydensematrix_getrf"

    external getrs : t -> lint_array -> real_array -> unit
        = "c_arraydensematrix_getrs"

    external getrs' : t -> lint_array -> real_array -> int -> unit
        = "c_arraydensematrix_getrs_off"

    external potrf : t -> unit
        = "c_arraydensematrix_potrf"

    external potrs : t -> real_array -> unit
        = "c_arraydensematrix_potrs"

    external geqrf : t -> real_array -> real_array -> unit
        = "c_arraydensematrix_geqrf"

    external ormqr'
        : t -> (real_array * real_array * real_array * real_array) -> unit
        = "c_arraydensematrix_ormqr"

    let ormqr ~a ~beta ~v ~w ~work = ormqr' a (beta, v, w, work)
  end

module BandMatrix =
  struct
    type dlsmat = Dls_impl.dlsmat
    include Dls_impl.BandTypes

    (** Must agree with dls_bandmatrix_dims_index in dls_ml.h *)
    type dimensions = {
        n   : int;
        mu  : int;
        smu : int;
        ml  : int;
      }

    exception Invalidated

    external create : dimensions -> t
        = "c_bandmatrix_new_band_mat"

    (* Allowing direct access is not safe because the underlying data may
       have been invalidated. Invalidating by setting the dims of the
       bigarray to 0 is tempting but error prone and the mechanism can
       be circumvented using Bigarray.Array2.sub (see:
         https://groups.google.com/d/msg/fa.caml/ROr_PifT_44/aqQ8Z0TWzH8J). *)
    let unsafe_unwrap { payload } = payload

    let invalidate v = v.valid <- false

    external c_size : dlsmat -> dimensions
        = "c_bandmatrix_size"

    let size { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_size dlsmat

    external c_print          : dlsmat -> unit
        = "c_densematrix_print_mat"
          (* NB: same as densematrix *)

    let print { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_print dlsmat

    let pp fmt ({ payload; valid } as m) =
      if Sundials_config.safe && not valid then raise Invalidated;
      let {n; mu; ml; smu} = size m in

      Format.pp_print_string fmt "[";
      Format.pp_open_vbox fmt 0;
      for i = 0 to n - 1 do

        Format.pp_open_hovbox fmt 4;
        for j = 0 to n - 1 do
          if j > 0 then (
            Format.pp_print_string fmt " ";
            Format.pp_print_cut fmt ();
          );
          if (i > j + ml) || (j > i + mu)
          then Format.pp_print_string fmt "~"
          else Format.fprintf fmt "% -15e" payload.{j, i - j + smu}
        done;
        Format.pp_close_box fmt ();

        if i < n - 1 then (
          Format.pp_print_string fmt ";";
          Format.pp_print_cut fmt ();
        );

      done;
      Format.pp_close_box fmt ();
      Format.pp_print_string fmt "]"

    let ppi ?(start="[") ?(stop="]") ?(rowsep=";") ?(indent=4) ?(sep=" ")
            ?(empty="~")
            ?(item=fun f->Format.fprintf f "(%2d,%2d)=% -15e")
            fmt ({ payload; valid } as m) =
      if Sundials_config.safe && not valid then raise Invalidated;
      let {n; mu; ml; smu} = size m in

      Format.pp_print_string fmt start;
      Format.pp_open_vbox fmt 0;
      for i = 0 to n - 1 do

        Format.pp_open_hovbox fmt indent;
        for j = 0 to n - 1 do
          if j > 0 then (
            Format.pp_print_string fmt sep;
            Format.pp_print_cut fmt ();
          );
          if (i > j + ml) || (j > i + mu)
          then Format.pp_print_string fmt empty
          else item fmt i j payload.{j, i - j + smu}
        done;
        Format.pp_close_box fmt ();

        if i < n - 1 then (
          Format.pp_print_string fmt rowsep;
          Format.pp_print_cut fmt ();
        );

      done;
      Format.pp_close_box fmt ();
      Format.pp_print_string fmt stop

    external c_set_to_zero    : dlsmat -> unit
        = "c_densematrix_set_to_zero"
          (* NB: same as densematrix *)

    let set_to_zero { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_set_to_zero dlsmat

    external c_add_identity : dlsmat -> unit
        = "c_densematrix_add_identity"
          (* NB: same as densematrix *)

    let add_identity { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_add_identity dlsmat

    external c_matvec : dlsmat -> real_array -> real_array -> unit
        = "c_bandmatrix_matvec"

    let matvec { dlsmat; valid } ~x ~y =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_matvec dlsmat x y

    external c_copy : dlsmat -> dlsmat -> int -> int -> unit
        = "c_bandmatrix_copy"

    let blit { dlsmat=dlsmat1; valid=valid1 }
             { dlsmat=dlsmat2; valid=valid2 } copymu copyml =
      if Sundials_config.safe && not (valid1 && valid2) then raise Invalidated;
      c_copy dlsmat1 dlsmat2 copymu copyml

    external c_scale : float -> dlsmat -> unit
        = "c_bandmatrix_scale"

    let scale a { dlsmat; valid } =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_scale a dlsmat

    external c_gbtrf : dlsmat -> lint_array -> unit
        = "c_bandmatrix_gbtrf"

    let gbtrf { dlsmat; valid } la =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_gbtrf dlsmat la

    external c_gbtrs : dlsmat -> lint_array -> real_array -> unit
        = "c_bandmatrix_gbtrs"

    let gbtrs { dlsmat; valid } la ra =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_gbtrs dlsmat la ra

    (*
    external c_get : dlsmat -> int -> int -> float
        = "c_bandmatrix_get"

    let get { dlsmat; valid } i j =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_get dlsmat i j
    *)
    let get { payload; valid; ismu } i j =
      if Sundials_config.safe && not valid then raise Invalidated;
      payload.{j, i - j + ismu}

    (*
    external c_set : dlsmat -> int -> int -> float -> unit
        = "c_bandmatrix_set"

    let set { dlsmat; valid } i j e =
      if Sundials_config.safe && not valid then raise Invalidated;
      c_set dlsmat i j e
    *)
    let set { payload; valid; ismu } i j v =
      if Sundials_config.safe && not valid then raise Invalidated;
      payload.{j, i - j + ismu} <- v

    let update { payload; valid; ismu } i j f =
      if Sundials_config.safe && not valid then raise Invalidated;
      let k = i - j + ismu in
      payload.{j, k} <- f payload.{j, k}

    let make ({ n; smu } as dims) v =
      let { payload } as r = create dims in
      for i = 0 to n - 1 do
        for j = (max 0 (i - 1)) to (min n (i + 1)) - 1 do
          Bigarray.Array2.unsafe_set payload j (i - j + smu) v
        done
      done;
      r
  end

module ArrayBandMatrix =
  struct
    type t = Sundials.RealArray2.t

    type smu = int
    type mu = int
    type ml = int

    let make n smu ml v =
      Sundials.RealArray2.make (smu + ml + 1) n v

    let create n smu ml =
      Sundials.RealArray2.create (smu + ml + 1) n

    let get a smu i j =
      Sundials.RealArray2.get a (i - j + smu) j

    let set a smu i j v =
      Sundials.RealArray2.set a (i - j + smu) j v

    let update a smu i j f =
      let k = i - j + smu in
      Sundials.RealArray2.set a k j (f (Sundials.RealArray2.get a k j))

    external copy' : t -> t -> int * int * int * int -> unit
        = "c_arraybandmatrix_copy"

    let blit a b a_smu b_smu copymu copyml
        = copy' a b (a_smu, b_smu, copymu, copyml)

    external scale' : float -> t -> int * int * int -> unit
        = "c_arraybandmatrix_scale"

    let scale c a smu mu ml = scale' c a (mu, ml, smu)

    external add_identity : t -> int -> unit
        = "c_arraybandmatrix_add_identity"

    external matvec' : t -> int * int * int -> real_array -> real_array -> unit
        = "c_arraybandmatrix_matvec"

    let matvec a smu mu ml ~x ~y = matvec' a (mu, ml, smu) x y

    external gbtrf' : t -> int * int * int -> lint_array -> unit
        = "c_arraybandmatrix_gbtrf"

    let gbtrf a smu mu ml p = gbtrf' a (mu, ml, smu) p

    external gbtrs'
        : t -> int * int -> lint_array -> real_array -> unit
        = "c_arraybandmatrix_gbtrs"

    let gbtrs a smu ml p b = gbtrs' a (smu, ml) p b
  end

