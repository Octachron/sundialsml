/***********************************************************************
 *                                                                     *
 *               OCaml interface to (serial) Sundials                  *
 *                                                                     *
 *  Timothy Bourke (Inria), Jun Inoue (Inria), and Marc Pouzet (LIENS) *
 *                                                                     *
 *  Copyright 2014 Institut National de Recherche en Informatique et   *
 *  en Automatique.  All rights reserved.  This file is distributed    *
 *  under a BSD 2-Clause License, refer to the file LICENSE.           *
 *                                                                     *
 ***********************************************************************/

/* The parts of the Sundials interface that distinguish between Serial
   NVectors (handled by Bigarrays) and generic NVectors (handled by a
   wrapper type). */

// TODO: rename presetup to precsetup everywhere
// TODO: rename presolve to precsolve everywhere

#include <cvodes/cvodes.h>
#include <sundials/sundials_config.h>
#include <sundials/sundials_types.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/unixsupport.h>
#include <caml/bigarray.h>

/* linear solvers */
#include <cvodes/cvodes_dense.h>
#include <cvodes/cvodes_band.h>
#include <cvodes/cvodes_diag.h>
#include <cvodes/cvodes_spgmr.h>
#include <cvodes/cvodes_spbcgs.h>
#include <cvodes/cvodes_sptfqmr.h>
#include <cvodes/cvodes_bandpre.h>
#include <sundials/sundials_config.h>

#include "spils_ml.h"
#include "sundials_ml.h"
#include "cvode_ml.h"
#include "cvodes_ml.h"
#include "nvector_ml.h"

#if SUNDIALS_BLAS_LAPACK == 1
#include <cvodes/cvodes_lapack.h>
#endif

// Call with CVODE_ML_BIGARRAYS to compile for the Serial NVector to
// Bigarray interface code.

#ifdef CVODE_ML_BIGARRAYS

#define CVTYPE(fname) c_ba_cvodes_ ## fname
#include <nvector/nvector_serial.h>

#define WRAP_NVECTOR(v) caml_ba_alloc(BIGARRAY_FLOAT, 1, NV_DATA_S(v), &(NV_LENGTH_S(v)))
#define RELINQUISH_WRAPPEDNV(v_ba) Caml_ba_array_val(v_ba)->dim[0] = 0

#define NVECTORIZE_VAL(ba) N_VMake_Serial(Caml_ba_array_val(ba)->dim[0], (realtype *)Caml_ba_data_val(ba))
#define RELINQUISH_NVECTORIZEDVAL(nv) N_VDestroy(nv)

#else

#define CVTYPE(fname) c_nvec_cvodes_ ## fname
#include <sundials/sundials_nvector.h>

#define WRAP_NVECTOR(v) NVEC_DATA(v)
#define RELINQUISH_WRAPPEDNV(v) {}

#define NVECTORIZE_VAL(v) NVEC_VAL(v)
#define RELINQUISH_NVECTORIZEDVAL(nv) {}

#endif

#define DOQUOTE(text) #text
#define QUOTE(val) DOQUOTE(val)
#define CVTYPESTR(fname) QUOTE(CVTYPE(fname))

CAMLprim value CVTYPE(alloc_nvector_array)(value vn)
{
    CAMLparam1(vn);
    value r;
    int emptydim = 0;
    int n = Int_val(vn);

    r = caml_alloc_tuple(n);

#ifdef CVODE_ML_BIGARRAYS
    for (i = 0; i < n; ++i) {
	Store_field(r, i,
	  caml_ba_alloc(BIGARRAY_FLOAT, 1,
			1 /* Any non-NULL value */, &emptydim);
    }
#endif

    CAMLreturn(r);
}

static void wrap_to_nvector_table(int n, value vy, N_Vector *y)
{
    int i;
    for (i = 0; i < n; ++i) {
#ifdef CVODE_ML_BIGARRAYS
	Caml_ba_array_val(Field(vy, i))->data = NV_DATA_S(y[i]);
	Caml_ba_array_val(Field(vy, i))->dim[0] = NV_LENGTH_S(y[i]);
#else
	Store_field(vy, i, NVEC_DATA(y[i]));
#endif
    }
}

static void relinquish_from_nvector_table(int n, value vy)
{
    int i;
    for (i = 0; i < n; ++i) {
#ifdef CVODE_ML_BIGARRAYS
	Caml_ba_array_val(Field(vy, i))->dim[0] = 0
#else
	Store_field(vy, i, Val_unit);
#endif
    }
}

static N_Vector *nvector_table_to_array(value vtable)
{
    int ns = (int)caml_array_length(vtable);
    N_Vector *r = calloc(ns + 1, sizeof(N_Vector));
    int i;

    for (i=0; i < ns; ++i) {
	r[i] = NVECTORIZE_VAL(Field(vtable, i));
    }
    r[ns] = NULL;

    return r;
}

static void free_nvector_array(N_Vector *nvarr)
{
    for (i=0; nvarr[i] != NULL; ++i) {
	RELINQUISH_NVECTORIZEDVAL(nvarr[i]);
    }

    free(nvarr);
}

/* Callbacks */

#define CAML_FN(name)					\
    static value *name;					\
    if (name == NULL)					\
	name = caml_named_value (CVTYPESTR (name));

static int check_exception(value session, value r)
{
    CAMLparam2(session, r);
    CAMLlocal1(exn);

    static value *recoverable_failure = NULL;
    if (recoverable_failure == NULL) {
	recoverable_failure = caml_named_value("cvodes_RecoverableFailure");
    }

    if (!Is_exception_result(r)) return 0;

    r = Extract_exception(r);

    if (Field(r, 0) == *recoverable_failure)
	CAMLreturnT (int, 1);

    /* Unrecoverable error.  Save the exception and return -1.  */
    exn = caml_alloc_small (1,0);
    Field (exn, 0) = r;
    Store_field (session, RECORD_CVODE_SESSION_EXN_TEMP, exn);
    CAMLreturnT (int, -1);
}

static int quadrhsfn(realtype t, N_Vector y, N_Vector yQdot, void *user_data)
{
    CAMLparam0();
    CAMLlocalN(args, 4);
    int r;
    value *backref = user_data;
    CAML_FN (call_quadrhsfn);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = WRAP_NVECTOR(y);
    args[3] = WRAP_NVECTOR(yQdot);

    // the data payloads inside args[2] and args[3] are only valid during
    // this call, afterward that memory goes back to cvode. These bigarrays
    // must not be retained by closure_quadrhsfn! If it wants a permanent
    // copy, then it has to make it manually.
    r = Int_val (caml_callbackN(*call_quadrhsfn,
                                sizeof (args) / sizeof (*args),
                                args));

    RELINQUISH_WRAPPEDNV(args[2]);
    RELINQUISH_WRAPPEDNV(args[3]);

    CAMLreturnT(int, r);
}

static int sensrhsfn(int ns, realtype t, N_Vector y, N_Vector ydot,
		     N_Vector *ys, N_Vector *ysdot, void *user_data,
		     N_Vector tmp1, N_Vector tmp2)
{
    CAMLparam0();
    CAMLlocal2(session, sensext);
    CAMLlocalN(args, 8);
    int r;
    value *backref = user_data;

    /* We need to dereference on the C side, so that we can get access to
     * the values used to pass arrays of nvectors. */
    WEAK_DEREF (session, *backref);
    sensext = Field(session, RECORD_CVODES_SESSION_SENSEXT);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = WRAP_NVECTOR(y);
    args[3] = WRAP_NVECTOR(ydot);
    args[4] = CVODES_SENSARRAY1_FROM_EXT(sensext);
    args[5] = CVODES_SENSARRAY2_FROM_EXT(sensext);
    args[6] = WRAP_NVECTOR(tmp1);
    args[7] = WRAP_NVECTOR(tmp2);

    wrap_to_nvector_table(ns, args[4], ys);
    wrap_to_nvector_table(ns, args[5], ysdot);

    // The data payloads inside args[2..7] are only valid during this call,
    // afterward that memory goes back to cvode. These bigarrays must not be
    // retained by closure_quadrhsfn! If it wants a permanent copy, then it
    // has to make it manually.
    r = caml_callbackN_exn(CVODES_SENSRHSFN_FROM_EXT(sensext),
			   sizeof (args) / sizeof (*args),
                           args);

    RELINQUISH_WRAPPEDNV(args[2]);
    RELINQUISH_WRAPPEDNV(args[3]);
    relinquish_from_nvector_table(ns, args[4]);
    relinquish_from_nvector_table(ns, args[5]);
    RELINQUISH_WRAPPEDNV(args[6]);
    RELINQUISH_WRAPPEDNV(args[7]);

    CAMLreturnT(int, check_exception(session, r));
}

static int sensrhsfn1(int ns, realtype t, N_Vector y, N_Vector ydot,
		      int is, N_Vector ys, N_Vector ysdot, void *user_data,
		      N_Vector tmp1, N_Vector tmp2)
{
    CAMLparam0();
    CAMLlocalN(args, 9);
    int r;
    value *backref = user_data;
    CAML_FN (call_sensrhsfn1);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = WRAP_NVECTOR(y);
    args[3] = WRAP_NVECTOR(ydot);
    args[4] = Val_int(is);
    args[5] = WRAP_NVECTOR(ys);
    args[6] = WRAP_NVECTOR(ysdot);
    args[7] = WRAP_NVECTOR(tmp1);
    args[8] = WRAP_NVECTOR(tmp2);

    // The data payloads inside args[2..3, 5..7] are only valid during this call,
    // afterward that memory goes back to cvode. These bigarrays must not be
    // retained by closure_quadrhsfn! If it wants a permanent copy, then it
    // has to make it manually.
    r = Int_val (caml_callbackN(*call_sensrhsfn1,
                                sizeof (args) / sizeof (*args),
                                args));

    RELINQUISH_WRAPPEDNV(args[2]);
    RELINQUISH_WRAPPEDNV(args[3]);
    RELINQUISH_WRAPPEDNV(args[5]);
    RELINQUISH_WRAPPEDNV(args[6]);
    RELINQUISH_WRAPPEDNV(args[7]);
    RELINQUISH_WRAPPEDNV(args[8]);

    CAMLreturnT(int, r);
}

static int quadsensrhsfn(int ns, realtype t, N_Vector y, N_Vector *ys,
		         N_Vector yqdot, N_vector *yqsdot, void *user_data,
		         N_Vector tmp1, N_Vector tmp2)
{
    CAMLparam0();
    CAMLlocal2(session, sensext);
    CAMLlocalN(args, 8);
    int r;
    value *backref = user_data;
    CAML_FN (call_quadsensrhsfn);

    /* We need to dereference on the C side, so that we can get access to
     * the values used to pass arrays of nvectors. */
    WEAK_DEREF (session, *backref);
    sensext = Field(session, RECORD_CVODES_SESSION_SENSEXT);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = WRAP_NVECTOR(y);
    args[3] = CVODES_SENSARRAY1_FROM_EXT(sensext);
    args[4] = WRAP_NVECTOR(yqdot);
    args[5] = CVODES_SENSARRAY2_FROM_EXT(sensext);
    args[6] = WRAP_NVECTOR(tmp1);
    args[7] = WRAP_NVECTOR(tmp2);

    wrap_to_nvector_table(ns, args[3], ys);
    wrap_to_nvector_table(ns, args[5], yqsdot);

    // The data payloads inside args[2..7] are only valid during this call,
    // afterward that memory goes back to cvode. These bigarrays must not be
    // retained by closure_quadrhsfn! If it wants a permanent copy, then it
    // has to make it manually.
    r = caml_callbackN_exn(CVODES_QUADSENSRHSFN_FROM_EXT(sensext),
		           sizeof (args) / sizeof (*args),
                           args);

    RELINQUISH_WRAPPEDNV(args[2]);
    relinquish_from_nvector_table(ns, args[3]);
    RELINQUISH_WRAPPEDNV(args[4]);
    relinquish_from_nvector_table(ns, args[5]);
    RELINQUISH_WRAPPEDNV(args[6]);
    RELINQUISH_WRAPPEDNV(args[7]);

    CAMLreturnT(int, check_exception(session, r));
}

static int brhsfn(realtype t, N_Vector y, N_Vector yb, N_Vector ybdot,
		  void *user_data)
{
    CAMLparam0();
    CAMLlocalN(args, 5);
    int r;
    value *backref = user_data;
    CAML_FN (call_brhsfn);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = WRAP_NVECTOR(y);
    args[3] = WRAP_NVECTOR(yb);
    args[4] = WRAP_NVECTOR(ybdot);

    // The data payloads inside args[2..4] are only valid during this call,
    // afterward that memory goes back to cvode. These bigarrays must not be
    // retained by closure_quadrhsfn! If it wants a permanent copy, then it
    // has to make it manually.
    r = Int_val (caml_callbackN(*call_brhsfn,
                                sizeof (args) / sizeof (*args),
                                args));

    RELINQUISH_WRAPPEDNV(args[2]);
    RELINQUISH_WRAPPEDNV(args[3]);
    RELINQUISH_WRAPPEDNV(args[4]);

    CAMLreturnT(int, r);
}

static int brhsfn1(realtype t, N_Vector y, N_Vector *ys, N_Vector yb,
		   N_Vector ybdot, void *user_data)
{
    CAMLparam0();
    CAMLlocal2(session, sensext);
    CAMLlocalN(args, 6);
    int r;
    value *backref = user_data;

    /* We need to dereference on the C side, so that we can get access to
     * the values used to pass arrays of nvectors. */
    WEAK_DEREF (session, *backref);
    sensext = Field(session, RECORD_CVODES_SESSION_SENSEXT);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = WRAP_NVECTOR(y);
    args[3] = CVODES_BSENSARRAY_FROM_EXT(sensext);
    args[4] = WRAP_NVECTOR(yb);
    args[5] = WRAP_NVECTOR(ybdot);

    wrap_to_nvector_table(ns, args[3], ys);

    // The data payloads inside args[2..5] are only valid during this call,
    // afterward that memory goes back to cvode. These bigarrays must not be
    // retained by closure_quadrhsfn! If it wants a permanent copy, then it
    // has to make it manually.
    r = caml_callbackN_ext(CVODES_BRHSFN1_FROM_EXT(sensext),
                           sizeof (args) / sizeof (*args),
                           args);

    RELINQUISH_WRAPPEDNV(args[2]);
    relinquish_from_nvector_table(ns, args[3]);
    RELINQUISH_WRAPPEDNV(args[4]);
    RELINQUISH_WRAPPEDNV(args[5]);

    CAMLreturnT(int, check_exception(session, r));
}

static int bquadrhsfn(realtype t, N_Vector y, N_Vector yb, N_Vector qbdot,
		      void *user_data)
{
    CAMLparam0();
    CAMLlocalN(args, 5);
    int r;
    value *backref = user_data;
    CAML_FN (call_bquadrhsfn);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = WRAP_NVECTOR(y);
    args[3] = WRAP_NVECTOR(yb);
    args[4] = WRAP_NVECTOR(qbdot);

    // The data payloads inside args[2..4] are only valid during this call,
    // afterward that memory goes back to cvode. These bigarrays must not be
    // retained by closure_quadrhsfn! If it wants a permanent copy, then it
    // has to make it manually.
    r = Int_val (caml_callbackN(*call_bquadrhsfn,
                                sizeof (args) / sizeof (*args),
                                args));

    RELINQUISH_WRAPPEDNV(args[2]);
    RELINQUISH_WRAPPEDNV(args[3]);
    RELINQUISH_WRAPPEDNV(args[4]);

    CAMLreturnT(int, r);
}

static int bquadrhsfn1(realtype t, N_Vector y, N_Vector *ys, N_Vector yb,
		       N_Vector qbdot, void *user_data)
{
    CAMLparam0();
    CAMLlocalN(args, 6);
    int r;
    value *backref = user_data;

    /* We need to dereference on the C side, so that we can get access to
     * the values used to pass arrays of nvectors. */
    WEAK_DEREF (session, *backref);
    sensext = Field(session, RECORD_CVODES_SESSION_SENSEXT);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = WRAP_NVECTOR(y);
    args[3] = CVODES_BSENSARRAY_FROM_EXT(sensext);
    args[4] = WRAP_NVECTOR(yb);
    args[5] = WRAP_NVECTOR(qbdot);

    wrap_to_nvector_table(ns, args[3], ys);

    // The data payloads inside args[2..5] are only valid during this call,
    // afterward that memory goes back to cvode. These bigarrays must not be
    // retained by closure_quadrhsfn! If it wants a permanent copy, then it
    // has to make it manually.
    r = caml_callbackN(CVODES_BQUADRHSFN1_FROM_EXT(sensext),
                       sizeof (args) / sizeof (*args),
                       args);

    RELINQUISH_WRAPPEDNV(args[2]);
    relinquish_from_nvector_table(ns, args[3]);
    RELINQUISH_WRAPPEDNV(args[4]);
    RELINQUISH_WRAPPEDNV(args[5]);

    CAMLreturnT(int, check_exception(session, r));
}

static value make_jac_arg(realtype t, N_Vector y, N_Vector yb,
			   N_Vector fyb, value tmp)
{
    CAMLparam1(tmp);
    CAMLlocal1(r);

    r = caml_alloc_tuple(RECORD_CVODES_ADJ_JACOBIAN_ARG_JAC_SIZE);
    Store_field(r, RECORD_CVODES_JACOBIAN_ARG_JAC_T, caml_copy_double(t));
    Store_field(r, RECORD_CVODES_JACOBIAN_ARG_JAC_Y, WRAP_NVECTOR(y));
    Store_field(r, RECORD_CVODES_JACOBIAN_ARG_JAC_YB, WRAP_NVECTOR(yb));
    Store_field(r, RECORD_CVODES_JACOBIAN_ARG_JAC_FYB, WRAP_NVECTOR(fyb));
    Store_field(r, RECORD_CVODES_JACOBIAN_ARG_JAC_TMP, tmp);

    CAMLreturn(r);
}

static value make_triple_tmp(N_Vector tmp1, N_Vector tmp2, N_Vector tmp3)
{
    CAMLparam0();
    CAMLlocal1(r);

    r = caml_alloc_tuple(3);
    Store_field(r, 0, WRAP_NVECTOR(tmp1));
    Store_field(r, 1, WRAP_NVECTOR(tmp2));
    Store_field(r, 2, WRAP_NVECTOR(tmp3));
    CAMLreturn(r);
}

#define TRIPLE 1
#define SINGLE 0
static void relinquish_jac_arg(value arg, int triple)
{
    CAMLparam1(arg);
    CAMLlocal1(tmp);

    RELINQUISH_WRAPPEDNV(Field(arg, RECORD_CVODES_JACOBIAN_ARG_JAC_Y));
    RELINQUISH_WRAPPEDNV(Field(arg, RECORD_CVODES_JACOBIAN_ARG_JAC_YB));
    RELINQUISH_WRAPPEDNV(Field(arg, RECORD_CVODES_JACOBIAN_ARG_JAC_FYB));

    tmp = Field(arg, RECORD_CVODES_JACOBIAN_ARG_JAC_TMP);

    if (triple) {
	RELINQUISH_WRAPPEDNV(Field(tmp, 0));
	RELINQUISH_WRAPPEDNV(Field(tmp, 1));
	RELINQUISH_WRAPPEDNV(Field(tmp, 2));
    } else {
	RELINQUISH_WRAPPEDNV(tmp);
    }

    CAMLreturn0;
}

static value make_spils_solve_arg(
	N_Vector rvecb,
	realtype gammab,
	realtype deltab)

{
    CAMLparam0();
    CAMLlocal1(v);

    v = caml_alloc_tuple(RECORD_CVODES_SPILS_SOLVE_ARG_SIZE);
    Store_field(v, RECORD_CVODES_SPILS_SOLVE_ARG_RVECB, WRAP_NVECTOR(rvecb));
    Store_field(v, RECORD_CVODES_SPILS_SOLVE_ARG_GAMMAB,
                caml_copy_double(gamma));
    Store_field(v, RECORD_CVODES_SPILS_SOLVE_ARG_DELTAB,
                caml_copy_double(delta));

    CAMLreturn(v);
}

static void relinquish_spils_solve_arg(value arg)
{
    CAMLparam1(arg);
    RELINQUISH_WRAPPEDNV(Field(arg, RECORD_CVODES_SPILS_SOLVE_ARG_RVECB));
    CAMLreturn0;
}

static int bpresolvefn(
	realtype t,
	N_Vector y,
	N_Vector yb,
	N_Vector fyb,
	N_Vector rvecb,
	N_Vector zvecb,
	realtype gammab,
	realtype deltab,
	void *user_data,
	N_Vector tmpb)
{
    CAMLparam0();
    CAMLlocal1(rv);
    CAMLlocalN(args, 4);
    int retcode;
    value *backref = user_data;
    CAML_FN (call_bpresolvefn);

    args[0] = *backref;
    args[1] = make_jac_arg(t, y, yb, fyb, WRAP_NVECTOR(tmpb));
    args[2] = make_spils_solve_arg(rvecb, gammab, deltab);
    args[3] = WRAP_NVECTOR(zvecb);

    retcode = Int_val (caml_callbackN(*call_bpresolvefn,
                                      sizeof (args) / sizeof (*args),
                                      args));

    relinquish_jac_arg(args[1], SINGLE);
    relinquish_spils_solve_arg(args[2]);
    RELINQUISH_WRAPPEDNV(args[3]);

    CAMLreturnT(int, retcode);
}

static int bpresetupfn(
    realtype t,
    N_Vector y,
    N_Vector yb,
    N_Vector fyb,
    booleantype jokb,
    booleantype *jcurPtrB,
    realtype gammab,
    void *user_data,
    N_Vector tmp1b,
    N_Vector tmp2b,
    N_Vector tmp3b)
{
    CAMLparam0();
    CAMLlocal3(session, sensext, r);
    CAMLlocalN(args, 3);
    value *backref = user_data;

    /* The presetup function must return a boolean (in addition to possible
     * exceptions), so, we do all of the setup here and directly call the
     * user-supplied OCaml function without going through an OCaml
     * trampoline.  */
    WEAK_DEREF (session, *backref);
    sensext = Field(session, RECORD_CVODES_SESSION_SENSEXT);

    args[0] = make_jac_arg(t, y, yb, fyb, make_triple_tmp(tmp1b, tmp2b, tmp3b));
    args[1] = Val_bool(jokb);
    args[2] = caml_copy_double(gammab);

    r = caml_callbackN_exn(CVODES_BPRESETUPFN_FROM_EXT (sensext),
                           sizeof (args) / sizeof (*args),
                           args);

    relinquish_jac_arg(args[0], TRIPLE);

    if (!Is_exception_result(r)) {
	*jcurPtr = Bool_val(r);
    }

    CAMLreturnT(int, check_exception(session, r));
}

static int bjactimesfn(
    N_Vector vb,
    N_Vector Jvb,
    realtype t,
    N_Vector y,
    N_Vector yb,
    N_Vector fyb,
    void *user_data,
    N_Vector tmpb)
{
    CAMLparam0();
    CAMLlocal1(r);
    CAMLlocalN(args, 4);
    int retcode;
    value *backref = user_data;
    CAML_FN (call_bjactimesfn);

    args[0] = *backref;
    args[1] = make_jac_arg(t, y, yb, fyb, WRAP_NVECTOR(tmpb));
    args[2] = WRAP_NVECTOR(vb);
    args[3] = WRAP_NVECTOR(Jvb);

    retcode = Int_val (caml_callbackN(*call_jactimesfn,
                                      sizeof (args) / sizeof (*args),
                                      args));

    relinquish_jac_arg(args[1], SINGLE);
    RELINQUISH_WRAPPEDNV(args[2]);
    RELINQUISH_WRAPPEDNV(args[3]);

    CAMLreturnT(int, retcode);
}

/* quadrature interface */

CAMLprim void CVTYPE(quad_init)(value vdata, value vq0)
{
    CAMLparam2(vdata, vq0);
    CAMLlocal1(r);
    int flag;
    N_Vector q0 = NVECTORIZE_VAL(vq0);
    
    flag = CVodeQuadInit(CVODE_MEM_FROM_ML(vdata), quadrhsfn, q0);
    RELINQUISH_NVECTORIZEDVAL(q0);
    CHECK_FLAG("CVodeQuadInit", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(quad_reinit)(value vdata, value vq0)
{
    CAMLparam2(vdata, vq0);
    CAMLlocal1(r);
    int flag;
    N_Vector q0 = NVECTORIZE_VAL(vq0);
    
    flag = CVodeQuadReInit(CVODE_MEM_FROM_ML(vdata), q0);
    RELINQUISH_NVECTORIZEDVAL(q0);
    CHECK_FLAG("CVodeQuadReInit", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(quad_sv_tolerances)(value vdata, value reltol,
					 value abstol)
{
    CAMLparam3(vdata, reltol, abstol);

    N_Vector atol_nv = NVECTORIZE_VAL(abstol);

    int flag = CVodeQuadSVtolerances(CVODE_MEM_FROM_ML(vdata),
	    Double_val(reltol), atol_nv);
    RELINQUISH_NVECTORIZEDVAL(atol_nv);
    CHECK_FLAG("CVodeQuadSVtolerances", flag);

    CAMLreturn0;
}

CAMLprim value CVTYPE(quad_get)(value vdata, value vyq)
{
    CAMLparam2(vdata, vyq);
    N_Vector yq = NVECTORIZE_VAL(vyq);
    realtype tret;

    int flag = CVodeGetQuad(CVODE_MEM_FROM_ML(vdata), &tret, yq);
    RELINQUISH_NVECTORIZEDVAL(yq);
    CHECK_FLAG("CVodeGetQuad", flag);

    CAMLreturn(caml_copy_double(tret));
}

CAMLprim void CVTYPE(quad_get_dky)(value vdata, value vt, value vk,
				   value vdkyq)
{
    CAMLparam4(vdata, vt, vk, vdkyq);
    N_Vector dkyq = NVECTORIZE_VAL(vdkyq);

    int flag = CVodeGetQuadDky(CVODE_MEM_FROM_ML(vdata), Double_val(vt),
	    Int_val(vk), dkyq);
	    
    RELINQUISH_NVECTORIZEDVAL(dkyq);
    CHECK_FLAG("CVodeGetQuadDky", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(quad_get_err_weights)(value vdata, value veqweight)
{
    CAMLparam2(vdata, veqweight);
    N_Vector eqweight = NVECTORIZE_VAL(veqweight);

    int flag = CVodeGetQuadErrWeights(CVODE_MEM_FROM_ML(vdata), eqweight);
    RELINQUISH_NVECTORIZEDVAL(eqweight);
    CHECK_FLAG("CVodeGetQuadErrWeights", flag);

    CAMLreturn0;
}

/* sensitivity interface */

CAMLprim void CVTYPE(sens_sv_tolerances)(value vdata, value reltol,
					 value abstol)
{
    CAMLparam3(vdata, reltol, abstol);

    N_Vector atol_nv = NVECTORIZE_VAL(abstol);

    int flag = CVodeSensSVtolerances(CVODE_MEM_FROM_ML(vdata),
	    Double_val(reltol), atol_nv);
    RELINQUISH_NVECTORIZEDVAL(atol_nv);
    CHECK_FLAG("CVodeSensSVtolerances", flag);

    CAMLreturn0;
}

static int decode_sens_method(value vmethod)
{
    switch (Int_val(vmethod)) {
    case VARIANT_CVODES_SENS_METHOD_SIMULTANEOUS:
	return CV_SIMULTANEOUS;

    case VARIANT_CVODES_SENS_METHOD_STAGGERED:
	return CV_STAGGERED;

    case VARIANT_CVODES_SENS_METHOD_STAGGERED1:
	return CV_STAGGERED1;

    default:
	caml_failwith("Illegal sens method.");
    }
}

CAMLprim void CVTYPE(sens_init)(value vdata, value vmethod, value vys0)
{
    CAMLparam3(vdata, vmethod, vys0);
    int ns = (int)caml_array_length(vys0);
    N_Vector *ys0 = nvector_table_to_array(vys0);


    int flag = CVodeSensInit(CVODE_MEM_FROM_ML(vdata), ns,
			     decode_sens_method(vmethod), sensrhsfn, ys0);
    free_nvector_array(ys0); 
    CHECK_FLAG("CVodeSensInit", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(sens_init_1)(value vdata, value vmethod, value vys0)
{
    CAMLparam3(vdata, vmethod, vys0);
    int ns = (int)caml_array_length(vys0);
    N_Vector *ys0 = nvector_table_to_array(vys0);


    int flag = CVodeSensInit1(CVODE_MEM_FROM_ML(vdata), ns,
			      decode_sens_method(vmethod), sensrhsfn1, ys0);
    free_nvector_array(ys0); 
    CHECK_FLAG("CVodeSensInit", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(sens_reinit)(value vdata, value method, value vs0)
{
    CAMLparam2(vdata, vq0);
    CAMLlocal1(r);
    int flag;
    N_Vector *s0 = nvector_table_to_array(vs0);
    
    flag = CVodeQuadReInit(CVODE_MEM_FROM_ML(vdata), quadrhsfn, s0);
    free_nvector_array(s0);
    CHECK_FLAG("CVodeQuadReInit", flag);

    CAMLreturn0;
}

CAMLprim value CVTYPE(sens_get)(value vdata, value vys)
{
    CAMLparam2(vdata, vyq);
    N_Vector *ys = nvector_table_to_array(vys);
    realtype tret;

    int flag = CVodeGetSens(CVODE_MEM_FROM_ML(vdata), &tret, ys);
    free_nvector_array(ys);
    CHECK_FLAG("CVodeGetSens", flag);

    CAMLreturn(caml_copy_double(tret));
}

CAMLprim void CVTYPE(sens_get_dky)(value vdata, value vt, value vk, value vdkys)
{
    CAMLparam4(vdata, vt, vk, vdkyq);
    N_Vector *dkys = nvector_table_to_array(vdkys);

    int flag = CVodeGetSensDky(CVODE_MEM_FROM_ML(vdata), Double_val(vt),
	    Int_val(vk), dkys);
    free_nvector_array(dkys);
    CHECK_FLAG("CVodeGetSensDky", flag);

    CAMLreturn0;
}

CAMLprim value CVTYPE(sens_get1)(value vdata, value vis, value vys)
{
    CAMLparam3(vdata, vis, vys);
    N_Vector ys = NVECTORIZE_VAL(vys);
    realtype tret;

    int flag = CVodeGetSens1(CVODE_MEM_FROM_ML(vdata), &tret, Int_val(vis), ys);
    RELINQUISH_NVECTORIZEDVAL(ys);
    CHECK_FLAG("CVodeGetSens1", flag);

    CAMLreturn(caml_copy_double(tret));
}

CAMLprim void CVTYPE(sens_get_dky1)(value vdata, value vt, value vk,
				     value vis, value vdkys)
{
    CAMLparam5(vdata, vt, vk, vis, vdkys);
    N_Vector dkys = NVECTORIZE_VAL(vdkys);

    int flag = CVodeGetSensDky1(CVODE_MEM_FROM_ML(vdata), Double_val(vt),
	    Int_val(vk), Int_val(vis), dkys);
	    
    RELINQUISH_NVECTORIZEDVAL(dkys);
    CHECK_FLAG("CVodeGetSensDky1", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(sens_get_err_weights)(value vdata, value vesweight)
{
    CAMLparam2(vdata, veqweight);
    N_Vector *esweight = nvector_table_to_array(vesweight);

    int flag = CVodeGetSensErrWeights(CVODE_MEM_FROM_ML(vdata), esweight);
    free_nvector_array(esweight);
    CHECK_FLAG("CVodeGetSensErrWeights", flag);

    CAMLreturn0;
}

/* sensitivity/quadrature interface */

CAMLprim void CVTYPE(quadsens_init)(value vdata, value vyqs0)
{
    CAMLparam2(vdata, vyqs0);
    int ns = (int)caml_array_length(vyqs0);
    N_Vector *yqs0 = nvector_table_to_array(vyqs0);

    int flag = CVodeQuadSensInit(CVODE_MEM_FROM_ML(vdata), quadsensrhsfn, yqs0);
    free_nvector_array(yqs0); 
    CHECK_FLAG("CVodeQuadSensInit", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(quadsens_reinit)(value vdata, value vyqs0)
{
    CAMLparam2(vdata, vyqs0);
    N_Vector *yqs0 = nvector_table_to_array(vyqs0);

    int flag = CVodeQuadSensReInit(CVODE_MEM_FROM_ML(vdata), yqs0);
    free_nvector_array(yqs0); 
    CHECK_FLAG("CVodeQuadSensReInit", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(quadsens_sv_tolerances)(value vdata, value reltol,
					     value abstol)
{
    CAMLparam3(vdata, reltol, abstol);
    N_Vector atol_nv = NVECTORIZE_VAL(abstol);

    int flag = CVodeQuadSensSVtolerances(CVODE_MEM_FROM_ML(vdata),
	    Double_val(reltol), atol_nv);
    RELINQUISH_NVECTORIZEDVAL(atol_nv);
    CHECK_FLAG("CVodeQuadSensSVtolerances", flag);

    CAMLreturn0;
}

CAMLprim value CVTYPE(quadsens_get)(value vdata, value vyqs)
{
    CAMLparam2(vdata, vyqs);
    N_Vector *yqs = nvector_table_to_array(vyqs);
    realtype tret;

    int flag = CVodeGetQuadSens(CVODE_MEM_FROM_ML(vdata), &tret, yqs);
    free_nvector_array(yqs); 
    CHECK_FLAG("CVodeGetQuadSens", flag);

    CAMLreturn(caml_copy_double(tret));
}

CAMLprim value CVTYPE(quadsens_get1)(value vdata, value vis, value vyqs)
{
    CAMLparam3(vdata, vis, vyqs);
    N_Vector *yqs = nvector_table_to_array(vyqs);
    realtype tret;

    int flag = CVodeGetQuadSens1(CVODE_MEM_FROM_ML(vdata), &tret,
			         Int_val(vis), yqs);
    free_nvector_array(yqs); 
    CHECK_FLAG("CVodeGetQuadSens1", flag);

    CAMLreturn(caml_copy_double(tret));
}

CAMLprim void CVTYPE(quadsens_get_dky)(value vdata, value vt, value vk,
				       value vdkyqs)
{
    CAMLparam4(vdata, vt, vk, vdkyqs);
    N_Vector *dkyqs = nvector_table_to_array(vdkyqs);

    int flag = CVodeGetQuadSensDky(CVODE_MEM_FROM_ML(vdata), Double_val(vt),
				   Int_val(vk), dkyqs);
    free_nvector_array(dkyqs); 
    CHECK_FLAG("CVodeGetQuadSensDky", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(quadsens_get_dky1)(value vdata, value vt, value vk,
					value vis, value vdkyqs)
{
    CAMLparam5(vdata, vt, vk, vis, vdkyqs);
    N_Vector *dkyqs = nvector_table_to_array(vdkyqs);

    int flag = CVodeGetQuadSensDky1(CVODE_MEM_FROM_ML(vdata), Double_val(vt),
				    Int_val(vk), Int_val(vis), dkyqs);
    free_nvector_array(dkyqs); 
    CHECK_FLAG("CVodeGetQuadSensDky1", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(quadsens_get_err_weights)(value vdata, value veqweights)
{
    CAMLparam2(vdata, veqweights);
    N_Vector *eqweights = nvector_table_to_array(veqweights);

    int flag = CVodeGetQuadSensErrWeights(CVODE_MEM_FROM_ML(vdata), eqweights);
    free_nvector_array(eqweights); 
    CHECK_FLAG("CVodeGetQuadSensErrWeights", flag);

    CAMLreturn0;
}

/* adjoint interface */

CAMLprim value CVTYPE(adj_forward_normal)(value vdata, value vtout, value vyret)
{
    CAMLparam3(vdata, vtout, vyret);
    N_Vector yret = WRAP_NVECTOR(vyret);
    realtype tret;
    int ncheck;

    int flag = CVodeF(CVODE_MEM_FROM_ML(vdata), Double_val(vtout), yret,
		      &tret, CV_NORMAL, &ncheck);
    RELINQUISH_WRAPPEDNV(yret);
    CHECK_FLAG("CVodeF", flag);

    r = caml_alloc_tuple(2);
    Store_field(r, 0, caml_copy_double(tret));
    Store_field(r, 1, Val_int(ncheck));

    CAMLreturn(r);
}

CAMLprim value CVTYPE(adj_forward_one_step)(value vdata, value vtout,
					    value vyret)
{
    CAMLparam3(vdata, vtout, vyret);
    N_Vector yret = WRAP_NVECTOR(vyret);
    realtype tret;
    int ncheck;

    int flag = CVodeF(CVODE_MEM_FROM_ML(vdata), Double_val(vtout), yret,
		      &tret, CV_ONE_STEP, &ncheck);
    RELINQUISH_WRAPPEDNV(yret);
    CHECK_FLAG("CVodeF", flag);

    r = caml_alloc_tuple(2);
    Store_field(r, 0, caml_copy_double(tret));
    Store_field(r, 1, Val_int(ncheck));

    CAMLreturn(r);
}

CAMLprim void CVTYPE(adj_sv_tolerances)(value vparent, value vwhich,
					value vreltol, value vabstol)
{
    CAMLparam4(vparent, vwhich, vreltol, vabstol);
    N_Vector atol_nv = NVECTORIZE_VAL(vabstol);

    int flag = CVodeSStolerancesB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
				  Double_val(vreltol), atol_nv);
    RELINQUISH_NVECTORIZEDVAL(atol_nv);
    CHECK_FLAG("CVodeSStolerancesB", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_spils_set_preconditioner)(value vparent,
						   value vwhich,
						   value vset_presetup,
						   value vset_jac)
{
    CAMLparam4(vparent, vwhich, vset_presetup, vset_jac);
    int flag;
    void *mem = CVODE_MEM_FROM_ML(vparent);
    CVSpilsPrecSetupFnB bsetup = Bool_val(vset_presetup) ? bpresetupfn : NULL;

    flag = CVSpilsSetPreconditionerB(mem, Int_val(vwhich), bsetup, bpresolvefn);
    CHECK_FLAG ("CVSpilsSetPreconditionerB", flag);
    if (Bool_val(vset_jac)) {
	flag = CVSpilsSetJacTimesVecFnB(mem, bjactimesfn);
	CHECK_FLAG ("CVSpilsSetJacTimesVecFnB", flag);
    }

    CAMLreturn0;
}

/* Dense and Band can only be used with serial NVectors.  */
#ifdef CVODE_ML_BIGARRAYS
CAMLprim void CVTYPE(adj_dls_dense)(value vparent, value vwhich, value vset_jac)
{
    CAMLparam3(vparent, vwhich, vset_jac);
    void *cvode_mem = CVODE_MEM_FROM_ML (vparent);
    long neqs = CVODE_NEQS_FROM_ML (vcvode_mem);
    int which = Int_val(vwhich);
    int flag;

    flag = CVodeSetIterTypeB (cvode_mem, which, CV_NEWTON);
    CHECK_FLAG ("CVodeSetIterTypeB", flag);
    flag = CVDenseB (cvode_mem, which, neqs);
    CHECK_FLAG ("CVDenseB", flag);
    if (Bool_val (vset_jac)) {
	flag = CVDlsSetDenseJacFnB(cvode_mem, which, jacfn);
	CHECK_FLAG("CVDlsSetDenseJacFnB", flag);
    }
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_dls_lapack_dense)(value vparent, value vwhich,
					   value vset_jac)
{
    CAMLparam3 (vparent, vwhich, vset_jac);
#if SUNDIALS_BLAS_LAPACK
    void *cvode_mem = CVODE_MEM_FROM_ML (vparent);
    long neqs = CVODE_NEQS_FROM_ML (vcvode_mem);
    int which = Int_val(vwhich);
    int flag;

    flag = CVodeSetIterTypeB (cvode_mem, which, CV_NEWTON);
    CHECK_FLAG ("CVodeSetIterTypeB", flag);
    flag = CVLapackDense (cvode_mem, which, neqs);
    CHECK_FLAG ("CVLapackDenseB", flag);
    if (Bool_val (vset_jac)) {
	flag = CVDlsSetDenseJacFnB (cvode_mem, which, jacfn);
	CHECK_FLAG("CVDlsSetDenseJacFnB", flag);
    }
#else
    caml_failwith("Lapack solvers are not available.");
#endif
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_dls_set_dense_jac_fn)(value vparent, value vwhich)
{
    CAMLparam2(vparent, vwhich);
    int flag = CVDlsSetDenseJacFnB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
				   jacfn);
    CHECK_FLAG("CVDlsSetDenseJacFnB", flag);
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_dls_clear_dense_jac_fn)(value vparent, value vwhich)
{
    CAMLparam2(vdata, vwhich);
    int flag = CVDlsSetDenseJacFnB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
				   NULL);
    CHECK_FLAG("CVDlsSetDenseJacFnB", flag);
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_dls_band) (value vparent, value vwhich,
				    value vmupper, value vmlower,
				    value vset_jac)
{
    CAMLparam5(vparent, vwhich, vmupper, vmlower, vset_jac);
    void *cvode_mem = CVODE_MEM_FROM_ML (vcvode_mem);
    long neqs = CVODE_NEQS_FROM_ML (vcvode_mem);
    int which = Int_val(vwhich);
    int flag;

    flag = CVodeSetIterTypeB (cvode_mem, which, CV_NEWTON);
    CHECK_FLAG ("CVodeSetIterTypeB", flag);
    flag = CVBandB (cvode_mem, which, neqs,
		    Long_val (vmupper), Long_val (vmlower));
    CHECK_FLAG ("CVBandB", flag);
    if (Bool_val (vset_jac)) {
	flag = CVDlsSetBandJacFnB(cvode_mem, which, bandjacfn);
	CHECK_FLAG("CVDlsSetBandJacFnB", flag);
    }
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_dls_lapack_band) (value vparent, value vwhich,
					   value vmupper, value vmlower,
					   value vset_jac)
{
    CAMLparam5(vparent, vwhich, vmupper, vmlower, vset_jac);
#if SUNDIALS_BLAS_LAPACK
    void *cvode_mem = CVODE_MEM_FROM_ML (vcvode_mem);
    long neqs = CVODE_NEQS_FROM_ML (vcvode_mem);
    int which = Int_val(vwhich);
    int flag;

    flag = CVodeSetIterTypeB (cvode_mem, which, CV_NEWTON);
    CHECK_FLAG ("CVodeSetIterTypeB", flag);
    flag = CVLapackBandB (cvode_mem, which, neqs,
			  Long_val (vmupper), Long_val (vmlower));
    CHECK_FLAG ("CVLapackBandB", flag);
    if (Bool_val (vset_jac)) {
	flag = CVDlsSetBandJacFnB(cvode_mem, which, bandjacfn);
	CHECK_FLAG("CVDlsSetBandJacFnB", flag);
    }
#else
    caml_failwith("Lapack solvers are not available.");
#endif
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_dls_set_band_jac_fn)(value vparent, value vwhich)
{
    CAMLparam2(vparent, vwhich);
    int flag = CVDlsSetBandJacFnB(CVODE_MEM_FROM_ML(vdata), Int_val(vwhich),
				  bandjacfn);
    CHECK_FLAG("CVDlsSetBandJacFnB", flag);
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_dls_clear_band_jac_fn)(value vparent, value vwhich)
{
    CAMLparam2(vparent, vwhich);
    int flag = CVDlsSetBandJacFnB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
				  NULL);
    CHECK_FLAG("CVDlsSetBandJacFnB", flag);
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_spils_banded_spgmr) (value vparent_which,
					      value vmupper, value vmlower,
					      value vmaxl, value vtype)
{
    CAMLparam5 (vparent_which, vmupper, vmlower, vmaxl, vtype);
    void *cvode_mem = CVODE_MEM_FROM_ML (Field(vparent_which, 0));
    long neqs = CVODE_NEQS_FROM_ML (vcvode_mem);
    int which = Int_val(Field(vparent_which, 1));
    int flag;

    flag = CVodeSetIterTypeB (cvode_mem, which, CV_NEWTON);
    CHECK_FLAG ("CVodeSetIterTypeB", flag);
    flag = CVSpgmrB (cvode_mem, which, spils_precond_type (vtype),
		     Int_val (vmaxl));
    CHECK_FLAG ("CVSpgmrB", flag);
    flag = CVBandPrecInitB (cvode_mem, which, neqs,
			    Long_val (vmupper), Long_val (vmlower));
    CHECK_FLAG ("CVBandPrecInitB", flag);
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_spils_banded_spbcg) (value vparent_which,
					      value vmupper, value vmlower,
					      value vmaxl, value vtype)
{
    CAMLparam5 (vparent_which, vmupper, vmlower, vmaxl, vtype);
    void *cvode_mem = CVODE_MEM_FROM_ML (Field(vparent_which, 0));
    long neqs = CVODE_NEQS_FROM_ML (vcvode_mem);
    int which = Int_val(Field(vparent_which, 1));
    int flag;

    flag = CVodeSetIterTypeB (cvode_mem, which, CV_NEWTON);
    CHECK_FLAG ("CVodeSetIterTypeB", flag);
    flag = CVSpbcgB (cvode_mem, which, spils_precond_type (vtype),
		     Int_val (vmaxl));
    CHECK_FLAG ("CVSpbcgB", flag);
    flag = CVBandPrecInitB (cvode_mem, which, neqs,
			    Long_val (vmupper), Long_val (vmlower));
    CHECK_FLAG ("CVBandPrecInitB", flag);
    CAMLreturn0;
}

CAMLprim void CVTYPE(adj_spils_banded_sptfqmr) (value vparent_which,
					        value vmupper, value vmlower,
					        value vmaxl, value vtype)
{
    CAMLparam5 (vparent_which, vmupper, vmlower, vmaxl, vtype);
    void *cvode_mem = CVODE_MEM_FROM_ML (Field(vparent_which, 0));
    long neqs = CVODE_NEQS_FROM_ML (vcvode_mem);
    int which = Int_val(Field(vparent_which, 1));
    int flag;

    flag = CVodeSetIterTypeB (cvode_mem, which, CV_NEWTON);
    CHECK_FLAG ("CVodeSetIterTypeB", flag);
    flag = CVSptfqmrB (cvode_mem, which, spils_precond_type (vtype),
		       Int_val (vmaxl));
    CHECK_FLAG ("CVSptfqmrB", flag);
    flag = CVBandPrecInitB (cvode_mem, which, neqs,
			    Long_val (vmupper), Long_val (vmlower));
    CHECK_FLAG ("CVBandPrecInitB", flag);
    CAMLreturn0;
}

#endif

CAMLprim value CVTYPE(adj_init_backward)(value vparent, value weakref,
					 value vargs, value vwithsens)
{
    CAMLparam4(vparent, weakref, vargs, vwithsens)
    CAMLlocal1(r);
    CAMLlocal2(vlmm, viter);
    realtype tb0;
    N_Vector initial_nv;
    int flag, lmm_c, which;
    void *parent = CVODE_MEM_FROM_ML(vparent);

    lmm = Field(vargs, 0);
    iter = Field(vargs, 1);
    tb0 = Double_val(Field(vargs, 2));
    initial_nv = NVECTORIZE_VAL(Field(vargs, 3));

    switch (Int_val(lmm)) {
    case VARIANT_CVODE_LMM_ADAMS:
	lmm_c = CV_ADAMS;
	break;

    case VARIANT_CVODE_LMM_BDF:
	lmm_c = CV_BDF;
	break;

    default:
	caml_failwith("Illegal lmm value.");
    }

    int iter_c;
    if (Is_block(iter)) {
	iter_c = CV_NEWTON;
    } else {
	iter_c = CV_FUNCTIONAL;
    }

    flag = CVodeCreateB(parent, lmm_c, iter_c, &which);
    if (flag != CV_SUCCESS) {
	CHECK_FLAG("CVodeCreateB", flag);
    }

    if (Bool_val(vwithsens)) {
	flag = CVodeInitBS(parent, which, brhsfn1, tb0, initial_nv);
	RELINQUISH_NVECTORIZEDVAL(initial_nv);
	if (flag != CV_SUCCESS) {
	    CHECK_FLAG("CVodeInitBS", flag);
	}
    } else {
	flag = CVodeInitB(parent, which, brhsfn, tb0, initial_nv);
	RELINQUISH_NVECTORIZEDVAL(initial_nv);
	if (flag != CV_SUCCESS) {
	    CHECK_FLAG("CVodeInitB", flag);
	}
    }

    value *backref;
    backref = malloc (sizeof (*backref));
    if (backref == NULL) {
	caml_raise_out_of_memory();
    }
    *backref = weakref;
    caml_register_generational_global_root (backref);
    CVodeSetUserDataB (parent, which, backref);

    r = caml_alloc_tuple (4);
    Store_field (r, 0, (value)CVodeGetAdjCVodeBmem(parent, which));
    Store_field (r, 1, Val_int(which));
    Store_field (r, 2, (value)backref);
    Store_field (r, 3, Val_long (0)); /* no err_file = NULL */

    CAMLreturn(r);
}

CAMLprim void CVTYPE(adj_reinit)(value vparent, value vwhich,
				 value vtb0, value vyb0)
{
    CAMLparam4(vparent, vwhich, vtb0, vyb0);
    CAMLlocal1(r);
    int flag;
    N_Vector yb0 = NVECTORIZE_VAL(vyb0);
    
    flag = CVodeReInitB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
			Double_val(vtb0), yb0);
    RELINQUISH_NVECTORIZEDVAL(yb0);
    CHECK_FLAG("CVodeReInitB", flag);

    CAMLreturn0;
}

CAMLprim value CVTYPE(adj_get)(value vparent, value vwhich, value vyb)
{
    CAMLparam3(vparent, vwhich, vyb);
    N_Vector yq = NVECTORIZE_VAL(vyb);
    realtype tret;

    int flag = CVodeGetB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
			 &tret, yb);
    RELINQUISH_NVECTORIZEDVAL(yq);
    CHECK_FLAG("CVodeGetB", flag);

    CAMLreturn(caml_copy_double(tret));
}

/* adjoint/quadrature interface */

CAMLprim void CVTYPE(adjquad_initb)(value vparent, value vwhich, value vyqb0)
{
    CAMLparam3(vdata, vwhich, vyqb0);
    CAMLlocal1(r);
    int flag;
    N_Vector yqb0 = NVECTORIZE_VAL(vyqb0);
    
    flag = CVodeQuadInitB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
			  bquadrhsfn, yqb0);
    RELINQUISH_NVECTORIZEDVAL(yqb0);
    CHECK_FLAG("CVodeQuadInitB", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(adjquad_initbs)(value vparent, value vwhich, value vyqb0)
{
    CAMLparam3(vdata, vwhich, vyqb0);
    CAMLlocal1(r);
    int flag;
    N_Vector yqb0 = NVECTORIZE_VAL(vyqb0);
    
    flag = CVodeQuadInitBS(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
			   bquadrhsfn1, yqb0);
    RELINQUISH_NVECTORIZEDVAL(yqb0);
    CHECK_FLAG("CVodeQuadInitBS", flag);

    CAMLreturn0;
}

CAMLprim void CVTYPE(adjquad_reinit)(value vparent, value vwhich, value vyqb0)
{
    CAMLparam3(vparent, vwhich, vyqb0);
    CAMLlocal1(r);
    int flag;
    N_Vector yqb0 = NVECTORIZE_VAL(vyqb0);
    
    flag = CVodeQuadReInitB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich), yqb0);
    RELINQUISH_NVECTORIZEDVAL(yqb0);
    CHECK_FLAG("CVodeQuadReInitB", flag);

    CAMLreturn0;
}

CAMLprim value CVTYPE(adjquad_get)(value vparent, value vwhich, value vyqb)
{
    CAMLparam3(vparent, vwhich, vyqb);
    CAMLlocal1(r);
    N_Vector yqb = NVECTORIZE_VAL(vyqb);
    realtype tret;

    int flag = CVodeGetQuadB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
			     &tret, yqb);
    RELINQUISH_NVECTORIZEDVAL(yqb);
    CHECK_FLAG("CVodeGetQuadB", flag);

    CAMLreturn(caml_copy_double(tret));
}

CAMLprim void CVTYPE(adjquad_sv_tolerances)(value vparent, value vwhich,
					    value vreltol, value vabstol)
{
    CAMLparam4(vparent, vwhich, vreltol, vabstol);
    N_Vector atol_nv = NVECTORIZE_VAL(vabstol);

    int flag = CVodeQuadSVtolerancesB(CVODE_MEM_FROM_ML(vparent), Int_val(vwhich),
				      Double_val(reltol), atol_nv);
    RELINQUISH_NVECTORIZEDVAL(atol_nv);
    CHECK_FLAG("CVodeQuadSVtolerancesB", flag);

    CAMLreturn0;
}

