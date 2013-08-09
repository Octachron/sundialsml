module Ida = Ida_serial
module Carray = Ida_serial.Carray
module Roots = Ida.Roots
open Pprint
open Quickcheck
open Quickcheck_ida
open Camlp4.PreCast


(* The test code is generated by Camlp4 and compiled and run in a separate
   process.  This is done for two reasons:

    - In the worst case, IDA segfaults and this is hard to catch cleanly in
      OCaml.  Running it in a separate process saves the main driver loop from
      crashing together with the test case, so that it can shrink and re-run
      the test case.

    - Once we find a bug, we have to present a test case to the user, and a
      directly compilable .ml file is the best way to do it.  So we need code
      generation anyway.  *)

let _loc = Loc.ghost

let semis when_empty ctor = function
  | [] -> when_empty
  | e::es -> ctor (List.fold_left (fun e1 e2 -> Ast.ExSem (_loc, e1, e2)) e es)
let expr_array es = semis <:expr<[||]>> (fun e -> Ast.ExArr (_loc, e)) es
let expr_seq es = semis <:expr<()>> (fun e -> Ast.ExSeq (_loc, e)) es
let expr_of_carray v =
  let n = Carray.length v in
  if n = 0 then <:expr<Carray.create 0>>
  else <:expr<Carray.of_array
              $expr_array (List.map (fun i -> <:expr<$`flo:v.{i}$>>)
                            (enum 0 (n-1)))$>>
let expr_of_linear_solver = function
  | Ida.Dense -> <:expr<Ida.Dense>>
  | Ida.Band range -> <:expr<Ida.Band
                             { Ida.mupper = $`int:range.Ida.mupper$;
                               Ida.mlower = $`int:range.Ida.mlower$; }>>
  | Ida.Sptfqmr _ | Ida.Spbcg _ | Ida.Spgmr _
  | Ida.LapackBand _ | Ida.LapackDense _ ->
    raise (Failure "linear solver not implemented")

let expr_of_resfn neqs = function
  | ResFnLinear slopes ->
    (* forall i. vec.{i} = slopes.{i}*t *)
    let set i = <:expr<res.{$`int:i$}
                         <- vec'.{$`int:i$} -. $`flo:slopes.{i}$>>
    in <:expr<fun t vec vec' res ->
               $expr_seq (List.map set (enum 0 (neqs-1)))$>>

let expr_of_roots roots =
  let n = Array.length roots in
  let set i =
    match roots.(i) with
    | r, Roots.Rising -> <:expr<g.{$`int:i$} <- t -. $`flo:r$>>
    | r, Roots.Falling -> <:expr<g.{$`int:i$} <- $`flo:r$ -. t>>
    | _, Roots.NoRoot -> assert false
  in
  let f ss i = <:expr<$ss$; $set i$>> in
  if n = 0 then <:expr<Ida.no_roots>>
  else <:expr<($`int:n$,
               (fun t vec vec' g ->
                  $Fstream.fold_left f (set 0)
                    (Fstream.enum 1 (n-1))$))>>

let expr_of_root_direction = function
  | RootDirs.Increasing -> <:expr<Ida.RootDirs.Increasing>>
  | RootDirs.Decreasing -> <:expr<Ida.RootDirs.Decreasing>>
  | RootDirs.IncreasingOrDecreasing ->
    <:expr<Ida.RootDirs.IncreasingOrDecreasing>>

(* Generate the test code that executes a given command.  *)
let expr_of_cmd = function
  | SolveNormal t ->
    <:expr<let tret, flag = Ida.solve_normal session $`flo:t$ vec vec' in
           Aggr [Float tret; SolverResult flag; carray vec; carray vec']>>
  | GetRootInfo ->
    <:expr<let roots = Ida.Roots.create (Ida.nroots session) in
           Ida.get_root_info session roots;
           RootInfo roots>>
  | GetNRoots ->
    <:expr<Int (Ida.nroots session)>>
  | SetAllRootDirections dir ->
    <:expr<Ida.set_all_root_directions session $expr_of_root_direction dir$;
           Unit>>
  | SetRootDirection dirs ->
    <:expr<Ida.set_root_direction session
           $expr_array (List.map expr_of_root_direction (Array.to_list dirs))$;
           Unit>>

let expr_of_cmds = function
  | [] -> <:expr<()>>
  | cmds ->
    let sandbox exp = <:expr<output (lazy $exp$)>> in
    expr_seq (List.map (fun cmd -> sandbox (expr_of_cmd cmd))
                cmds)

let ml_of_script (model, cmds) =
  let nsteps = List.length cmds in
  let step_width = String.length (string_of_int nsteps) in
  let step_fmt = "step %" ^ string_of_int step_width ^ "d: " in
  let init_str = "init:  " ^ String.make step_width ' ' in
  <:str_item<
    module Ida = Ida_serial
    module Carray = Ida.Carray
    open Quickcheck_ida
    open Pprint
    let marshal_results = ref false
    let step = ref 0
    let output thunk =
      let r = try Lazy.force thunk with exn -> Exn exn in
      if !marshal_results
      then Marshal.to_channel stdout r []
      else
        begin
          (match !step, !read_write_invariance with
          | 0, false ->
            Format.print_string $`str:init_str$;
            print_result r
          | 0, true -> print_result r
          | s, false ->
            Format.printf $`str:("@," ^ step_fmt)$ s;
            print_result r
          | s, true ->
            Format.printf ";@,";
            print_result r);
          step := !step + 1
        end
    let vec  = $expr_of_carray model.vec0$
    let vec' = $expr_of_carray model.vec'0$
    let session = Ida.init_at_time
                  $expr_of_linear_solver model.solver$
                  $expr_of_resfn (Carray.length model.vec0) model.resfn$
                  $expr_of_roots model.roots$
                  $`flo:model.t0$
                  vec vec'
    let test () =
      output (lazy (Aggr [Float (Ida.get_current_time session);
                          carray vec; carray vec']));
      $expr_of_cmds cmds$
    let _ =
      Arg.parse
        [("--marshal-results", Arg.Set marshal_results,
          "For internal use only");
         ("--read-write-invariance", Arg.Set read_write_invariance,
          "print data in a format that can be fed to ocaml toplevel")]
        (fun _ -> ()) "a test case generated by quickcheck";
      if not !marshal_results then
        (if !read_write_invariance then Format.printf "@[[@[<v>"
         else Format.printf "@[<v>");
      test ();
      if not !marshal_results then
        (if !read_write_invariance then Format.printf "@]]@."
         else Format.printf "@.")
   >>

let randseed =
  Random.self_init ();
  ref (Random.int ((1 lsl 30) - 1))

let ml_file_of_script script src_file =
  Camlp4.PreCast.Printers.OCaml.print_implem ~output_file:src_file
    (ml_of_script script);
  let chan = open_out_gen [Open_text; Open_append; Open_wronly] 0 src_file in
  Printf.fprintf chan "\n(* generated with random seed %d, test case %d *)\n"
    !randseed !test_case_number;
  close_out chan

;;
let _ =
  let max_tests = ref 50 in
  let options = [("--exec-file", Arg.Set_string test_exec_file,
                  "test executable name \
                   (must be absolute, prefixed with ./, or on path)");
                 ("--failed-file", Arg.Set_string test_failed_file,
                  "file in which to dump the failed test case");
                 ("--compiler", Arg.Set_string test_compiler,
                  "compiler name with compilation options");
                 ("--rand-seed", Arg.Set_int randseed,
                  "seed value for random generator");
                 ("--verbose", Arg.Set verbose,
                  "print every test script before trying");
                 ("--read-write-invariance", Arg.Set read_write_invariance,
                  "print data in a format that can be fed to ocaml toplevel");
                ] in
  Arg.parse options (fun n -> max_tests := int_of_string n)
    "randomly generate programs using IDA and check if they work as expected";

  Printf.printf "random generator seed value = %d\n" !randseed;
  flush stdout;
  Random.init !randseed;
  size := 1;
  quickcheck_ida ml_file_of_script !max_tests

