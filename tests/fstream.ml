(* Functional lazy stream.  Only the spine is lazy.  *)

type 'a cons = Cons of 'a * 'a t | Nil
and  'a t = 'a cons Lazy.t

let nil = Lazy.lazy_from_val Nil

let cons x xs = Lazy.lazy_from_val (Cons (x, xs))

let null = function
  | lazy Nil -> true
  | lazy _ -> false

let singleton x = Lazy.lazy_from_val (Cons (x, nil))

let decons = function
  | lazy Nil -> None
  | lazy (Cons (x,xs)) -> Some (x,xs)

let rec of_list = function
  | [] -> nil
  | x::xs -> lazy (Cons (x, of_list xs))

let rec map f xs =
  lazy (match xs with
        | lazy (Cons (x,xs)) -> Cons (f x, map f xs)
        | lazy Nil -> Nil)

let mapi f xs =
  let rec go i = function
    | lazy Nil -> Nil
    | lazy (Cons (x,xs)) -> Cons (f i x, lazy (go (i+1) xs))
  in lazy (go 0 xs)

(* If the streams' sizes differ, the longer one is cut short (i.e. Haskell's
   semantics, hence the name).  *)
let zip_with f xs ys =
  let rec go xs ys =
    match xs, ys with
    | lazy Nil, _ -> Nil
    | _, lazy Nil -> Nil
    | lazy (Cons (x,xs)), lazy (Cons (y, ys)) -> Cons (f x y, lazy (go xs ys))
  in lazy (go xs ys)

(* If the streams' sizes differ, raises an exception.  *)
type which_is_too_short = LeftTooShort | RightTooShort
exception Stream_length_mismatch of which_is_too_short

let map2 f xs ys =
  let rec go xs ys =
    match xs, ys with
    | lazy Nil, lazy Nil -> Nil
    | lazy Nil, _ -> raise (Stream_length_mismatch RightTooShort)
    | _, lazy Nil -> raise (Stream_length_mismatch LeftTooShort)
    | lazy (Cons (x,xs)), lazy (Cons (y, ys)) -> Cons (f x y, lazy (go xs ys))
  in lazy (go xs ys)

let map2i f xs ys =
  let rec go i xs ys =
    match xs, ys with
    | lazy Nil, lazy Nil -> Nil
    | lazy Nil, _ -> raise (Stream_length_mismatch RightTooShort)
    | _, lazy Nil -> raise (Stream_length_mismatch LeftTooShort)
    | lazy (Cons (x,xs)), lazy (Cons (y, ys)) ->
      Cons (f i x y, lazy (go (i+1) xs ys))
  in lazy (go 0 xs ys)

let unzip xys =
  let rec go = function
    | lazy Nil -> (Nil, Nil)
    | lazy (Cons ((x,y), xys)) ->
      let rest = lazy (go xys) in
      (Cons (x, lazy (fst (Lazy.force rest))),
       Cons (y, lazy (snd (Lazy.force rest))))
  in
  let unzipped = lazy (go xys) in
  (lazy (fst (Lazy.force unzipped)), lazy (snd (Lazy.force unzipped)))

let rec iter f = function
  | lazy Cons (x, xs) -> f x; iter f xs
  | lazy Nil -> ()

let to_list xs =
  let rec go acc = function
    | lazy Nil -> List.rev acc
    | lazy (Cons (x, xs)) -> go (x::acc) xs
  in go [] xs

let append xs ys =
  let rec go xs =
    match xs with
    | lazy Nil -> Lazy.force ys
    | lazy Cons (x,xs) -> Cons (x, lazy (go xs))
  in lazy (go xs)

let cons x xs = Lazy.lazy_from_val (Cons (x, xs))

let concat xss =
  let rec flatten xs xs' xss =
    match xs with
    | lazy Nil -> go xs' xss
    | lazy (Cons (x, xs)) -> Cons (x, lazy (flatten xs xs' xss))
  and go xs xss =
    match xss with
    | lazy Nil -> Lazy.force xs
    | lazy (Cons (xs', xss)) -> flatten xs xs' xss
  in lazy (go nil xss)

let take n xs =
  let rec go n xs =
    match n, xs with
    | 0, _ -> Nil
    | _, lazy Nil -> Nil
    | n, lazy (Cons (x, xs)) -> Cons (x, lazy (go (n-1) xs))
  in lazy (if n < 0 then Nil else go n xs)

let take_while p xs =
  let rec go = function
    | lazy (Cons (x, xs)) when p x -> Cons (x, lazy (go xs))
    | lazy _ -> Nil
  in lazy (go xs)

let drop_while p xs =
  let rec go = function
    | lazy (Cons (x, xs)) when p x -> Cons (x, xs)
    | lazy (Cons (_, xs)) -> go xs
    | lazy Nil -> Nil
  in lazy (go xs)

let rec fold_left f y = function
  | lazy Nil -> y
  | lazy (Cons (x, xs)) -> fold_left f (f y x) xs

let rec generate f =
  match f () with
  | Some x -> lazy (Cons (x, generate f))
  | None -> nil

let rec find p = function
  | lazy Nil -> None
  | lazy (Cons (x, xs)) -> if p x then Some x else find p xs

let rec find_some f = function
  | lazy Nil -> None
  | lazy (Cons (x, xs)) ->
    match f x with
    | None -> find_some f xs
    | Some x -> Some x

let rec iterate f x = lazy (Cons (x, iterate f (f x)))
let iterate_over x f = iterate f x

let rec repeat f = lazy (Cons (f (), repeat f))
let repeat_n n f = take n (repeat f)

let guard b x  = if b then x else lazy Nil
let guard1 b x = guard b (singleton x)

let filter p xs =
  let rec go xs =
    match xs with
    | lazy Nil -> Nil
    | lazy (Cons (x, xs)) when p x -> Cons (x, lazy (go xs))
    | lazy (Cons (_, xs)) -> go xs
  in lazy (go xs)

let filter_map f xs =
  let rec go xs =
    match xs with
    | lazy Nil -> Nil
    | lazy (Cons (x, xs)) ->
      match f x with
      | None -> go xs
      | Some x -> Cons (x, lazy (go xs))
  in lazy (go xs)

let rec enum istart iend =
  if istart <= iend
  then lazy (Cons (istart, enum (istart + 1) iend))
  else lazy Nil

let enum_then istart inext iend =
  let step = inext - istart in
  let rec go i =
    if (step > 0 && i <= iend) || (step < 0 && i >= iend)
    then lazy (Cons (i, go (i + step)))
    else lazy Nil
  in go istart

let length xs =
  let rec go i = function
    | lazy Nil -> i
    | lazy Cons (_, xs) -> go (i+1) xs
  in go 0 xs

let of_array a = map (Array.get a) (enum 0 (Array.length a - 1))

