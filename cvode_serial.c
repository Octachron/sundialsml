/* Aug 2010, Timothy Bourke (INRIA)
 *
 * Ocaml interface to the Sundials 2.4.0 CVode solver for serial NVectors.
 *
 */

#include <caml/mlvalues.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/unixsupport.h>

/* TODO:
 * - realtype must equal double
 * - we assume (in BIGARRAY_INT) that an int is 32-bits
 *   (this should be configured per platform.)
 */

/*
 * TODO:
 * - call Gc.full_major () from the f and roots routines to see if we get
 *   any segmentation fault problems.
 */

#include <cvode/cvode.h>
#include <nvector/nvector_serial.h>
#include <sundials/sundials_config.h>
#include <sundials/sundials_types.h>

/* linear solvers */
#include <cvode/cvode_dense.h>
#include <cvode/cvode_band.h>
#include <cvode/cvode_diag.h>
#include <cvode/cvode_spgmr.h>
#include <cvode/cvode_spbcgs.h>
#include <cvode/cvode_sptfqmr.h>

#if SUNDIALS_BLAS_LAPACK == 1
#include <cvode/cvode_lapack.h>
#endif

#include <stdio.h>

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
#define VARIANT_LINEAR_SOLVER_BAND	    0
#define VARIANT_LINEAR_SOLVER_LAPACKBAND    1
#define VARIANT_LINEAR_SOLVER_SPGMR	    2
#define VARIANT_LINEAR_SOLVER_SPBCG	    3
#define VARIANT_LINEAR_SOLVER_SPTFQMR	    4

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

#define BIGARRAY_FLOAT (CAML_BA_FLOAT64 | CAML_BA_C_LAYOUT)
#define BIGARRAY_INT (CAML_BA_INT32 | CAML_BA_C_LAYOUT)
#define MAX_ERRMSG_LEN 256

static void check_flag(const char *call, int flag, void *to_free);

// TODO: Is there any risk that the Ocaml GC will try to free the
//	 closures? Do we have to somehow record that we're using them,
//	 and then release them again in the free routine?
//	 SEE: ml_cvode_data_alloc and finalize
struct ml_cvode_data {
    void *cvode_mem;
    long int neq;
    intnat num_roots;
    value *closure_rhsfn;
    value *closure_rootsfn;
    value *closure_errh;

    value *closure_jacfn;
    value *closure_bandjacfn;
    value *closure_presetupfn;
    value *closure_presolvefn;
    value *closure_jactimesfn;

    FILE *err_file;
};

typedef struct ml_cvode_data* ml_cvode_data_p;

static void finalize_closure(value** closure_field)
{
    if (*closure_field != NULL) {
	caml_remove_generational_global_root(*closure_field);
	*closure_field = NULL;
    }
}

static void finalize(value vdata)
{
    ml_cvode_data_p data = (ml_cvode_data_p)Data_custom_val(vdata);

    // TODO:
    // The Ocaml Manual (18.9.1) says:
    // ``Note: the finalize, compare, hash, serialize and deserialize
    // functions attached to custom block descriptors must never trigger a
    // garbage collection. Within these functions, do not call any of the
    // Caml allocation functions, and do not perform a callback into Caml
    // code. Do not use CAMLparam to register the parameters to these
    // functions, and do not use CAMLreturn to return the result.''
    //
    // But, obviously, we're calling two caml functions. We need to find out
    // if this is ok.
    finalize_closure(&(data->closure_rhsfn));
    finalize_closure(&(data->closure_rootsfn));
    finalize_closure(&(data->closure_errh));

    finalize_closure(&(data->closure_jacfn));
    finalize_closure(&(data->closure_bandjacfn));
    finalize_closure(&(data->closure_presetupfn));
    finalize_closure(&(data->closure_presolvefn));
    finalize_closure(&(data->closure_jactimesfn));

    if (data->cvode_mem != NULL) {
	CVodeFree(&(data->cvode_mem));
    }

    if (data->err_file != NULL) {
	fclose(data->err_file);
	data->err_file = NULL;
    }
}

// TODO:
// The Ocaml Manual (18.9.3) says:
// ``The contents of custom blocks are not scanned by the garbage collector,
// and must therefore not contain any pointer inside the Caml heap. In other
// terms, never store a Caml value in a custom block, and do not use Field,
// Store_field nor caml_modify to access the data part of a custom block.
// Conversely, any C data structure (not containing heap pointers) can be
// stored in a custom block.''
//
// But, obviously, we're storing two closure values in the struct. We need
// to find out if and when this is ok.
//
static value ml_cvode_data_alloc(mlsize_t approx_size)
{
    return caml_alloc_final(sizeof(struct ml_cvode_data), &finalize,
			    approx_size, 10);
}

static ml_cvode_data_p cvode_data_from_ml(value vdata)
{
    ml_cvode_data_p data = (ml_cvode_data_p)Data_custom_val(vdata);
    if (data->cvode_mem == NULL) {
	caml_failwith("This session has been freed");
    }

    return data;
}

static int check_exception(value r)
{
    CAMLparam0();
    CAMLlocal1(exn);

    static value *recoverable_failure = NULL;

    if (!Is_exception_result(r)) return 0;

    if (recoverable_failure == NULL) {
	recoverable_failure =
	    caml_named_value("cvode_RecoverableFailure");
    }

    exn = Extract_exception(r);
    CAMLreturn((Field(exn, 0) == *recoverable_failure) ? 1 : -1);
}

/* callbacks */

static value wrap_nvector(N_Vector v)
{
    CAMLparam0();
    CAMLlocal1(v_ba);

    intnat v_l = NV_LENGTH_S(v);
    v_ba = caml_ba_alloc(BIGARRAY_FLOAT, 1, NV_DATA_S(v), &v_l);

    CAMLreturn(v_ba);
}

static void relinquish_nvector_wrapping(value v_ba)
{
    Caml_ba_array_val(v_ba)->dim[0] = 0;
}

static N_Vector vectorize_bigarray(value ba)
{
    int l = Caml_ba_array_val(ba)->dim[0];
    realtype *d = Caml_ba_data_val(ba);
    N_Vector nv = N_VMake_Serial(l, d);

    return nv;
}

static void relinquish_vectorized_bigarray(N_Vector nv)
{
    N_VDestroy(nv);
}


static int f(realtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    CAMLparam0();
    CAMLlocal3(y_ba, ydot_ba, r);

    value *closure_rhsfn = ((ml_cvode_data_p)user_data)->closure_rhsfn;

    y_ba = wrap_nvector(y);
    ydot_ba = wrap_nvector(ydot);

    // TODO: the data payloads inside y_ba and ydot_ba are only valid
    //	     during this call, afterward that memory goes back to cvode.
    //	     These bigarrays must not be retained by closure_rhsfn! If
    //	     it wants a permanent copy, then it has to make it manually.
    //
    //       Eventually y_ba and ydot_ba will be reclaimed by the ocaml gc,
    //       which should not, however, free the attached payload.
    r = caml_callback3_exn(*closure_rhsfn, caml_copy_double(t), y_ba, ydot_ba);

    relinquish_nvector_wrapping(y_ba);
    relinquish_nvector_wrapping(ydot_ba);

    CAMLreturn(check_exception(r));
}

static int roots(realtype t, N_Vector y, realtype *gout, void *user_data)
{
    CAMLparam0();
    CAMLlocal3(y_ba, gout_ba, r);

    ml_cvode_data_p data = (ml_cvode_data_p)user_data;

    y_ba = wrap_nvector(y);
    gout_ba = caml_ba_alloc(BIGARRAY_FLOAT, 1, gout, &(data->num_roots));

    // TODO: see notes for f()
    r = caml_callback3_exn(*(data->closure_rootsfn), caml_copy_double(t),
				 y_ba, gout_ba);

    relinquish_nvector_wrapping(y_ba);
    Caml_ba_array_val(gout_ba)->dim[0] = 0;

    CAMLreturn(check_exception(r));
}

static void errh(
	int error_code,
	const char *module,
	const char *func,
	char *msg,
	void *eh_data)
{
    CAMLparam0();
    CAMLlocal1(a);

    value *closure_errh = ((ml_cvode_data_p)eh_data)->closure_errh;

    a = caml_alloc_tuple(4);
    Store_field(a, RECORD_ERROR_DETAILS_ERROR_CODE, Val_int(error_code));
    Store_field(a, RECORD_ERROR_DETAILS_MODULE_NAME, caml_copy_string(module));
    Store_field(a, RECORD_ERROR_DETAILS_FUNCTION_NAME, caml_copy_string(func));
    Store_field(a, RECORD_ERROR_DETAILS_ERROR_MESSAGE, caml_copy_string(msg));

    caml_callback(*closure_errh, a);

    CAMLreturn0;
}

static value make_jac_arg(realtype t, N_Vector y, N_Vector fy, value tmp)
{
    CAMLparam0();
    CAMLlocal1(r);

    r = caml_alloc_tuple(4);
    Store_field(r, RECORD_JACOBIAN_ARG_JAC_T, caml_copy_double(t));
    Store_field(r, RECORD_JACOBIAN_ARG_JAC_Y, wrap_nvector(y));
    Store_field(r, RECORD_JACOBIAN_ARG_JAC_FY, wrap_nvector(fy));
    Store_field(r, RECORD_JACOBIAN_ARG_JAC_TMP, tmp);

    CAMLreturn(r);
}

static value make_triple_tmp(N_Vector tmp1, N_Vector tmp2, N_Vector tmp3)
{
    CAMLparam0();
    CAMLlocal1(r);

    r = caml_alloc_tuple(3);
    Store_field(r, 0, wrap_nvector(tmp1));
    Store_field(r, 1, wrap_nvector(tmp2));
    Store_field(r, 2, wrap_nvector(tmp3));
    CAMLreturn(r);
}

static relinquish_jac_arg(value arg, int triple)
{
    CAMLparam0();
    CAMLlocal1(tmp);

    relinquish_nvector_wrapping(Field(arg, RECORD_JACOBIAN_ARG_JAC_Y));
    relinquish_nvector_wrapping(Field(arg, RECORD_JACOBIAN_ARG_JAC_FY));

    tmp = Field(arg, RECORD_JACOBIAN_ARG_JAC_TMP);

    if (triple) {
	relinquish_nvector_wrapping(Field(tmp, 0));
	relinquish_nvector_wrapping(Field(tmp, 1));
	relinquish_nvector_wrapping(Field(tmp, 2));
    } else {
	relinquish_nvector_wrapping(tmp);
    }

    CAMLreturn0;
}

static int jacfn(
	int n,
	realtype t,
	N_Vector y,
	N_Vector fy,	     
	DlsMat Jac,
	void *user_data,
	N_Vector tmp1,
	N_Vector tmp2,
	N_Vector tmp3)
{
    CAMLparam0();
    CAMLlocal3(arg, r, matrix);

    ml_cvode_data_p data = (ml_cvode_data_p)user_data;

    arg = make_jac_arg(t, y, fy, make_triple_tmp(tmp1, tmp2, tmp3));

    matrix = caml_alloc(1, Abstract_tag);
    Store_field(matrix, 0, (value)Jac);

    r = caml_callback2_exn(*(data->closure_jacfn), arg, matrix);

    relinquish_jac_arg(arg, 1);
    // note: matrix is also invalid after the callback

    CAMLreturn(check_exception(r));
}

static int bandjacfn(
	int N,
	int mupper,
	int mlower, 	 
	realtype t,
	N_Vector y,
	N_Vector fy, 	 
	DlsMat Jac,
	void *user_data, 	 
	N_Vector tmp1,
	N_Vector tmp2,
	N_Vector tmp3)
{
    CAMLparam0();
    CAMLlocal1(r);
    CAMLlocalN(args, 4);

    ml_cvode_data_p data = (ml_cvode_data_p)user_data;

    args[0] = Val_int(mupper);
    args[1] = Val_int(mlower);
    args[2] = make_jac_arg(t, y, fy, make_triple_tmp(tmp1, tmp2, tmp3));
    args[3] = caml_alloc(1, Abstract_tag);
    Store_field(args[3], 0, (value)Jac);

    r = caml_callbackN_exn(*(data->closure_bandjacfn), 4, args);

    relinquish_jac_arg(args[2], 1);
    // note: matrix is also invalid after the callback

    CAMLreturn(check_exception(r));
}

static int presetupfn(
    realtype t,
    N_Vector y,
    N_Vector fy,
    booleantype jok,
    booleantype *jcurPtr,
    realtype gamma,
    void *user_data,
    N_Vector tmp1,
    N_Vector tmp2,
    N_Vector tmp3)
{
    CAMLparam0();
    CAMLlocal2(arg, r);

    ml_cvode_data_p data = (ml_cvode_data_p)user_data;

    arg = make_jac_arg(t, y, fy, make_triple_tmp(tmp1, tmp2, tmp3));

    r = caml_callback3_exn(*(data->closure_presetupfn),
	    arg, Val_bool(jok), caml_copy_double(gamma));

    relinquish_jac_arg(arg, 1);

    if (!Is_exception_result(r)) {
	*jcurPtr = Bool_val(r);
    }

    CAMLreturn(check_exception(r));
}

#define RECORD_SPILS_SOLVE_ARG_RHS	0
#define RECORD_SPILS_SOLVE_ARG_GAMMA	1
#define RECORD_SPILS_SOLVE_ARG_DELTA	2
#define RECORD_SPILS_SOLVE_ARG_LEFT	3

static value make_spils_solve_arg(
	N_Vector r,
	realtype gamma,
	realtype delta,
	int lr)

{
    CAMLparam0();
    CAMLlocal1(v);

    v = caml_alloc_tuple(4);
    Store_field(v, RECORD_SPILS_SOLVE_ARG_RHS, wrap_nvector(r));
    Store_field(v, RECORD_SPILS_SOLVE_ARG_GAMMA, caml_copy_double(gamma));
    Store_field(v, RECORD_SPILS_SOLVE_ARG_DELTA, caml_copy_double(delta));
    Store_field(v, RECORD_SPILS_SOLVE_ARG_LEFT, lr == 1 ? Val_true : Val_false);

    CAMLreturn(v);
}

static relinquish_spils_solve_arg(value arg)
{
    CAMLparam0();
    relinquish_nvector_wrapping(Field(arg, RECORD_SPILS_SOLVE_ARG_RHS));
    CAMLreturn0;
}

static int presolvefn(
	realtype t,
	N_Vector y,
	N_Vector fy,
	N_Vector r,
	N_Vector z,
	realtype gamma,
	realtype delta,
	int lr,
	void *user_data,
	N_Vector tmp)
{
    CAMLparam0();
    CAMLlocal4(arg, solvearg, zv, rv);

    ml_cvode_data_p data = (ml_cvode_data_p)user_data;

    arg = make_jac_arg(t, y, fy, wrap_nvector(tmp));
    solvearg = make_spils_solve_arg(r, gamma, delta, lr);
    zv = wrap_nvector(z);

    rv = caml_callback3_exn(*(data->closure_presolvefn), arg, solvearg, zv);

    relinquish_jac_arg(arg, 0);
    relinquish_spils_solve_arg(solvearg);
    relinquish_nvector_wrapping(zv);

    CAMLreturn(check_exception(rv));
}

static int jactimesfn(
    N_Vector v,
    N_Vector Jv,
    realtype t,
    N_Vector y,
    N_Vector fy,
    void *user_data,
    N_Vector tmp)
{
    CAMLparam0();
    CAMLlocal4(arg, varg, jvarg, r);

    ml_cvode_data_p data = (ml_cvode_data_p)user_data;

    arg = make_jac_arg(t, y, fy, wrap_nvector(tmp));
    varg = wrap_nvector(v);
    jvarg = wrap_nvector(Jv);

    r = caml_callback3_exn(*(data->closure_jactimesfn), arg, varg, jvarg);

    relinquish_jac_arg(arg, 0);
    relinquish_nvector_wrapping(varg);
    relinquish_nvector_wrapping(jvarg);

    CAMLreturn(check_exception(r));
}

/* basic interface */

static mlsize_t approx_size_cvode_mem(void *cvode_mem)
{
    mlsize_t used = 0;
    long int lenrw = 0;
    long int leniw = 0;
    int flag = CVodeGetWorkSpace(cvode_mem, &lenrw, &leniw);

    if (flag == CV_SUCCESS) {
    	used = lenrw * sizeof(realtype) + leniw * sizeof(long int);
    }

    return used;
}

static void set_linear_solver(void *cvode_mem, value ls, int n)
{
    int flag;

    if (Is_block(ls)) {
	int field0 = Field(ls, 0); /* mupper, pretype */
	int field1 = Field(ls, 1); /* mlower, maxl */

	switch (Tag_val(ls)) {
	case VARIANT_LINEAR_SOLVER_BAND:
	    flag = CVBand(cvode_mem, n, field0, field1);
	    check_flag("CVBand", flag, NULL);
	    break;

#if SUNDIALS_BLAS_LAPACK == 1
	case VARIANT_LINEAR_SOLVER_LAPACKBAND:
	    field0 = Field(Field(ls, 1), 0);
	    field1 = Field(Field(ls, 1), 1);
	    flag = CVLapackBand(cvode_mem, n, field0, field1);
	    check_flag("CVLapackBand", flag, NULL);
	    break;
#endif

	case VARIANT_LINEAR_SOLVER_SPGMR:
	    field0 = Field(Field(ls, 1), 0);
	    field1    = Field(Field(ls, 1), 1);
	    flag = CVSpgmr(cvode_mem, field0, field1);
	    check_flag("CVSpgmr", flag, NULL);
	    break;

	case VARIANT_LINEAR_SOLVER_SPBCG:
	    field0 = Field(Field(ls, 1), 0);
	    field1    = Field(Field(ls, 1), 1);
	    flag = CVSpbcg(cvode_mem, field0, field1);
	    check_flag("CVSpbcg", flag, NULL);
	    break;

	case VARIANT_LINEAR_SOLVER_SPTFQMR:
	    field0 = Field(Field(ls, 1), 0);
	    field1    = Field(Field(ls, 1), 1);
	    flag = CVSptfqmr(cvode_mem, field0, field1);
	    check_flag("CVSPtfqmr", flag, NULL);
	    break;

	default:
	    caml_failwith("Illegal linear solver block value.");
	    break;
	}

    } else {
	switch (Int_val(ls)) {
	case VARIANT_LINEAR_SOLVER_DENSE:
	    flag = CVDense(cvode_mem, n);
	    check_flag("CVDense", flag, NULL);
	    break;

#if SUNDIALS_BLAS_LAPACK == 1
	case VARIANT_LINEAR_SOLVER_LAPACKDENSE:
	    flag = CVLapackDense(cvode_mem, n);
	    check_flag("CVLapackDense", flag, NULL);
	    break;
#endif

	case VARIANT_LINEAR_SOLVER_DIAG:
	    flag = CVDiag(cvode_mem);
	    check_flag("CVDiag", flag, NULL);
	    break;

	default:
	    caml_failwith("Illegal linear solver value.");
	    break;
	}
    }
}
 
CAMLprim value c_init(value lmm, value iter, value initial, value num_roots,
		      value t0)
{
    CAMLparam4(lmm, iter, initial, num_roots);
    CAMLlocal1(vdata);

    int flag;

    int lmm_c;
    switch (Int_val(lmm)) {
    case VARIANT_LMM_ADAMS:
	lmm_c = CV_ADAMS;
	break;

    case VARIANT_LMM_BDF:
	lmm_c = CV_BDF;
	break;

    default:
	caml_failwith("Illegal lmm value.");
	break;
    }

    int iter_c;
    if (Is_block(iter)) {
	iter_c = CV_NEWTON;
    } else {
	iter_c = CV_FUNCTIONAL;
    }

    N_Vector initial_nv = vectorize_bigarray(initial);

    void *cvode_mem = CVodeCreate(lmm_c, iter_c);

    vdata = ml_cvode_data_alloc(approx_size_cvode_mem(cvode_mem));
    ml_cvode_data_p data = (ml_cvode_data_p)Data_custom_val(vdata);

    data->cvode_mem = cvode_mem;
    data->neq = Caml_ba_array_val(initial)->dim[0];
    data->err_file = NULL;

    /* these two closures must be registered afterward */
    data->closure_rhsfn = NULL;
    data->closure_rootsfn = NULL;

    data->closure_errh = NULL;

    data->closure_jacfn = NULL;
    data->closure_bandjacfn = NULL;
    data->closure_presetupfn = NULL;
    data->closure_presolvefn = NULL;
    data->closure_jactimesfn = NULL;

    data->num_roots = Int_val(num_roots);

    if (data->cvode_mem == NULL) {
	free(data);
	caml_failwith("CVodeCreate returned NULL");
	CAMLreturn0;
    }

    flag = CVodeInit(data->cvode_mem, f, Double_val(t0), initial_nv);
    relinquish_vectorized_bigarray(initial_nv);
    check_flag("CVodeInit", flag, data);

    flag = CVodeRootInit(data->cvode_mem, data->num_roots, roots);
    check_flag("CVodeRootInit", flag, data);

    CVodeSetUserData(data->cvode_mem, (void *)data);

    // setup linear solvers (if necessary)
    if (iter_c == CV_NEWTON) {
	set_linear_solver(data->cvode_mem, Field(iter, 0), data->neq);
    }

    // default tolerances
    N_Vector abstol = N_VNew_Serial(data->neq); 
    int i;
    for (i=0; i < data->neq; ++i) {
	NV_Ith_S(abstol, i) = RCONST(1.0e-8);
    }
    flag = CVodeSVtolerances(data->cvode_mem, RCONST(1.0e-4), abstol);
    check_flag("CVodeSVtolerances", flag, data);
    N_VDestroy_Serial(abstol);

    CAMLreturn(vdata);
}

CAMLprim value c_neqs(value vdata)
{
    CAMLparam1(vdata);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    CAMLreturn(Val_int(data->neq));
}

CAMLprim value c_nroots(value vdata)
{
    CAMLparam1(vdata);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    CAMLreturn(Val_int(data->num_roots));
}

CAMLprim value c_set_tolerances(value vdata, value reltol, value abstol)
{
    CAMLparam3(vdata, reltol, abstol);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    N_Vector atol_nv = vectorize_bigarray(abstol);

    int flag = CVodeSVtolerances(data->cvode_mem, Double_val(reltol), atol_nv);
    relinquish_vectorized_bigarray(atol_nv);
    check_flag("CVodeSVtolerances", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_reinit(value vdata, value t0, value y0)
{
    CAMLparam3(vdata, t0, y0);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    N_Vector y0_nv = vectorize_bigarray(y0);
    int flag = CVodeReInit(data->cvode_mem, Double_val(t0), y0_nv);
    relinquish_vectorized_bigarray(y0_nv);
    check_flag("CVodeReInit", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_get_roots(value vdata, value roots)
{
    CAMLparam2(vdata, roots);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int roots_l = Caml_ba_array_val(roots)->dim[0];
    int *roots_d = Caml_ba_data_val(roots);

    if (roots_l < data->num_roots) {
	caml_invalid_argument("roots array is too short");
    }

    int flag = CVodeGetRootInfo(data->cvode_mem, roots_d);
    check_flag("CVodeGetRootInfo", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_free(value vdata)
{
    CAMLparam1(vdata);
    finalize(vdata);
    Store_field(vdata, 1, (value)NULL);
    CAMLreturn0;
}

static void check_flag(const char *call, int flag, void *to_free)
{
    static char exmsg[MAX_ERRMSG_LEN] = "";

    if (flag == CV_SUCCESS
	|| flag == CV_ROOT_RETURN
	|| flag == CV_TSTOP_RETURN) return;

    if (to_free != NULL) free(to_free);

    switch (flag) {
    case CV_ILL_INPUT:
	caml_raise_constant(*caml_named_value("cvode_IllInput"));
	break;

    case CV_TOO_CLOSE:
	caml_raise_constant(*caml_named_value("cvode_TooClose"));
	break;

    case CV_TOO_MUCH_WORK:
	caml_raise_constant(*caml_named_value("cvode_TooMuchWork"));
	break;

    case CV_TOO_MUCH_ACC:
	caml_raise_constant(*caml_named_value("cvode_TooMuchAccuracy"));
	break;

    case CV_ERR_FAILURE:
	caml_raise_constant(*caml_named_value("cvode_ErrFailure"));
	break;

    case CV_CONV_FAILURE:
	caml_raise_constant(*caml_named_value("cvode_ConvergenceFailure"));
	break;

    case CV_LINIT_FAIL:
	caml_raise_constant(*caml_named_value("cvode_LinearInitFailure"));
	break;

    case CV_LSETUP_FAIL:
	caml_raise_constant(*caml_named_value("cvode_LinearSetupFailure"));
	break;

    case CV_LSOLVE_FAIL:
	caml_raise_constant(*caml_named_value("cvode_LinearSolveFailure"));
	break;

    case CV_RHSFUNC_FAIL:
	caml_raise_constant(*caml_named_value("cvode_RhsFuncFailure"));
	break;

    case CV_FIRST_RHSFUNC_ERR:
	caml_raise_constant(*caml_named_value("cvode_FirstRhsFuncError"));
	break;

    case CV_REPTD_RHSFUNC_ERR:
	caml_raise_constant(*caml_named_value("cvode_RepeatedRhsFuncError"));
	break;

    case CV_UNREC_RHSFUNC_ERR:
	caml_raise_constant(*caml_named_value("cvode_UnrecoverableRhsFuncError"));
	break;

    case CV_RTFUNC_FAIL:
	caml_raise_constant(*caml_named_value("cvode_RootFuncFailure"));
	break;

    case CV_BAD_K:
	caml_raise_constant(*caml_named_value("cvode_BadK"));
	break;

    case CV_BAD_T:
	caml_raise_constant(*caml_named_value("cvode_BadT"));
	break;

    case CV_BAD_DKY:
	caml_raise_constant(*caml_named_value("cvode_BadDky"));
	break;

    default:
	/* e.g. CVDIAG_MEM_NULL, CVDIAG_ILL_INPUT, CVDIAG_MEM_FAIL */
	snprintf(exmsg, MAX_ERRMSG_LEN, "%s: %s", call,
		 CVodeGetReturnFlagName(flag));
	caml_failwith(exmsg);
    }
}

static value solver(value vdata, value nextt, value y, int onestep)
{
    CAMLparam2(vdata, nextt);
    CAMLlocal1(r);

    realtype t = 0.0;
    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int leny = Bigarray_val(y)->dim[0];

    N_Vector y_nv = N_VMake_Serial(leny, Caml_ba_data_val(y));

    // TODO:
    // The payload of y (a big array) must not be shifted by the Ocaml GC
    // during this function call, even though Caml will be reentered
    // through the callback f. Is this guaranteed?
    int flag = CVode(data->cvode_mem, Double_val(nextt), y_nv, &t,
		     onestep ? CV_ONE_STEP : CV_NORMAL);
    N_VDestroy(y_nv);
    check_flag("CVode", flag, NULL);

    r = caml_alloc_tuple(2);
    Store_field(r, 0, caml_copy_double(t));

    switch (flag) {
    case CV_ROOT_RETURN:
	Store_field(r, 1, Val_int(VARIANT_SOLVER_RESULT_ROOTSFOUND));
	break;

    case CV_TSTOP_RETURN:
	Store_field(r, 1, Val_int(VARIANT_SOLVER_RESULT_STOPTIMEREACHED));
	break;

    default:
	Store_field(r, 1, Val_int(VARIANT_SOLVER_RESULT_CONTINUE));
    }

    CAMLreturn(r);
}

CAMLprim value c_advance(value vdata, value nextt, value y)
{
    CAMLparam3(vdata, nextt, y);
    CAMLreturn(solver(vdata, nextt, y, 0));
}

CAMLprim value c_step(value vdata, value nextt, value y)
{
    CAMLparam3(vdata, nextt, y);
    CAMLreturn(solver(vdata, nextt, y, 1));
}

CAMLprim value c_get_dky(value vdata, value vt, value vk, value vy)
{
    CAMLparam4(vdata, vt, vk, vy);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    N_Vector y_nv = vectorize_bigarray(vy);

    int flag = CVodeGetDky(data->cvode_mem, Double_val(vt), Int_val(vk), y_nv);
    check_flag("CVodeGetDky", flag, NULL);
    relinquish_vectorized_bigarray(y_nv);
    
    CAMLreturn0;
}

CAMLprim value c_integrator_stats(value vdata)
{
    CAMLparam1(vdata);
    CAMLlocal1(r);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    int flag;

    long int nsteps;
    long int nfevals;    
    long int nlinsetups;
    long int netfails;

    int qlast;
    int qcur;	 

    realtype hinused;
    realtype hlast;
    realtype hcur;
    realtype tcur;

    flag = CVodeGetIntegratorStats(data->cvode_mem,
	&nsteps,
	&nfevals,    
	&nlinsetups,
	&netfails,
	&qlast,
	&qcur,	 
	&hinused,
	&hlast,
	&hcur,
	&tcur
    ); 
    check_flag("CVodeGetIntegratorStats", flag, NULL);

    r = caml_alloc_tuple(10);
    Store_field(r, RECORD_INTEGRATOR_STATS_STEPS, Val_long(nsteps));
    Store_field(r, RECORD_INTEGRATOR_STATS_RHS_EVALS, Val_long(nfevals));
    Store_field(r, RECORD_INTEGRATOR_STATS_LINEAR_SOLVER_SETUPS, Val_long(nlinsetups));
    Store_field(r, RECORD_INTEGRATOR_STATS_ERROR_TEST_FAILURES, Val_long(netfails));

    Store_field(r, RECORD_INTEGRATOR_STATS_LAST_INTERNAL_ORDER, Val_int(qlast));
    Store_field(r, RECORD_INTEGRATOR_STATS_NEXT_INTERNAL_ORDER, Val_int(qcur));

    Store_field(r, RECORD_INTEGRATOR_STATS_INITIAL_STEP_SIZE, caml_copy_double(hinused));
    Store_field(r, RECORD_INTEGRATOR_STATS_LAST_STEP_SIZE, caml_copy_double(hlast));
    Store_field(r, RECORD_INTEGRATOR_STATS_NEXT_STEP_SIZE, caml_copy_double(hcur));
    Store_field(r, RECORD_INTEGRATOR_STATS_INTERNAL_TIME, caml_copy_double(tcur));

    CAMLreturn(r);
}

CAMLprim value c_last_step_size(value vdata)
{
    CAMLparam1(vdata);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    int flag;
    realtype hlast;

    flag = CVodeGetLastStep(data->cvode_mem, &hlast);
    check_flag("CVodeGetLastStep", flag, NULL);

    CAMLreturn(caml_copy_double(hlast));
}

CAMLprim value c_next_step_size(value vdata)
{
    CAMLparam1(vdata);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    int flag;
    realtype hcur;

    flag = CVodeGetCurrentStep(data->cvode_mem, &hcur);
    check_flag("CVodeGetCurrentStep", flag, NULL);

    CAMLreturn(caml_copy_double(hcur));
}

/* optional input functions */

CAMLprim value c_set_error_file(value vdata, value vpath, value vtrunc)
{
    CAMLparam3(vdata, vpath, vtrunc);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    if (data->err_file != NULL) {
	fclose(data->err_file);
    }
    char *mode = Bool_val(vtrunc) ? "w" : "a";
    data->err_file = fopen(String_val(vpath), mode);
    if (data->err_file == NULL) {
	uerror("fopen", vpath);
    }

    int flag = CVodeSetErrFile(data->cvode_mem, data->err_file);
    check_flag("CVodeSetErrFile", flag, NULL);

    CAMLreturn0;
}

#define VARIANT_HANDLER_RHSFN		0
#define VARIANT_HANDLER_ROOTSFN		1
#define VARIANT_HANDLER_ERRORHANDLER	2
#define VARIANT_HANDLER_JACFN		3
#define VARIANT_HANDLER_BANDJACFN	4
#define VARIANT_HANDLER_PRESETUPFN	5
#define VARIANT_HANDLER_PRESOLVEFN	6
#define VARIANT_HANDLER_JACTIMESFN	7

static const char *callback_ocaml_names[] = {
    "cvode_serial_callback_rhsfn",
    "cvode_serial_callback_rootsfn",
    "cvode_serial_callback_errorhandler",
    "cvode_serial_callback_jacfn",
    "cvode_serial_callback_bandjacfn",
    "cvode_serial_callback_presetupfn",
    "cvode_serial_callback_presolvefn",
    "cvode_serial_callback_jactimesfn",
};

CAMLprim value c_register_handler(value vdata, value handler)
{
    CAMLparam2(vdata, handler);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    const char* ocaml_name = callback_ocaml_names[Int_val(handler)];
    value **handler_field;

    switch (Int_val(handler)) {
    case VARIANT_HANDLER_RHSFN:
	handler_field = &(data->closure_rhsfn);
	break;

    case VARIANT_HANDLER_ROOTSFN:
	handler_field = &(data->closure_rootsfn);
	break;

    case VARIANT_HANDLER_ERRORHANDLER:
	handler_field = &(data->closure_errh);
	break;

    case VARIANT_HANDLER_JACFN:
	handler_field = &(data->closure_jacfn);
	break;

    case VARIANT_HANDLER_BANDJACFN:
	handler_field = &(data->closure_bandjacfn);
	break;

    case VARIANT_HANDLER_PRESETUPFN:
	handler_field = &(data->closure_presetupfn);
	break;

    case VARIANT_HANDLER_PRESOLVEFN:
	handler_field = &(data->closure_presolvefn);
	break;

    case VARIANT_HANDLER_JACTIMESFN:
	handler_field = &(data->closure_jactimesfn);
	break;

    default:
	break;
    }

    if ((*handler_field) != NULL) {
	caml_remove_generational_global_root(*handler_field);
    }
    (*handler_field) = caml_named_value(ocaml_name);
    // TODO: check if this call is necessary and ok:
    caml_register_generational_global_root(*handler_field);

    CAMLreturn0;
}

/* call c_register_handler first */
CAMLprim value c_enable_error_handler(value vdata)
{
    CAMLparam1(vdata);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);
 
    int flag = CVodeSetErrHandlerFn(data->cvode_mem, errh, (void *)data);
    check_flag("CVodeSetErrHandlerFn", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_max_ord(value vdata, value maxord)
{
    CAMLparam2(vdata, maxord);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetMaxOrd(data->cvode_mem, Int_val(maxord));
    check_flag("CVodeSetMaxOrd", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_max_num_steps(value vdata, value mxsteps)
{
    CAMLparam2(vdata, mxsteps);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetMaxNumSteps(data->cvode_mem, Long_val(mxsteps));
    check_flag("CVodeSetMaxNumSteps", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_max_hnil_warns(value vdata, value mxhnil)
{
    CAMLparam2(vdata, mxhnil);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetMaxHnilWarns(data->cvode_mem, Int_val(mxhnil));
    check_flag("CVodeSetMaxHnilWarns", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_stability_limit_detection(value vdata, value stldet)
{
    CAMLparam2(vdata, stldet);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetStabLimDet(data->cvode_mem, Bool_val(stldet));
    check_flag("CVodeSetStabLimDet", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_initial_step_size(value vdata, value hin)
{
    CAMLparam2(vdata, hin);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetInitStep(data->cvode_mem, Double_val(hin));
    check_flag("CVodeSetInitStep", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_min_abs_step_size(value vdata, value hmin)
{
    CAMLparam2(vdata, hmin);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetMinStep(data->cvode_mem, Double_val(hmin));
    check_flag("CVodeSetMinStep", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_max_abs_step_size(value vdata, value hmax)
{
    CAMLparam2(vdata, hmax);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetMaxStep(data->cvode_mem, Double_val(hmax));
    check_flag("CVodeSetMaxStep", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_stop_time(value vdata, value tstop)
{
    CAMLparam2(vdata, tstop);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetStopTime(data->cvode_mem, Double_val(tstop));
    check_flag("CVodeSetStopTime", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_max_error_test_failures(value vdata, value maxnef)
{
    CAMLparam2(vdata, maxnef);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetMaxErrTestFails(data->cvode_mem, Int_val(maxnef));
    check_flag("CVodeSetMaxErrTestFails", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_max_nonlinear_iterations(value vdata, value maxcor)
{
    CAMLparam2(vdata, maxcor);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetMaxNonlinIters(data->cvode_mem, Int_val(maxcor));
    check_flag("CVodeSetMaxNonlinIters", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_max_convergence_failures(value vdata, value maxncf)
{
    CAMLparam2(vdata, maxncf);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetMaxConvFails(data->cvode_mem, Int_val(maxncf));
    check_flag("CVodeSetMaxConvFails", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_nonlinear_convergence_coeffficient(value vdata, value nlscoef)
{
    CAMLparam2(vdata, nlscoef);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetNonlinConvCoef(data->cvode_mem, Double_val(nlscoef));
    check_flag("CVodeSetNonlinConvCoef", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_nonlinear_iteration_type(value vdata, value iter)
{
    CAMLparam2(vdata, iter);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int iter_c;
    if (Is_block(iter)) {
	iter_c = CV_NEWTON;
    } else {
	iter_c = CV_FUNCTIONAL;
    }

    int flag = CVodeSetIterType(data->cvode_mem, iter_c);
    check_flag("CVodeSetIterType", flag, NULL);

    if (iter_c == CV_NEWTON) {
	set_linear_solver(data->cvode_mem, Field(iter, 0), data->neq);
    }

    CAMLreturn0;
}

CAMLprim value c_set_root_direction(value vdata, value rootdirs)
{
    CAMLparam2(vdata, rootdirs);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int rootdirs_l = Caml_ba_array_val(rootdirs)->dim[0];
    int *rootdirs_d = Caml_ba_data_val(rootdirs);

    if (rootdirs_l < data->num_roots) {
	caml_invalid_argument("root directions array is too short");
    }

    int flag = CVodeSetRootDirection(data->cvode_mem, rootdirs_d);
    check_flag("CVodeSetRootDirection", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_disable_inactive_root_warnings(value vdata)
{
    CAMLparam1(vdata);

    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVodeSetNoInactiveRootWarn(data->cvode_mem);
    check_flag("CVodeSetNoInactiveRootWarn", flag, NULL);

    CAMLreturn0;
}

/* direct linear solvers optional input functions */

#define VARIANT_HANDLER_JACFN		3
#define VARIANT_HANDLER_BANDJACFN	4
#define VARIANT_HANDLER_PRESETUPFN	5
#define VARIANT_HANDLER_PRESOLVEFN	6
#define VARIANT_HANDLER_JACTIMESFN	7

/* call c_register_handler first */
CAMLprim value c_enable_dense_jacobian_fn(value vdata)
{
    CAMLparam1(vdata);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    int flag = CVDlsSetDenseJacFn(data->cvode_mem, jacfn);
    check_flag("CVDlsSetDenseJacFn", flag, NULL);
    CAMLreturn0;
}

/* call c_register_handler first */
CAMLprim value c_enable_band_jacobian_fn(value vdata)
{
    CAMLparam1(vdata);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    int flag = CVDlsSetBandJacFn(data->cvode_mem, bandjacfn);
    check_flag("CVDlsSetBandJacFn", flag, NULL);
    CAMLreturn0;
}

/* iterative linear solvers optional input functions */

#define VARIANT_PRECOND_TYPE_PRECNONE	0
#define VARIANT_PRECOND_TYPE_PRECLEFT	1
#define VARIANT_PRECOND_TYPE_PRECRIGHT	2
#define VARIANT_PRECOND_TYPE_PRECBOTH	3

#define VARIANT_GRAMSCHMIDT_TYPE_MODIFIEDGS  0
#define VARIANT_GRAMSCHMIDT_TYPE_CLASSICALGS 1

/* call c_register_handler for both functions first */
CAMLprim value c_enable_preconditioner_fns(value vdata)
{
    CAMLparam1(vdata);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    int flag = CVSpilsSetPreconditioner(data->cvode_mem,
	    presetupfn, presolvefn);
    check_flag("CVSpilsSetPreconditioner", flag, NULL);
    CAMLreturn0;
}

/* call c_register_handler first */
CAMLprim value c_enable_jacobian_times_vector_fn(value vdata)
{
    CAMLparam1(vdata);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);
    int flag = CVSpilsSetJacTimesVecFn(data->cvode_mem, jactimesfn);
    check_flag("CVSpilsSetJacTimesVecFn", flag, NULL);
    CAMLreturn0;
}

#define VARIANT_PRECONDITIONING_TYPE_PRECNONE	0
#define VARIANT_PRECONDITIONING_TYPE_PRECLEFT	1
#define VARIANT_PRECONDITIONING_TYPE_PRECRIGHT	2
#define VARIANT_PRECONDITIONING_TYPE_PRECBOTH	3

CAMLprim value c_set_preconditioning_type(value vdata, value vptype)
{
    CAMLparam2(vdata, vptype);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int ptype;
    switch (Int_val(vptype)) {
    case VARIANT_PRECONDITIONING_TYPE_PRECNONE:
	ptype = PREC_NONE;
	break;

    case VARIANT_PRECONDITIONING_TYPE_PRECLEFT:
	ptype = PREC_LEFT;
	break;

    case VARIANT_PRECONDITIONING_TYPE_PRECRIGHT:
	ptype = PREC_RIGHT;
	break;

    case VARIANT_PRECONDITIONING_TYPE_PRECBOTH:
	ptype = PREC_BOTH;
	break;
    }

    int flag = CVSpilsSetPrecType(data->cvode_mem, ptype);
    check_flag("CVSpilsSetPrecType", flag, NULL);

    CAMLreturn0;
}

#define VARIANT_GRAMSCHMIDT_TYPE_MODIFIEDGS	0
#define VARIANT_GRAMSCHMIDT_TYPE_CLASSICALGS	1

CAMLprim value c_set_gramschmidt_orthogonalization(value vdata, value vgstype)
{
    CAMLparam2(vdata, vgstype);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int gstype;
    switch (Int_val(vgstype)) {
    case VARIANT_GRAMSCHMIDT_TYPE_MODIFIEDGS:
	gstype = MODIFIED_GS;
	break;

    case VARIANT_GRAMSCHMIDT_TYPE_CLASSICALGS:
	gstype = CLASSICAL_GS;
	break;
    }

    int flag = CVSpilsSetGSType(data->cvode_mem, gstype);
    check_flag("CVSpilsSetGSType", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_eps_linear_convergence_factor(value vdata, value eplifac)
{
    CAMLparam2(vdata, eplifac);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVSpilsSetEpsLin(data->cvode_mem, Double_val(eplifac));
    check_flag("CVSpilsSetEpsLin", flag, NULL);

    CAMLreturn0;
}

CAMLprim value c_set_max_subspace_dimension(value vdata, value maxl)
{
    CAMLparam2(vdata, maxl);
    ml_cvode_data_p data = cvode_data_from_ml(vdata);

    int flag = CVSpilsSetMaxl(data->cvode_mem, Int_val(maxl));
    check_flag("CVSpilsSetMaxl", flag, NULL);

    CAMLreturn0;
}

/* functions for the abstract types Densematrix.t and Bandmatrix.t */

CAMLprim value c_densematrix_get(value vmatrix, value vij)
{
    CAMLparam2(vmatrix, vij);
    DlsMat m = (DlsMat)Field(vmatrix, 0);
    realtype v = DENSE_ELEM(m, Int_val(Field(vij, 0)), Int_val(Field(vij, 1)));
    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_densematrix_set(value vmatrix, value vij, value v)
{
    CAMLparam2(vmatrix, vij);
    DlsMat m = (DlsMat)Field(vmatrix, 0);
    DENSE_ELEM(m, Int_val(Field(vij, 0)), Int_val(Field(vij, 1)))
	= Double_val(v);
    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_bandmatrix_get(value vmatrix, value vij)
{
    CAMLparam2(vmatrix, vij);
    DlsMat m = (DlsMat)Field(vmatrix, 0);
    realtype v = BAND_ELEM(m, Int_val(Field(vij, 0)), Int_val(Field(vij, 1)));
    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_bandmatrix_set(value vmatrix, value vij, value v)
{
    CAMLparam2(vmatrix, vij);
    DlsMat m = (DlsMat)Field(vmatrix, 0);
    BAND_ELEM(m, Int_val(Field(vij, 0)), Int_val(Field(vij, 1)))
	= Double_val(v);
    CAMLreturn(caml_copy_double(v));
}

