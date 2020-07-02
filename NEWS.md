Sundials/ML 4.1.0p0 (March 2020)
--------------------------------
Sundials/ML v4.1.0p0 adds support for v4.x of the Sundials Suite of
numerical solvers.

Notes:
* New Sundials.Nonlinear module and corresponding changes to the Cvode, 
  Cvodes, Ida, and Idas integrators.
* Support for the new fused and array nvector operations.
* Testing of all OCaml nvector operations and several bug fixes.

Sundials/ML 3.1.1p0 (July 2018)
------------------------------------
Sundials/ML v3.1.1p0 adds support for v3.1.x of the Sundials Suite of
numerical solvers.

Notably this release adds support for the new generic matrix and linear 
solver interfaces. The OCaml interface changes but the library is backward 
compatible with Sundials 2.7.0.

OCaml 4.02.3 or greater is now required and optionally OCamlMPI 1.03.

Notes:
* New Sundials.Matrix and Sundials.LinearSolver modules.
* Better treatment of integer type used for matrix indexing.
* Refactor Dls and Sls modules into Sundials.Matrix.
* Add confidence intervals to performance graph.
* Miscellaneous improvements to configure script.
* Potential incompatibility: changes to some label names: comm_fn -> comm;
  iter_type -> iter.
* Untangle the ARKODE mass-solver interface from the Jacobian interface.

Sundials/ML 2.7.0p0 (December 2016)
------------------------------------
Sundials/ML v2.7.0p0 adds support for v2.7.x of the Sundials Suite of
numerical solvers.

Notes:
* Arkode: the interfaces to the Butcher tables have changed.
* The sparse matrix interface has changed:
  Sls.SparseMatrix:
    make       -> make_csc
    create     -> create_csc
    from_dense -> csc_from_dense
    from_band  -> csc_from_band
* The Klu and Superlumt linear solver interfaces have changed.
    *.Klu.solver -> Klu.solver_csc
    *.Superlumt.solver -> Superlumt.solver_csc

Sundials/ML 2.6.2p1 (September 2016)
------------------------------------
Sundials/ML v2.6.2p1 includes several bug fixes and minor 
additions/improvements:
* Add pretty printers with automatic installation
  (thanks to Nils Becker for the suggestion).
* Improve Opam integration allowing pin from source code
  (thanks to Gabriel Scherer for the suggestion).
* Ensure compatibility with OCaml no-naked-pointers mode.
* Fix segfaulting on exceptions in newer versions of OCaml.
* Fix bug in RealArray2.size.
* Update the set_err_file/set_info_file/set_diagnostics interface
  (minor incompatibility).
* Miscellaneous improvements to the build system.
* Remove the Kinsol.set_linear_solver function due to
  [memory leak issues] [1].

[1]: http://sundials.2283335.n4.nabble.com/KINSOL-documentation-td4653693.html

Sundials/ML 2.6.2p0 (March 2016)
--------------------------------
Sundials/ML v2.6.2p0 adds support for v2.6.x of the Sundials Suite of
numerical solvers, including:
* the new ARKODE solver,
* sparse matrices and the KLU and SuperLU/MT linear solvers,
* OpenMP and Pthreads nvectors, and
* various new functions and linear solvers in existing solvers.

OCaml 3.12.1 or greater is required, and optionally OCamlMPI 1.01.

We continue to provide support for the Sundials 2.5.x series which is still
found in many packaging systems (like Homebrew and Debian/Ubuntu).

Notes:
* The source files have been reorganized into subdirectories.
* Sensitivity features are now disabled via a findlib predicate.
* The Spils jac_times_vec function is no longer associated with individual
  preconditioners, but rather with the linear solvers directly.
* Adjoint linear solver callbacks in CVODES and IDAS may now depend on
  forward sensitivities, the types dense_jac_fn, band_jac_fn, and
  jac_times_vec_fn become variants, new preconditioner functions are
  provided.
* The Kinsol interface changes for new features (new strategies and Anderson
  iteration).
* Incompatibility: The {Cvode,Ida,...}.serial_session type synonyms gain a 
  polymorphic variable to admit OpenMP and Pthreads nvectors.

Sundials/ML 2.5.0p0 (November 2014)
-----------------------------------
Sundials/ML v2.5.0p0 is an OCaml interface to v2.5.0 of the Sundials suite
of numerical solvers (CVODE, CVODES, IDA, IDAS, KINSOL).

It requires OCaml 3.12.1 or greater, Sundials 2.5.0, and optionally
OCamlMPI 1.01.

* When building Sundials manually, we recommend applying the
  `sundials-2.5.0.patch` file and building with examples and shared library
  support:

      patch -p1 < path/to/sundials-2.5.0.patch
      ./configure --enable-examples --enable-shared

  Sundials/ML will function correctly if the patch is not applied, but some
  examples will fail with incorrect results.

* The backward preconditioner, banded and dense jacobian, and jacobian
  times vector callbacks in Cvodes.Adjoint and Idas.Adjoint do not function
  correctly due to an issue in the underlying C library.

