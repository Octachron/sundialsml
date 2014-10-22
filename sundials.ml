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

external format_float : string -> float -> string
    = "caml_format_float"

let floata = format_float "%a"

exception RecoverableFailure
exception NonPositiveEwt

type ('data, 'kind) nvector = ('data, 'kind) Nvector.t

(* Note the type annotations are redundant because there's already a .mli, but
   explicit annotations improve performance for bigarrays.  *)
module RealArray =
  struct
    open Bigarray

    let kind = float64
    let layout = c_layout
    type t = (float, float64_elt, c_layout) Array1.t

    let create : int -> t = Array1.create kind layout
    let of_array : float array -> t = Array1.of_array kind layout

    let fill : t -> float -> unit = Array1.fill

    let make size x =
      let a = create size in
      fill a x;
      a

    let init size f =
      let a = create size in
      for i = 0 to size - 1 do
        a.{i} <- f i
      done;
      a

    let length : t -> int = Array1.dim

    let blit_some src isrc dst idst len =
      if len < 0 || isrc < 0 || isrc + len >= length src
         || idst < 0 || idst + len >= length dst
      then invalid_arg "RealArray.blit_some";
      for k = 0 to len - 1 do
        Array1.unsafe_set dst (idst + k) (Array1.unsafe_get src (isrc + k))
      done

    let blit = Array1.blit

    let copy src =
      let dst = create (length src) in
      Array1.blit src dst;
      dst

    let sub = Array1.sub

    let of_list src = of_array (Array.of_list src)

    let to_list v =
      let rec go ls i =
        if i < 0 then ls
        else go (v.{i}::ls) (i-1)
      in go [] (length v - 1)

    let into_array (src : t) dst =
      let n = length src in
      if n <> Array.length dst
        then invalid_arg "into_array: array sizes do not match";
      for i = 1 to n-1 do
        dst.(i) <- src.{i}
      done

    let to_array (v : t) =
      let n = length v in
      let a = Array.make n v.{0} in
      for i = 1 to n-1 do
        a.(i) <- v.{i}
      done;
      a

    let fold_left f b (v : t) =
      let n = length v in
      let rec go acc i =
        if i < n then go (f acc v.{i}) (i+1)
        else acc
      in go b 0

    let fold_right f (v : t) b =
      let rec go acc i =
        if i >= 0 then go (f v.{i} acc) (i-1)
        else acc
      in go b (length v - 1)

    let iter f (v : t) =
      for i = 0 to (length v - 1) do
        f v.{i}
      done

    let map f (v : t) =
      for i = 0 to (length v - 1) do
        v.{i} <- f v.{i}
      done

    let iteri f (v : t) =
      for i = 0 to (length v - 1) do
        f i v.{i}
      done

    let mapi f (v : t) =
      for i = 0 to (length v - 1) do
        v.{i} <- f i v.{i}
      done
  end

module RealArray2 =
  struct
    open Bigarray

    type data = (float, float64_elt, c_layout) Array2.t

    let make_data = Array2.create float64 c_layout

    type t = data * Obj.t

    external wrap : data -> t
      = "c_sundials_realarray2_wrap"

    let unwrap = fst

    let create nr nc =
      let d = Array2.create float64 c_layout nc nr
      in wrap d

    let make nr nc v =
      let d = Array2.create float64 c_layout nc nr
      in
      Array2.fill d v;
      wrap d

    let size a =
      let d = unwrap a in
      (Array2.dim1 d, Array2.dim2 d)

    let get x i j = Array2.get (unwrap x) j i
    let set x i j = Array2.set (unwrap x) j i

    let col x j = Array2.slice_left (unwrap x) j

    let copy a =
      let d = unwrap a in
      let c = Array2.dim1 d in
      let r = Array2.dim2 d in
      let d' = Array2.create float64 c_layout c r in
      Array2.blit d d';
      wrap d'

    let blit a1 a2 =
      Array2.blit (unwrap a1) (unwrap a2)
  end


(* Opaque arrays *)

module type ArrayBaseOps =
  sig
    type t
    type elt
    val error_name : string
    val create : int -> t
    val get : t -> int -> elt
    val set : t -> int -> elt -> unit
    val length : t -> int
  end

module ArrayLike (A : ArrayBaseOps) =
  struct
    include A

    let make n x =
      let a = create n in
      for i = 0 to n-1 do
        set a i x
      done;
      a

    let copy a =
      let n = length a in
      let b = create n in
      for i = 0 to n-1 do
        set b i (get a i)
      done;
      b

    let fold_left f x a =
      let n = length a in
      let rec go x i =
        if i >= n then x
        else go (f x (get a i)) (i+1)
      in go x 0

    let fold_right f a x =
      let rec go x i =
        if i < 0 then x
        else go (f (get a i) x) (i-1)
      in go x (length a - 1)

    let iteri f a =
      for i = 0 to length a - 1 do
        f i (get a i)
      done

    let iter f a = iteri (fun _ x -> f x) a

    let mapi f a =
      let n = length a in
      let b = create n in
      for i = 0 to n-1 do
        set b i (f i (get a i))
      done;
      b

    let map f a = mapi (fun _ x -> f x) a

    let mapi_overwrite f a =
      for i = 0 to length a - 1 do
        set a i (f i (get a i))
      done;
      a

    let map_overwrite f a = mapi_overwrite (fun _ x -> f x) a

    let of_array a =
      let n = Array.length a in
      let b = create n in
      for i = 0 to n-1 do
        set b i a.(i)
      done;
      b

    let of_list a =
      let n = List.length a in
      let b = create n in
      ignore (List.fold_left (fun i x -> set b i x; (i+1)) 0 a);
      b

    let to_array a =
      let n = length a in
      if n = 0 then [||]
      else
        let b = Array.make n (get a 0) in
        iteri (fun i ai -> b.(i) <- ai) a;
        b

    let to_list a = fold_right (fun x xs -> x::xs) a []

    let fill a x =
      for i = 0 to length a - 1 do
        set a i x
      done

    let blit_some a oa b ob len =
      let na = length a
      and nb = length b in
      if len < 0 || oa < 0 || na < oa+len || ob < 0 || nb < ob+len
      then invalid_arg (Printf.sprintf "%s.blit" error_name)
      else
        for i = 0 to len-1 do
          set b (ob + i) (get a (oa + i))
        done

    let blit a b =
      for i = 0 to min (length a) (length b) - 1 do
        set b i (get a i)
      done

    let init n f =
      let a = create n in
      for i = 0 to n-1 do
        set a i (f i)
      done;
      a
  end

(* root arrays *)

module LintArray =
  struct
    open Bigarray

    type t = (int, int_elt, c_layout) Array1.t

    let create = Array1.create int RealArray.layout

    let make n x =
      let v = create n in
      Array1.fill v x;
      v

  end

module Roots =
  struct
    open Bigarray
    type t = (int32, int32_elt, c_layout) Array1.t

    type r =
      | NoRoot
      | Rising
      | Falling

    let root_of_int32 = function
      | 1l -> Rising
      | -1l -> Falling
      | 0l -> NoRoot
      | n ->
        failwith
          (Printf.sprintf
             "Sundials.Roots.root_of_int32: invalid root event %ld" n)

    let root_of_int = function
      |  1 -> Rising
      | -1 -> Falling
      |  0 -> NoRoot
      | n ->
        failwith
          ("Sundials.Roots.root_of_int: invalid root event " ^ string_of_int n)

    let int32_of_root x =
      match x with
      | NoRoot -> 0l
      | Rising -> 1l
      | Falling -> -1l

    let int_of_root x =
      match x with
      | NoRoot -> 0
      | Rising -> 1
      | Falling -> -1

    let reset v = Array1.fill v 0l

    let detected roots i = roots.{i} <> 0l
    let get roots i = root_of_int32 (roots.{i})
    let set a i v = a.{i} <- int32_of_root v

    let create n =
      let a = Array1.create int32 c_layout n in
      reset a;
      a

    let length = Array1.dim

    module A = ArrayLike (struct
      type t = (int32, int32_elt, c_layout) Array1.t
      and elt = r
      let error_name = "Roots"
      let get = get
      let set = set
      let create = create
      let length = length
    end)

    let make n x = A.make n x
    let copy = A.copy
    let fold_left = A.fold_left
    let fold_right = A.fold_right

    let of_array = A.of_array
    let of_list = A.of_list
    let to_array = A.to_array
    let to_list = A.to_list

    let fill = A.fill
    let blit_some = A.blit_some
    let blit = A.blit

    let rising  roots i = roots.{i} = 1l
    let falling roots i = roots.{i} = -1l

    let set_noroot a i = set a i NoRoot
    let set_rising a i = set a i Rising
    let set_falling a i = set a i Falling

    let iteri = A.iteri
    let iter = A.iter

    let exists a =
      let n = length a in
      let rec go i = a.{i} <> 0l || (i < n-1 && go (i+1)) in
      go 0
  end

module RootDirs =
  struct
    open Bigarray
    type t = (int32, int32_elt, c_layout) Array1.t

    type d =
      | Increasing
      | Decreasing
      | IncreasingOrDecreasing

    let int32_of_rootdir x =
      match x with
      | Increasing -> 1l
      | Decreasing -> -1l
      | IncreasingOrDecreasing -> 0l
    let rootdir_of_int32 x =
      match x with
      | 1l -> Increasing
      | -1l -> Decreasing
      | 0l -> IncreasingOrDecreasing
      | n ->
        failwith
          (Printf.sprintf
             "Sundials.Roots.rootdir_of_int32: invalid root direction %ld" n)

    let make n x =
      let a = Array1.create int32 c_layout n in
      Array1.fill a (int32_of_rootdir x);
      a

    let create n = make n IncreasingOrDecreasing

    let length a = Array1.dim a

    let copy n src =
      let nsrc = Array.length src in
      let a = Array1.create int32 c_layout n in
      if n > nsrc
      then Array1.fill a (int32_of_rootdir IncreasingOrDecreasing);
      for i = 0 to min n nsrc - 1 do
        a.{i} <- int32_of_rootdir src.(i)
      done;
      a

    let set a i v = a.{i} <- int32_of_rootdir v
    let get a i = rootdir_of_int32 a.{i}

    module A = ArrayLike (
      struct
        type t = (int32, int32_elt, c_layout) Array1.t
        and elt = d
        let error_name = "RootDirs"
        let create = create
        let set = set
        let get = get
        let length = length
      end)

    let of_array  = A.of_array
    let of_list   = A.of_list
    let to_array  = A.to_array
    let to_list   = A.to_list
    let fill      = A.fill
    let blit_some = A.blit_some
    let blit      = A.blit

    let init = A.init

  end

type solver_result =
  | Continue
  | RootsFound
  | StopTimeReached

type error_details = {
    error_code : int;
    module_name : string;
    function_name : string;
    error_message : string;
  }

(* Re-export constants generated by configure.  *)
let version = Sundials_config.version
let lapack_enabled = Sundials_config.lapack_enabled

(* Let C code know about some of the values in this module, and obtain
   a few parameters from the C side.  *)

external c_init_module :
  ('a Weak.t -> int -> 'a option)
  -> exn array
  -> (float * float * float)
  = "c_sundials_init_module"

let big_real, small_real, unit_roundoff =
  c_init_module Weak.get
    (* Exceptions must be listed in the same order as
       sundials_exn_index.  *)
    [|RecoverableFailure; NonPositiveEwt|]

