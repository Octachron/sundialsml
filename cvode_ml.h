/***********************************************************************
 *                                                                     *
 *              Ocaml interface to Sundials CVODE solver               *
 *                                                                     *
 *           Timothy Bourke (INRIA) and Marc Pouzet (LIENS)            *
 *                                                                     *
 *  Copyright 2013 Institut National de Recherche en Informatique et   *
 *  en Automatique.  All rights reserved.  This file is distributed    *
 *  under the terms of the GNU Library General Public License, with    *
 *  the special exception on linking described in file LICENSE.        *
 *                                                                     *
 ***********************************************************************/

/*
 * This module defines all constants and functions which do not depend on
 * the representation of continuous state vectors, i.e., those that are
 * shared between the bigarray and nvector versions of cvode_ml_nvec.
 *
 */

#ifndef _CVODE_ML_H__
#define _CVODE_ML_H__

#include "sundials_ml.h"

/* Configuration options */
#define CHECK_MATRIX_ACCESS 1

/*
 * The session data structure is shared in four parts across the OCaml and C
 * heaps:
 *
 *           C HEAP                 .             OCAML HEAP
 * ---------------------------------.-----------------------------------
 *                                  .       (Program using Sundials/ML)
 *                                  .                            |
 *              +---------------+   .   +-------------------+    |
 *              | generational  +------>| weak ref : Weak.t |    |
 *              | global root   |   .   +-------------------+    |
 *              | (type: value) |   .   | ~ ~ ~ ~ ~ ~ ~ ~ ~ |    |
 *              +---------------+   .   +----------------+--+    |
 *                      /|\  /|\    .                    |       |
 *                       |    |     .                    |       |
 *                       |    |     .                   \|/     \|/
 *                       |    |     .                 +----------------+
 *                       |    |     .                 |  session       |
 *   +------------+      |    |     .                 +----------------+
 *   | cvode_mem  |<----------------------------------+ cvode          |
 *   +------------+      |    +-----------------------+ backref        |
 *   |    ...     |      |          .                 | neqs           |
 *   |cv_user_data+------+          .                 | nroots         |
 *   |    ...     |                 .                 | err_file       |
 *   +------------+                 .                 | closure_rhsfn  |
 *                                  .                 | closure_rootsfn|
 *                                  .                 | ...            |
 *                                  .                 +----------------+
 *
 *  * A cvode_mem structure is allocated by CVodeInit for each session. It
 *    is the "C side" of the session data structure.
 *
 *  * The "OCaml side" of the session data structure is a record which contains
 *    a pointer to cvode_mem, several data fields, and the callback closures.
 *    It is returned to users of the library and used like any other abstract
 *    data type in OCaml.
 *
 *  * cvode_mem holds an indirect reference to the session record as user data
 *    (set by CVodeSetUserData).  It cannot directly point to the record
 *    because GC can change the record's address.  Instead, user data points to
 *    a global root which the GC updates whenever it relocates the session.
 *
 *  * The global root points to a weak reference (a Weak.t of size 1) which
 *    points to the session record.  The root is destroyed when the session
 *    record is GC'ed -- note that if the root referenced the session record
 *    via a non-weak pointer the session would never be GC'ed, hence the root
 *    would never be destroyed either.
 *
 * 1. CVodeInit() on the C side creates cvode_mem and the global root, and the
 *    OCaml side wraps that in a session record.  The OCaml side associates
 *    that record with a finalizer that unregisters the global root and frees
 *    all the C-side memory.
 *
 * 2. Callback functions (the right-hand side function, root function, etc)
 *    access the session through the user data.  This is the only way they can
 *    access the session.  The weak pointer is guaranteed to be alive during
 *    callback because the session record is alive.  The session record is
 *    captured in a C stack variable of type value when control enters the C
 *    stub that initiated the callback.
 *
 * 3. Other functions, like those that query integrator statistics, access the
 *    session record directly.
 *
 * 4. Eventually, when the user program abandons all references to the session
 *    record, the GC can reclaim the record because the only remaining direct
 *    reference to it is the weak pointer.
 */
/* Implementation note: we have also considered an arrangement where the global
 * root is replaced by a pointer of type value*.  The idea was that whenever
 * execution enters the C side, we capture the session record in a stack
 * variable (which is registered with OCaml's GC through CAMLparam()) and make
 * the pointer point to this stack variable.  The stack variable is updated by
 * GC, while the pointer pointing to the stack variable is always at the same
 * address.
 *
 * In the following figure, the GC sees everything on the stack and OCaml heap,
 * while seeing nothing on the C heap.
 *
 *           C HEAP         .     STACK     .        OCAML HEAP
 * -------------------------.---------------.---------------------------
 *   +-------------+        . +-----------+ . (Program using Sundials/ML)
 *   | pointer of  |        . |function   | .                     |
 *   | type value* +--------->|param of   +--------------+        |
 *   +-------------+        . |type value | .            |        |
 *         /|\              . +-----------+ .            |        |
 *          |               .               .           \|/      \|/
 *  +-------+               .  NB: This     .        +----------------+
 *  |                       .  diagram does .        |  session       |
 *  |  +--------------+     .  NOT show how .        +----------------+
 *  |  |  cvode_mem   |<-----  the current  ---------+ cvode          |
 *  |  +--------------+     .  code works!! .        | neqs           |
 *  |  |     ...      |     .  The diagram  .        | nroots         |
 *  +--+ cv_user_data |     .  above does!! .        | err_file       |
 *     | conceptually |     .               .        | closure_rhsfn  |
 *     | of type      |     .               .        | closure_rootsfn|
 *     | value **     |     .               .        | ...            |
 *     |     ...      |     .               .        +----------------+
 *     +--------------+     .               .
 *
 * On the one hand, we dropped this approach because it's invasive and
 * error-prone.  The error handler callback (errh) needs to access the session
 * record too, and almost every Sundials API can potentially call this handler.
 * This means that every C stub must update the pointer before doing anything
 * else (including functions that do not ostensibly initiate any callbacks),
 * and we have to ensure that callbacks never see the pointer pointing to an
 * expired stack variable.
 *
 * On the other hand, this approach is probably more efficient than the current
 * approach with weak tables.  Perhaps if the callback overhead is found to be
 * a major bottleneck, we can switch over to this alternative.
 */

void cvode_ml_check_flag(const char *call, int flag);

#define CHECK_FLAG(call, flag) if (flag != CV_SUCCESS) \
				 cvode_ml_check_flag(call, flag)

void set_linear_solver(void *cvode_mem, value ls, int n);
value cvode_ml_big_real();

/* Interface with Ocaml types */

/* Indices into the Cvode_*.session type.  This enum must be in the same order
 * as the session type's member declaration.  */
enum cvode_index {
    RECORD_SESSION_CVODE = 0,
    RECORD_SESSION_BACKREF,
    RECORD_SESSION_NEQS,
    RECORD_SESSION_NROOTS,
    RECORD_SESSION_ERRFILE,
    RECORD_SESSION_EXN_TEMP,
    RECORD_SESSION_RHSFN,
    RECORD_SESSION_ROOTSFN,
    RECORD_SESSION_ERRH,
    RECORD_SESSION_ERRW,
    RECORD_SESSION_JACFN,
    RECORD_SESSION_BANDJACFN,
    RECORD_SESSION_PRESETUPFN,
    RECORD_SESSION_PRESOLVEFN,
    RECORD_SESSION_JACTIMESFN,
    RECORD_SESSION_SIZE,	/* This has to come last.  */
};

#define CVODE_MEM_FROM_ML(v)       ((void *)Field((v), RECORD_SESSION_CVODE))
#define CVODE_BACKREF_FROM_ML(v) \
    ((value *)(Field((v), RECORD_SESSION_BACKREF)))
#define CVODE_NEQS_FROM_ML(v)      Long_val(Field((v), RECORD_SESSION_NEQS))
#define CVODE_NROOTS_FROM_ML(v)    Long_val(Field((v), RECORD_SESSION_NROOTS))
#define CVODE_ROOTSFN_FROM_ML(v)   Field((v), RECORD_SESSION_ROOTSFN)
#define CVODE_PRESETUPFN_FROM_ML(v)   Field((v), RECORD_SESSION_PRESETUPFN)

#define VARIANT_LMM_ADAMS 0
#define VARIANT_LMM_BDF   1

#define RECORD_BANDRANGE_MUPPER 0
#define RECORD_BANDRANGE_MLOWER 1

#define RECORD_SPRANGE_PRETYPE 0
#define RECORD_SPRANGE_MAXL    1

/* untagged: */
#define VARIANT_LINEAR_SOLVER_DENSE	    0
#define VARIANT_LINEAR_SOLVER_LAPACKDENSE   1
#define VARIANT_LINEAR_SOLVER_DIAG	    2
/* tagged: */
#define VARIANT_LINEAR_SOLVER_BAND		    0
#define VARIANT_LINEAR_SOLVER_LAPACKBAND	    1
#define VARIANT_LINEAR_SOLVER_SPGMR		    2
#define VARIANT_LINEAR_SOLVER_SPBCG		    3
#define VARIANT_LINEAR_SOLVER_SPTFQMR		    4
#define VARIANT_LINEAR_SOLVER_BANDED_SPGMR	    5
#define VARIANT_LINEAR_SOLVER_BANDED_SPBCG	    6
#define VARIANT_LINEAR_SOLVER_BANDED_SPTFQMR	    7

#define VARIANT_SOLVER_RESULT_CONTINUE		0
#define VARIANT_SOLVER_RESULT_ROOTSFOUND	1
#define VARIANT_SOLVER_RESULT_STOPTIMEREACHED	2

#define RECORD_INTEGRATOR_STATS_STEPS			0
#define RECORD_INTEGRATOR_STATS_RHS_EVALS		1
#define RECORD_INTEGRATOR_STATS_LINEAR_SOLVER_SETUPS	2
#define RECORD_INTEGRATOR_STATS_ERROR_TEST_FAILURES	3
#define RECORD_INTEGRATOR_STATS_LAST_INTERNAL_ORDER	4
#define RECORD_INTEGRATOR_STATS_NEXT_INTERNAL_ORDER	5
#define RECORD_INTEGRATOR_STATS_INITIAL_STEP_SIZE	6
#define RECORD_INTEGRATOR_STATS_LAST_STEP_SIZE		7
#define RECORD_INTEGRATOR_STATS_NEXT_STEP_SIZE		8
#define RECORD_INTEGRATOR_STATS_INTERNAL_TIME		9

#define RECORD_ERROR_DETAILS_ERROR_CODE	    0
#define RECORD_ERROR_DETAILS_MODULE_NAME    1
#define RECORD_ERROR_DETAILS_FUNCTION_NAME  2
#define RECORD_ERROR_DETAILS_ERROR_MESSAGE  3

#define RECORD_JACOBIAN_ARG_JAC_T	0
#define RECORD_JACOBIAN_ARG_JAC_Y	1
#define RECORD_JACOBIAN_ARG_JAC_FY	2
#define RECORD_JACOBIAN_ARG_JAC_TMP	3

#define RECORD_SPILS_SOLVE_ARG_RHS	0
#define RECORD_SPILS_SOLVE_ARG_GAMMA	1
#define RECORD_SPILS_SOLVE_ARG_DELTA	2
#define RECORD_SPILS_SOLVE_ARG_LEFT	3

#define VARIANT_PRECOND_TYPE_PRECNONE	0
#define VARIANT_PRECOND_TYPE_PRECLEFT	1
#define VARIANT_PRECOND_TYPE_PRECRIGHT	2
#define VARIANT_PRECOND_TYPE_PRECBOTH	3

#define VARIANT_PRECONDITIONING_TYPE_PRECNONE	0
#define VARIANT_PRECONDITIONING_TYPE_PRECLEFT	1
#define VARIANT_PRECONDITIONING_TYPE_PRECRIGHT	2
#define VARIANT_PRECONDITIONING_TYPE_PRECBOTH	3

#define VARIANT_GRAMSCHMIDT_TYPE_MODIFIEDGS	0
#define VARIANT_GRAMSCHMIDT_TYPE_CLASSICALGS	1

#endif

