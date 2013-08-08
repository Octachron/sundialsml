open Pprint
open Pprint_sundials

let (@@) = Fstream.append

(* Controls the size of the generated test case.  *)
let size = ref 5

(* Generation & shrinking *)
let gen_nat () = Random.int (max 1 !size)
let gen_pos () = gen_nat () + 1
let gen_int () = let size = max !size 1 in
                 Random.int (size * 2) - size

(* Rearrange as gen -> shrink -> gen -> shrink.  Make gen_* for each type of
   time value.  Algorithm taken from Haskell's quickcheck.  *)
let shrink_int n =
  (* abs k < abs n, but taking care of overflow.  *)
  let less_complex k =
    match k >= 0, n >= 0 with
    | true, true   -> k < n
    | false, false -> k > n
    | false, true  -> k+n > 0
    | true, false  -> k+n < 0
  in
  Fstream.guard1 (n < -n) (- n)
  @@ Fstream.filter less_complex
     (Fstream.of_list [0;1;2]
      @@ Fstream.filter (fun x -> x <> 0 && x <> 1 && x <> 2)
         (Fstream.take_while less_complex
            (Fstream.map (fun higher_bits -> n - higher_bits)
               (Fstream.iterate (fun x -> x / 2) n))))

let shrink_nat n = Fstream.map abs (shrink_int n)
let shrink_pos n = Fstream.map ((+) 1) (shrink_nat (n-1))

(* Generators and shrinkers for different kinds of time values.  Time values
   can occur in several places in a script:

   - the query time of SolveNormal

   - the time of the zero of a root function

   - the stop time

   We have to make sure that these three types of events are mutually disjoint,
   because otherwise the order in which IDA detects them is dictated by
   floating point error and is unpredictable.

   We therefore:

   - discretize the time values, i.e. make them a multiple of a fixed value
     called discrete_unit

   - offset each type of time value by a sub-discrete_unit value, so that
     e.g. the stop time is always distinct from a query time modulo
     discrete_unit.

 *)
let discrete_unit = 1.
let query_time_offs = 0.
let root_time_offs = discrete_unit /. 2.
let stop_time_offs = discrete_unit /. 4.

(* This must be smaller than any of the offsets.  *)
let time_epsilon = discrete_unit /. 8.

type sign = Positive | NonNegative | ArbitrarySign
(* Returns (gen, shrink) *)
let discrete_float_type ?(sign=NonNegative) offset =
  let gen_rank, shrink_rank =
    match sign with
    | Positive -> gen_pos, shrink_pos
    | NonNegative -> gen_nat, shrink_nat
    | ArbitrarySign -> gen_int, shrink_int
  in
  ((fun () -> float_of_int (gen_rank ()) *. discrete_unit +. offset),
   (fun f ->
     Fstream.map
       (fun x -> float_of_int x *. discrete_unit +. offset)
       (shrink_rank (int_of_float ((f -. offset) /. discrete_unit)))))

let gen_t0, shrink_t0 = discrete_float_type 0.
let gen_query_time, shrink_query_time = discrete_float_type query_time_offs
let gen_root_time, shrink_root_time = discrete_float_type root_time_offs
let gen_stop_time, shrink_stop_time = discrete_float_type stop_time_offs

(* Similar arrangement for non-time values.  *)
let gen_discrete_float, shrink_discrete_float = discrete_float_type 0.

(* Choose a generator from an array and call it.  *)
let gen_choice choices =
  choices.(Random.int (Array.length choices))

let enum istart iend =
  let rec go acc i =
    if istart <= i then go (i::acc) (i-1)
    else acc
  in go [] iend

let gen_list g = List.map (fun _ -> g ()) (enum 1 (gen_nat ()))
let rec shrink_list shrink_elem = function
  | [] -> Fstream.of_list []
  | x::xs ->
    Fstream.cons xs
      (Fstream.map (fun xs -> x::xs) (shrink_list shrink_elem xs)
       @@ Fstream.map (fun x -> x::xs) (shrink_elem x))

(** Generate a list of values that satisfy an invariant which can be checked by
    scanning the list once, in order.

    [gen_1pass_list gen seed] returns {[[y1, y2, ..., yn]]} where
    [(seed1, y1) = gen seed,
     (seed2, y2) = gen seed1,
     (seed3, y3) = gen seed2,
     ...].

    [gen x] should produce a value taking into account some information [x]
    about previously generated elements, and return that value along with [x]
    updated with information about the new value.  [seed] is the initial value
    of [x].

    For example, [gen_1pass_list (fun x -> let x = gen_nat () + x in (x,x)) 0]
    generates non-strictly increasing lists of natural numbers.

 *)
let gen_1pass_list gen seed =
  (* In haskell notation,
     let (seeds_tl, ys) = unzip $ map gen seeds
         seeds = seed:seeds_tl
     in take (gen_nat ()) ys
   *)
  let rec seeds_tl_and_ys = lazy (Fstream.unzip (Fstream.map gen seeds))
  and seeds = lazy (Fstream.Cons (seed, fst (Lazy.force seeds_tl_and_ys))) in
  Fstream.to_list
    (Fstream.take (gen_nat ()) (snd (Lazy.force seeds_tl_and_ys)))

(** Shrink a list of values while maintaining an invariant that can be checked
    by scanning the list once, in order.

    {[shrink_1pass_list shrink fixup seed xs]} assumes [shrink] and [fixup] are
    purely functional.  It must be the case that [xs] is one of the lists that
    can be produced by [gen_1pass_list gen seed] using the same [seed] and some
    impure function [gen]; the shrunk lists will also be such lists.

    [shrink] is a function that shrinks one element of the list.  [shrink s x]
    should produce some or all of the possible return values of [gen s] whose
    [snd]'s are "smaller" than [x].

    [fixup] is used when an element of the list is shrunk.  Its job is to
    update all subsequent elements and restore the invariant if it is broken.
    [fixup s x] should produce one of the possible return values of [gen s].
    The [snd] of the return value need not be "smaller" than [x], but it should
    be equal to [x] whenever possible (i.e. it should return [x] as-is if it
    already satisfies the invariant).  Unlike [gen], [fixup] can (and probably
    should) be purely functional.

    Currently, [shrink_1pass_list] enumerates lists produced by the following
    procedure: either drop an element of the list or replace it by a smaller
    value produced by [shrink]; then pass [fixup] through the whole list to
    restore any invariants broken by shrinking.

 *)
let shrink_1pass_list shrink fixup seed xs =
  let rec fixup_list seed acc = function
    | [] -> List.rev acc
    | x::xs -> let (seed, x) = fixup seed x in
               fixup_list seed (x::acc) xs
  and go seed = function
    | [] -> Fstream.nil
    | x::xs ->
      Fstream.cons (fixup_list seed [] xs)     (* drop x *)
        (Fstream.map                           (* keep x *)
           (fun xs -> x::xs)
           (go (fst (fixup seed x)) xs)
         @@ Fstream.map                        (* shrink x *)
             (fun (seed, x) -> x::fixup_list seed [] xs)
             (shrink seed x))
  in
  go seed xs

let gen_array ?(size=gen_pos ()) gen_elem =
  let v = Array.make size (gen_elem ()) in
  for i = 1 to size-1 do
    v.(i) <- gen_elem ()
  done;
  v

(* Remove duplicates without reordering.  *)
let uniq_list ls =
  let seen = Hashtbl.create 10 in
  let rec go acc = function
    | [] -> List.rev acc
    | x::xs when Hashtbl.mem seen x -> go acc xs
    | x::xs -> Hashtbl.add seen x (); go (x::acc) xs
  in go [] ls

let uniq_array a =
  let seen = Hashtbl.create 10 in
  let b = Array.copy a in
  let bsize = ref 0 in
  for i = 0 to Array.length a - 1 do
    if not (Hashtbl.mem seen a.(i)) then
      (b.(!bsize) <- a.(i);
       bsize := !bsize + 1;
       Hashtbl.add seen a.(i) ())
  done;
  Array.sub b 0 !bsize

(* Shrinking.  Some of the algorithms are adapted from Haskell's QuickCheck.
   Keep in mind that the shrink-and-test cycle requires all shrinkers to ensure
   the outputs are strictly simpler than the input in some sense.  *)

let shrink_pair shrink_x shrink_y (x,y) =
  Fstream.map (fun x -> (x,y)) (shrink_x x)
  @@ Fstream.map (fun y -> (x,y)) (shrink_y y)

let shrink_fixed_size_list shrink_elem = function
  | [] -> Fstream.of_list []
  | x::xs ->
    Fstream.map (fun xs -> x::xs) (shrink_list shrink_elem xs)
    @@ Fstream.map (fun x -> x::xs) (shrink_elem x)

let shrink_array shrink_elem a =
  Fstream.map Array.of_list (shrink_list shrink_elem (Array.to_list a))

let shrink_bigarray1 ?(shrink_size=true) shrink_elem a =
  let open Bigarray in
  let n = Array1.dim a in
  let create = Array1.create (Array1.kind a) (Array1.layout a) in
  let copy () =
    let b = create (n - 1) in
    for j = 0 to n-1 do
      b.{j} <- a.{j}
    done;
    b
  and drop i =
    let b = create (n - 1) in
    for j = 0 to i-1 do
      b.{j} <- a.{j}
    done;
    for j = i+1 to n-1 do
      b.{j} <- a.{j}
    done;
    b
  in
  let shrink_at i =
    Fstream.map (fun ai -> let a = copy () in
                          a.{i} <- ai; a)
      (shrink_elem a.{i})
  in
  Fstream.guard shrink_size (Fstream.map drop
                              (Fstream.enum 0 (Bigarray.Array1.dim a)))
  @@ Fstream.concat (Fstream.map shrink_at (Fstream.enum 0 (n-1)))


(** A property is a function from some type ['a] to a ['b test_result].  The
    test result [OK] means the property holds for that data, [Falsified foo]
    means the data falsifies the property, where [foo] is a user-defined
    description of why/how it was falsified, and [Failed] means the property
    raised an exception.  Properties should not return [Failed] but rather let
    exceptions propagate; the quickcheck framework catches them and conerts
    them to [Failed].
 *)
type ('a,'b) property = 'a -> 'b test_result
and  'reason test_result = OK | Falsified of 'reason | Failed of exn

let isOK = function
  | OK -> true
  | _ -> false

(** Convert a function of type ['a -> bool] to a property.  *)
let boolean_prop prop x =
  if prop x then OK
  else Falsified ()

(** A formatter that performs no output.  Useful for disabling output from
    {!quickcheck}, {!minimize}, etc.  *)
let null_formatter = Format.make_formatter (fun _ _ _ -> ()) (fun _ -> ())

(** A shrinker that always fails to produce a shrunk value.  Used as a stub
    when you can't supply a shrinking function.  *)
let no_shrink _ = Fstream.nil

let test_in_sandbox prop x =
  try prop x
  with exn -> Failed exn

(** [minimize shrink prop x reason] minimizes a counterexample [x] of property
    [prop].  [reason] is the return value of [prop x] and is returned when no
    counterexample smaller than [x] is found.  It's up to the caller to ensure
    [reason <> OK]; this function just assumes that's the case.

    If the optional argument [pp_input] is supplied, it is used to print each
    shrunk test case before trying it, along with additional output.  The
    optional argument [pp_formatter] tells where to direct this output.

    Returns (<number of shrinks performed>, <shrunk data>, <prop result>)
 *)
let minimize ?pp_input ?(pp_formatter=Format.err_formatter) shrink prop x res =
  let trace, pp_input =
    match pp_input with
    | Some s -> true, s
    | None -> false, (fun _ -> failwith "internal error")
  in
  if trace then Format.pp_print_char pp_formatter '\n';
  let rec go ct x reason =
    let failure x =
      let res = test_in_sandbox prop x in
      if trace then
        (Format.fprintf pp_formatter "Trying: ";
         pp_input pp_formatter x;
         Format.fprintf pp_formatter "\n -> %s\n"
           (if isOK res then "triggers bug"
            else "not a counterexample"));
      if res = OK then None
      else Some (x, res)
    in
    match Fstream.find_some failure (shrink x) with
    | None -> (ct, x, reason)
    | Some (x, reason) -> go (ct+1) x reason
  in go 0 x res

(** Returns an input that fails the property with the return value of the
    property, or lack thereof.  The optional arguments, if specified, dumps
    intermediate results; see {!minimize} for what they mean.  *)
let quickcheck gen shrink ?pp_input ?(pp_formatter=Format.err_formatter)
    prop max_tests =
  let old_size = !size in
  let minimize x res =
    if shrink == no_shrink then (x, res)
    else
      begin
        Printf.fprintf stderr "Shrinking...";
        flush stderr;
        let (ct, x, res) =
          minimize ?pp_input ~pp_formatter shrink prop x res
        in
        Printf.fprintf stderr "%d shrinks.\n" ct;
        flush stderr;
        (x, res)
      end
  in
  let trace, pp_input =
    match pp_input with
    | Some pp_input -> true, pp_input
    | None -> false, (fun _ -> failwith "internal error")
  in
  let rec test num_passed =
    let gen () =
      try size := num_passed; gen ()
      with exc ->
        Printf.fprintf stderr
          "Error: the generator failed (after %d tests)\n%s\n"
          num_passed (Printexc.to_string exc);
        size := old_size;
        raise exc
    in
    let check_for_bug x =
      if trace then
        (Format.fprintf pp_formatter "Testing ";
         pp_input pp_formatter x;
         Format.pp_print_newline pp_formatter ());
      let res = test_in_sandbox prop x in
      match res with
      | OK -> res
      | Falsified _ ->
        Printf.fprintf stderr "Failed! (after %d test(s))\n" num_passed;
        flush stderr;
        if trace then
          (Format.pp_print_string pp_formatter "Counterexample was: ";
           pp_input pp_formatter x;
           Format.pp_print_newline pp_formatter ());
        res
      | Failed exc -> 
        Printf.fprintf stderr
          "Failed! Exception raised (after %d test(s)):\n%s\n"
          num_passed
          (Printexc.to_string exc);
        flush stderr;
        res
    in
    if num_passed < max_tests then
      let x = gen () in
      match check_for_bug x with
      | OK -> print_char '*'; flush stdout; test (num_passed + 1)
      | res -> Some (minimize x res)
    else
      (Printf.printf "\n+++ OK, passed %d tests." max_tests;
       None)
  in
  let ret = test 0 in
  size := old_size;
  ret


(* Types and functions for modeling IDA.  *)
module IdaModel =
struct
  module Carray = Sundials.Carray
  type cmd = SolveNormal of float       (* NB: carries dt, not t *)
             | GetRootInfo
  type result = Unit | Int of int | Float of float
                | Any
                | Type of result
                | Aggr of result list
                | Carray of Carray.t    (* NB: always copy the array! *)
                | SolverResult of Ida.solver_result
                | Exn of exn
                | RootInfo of Ida.Roots.t
  type resfn_type = ResFnLinear of Carray.t

  let carray x = Carray (Carray.of_carray x)

  (* Whole-test results *)
  type failure_type = ResultMismatch of int * result * result
                      | TestCodeDied of result list
                      | TestCodeOverrun
  type test_result = OK | Failed of failure_type

  let cmp_eps = ref 1e-5

  let pp_cmd, dump_cmd, show_cmd, display_cmd, print_cmd, prerr_cmd =
    printers_of_pp (fun fmt -> function
    | SolveNormal f ->
      Format.fprintf fmt "SolveNormal ";
      if f < 0. then Format.fprintf fmt "(";
      pp_float fmt f;
      if f < 0. then Format.fprintf fmt ")"
    | GetRootInfo -> Format.fprintf fmt "GetRootInfo"
    )
  let pp_cmds, dump_cmds, show_cmds, display_cmds, print_cmds, prerr_cmds =
    printers_of_pp (fun fmt cmds ->
      if !read_write_invariance then pp_list pp_cmd fmt cmds
      else
        (* List one command per line, with step numbers starting from 0.  *)
        let nsteps = List.length cmds in
        let step_width = String.length (string_of_int (nsteps - 1)) in
        let pad_show n = let s = string_of_int n in
                         String.make (step_width - String.length s) ' ' ^ s
        in
        pp_seq "[" ";" "]" fmt
          (Fstream.mapi (fun i cmd fmt ->
            Format.fprintf fmt "Step %s: " (pad_show i);
            pp_cmd fmt cmd)
             (Fstream.of_list cmds)))

  let show_solver s =
    let solver_name = function
    | Ida.Dense -> "Dense"
    | Ida.Band range -> Printf.sprintf "Band { mupper=%d; mlower=%d }"
                                       range.Ida.mupper range.Ida.mlower
    | Ida.Sptfqmr _ | Ida.Spbcg _ | Ida.Spgmr _
    | Ida.LapackBand _ | Ida.LapackDense _ ->
      raise (Failure "linear solver not implemented")
    in
    if !read_write_invariance then "Ida." ^ solver_name s
    else solver_name s

  let dump_solver solver =
    with_read_write_invariance (fun () -> show_solver solver)

  let show_root_event x =
    let prefix = if !read_write_invariance then "Ida.Roots." else "" in
    prefix ^ Ida.Roots.string_of_root_event x

  let pp_ida_ident fmt ident =
    if !read_write_invariance then Format.fprintf fmt "Ida.%s" ident
    else Format.fprintf fmt "%s" ident

  let pp_result, dump_result, show_result, display_result,
    print_result, prerr_result =
    let rec pre_pp_result arg_pos fmt = function
      | Any -> Format.fprintf fmt "_"
      | Unit -> Format.fprintf fmt "()"
      | Int i -> pp_parens (arg_pos && i < 0) fmt (fun fmt -> pp_int fmt i)
      | Float f -> pp_parens (arg_pos && f < 0.) fmt
                      (fun fmt -> pp_float fmt f)
      | Type r -> pp_parens arg_pos fmt (fun fmt ->
                    pp_ida_ident fmt "Type ";
                    pre_pp_result true fmt r)
      | Carray ca -> pp_carray fmt ca
      | SolverResult Ida.Continue -> pp_ida_ident fmt "Continue"
      | SolverResult Ida.RootsFound -> pp_ida_ident fmt "RootsFound"
      | SolverResult Ida.StopTimeReached -> pp_ida_ident fmt "StopTimeReached"
      | RootInfo roots -> pp_parens arg_pos fmt (fun fmt ->
                            pp_string_verbatim fmt "RootInfo ";
                            pp_root_info fmt roots)
      | Aggr rs -> pp_parens arg_pos fmt (fun fmt ->
                     pp_string_verbatim fmt "Aggr ";
                     pp_list (pre_pp_result false) fmt rs)
      | Exn exn -> pp_parens arg_pos fmt (fun fmt ->
                     pp_string_verbatim fmt "exception ";
                     pp_string_verbatim fmt (Printexc.to_string exn))
    in printers_of_pp (pre_pp_result false)
  let pp_results, dump_results, show_results, display_results,
    print_results, prerr_results =
    printers_of_pp (pp_list pp_result)

  let pp_resfn_type, dump_resfn_type, show_resfn_type, display_resfn_type,
    print_resfn_type, prerr_resfn_type
      =
    printers_of_pp
    (fun fmt -> function
     | ResFnLinear slope -> pp_string_verbatim fmt "ResFnLinear ";
                            pp_carray fmt slope
    )

  (* Check if r1 is a valid approximation of r2.  *)
  let rec result_matches r1 r2 =
    match r1, r2 with
    | Any, _ -> true
    | _, Any -> raise (Invalid_argument "result_matches: wild card on rhs")
    | Type t, _ -> result_type_matches t r2
    | Unit, Unit -> true
    | Int i1, Int i2 -> i1 = i2
    | Float f1, Float f2 -> abs_float (f1 -. f2) < !cmp_eps
    | Aggr l1, Aggr l2 -> for_all2_and_same_len result_matches l1 l2
    | Carray v1, Carray v2 -> carrays_equal v1 v2
    | SolverResult r1, SolverResult r2 -> r1 = r2
    | Exn e1, Exn e2 -> exns_equal e1 e2
    | RootInfo r1, RootInfo r2 -> r1 = r2
    | _, _ -> false
  and result_type_matches r1 r2 =
    match r1, r2 with
    | Any, _ -> true
    | Type t, _ -> raise (Invalid_argument "result_matches: nested Type")
    | Unit, Unit -> true
    | Int _, Int _ -> true
    | Float _, Float _ -> true
    | Aggr l1, Aggr l2 -> for_all2_and_same_len result_type_matches l1 l2
    | Carray _, Carray _ -> true
    | SolverResult _, SolverResult _ -> true
    | RootInfo _, RootInfo _ -> true
    | Exn e1, Exn e2 -> raise (Invalid_argument "result_matches: Type Exn")
    | _, Any | _, Type _ ->
      raise (Invalid_argument "result_matches: wild card on rhs")
    | _, _ -> false
  and for_all2_and_same_len f r1 r2 =
    match r1, r2 with
    | [], [] -> true
    | x::xs, y::ys -> f x y && for_all2_and_same_len f xs ys
    | _, _ -> false
  and carrays_equal v1 v2 =
    let n = Carray.length v1 in
    let rec go i =
      if i < n then abs_float (v1.{i} -. v2.{i}) < !cmp_eps && go (i+1)
      else true
    in
    n = Carray.length v2 && go 0
  and exns_equal e1 e2 =
  (* Compare only the tags *)
    match e1, e2 with
    | Failure _, Failure _ -> true
    | Invalid_argument _, Invalid_argument _ -> true
    | _, _ -> e1 = e2

  let is_exn = function
    | Exn _ -> true
    | _ -> false
  let not_exn x = not (is_exn x)
  let shrink_carray = shrink_bigarray1
end
