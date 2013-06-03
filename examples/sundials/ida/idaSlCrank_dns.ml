(*
 * -----------------------------------------------------------------
 * $Revision: 1.2 $
 * $Date: 2009/09/30 23:25:59 $
 * -----------------------------------------------------------------
 * Programmer: Radu Serban @ LLNL
 * -----------------------------------------------------------------
 * Simulation of a slider-crank mechanism modelled with 3 generalized
 * coordinates: crank angle, connecting bar angle, and slider location.
 * The mechanism moves under the action of a constant horizontal force
 * applied to the connecting rod and a spring-damper connecting the crank
 * and connecting rod.
 *
 * The equations of motion are formulated as a system of stabilized
 * index-2 DAEs (Gear-Gupta-Leimkuhler formulation).
 *
 * -----------------------------------------------------------------
 *)
module Ida = Ida_serial
module Carray = Ida.Carray

(* Problem Constants *)

let neq = 10
and tend = 10.0
and nout = 41

(* Output functions *)
let printf = Printf.printf
let print_header rtol atol y =
  printf "\nidaSlCrank_dns: Slider-Crank DAE serial example problem for IDAS\n";
  printf "Linear solver: IDADENSE, Jacobian is computed by IDAS.\n";
  printf "Tolerance parameters:  rtol = %g   atol = %g\n" rtol atol;
  printf "-----------------------------------------------------------------------\n";
  printf "  t            y1          y2           y3";
  printf "      | nst  k      h\n";
  printf "-----------------------------------------------------------------------\n"
let print_output mem t y =
  let kused = Ida.get_last_order mem
  and nst   = Ida.get_num_steps mem
  and hused = Ida.get_last_step mem in

  printf "%10.4e %12.4e %12.4e %12.4e %3d  %1d %12.4e\n"
         t y.{0} y.{1} y.{2} nst kused hused

let print_final_stats mem =
  let nst = Ida.get_num_steps mem
  and nre = Ida.get_num_res_evals mem
  and nje = Ida.Dls.get_num_jac_evals mem
  and nni = Ida.get_num_nonlin_solv_iters mem
  and netf = Ida.get_num_err_test_fails mem
  and ncfn = Ida.get_num_nonlin_solv_conv_fails mem
  and nreLS = Ida.Dls.get_num_res_evals mem in

  printf "\nFinal Run Statistics: \n\n";
  printf "Number of steps                    = %d\n" nst;
  printf "Number of residual evaluations     = %d\n" (nre+nreLS);
  printf "Number of Jacobian evaluations     = %d\n" nje;
  printf "Number of nonlinear iterations     = %d\n" nni;
  printf "Number of error test failures      = %d\n" netf;
  printf "Number of nonlinear conv. failures = %d\n" ncfn

type user_data =
  {
    a  : float;
    j1 : float;
    j2 : float;
    m2 : float;
    k  : float;
    c  : float;
    l0 : float;
    f  : float;
  }

let force data y qq =
  let a = data.a
  and k = data.k
  and c = data.c
  and l0 = data.l0
  and q = y.{0}
  and x = y.{1}
  and p = y.{2}
  and qd = y.{3}
  and xd = y.{4}
  and pd = y.{5} in

  let s1 = sin q
  and c1 = cos q
  and s2 = sin p
  and c2 = cos p in
  let s21 = s2*.c1 -. c2*.s1
  and c21 = c2*.c1 +. s2*.s1 in

  let l2 = x*.x -. x*.(c2+.a*.c1) +. (1. +. a*.a)/.4. +. a*.c21/.2. in
  let l = sqrt l2 in
  let ld = (2.*.x*.xd -. xd*.(c2+.a*.c1)
            +. x*.(s2*.pd+.a*.s1*.qd) -. a*.s21*.(pd-.qd)/.2.
            ) /. (2.*.l) in

  let f = k*.(l-.l0) +. c*.ld in
  let fl = f/.l in

  qq.{0} <- -. fl *. a *. (s21/.2. +. x*.s1) /. 2.;
  qq.{1} <- fl *. (c2/.2. -. x +. a*.c1/.2.) +. data.f;
  qq.{2} <- -. fl *. (x*.s2 -. a*.s21/.2.) /. 2. -. data.f*.s2

let set_ic data y y' =
  let a = data.a
  and j1 = data.j1
  and m2 = data.m2
  and j2 = data.j2
  and pi = 4. *. atan (1.)
  in

  let qq = Carray.create 3
  and q = pi/.2.
  and p = asin (-.a) in
  let x = cos p in

  y.{0} <- q;
  y.{1} <- x;
  y.{2} <- p;

  force data y qq;

  y'.{3} <- qq.{0} /. j1;
  y'.{4} <- qq.{1} /. m2;
  y'.{5} <- qq.{2} /. j2

let ressc data tres y y' res =
  let a = data.a
  and j1 = data.j1
  and m2 = data.m2
  and j2 = data.j2 in

  let qq = Carray.create 3
  and q = y.{0}
  and x = y.{1}
  and p = y.{2}
  and qd = y.{3}
  and xd = y.{4}
  and pd = y.{5}
  and lam1 = y.{6}
  and lam2 = y.{7}
  and mu1 = y.{8}
  and mu2 = y.{9} in

  let s1 = sin q
  and c1 = cos q
  and s2 = sin p
  and c2 = cos p in

  force data y qq;

  res.{0} <- y'.{0} -. qd +. a*.s1*.mu1 -. a*.c1*.mu2;
  res.{1} <- y'.{1} -. xd +. mu1;
  res.{2} <- y'.{2} -. pd +. s2*.mu1 -. c2*.mu2;

  res.{3} <- j1*.y'.{3} -. qq.{0} +. a*.s1*.lam1 -. a*.c1*.lam2;
  res.{4} <- m2*.y'.{4} -. qq.{1} +. lam1;
  res.{5} <- j2*.y'.{5} -. qq.{2} +. s2*.lam1 -. c2*.lam2;

  res.{6} <- x -. c2 -. a*.c1;
  res.{7} <- -.s2 -. a*.s1;

  res.{8} <- a*.s1*.qd +. xd +. s2*.pd;
  res.{9} <- -.a*.c1*.qd -. c2*.pd

let main () =
  let data = { a = 0.5;   (* half-length of crank *)
               j1 = 1.0;  (* crank moment of inertia *)
               m2 = 1.0;  (* mass of connecting rod *)
               j2 = 2.0;  (* moment of inertia of connecting rod *)
               k = 1.0;   (* spring constant *)
               c = 1.0;   (* damper constant *)
               l0 = 1.0;  (* spring free length *)
               f = 1.0;   (* external constant force *)
             }
  in

  (* Create nvectors *)
  let y = Carray.create neq
  and y' = Carray.create neq in

  (* Consistent IC *)
  set_ic data y y';

  (* ID array *)
  let id = Ida.Id.init neq Ida.Id.Differential in
  for i = 6 to 9 do
    Ida.Id.set id i Ida.Id.Algebraic
  done;

  (* Tolerances *)
  let rtol = 1.0e-6
  and atol = 1.0e-6 in

  (* Integration limits *)
  let t0 = 0.
  and tf = tend in
  let dt = (tf -. t0) /. float_of_int (nout - 1) in

  (* IDA initialization *)
  let mem = Ida.init_at_time Ida.Dense (ressc data) Ida.no_roots y y' t0 in
  Ida.ss_tolerances mem rtol atol;
  Ida.set_var_types mem id;
  Ida.set_suppress_alg mem true;

  print_header rtol atol y;

  (* In loop, call IDASolve, print results, and test for error. *)
  print_output mem t0 y;

  let tout = ref dt in
  begin
    try
      for iout = 1 to nout-1 do
        tout := float_of_int iout *. dt;
        let (tret, flag) = Ida.solve_normal mem !tout y y' in
        print_output mem tret y;
      done;
    with _ -> ()
  end;

  print_final_stats mem

let _ = main ()
