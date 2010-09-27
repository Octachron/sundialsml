
module Cvode = Cvode_serial
module Roots = Cvode.Roots
module Carray = Cvode.Carray

(*
 * Benoît's 'billiard à 1 dimension'
 *
 * assume:
 *   d1 <= d2 <= 0
 *
 * der(x1) = v1 init d1
 * der(x2) = v2 init d2
 * der(v1) = 0 init w1 reset
 *                     | last(v2) when up(x1 - x2)
 * der(v2) = 0 init w2 reset
 *                     | last(v1) when up(x1 - x2)
 *                     | -last(v2) when up(x2)
 *)

(* simulation parameters *)
let max_sim_time = 5.0
let max_step_size = 0.1

(* initial values *)
let d1, w1 = -5.0, 1.0
and d2, w2 = -3.0, 2.0

(* index elements of v and der *)
let x1 = 0
and x2 = 1
and v1 = 2
and v2 = 3
and n_eq = 4

(* index elements of up and up_e *)
and zc_x1minx2  = 0 (* up(x1 - x2)  *)
and zc_x2 = 1       (* up(x2) *)
and n_zc = 2

let f init      (* boolean: true => initialization *)
      up_arr    (* array of booleans: zero-crossings, value of up() *)
      v         (* array of floats: continuous state values *)
      der       (* array of floats: continuous state derivatives *)
      up_e =    (* array of floats: value of expressions inside up() *)
  begin
    if init then
      begin    (* initialization: calculate v *)
        v.{x1} <- d1;
        v.{x2} <- d2;
        v.{v1} <- w1;
        v.{v2} <- w2
      end
    else
    if Roots.exists up_arr
    then begin (* discrete mode: using up, calculate v *)
      let up = Roots.get up_arr in
      let last_v1 = v.{v1} in

      v.{v1} <- (if up(zc_x1minx2) then (* last *) v.{v2} else v.{x1});
      v.{v2} <- (if up(zc_x1minx2) then last_v1
                 else if up(zc_x2) then -. v.{x2}
                 else v.{x2})
    end
    else begin (* continuous mode: using v, calculate der *)
      der.{x1} <- v.{v1};
      der.{x2} <- v.{v2};
      der.{v1} <- 0.0;
      der.{v2} <- 0.0
    end
  end;
  begin        (* discrete and continuous: calculate up_e *)
    up_e.{zc_x1minx2} <- v.{x1} -. v.{x2};
    up_e.{zc_x2} <- v.{x2}
  end;
  true

let _ = Arg.parse (Solvelucy.args n_eq) (fun _ -> ())
        "billiard1d: 1-dimensional billiard balls"

let _ =
  print_endline "";
  print_endline "C: result of continuous solver";
  print_endline "D: result of discrete solver";
  print_endline "";
  print_endline "    up(x1 - x2)";
  print_endline "   /  up(x2)";
  print_endline "   | /";
  print_endline "   | |";
  print_endline "   | |";
  print_endline "   | |";
  print_endline "R: 0 0";
  print_endline ""

let _ = print_endline "        time\t      x\t\t      y"

let _ = Solvelucy.run_delta
          (Some max_sim_time) f (fun t -> t +. max_step_size) n_eq n_zc

