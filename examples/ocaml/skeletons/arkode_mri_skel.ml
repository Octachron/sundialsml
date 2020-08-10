open Sundials

(* 1. Define right-hand-side functions. *)
let fs t y yd = yd.{0} <- y.{1}
let ff t y yd = yd.{1} <- -9.81

(* 2. Optionally define a root function. *)
let g t y gout = gout.{0} <- 1.0 -. y.{0}

(* 3. Set vector of initial values.
      The length of this vector determines the problem size. *)
let yd = RealArray.of_list [ 10.0; 0.0 ]
let y = Nvector_serial.wrap yd

(* 4. Create and initialize a solver session. *)
let s = Arkode.MRIStep.(init ~slow:fs ~fast:ff ~roots:(1, g) 0.0 y);;

(* 5. Set optional inputs, e.g.,
      call [set_*] functions to change solver parameters. *)
Arkode.MRIStep.set_stop_time s 10.0;;
Arkode.MRIStep.set_all_root_directions s RootDirs.Increasing;;

(* 6. Advance the solution in time,
      by repeatedly calling [solve_normal] or [solve_one_step]. *)
let rec go (t, r) =
  Printf.printf "% .10e\t% .10e\t% .10e\n" t yd.{0} yd.{1};
  match r with
  | Arkode.Success -> go (Arkode.MRIStep.solve_normal s (t +. 0.5) y)
  | Arkode.RootsFound -> begin
        yd.{1} <- -0.8 *. yd.{1};
        Arkode.MRIStep.reinit s t y;
        go (t, Arkode.Success)
      end
  | Arkode.StopTimeReached -> ();;

Printf.printf "time\ty\ty'\n";;
go (0.0, Arkode.Success);;

(* 7. Get optional outputs,
      call the [get_*] functions to examine solver statistics. *)
let ns = Arkode.MRIStep.get_num_steps s
