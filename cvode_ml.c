/***********************************************************************
 *                                                                     *
 *              Ocaml interface to Sundials CVODE solver               *
 *                                                                     *
 *       Timothy Bourke (INRIA Rennes) and Marc Pouzet (LIENS)         *
 *                                                                     *
 *  Copyright 2011 Institut National de Recherche en Informatique et   *
 *  en Automatique.  All rights reserved.  This file is distributed    *
 *  under the terms of the GNU Library General Public License, with    *
 *  the special exception on linking described in file LICENSE.        *
 *                                                                     *
 ***********************************************************************/

/* Sundials interface functions that do not involve NVectors. */

/*
 * TODO:
 * - see notes throughout program related to garbage collection.
 */

#include <cvode/cvode.h>
#include <sundials/sundials_config.h>
#include <sundials/sundials_types.h>
#include <sundials/sundials_band.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/unixsupport.h>
#include <caml/bigarray.h>

/* linear solvers */
#include <cvode/cvode_dense.h>
#include <cvode/cvode_band.h>
#include <cvode/cvode_diag.h>
#include <cvode/cvode_spgmr.h>
#include <cvode/cvode_spbcgs.h>
#include <cvode/cvode_sptfqmr.h>
#include <cvode/cvode_bandpre.h>
#include <cvode/cvode_spils.h>

#include "cvode_ml.h"

#include <stdio.h>
#define MAX_ERRMSG_LEN 256

static const char *callback_ocaml_names[] = {
    "cvode_serial_callback_rhsfn",
    "cvode_serial_callback_rootsfn",
    "cvode_serial_callback_errorhandler",
    "cvode_serial_callback_errorweight",
    "cvode_serial_callback_jacfn",
    "cvode_serial_callback_bandjacfn",
    "cvode_serial_callback_presetupfn",
    "cvode_serial_callback_presolvefn",
    "cvode_serial_callback_jactimesfn",
};

static void finalize_closure(value** closure_field)
{
    if (*closure_field != NULL) {
	caml_remove_generational_global_root(*closure_field);
	*closure_field = NULL;
    }
}

static void finalize(value vdata)
{
    CVODE_DATA_FROM_ML(data, vdata);

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
    finalize_closure(&(data->closure_errw));

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
value cvode_ml_data_alloc(void* cvode_mem)
{
    CAMLparam0();
    CAMLlocal1(r);

    mlsize_t approx_size = 0;
    long int lenrw, leniw;
    if (CVodeGetWorkSpace(cvode_mem, &lenrw, &leniw) == CV_SUCCESS) {
    	approx_size = lenrw * sizeof(realtype) + leniw * sizeof(long int);
    }

    r = caml_alloc_final(sizeof(struct cvode_ml_data),
			 &finalize, approx_size, approx_size * 5);

    cvode_ml_data_p d = CVODE_DATA(r);
    d->cvode_mem = cvode_mem;

    d->err_file = NULL;
    d->closure_rhsfn = NULL;
    d->closure_rootsfn = NULL;
    d->closure_errh = NULL;
    d->closure_errw = NULL;
    d->closure_jacfn = NULL;
    d->closure_bandjacfn = NULL;
    d->closure_presetupfn = NULL;
    d->closure_presolvefn = NULL;
    d->closure_jactimesfn = NULL;
    
    CAMLreturn(r);
}

void cvode_ml_check_flag(const char *call, int flag, void *to_free)
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

static int precond_type(value vptype)
{
    CAMLparam1(vptype);

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

    CAMLreturn(ptype);
}

/* callbacks */

static void errh(
	int error_code,
	const char *module,
	const char *func,
	char *msg,
	void *eh_data)
{
    CAMLparam0();
    CAMLlocal1(a);

    value *closure_errh = ((cvode_ml_data_p)eh_data)->closure_errh;

    a = caml_alloc_tuple(4);
    Store_field(a, RECORD_ERROR_DETAILS_ERROR_CODE, Val_int(error_code));
    Store_field(a, RECORD_ERROR_DETAILS_MODULE_NAME, caml_copy_string(module));
    Store_field(a, RECORD_ERROR_DETAILS_FUNCTION_NAME, caml_copy_string(func));
    Store_field(a, RECORD_ERROR_DETAILS_ERROR_MESSAGE, caml_copy_string(msg));

    caml_callback(*closure_errh, a);

    CAMLreturn0;
}

CAMLprim value c_enable_err_handler_fn(value vdata)
{
    CAMLparam1(vdata);
    CVODE_DATA_FROM_ML(data, vdata);
 
    int flag = CVodeSetErrHandlerFn(data->cvode_mem, errh, (void *)data);
    CHECK_FLAG("CVodeSetErrHandlerFn", flag);

    CAMLreturn0;
}

CAMLprim value c_disable_err_handler_fn(value vdata)
{
    CAMLparam1(vdata);
    CVODE_DATA_FROM_ML(data, vdata);

    int flag = CVodeSetErrHandlerFn(data->cvode_mem, NULL, (void *)data);
    CHECK_FLAG("CVodeSetErrHandlerFn", flag);

    CAMLreturn0;
}

/* basic interface */

void set_linear_solver(void *cvode_mem, value ls, int n)
{
    int flag;

    if (Is_block(ls)) {
	int field0 = Field(Field(ls, 0), 0); /* mupper, pretype */
	int field1 = Field(Field(ls, 0), 1); /* mlower, maxl */
	value sprange, bandrange;

	switch (Tag_val(ls)) {
	case VARIANT_LINEAR_SOLVER_BAND:
	    flag = CVBand(cvode_mem, n, Int_val(field0), Int_val(field1));
	    CHECK_FLAG("CVBand", flag);
	    break;

	case VARIANT_LINEAR_SOLVER_LAPACKBAND:
#if SUNDIALS_BLAS_LAPACK == 1
	    flag = CVLapackBand(cvode_mem, n, Int_val(field0), Int_val(field1));
	    CHECK_FLAG("CVLapackBand", flag);
#else
	    caml_failwith("Lapack solvers are not available.");
#endif
	    break;

	case VARIANT_LINEAR_SOLVER_SPGMR:
	    flag = CVSpgmr(cvode_mem, precond_type(field0), Int_val(field1));
	    CHECK_FLAG("CVSpgmr", flag);
	    break;

	case VARIANT_LINEAR_SOLVER_SPBCG:
	    flag = CVSpbcg(cvode_mem, precond_type(field0), Int_val(field1));
	    CHECK_FLAG("CVSpbcg", flag);
	    break;

	case VARIANT_LINEAR_SOLVER_SPTFQMR:
	    flag = CVSptfqmr(cvode_mem, precond_type(field0), Int_val(field1));
	    CHECK_FLAG("CVSPtfqmr", flag);
	    break;

	case VARIANT_LINEAR_SOLVER_BANDED_SPGMR:
	    sprange = Field(ls, 0);
	    bandrange = Field(ls, 1);

	    flag = CVSpgmr(cvode_mem, precond_type(Field(sprange, 0)),
				      Int_val(Field(sprange, 1)));
	    CHECK_FLAG("CVSpgmr", flag);

	    flag = CVBandPrecInit(cvode_mem, n, Int_val(Field(bandrange, 0)),
						Int_val(Field(bandrange, 1)));
	    CHECK_FLAG("CVBandPrecInit", flag);
	    break;

	case VARIANT_LINEAR_SOLVER_BANDED_SPBCG:
	    sprange = Field(ls, 0);
	    bandrange = Field(ls, 1);

	    flag = CVSpbcg(cvode_mem, precond_type(Field(sprange, 0)),
				      Int_val(Field(sprange, 1)));
	    CHECK_FLAG("CVSpbcg", flag);

	    flag = CVBandPrecInit(cvode_mem, n, Int_val(Field(bandrange, 0)),
						Int_val(Field(bandrange, 1)));
	    CHECK_FLAG("CVBandPrecInit", flag);
	    break;

	case VARIANT_LINEAR_SOLVER_BANDED_SPTFQMR:
	    sprange = Field(ls, 0);
	    bandrange = Field(ls, 1);

	    flag = CVSptfqmr(cvode_mem, precond_type(Field(sprange, 0)),
				        Int_val(Field(sprange, 1)));
	    CHECK_FLAG("CVSptfqmr", flag);

	    flag = CVBandPrecInit(cvode_mem, n, Int_val(Field(bandrange, 0)),
						Int_val(Field(bandrange, 1)));
	    CHECK_FLAG("CVBandPrecInit", flag);
	    break;

	default:
	    caml_failwith("Illegal linear solver block value.");
	    break;
	}

    } else {
	switch (Int_val(ls)) {
	case VARIANT_LINEAR_SOLVER_DENSE:
	    flag = CVDense(cvode_mem, n);
	    CHECK_FLAG("CVDense", flag);
	    break;

	case VARIANT_LINEAR_SOLVER_LAPACKDENSE:
#if SUNDIALS_BLAS_LAPACK == 1
	    flag = CVLapackDense(cvode_mem, n);
	    CHECK_FLAG("CVLapackDense", flag);
#else
	    caml_failwith("Lapack solvers are not available.");
#endif
	    break;

	case VARIANT_LINEAR_SOLVER_DIAG:
	    flag = CVDiag(cvode_mem);
	    CHECK_FLAG("CVDiag", flag);
	    break;

	default:
	    caml_failwith("Illegal linear solver value.");
	    break;
	}
    }
}
 
CAMLprim value c_neqs(value vdata)
{
    CAMLparam1(vdata);
    CVODE_DATA_FROM_ML(data, vdata);
    CAMLreturn(Val_int(data->neq));
}

CAMLprim value c_nroots(value vdata)
{
    CAMLparam1(vdata);
    CVODE_DATA_FROM_ML(data, vdata);
    CAMLreturn(Val_int(data->num_roots));
}

CAMLprim value c_ss_tolerances(value vdata, value reltol, value abstol)
{
    CAMLparam3(vdata, reltol, abstol);

    CVODE_DATA_FROM_ML(data, vdata);

    int flag = CVodeSStolerances(data->cvode_mem,
		 Double_val(reltol), Double_val(abstol));
    CHECK_FLAG("CVodeSStolerances", flag);

    CAMLreturn0;
}

CAMLprim value c_get_root_info(value vdata, value roots)
{
    CAMLparam2(vdata, roots);

    CVODE_DATA_FROM_ML(data, vdata);

    int roots_l = Caml_ba_array_val(roots)->dim[0];
    int *roots_d = Caml_ba_data_val(roots);

    if (roots_l < data->num_roots) {
	caml_invalid_argument("roots array is too short");
    }

    int flag = CVodeGetRootInfo(data->cvode_mem, roots_d);
    CHECK_FLAG("CVodeGetRootInfo", flag);

    CAMLreturn0;
}

CAMLprim value c_get_integrator_stats(value vdata)
{
    CAMLparam1(vdata);
    CAMLlocal1(r);

    CVODE_DATA_FROM_ML(data, vdata);
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
    CHECK_FLAG("CVodeGetIntegratorStats", flag);

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

CAMLprim value c_set_error_file(value vdata, value vpath, value vtrunc)
{
    CAMLparam3(vdata, vpath, vtrunc);

    CVODE_DATA_FROM_ML(data, vdata);

    if (data->err_file != NULL) {
	fclose(data->err_file);
    }
    char *mode = Bool_val(vtrunc) ? "w" : "a";
    data->err_file = fopen(String_val(vpath), mode);
    if (data->err_file == NULL) {
	uerror("fopen", vpath);
    }

    int flag = CVodeSetErrFile(data->cvode_mem, data->err_file);
    CHECK_FLAG("CVodeSetErrFile", flag);

    CAMLreturn0;
}

CAMLprim value c_register_handler(value vdata, value handler)
{
    CAMLparam2(vdata, handler);

    CVODE_DATA_FROM_ML(data, vdata);
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

    case VARIANT_HANDLER_ERRORWEIGHT:
	handler_field = &(data->closure_errw);
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

CAMLprim value c_set_iter_type(value vdata, value iter)
{
    CAMLparam2(vdata, iter);

    CVODE_DATA_FROM_ML(data, vdata);

    int iter_c;
    if (Is_block(iter)) {
	iter_c = CV_NEWTON;
    } else {
	iter_c = CV_FUNCTIONAL;
    }

    int flag = CVodeSetIterType(data->cvode_mem, iter_c);
    CHECK_FLAG("CVodeSetIterType", flag);

    if (iter_c == CV_NEWTON) {
	set_linear_solver(data->cvode_mem, Field(iter, 0), data->neq);
    }

    CAMLreturn0;
}

CAMLprim value c_set_root_direction(value vdata, value rootdirs)
{
    CAMLparam2(vdata, rootdirs);

    CVODE_DATA_FROM_ML(data, vdata);

    int rootdirs_l = Caml_ba_array_val(rootdirs)->dim[0];
    int *rootdirs_d = Caml_ba_data_val(rootdirs);

    if (rootdirs_l < data->num_roots) {
	caml_invalid_argument("root directions array is too short");
    }

    int flag = CVodeSetRootDirection(data->cvode_mem, rootdirs_d);
    CHECK_FLAG("CVodeSetRootDirection", flag);

    CAMLreturn0;
}

CAMLprim value c_set_prec_type(value vcvode_mem, value vptype)
{
    CAMLparam2(vcvode_mem, vptype);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVSpilsSetPrecType(cvode_mem, precond_type(vptype));
    CHECK_FLAG("CVSpilsSetPrecType", flag);

    CAMLreturn0;
}

value cvode_ml_big_real()
{
    CAMLparam0();
    CAMLreturn(caml_copy_double(BIG_REAL));
}

value cvode_ml_unit_roundoff()
{
    CAMLparam0();
    CAMLreturn(caml_copy_double(UNIT_ROUNDOFF));
}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *
 * Boiler plate definitions for Sundials interface.
 *
 */

#define INT_ARRAY(v) ((int *)Caml_ba_data_val(v))
#define REAL_ARRAY(v) ((realtype *)Caml_ba_data_val(v))
#define REAL_ARRAY2(v) ((realtype **)Caml_ba_data_val(v))

CAMLprim value c_get_work_space(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CAMLlocal1(r);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    long int lenrw;
    long int leniw;

    flag = CVodeGetWorkSpace(cvode_mem, &lenrw, &leniw);
    CHECK_FLAG("CVodeGetWorkSpace", flag);

    r = caml_alloc_tuple(2);

    Store_field(r, 0, Val_int(lenrw));
    Store_field(r, 1, Val_int(leniw));

    CAMLreturn(r);
}

CAMLprim value c_get_num_steps(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    long int v;

    flag = CVodeGetNumSteps(cvode_mem, &v);
    CHECK_FLAG("CVodeGetNumSteps", flag);

    CAMLreturn(Val_long(v));
}

CAMLprim value c_get_num_rhs_evals(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    long int v;

    flag = CVodeGetNumRhsEvals(cvode_mem, &v);
    CHECK_FLAG("CVodeGetNumRhsEvals", flag);

    CAMLreturn(Val_long(v));
}

CAMLprim value c_get_num_lin_solv_setups(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    long int v;

    flag = CVodeGetNumLinSolvSetups(cvode_mem, &v);
    CHECK_FLAG("CVodeGetNumLinSolvSetups", flag);

    CAMLreturn(Val_long(v));
}

CAMLprim value c_get_num_err_test_fails(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    long int v;

    flag = CVodeGetNumErrTestFails(cvode_mem, &v);
    CHECK_FLAG("CVodeGetNumErrTestFails", flag);

    CAMLreturn(Val_long(v));
}

CAMLprim value c_get_last_order(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    int v;

    flag = CVodeGetLastOrder(cvode_mem, &v);
    CHECK_FLAG("CVodeGetLastOrder", flag);

    CAMLreturn(Val_int(v));
}

CAMLprim value c_get_current_order(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    int v;

    flag = CVodeGetCurrentOrder(cvode_mem, &v);
    CHECK_FLAG("CVodeGetCurrentOrder", flag);

    CAMLreturn(Val_int(v));
}

CAMLprim value c_get_actual_init_step(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    realtype v;

    flag = CVodeGetActualInitStep(cvode_mem, &v);
    CHECK_FLAG("CVodeGetActualInitStep", flag);

    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_get_last_step(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    realtype v;

    flag = CVodeGetLastStep(cvode_mem, &v);
    CHECK_FLAG("CVodeGetLastStep", flag);

    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_get_current_step(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    realtype v;

    flag = CVodeGetCurrentStep(cvode_mem, &v);
    CHECK_FLAG("CVodeGetCurrentStep", flag);

    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_get_current_time(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    realtype v;

    flag = CVodeGetCurrentTime(cvode_mem, &v);
    CHECK_FLAG("CVodeGetCurrentTime", flag);

    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_set_max_ord(value vcvode_mem, value maxord)
{
    CAMLparam2(vcvode_mem, maxord);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetMaxOrd(cvode_mem, Int_val(maxord));
    CHECK_FLAG("CVodeSetMaxOrd", flag);

    CAMLreturn0;
}

CAMLprim value c_set_max_num_steps(value vcvode_mem, value mxsteps)
{
    CAMLparam2(vcvode_mem, mxsteps);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetMaxNumSteps(cvode_mem, Long_val(mxsteps));
    CHECK_FLAG("CVodeSetMaxNumSteps", flag);

    CAMLreturn0;
}

CAMLprim value c_set_max_hnil_warns(value vcvode_mem, value mxhnil)
{
    CAMLparam2(vcvode_mem, mxhnil);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetMaxHnilWarns(cvode_mem, Int_val(mxhnil));
    CHECK_FLAG("CVodeSetMaxHnilWarns", flag);

    CAMLreturn0;
}

CAMLprim value c_set_stab_lim_det(value vcvode_mem, value stldet)
{
    CAMLparam2(vcvode_mem, stldet);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetStabLimDet(cvode_mem, Bool_val(stldet));
    CHECK_FLAG("CVodeSetStabLimDet", flag);

    CAMLreturn0;
}

CAMLprim value c_set_init_step(value vcvode_mem, value hin)
{
    CAMLparam2(vcvode_mem, hin);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetInitStep(cvode_mem, Double_val(hin));
    CHECK_FLAG("CVodeSetInitStep", flag);

    CAMLreturn0;
}

CAMLprim value c_set_min_step(value vcvode_mem, value hmin)
{
    CAMLparam2(vcvode_mem, hmin);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetMinStep(cvode_mem, Double_val(hmin));
    CHECK_FLAG("CVodeSetMinStep", flag);

    CAMLreturn0;
}

CAMLprim value c_set_max_step(value vcvode_mem, value hmax)
{
    CAMLparam2(vcvode_mem, hmax);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetMaxStep(cvode_mem, Double_val(hmax));
    CHECK_FLAG("CVodeSetMaxStep", flag);

    CAMLreturn0;
}

CAMLprim value c_set_stop_time(value vcvode_mem, value tstop)
{
    CAMLparam2(vcvode_mem, tstop);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetStopTime(cvode_mem, Double_val(tstop));
    CHECK_FLAG("CVodeSetStopTime", flag);

    CAMLreturn0;
}

CAMLprim value c_set_max_err_test_fails(value vcvode_mem, value maxnef)
{
    CAMLparam2(vcvode_mem, maxnef);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetMaxErrTestFails(cvode_mem, Int_val(maxnef));
    CHECK_FLAG("CVodeSetMaxErrTestFails", flag);

    CAMLreturn0;
}

CAMLprim value c_set_max_nonlin_iters(value vcvode_mem, value maxcor)
{
    CAMLparam2(vcvode_mem, maxcor);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetMaxNonlinIters(cvode_mem, Int_val(maxcor));
    CHECK_FLAG("CVodeSetMaxNonlinIters", flag);

    CAMLreturn0;
}

CAMLprim value c_set_max_conv_fails(value vcvode_mem, value maxncf)
{
    CAMLparam2(vcvode_mem, maxncf);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetMaxConvFails(cvode_mem, Int_val(maxncf));
    CHECK_FLAG("CVodeSetMaxConvFails", flag);

    CAMLreturn0;
}

CAMLprim value c_set_nonlin_conv_coef(value vcvode_mem, value nlscoef)
{
    CAMLparam2(vcvode_mem, nlscoef);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetNonlinConvCoef(cvode_mem, Double_val(nlscoef));
    CHECK_FLAG("CVodeSetNonlinConvCoef", flag);

    CAMLreturn0;
}

CAMLprim value c_set_no_inactive_root_warn(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVodeSetNoInactiveRootWarn(cvode_mem);
    CHECK_FLAG("CVodeSetNoInactiveRootWarn", flag);

    CAMLreturn0;
}

CAMLprim value c_set_gs_type(value vcvode_mem, value vgstype)
{
    CAMLparam2(vcvode_mem, vgstype);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int gstype;
    switch (Int_val(vgstype)) {
    case VARIANT_GRAMSCHMIDT_TYPE_MODIFIEDGS:
	gstype = MODIFIED_GS;
	break;

    case VARIANT_GRAMSCHMIDT_TYPE_CLASSICALGS:
	gstype = CLASSICAL_GS;
	break;
    }

    int flag = CVSpilsSetGSType(cvode_mem, gstype);
    CHECK_FLAG("CVSpilsSetGSType", flag);

    CAMLreturn0;
}

CAMLprim value c_set_eps_lin(value vcvode_mem, value eplifac)
{
    CAMLparam2(vcvode_mem, eplifac);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVSpilsSetEpsLin(cvode_mem, Double_val(eplifac));
    CHECK_FLAG("CVSpilsSetEpsLin", flag);

    CAMLreturn0;
}

CAMLprim value c_set_maxl(value vcvode_mem, value maxl)
{
    CAMLparam2(vcvode_mem, maxl);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    int flag = CVSpilsSetMaxl(cvode_mem, Int_val(maxl));
    CHECK_FLAG("CVSpilsSetMaxl", flag);

    CAMLreturn0;
}

/* Dense matrix functions */

#define DLSMAT(v) (*(DlsMat *)Data_custom_val(v))

static void finalize_dlsmat(value va)
{
    DestroyMat(DLSMAT(va));
}

CAMLprim value c_densematrix_new_dense_mat(value vmn)
{
    CAMLparam1(vmn);
    CAMLlocal1(vr);

    int m = Int_val(Field(vmn, 0));
    int n = Int_val(Field(vmn, 1));

    DlsMat a = NewDenseMat(m, n);
    mlsize_t approx_size = m * n * sizeof(realtype);

    vr = caml_alloc_final(sizeof(DlsMat), &finalize_dlsmat,
			 approx_size, approx_size * 20);
    DlsMat *r = (DlsMat *)Data_custom_val(vr);
    *r = a;

    CAMLreturn(vr);
}

CAMLprim value c_densematrix_print_mat(value va)
{
    CAMLparam1(va);
    fflush(stdout);
    PrintMat(DLSMAT(va));
    fflush(stdout);
    CAMLreturn0;
}

CAMLprim value c_densematrix_set_to_zero(value va)
{
    CAMLparam1(va);
    SetToZero(DLSMAT(va));
    CAMLreturn0;
}

CAMLprim value c_densematrix_add_identity(value va)
{
    CAMLparam1(va);
    AddIdentity(DLSMAT(va));
    CAMLreturn0;
}

CAMLprim value c_densematrix_copy(value va, value vb)
{
    CAMLparam2(va, vb);
    DenseCopy(DLSMAT(va), DLSMAT(vb));
    CAMLreturn0;
}

CAMLprim value c_densematrix_scale(value vc, value va)
{
    CAMLparam2(vc, va);
    DenseScale(Double_val(vc), DLSMAT(va));
    CAMLreturn0;
}

CAMLprim value c_densematrix_getrf(value va, value vp)
{
    CAMLparam2(va, vp);
    int r = DenseGETRF(DLSMAT(va), INT_ARRAY(vp));

    if (r != 0) {
	caml_raise_with_arg(*caml_named_value("cvode_ZeroDiagonalElement"),
			    Val_int(r));
    }
    CAMLreturn0;
}

CAMLprim value c_densematrix_getrs(value va, value vp, value vb)
{
    CAMLparam3(va, vp, vb);
    DenseGETRS(DLSMAT(va), INT_ARRAY(vp), REAL_ARRAY(vb));
    CAMLreturn0;
}

CAMLprim value c_densematrix_potrf(value va)
{
    CAMLparam1(va);
    DensePOTRF(DLSMAT(va));
    CAMLreturn0;
}

CAMLprim value c_densematrix_potrs(value va, value vb)
{
    CAMLparam2(va, vb);
    DensePOTRS(DLSMAT(va), REAL_ARRAY(vb));
    CAMLreturn0;
}

CAMLprim value c_densematrix_geqrf(value va, value vbeta, value vwork)
{
    CAMLparam3(va, vbeta, vwork);
    DenseGEQRF(DLSMAT(va), REAL_ARRAY(vbeta), REAL_ARRAY(vwork));
    CAMLreturn0;
}

CAMLprim value c_densematrix_ormqr(value va, value vormqr)
{
    CAMLparam2(va, vormqr);

    realtype *beta = REAL_ARRAY(Field(vormqr, 0));
    realtype *vv   = REAL_ARRAY(Field(vormqr, 1));
    realtype *vw   = REAL_ARRAY(Field(vormqr, 2));
    realtype *work = REAL_ARRAY(Field(vormqr, 3));

    DenseORMQR(DLSMAT(va), beta, vv, vw, work);
    CAMLreturn0;
}
 
CAMLprim value c_densematrix_get(value vmatrix, value vij)
{
    CAMLparam2(vmatrix, vij);
    DlsMat m = DLSMAT(vmatrix);

    int i = Int_val(Field(vij, 0));
    int j = Int_val(Field(vij, 1));

#if CHECK_MATRIX_ACCESS == 1
    if (i < 0 || i >= m->M) caml_invalid_argument("Densematrix.get: invalid i");
    if (j < 0 || j >= m->N) caml_invalid_argument("Densematrix.get: invalid j");
#endif

    realtype v = DENSE_ELEM(m, i, j);
    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_densematrix_set(value vmatrix, value vij, value v)
{
    CAMLparam3(vmatrix, vij, v);
    DlsMat m = DLSMAT(vmatrix);

    int i = Int_val(Field(vij, 0));
    int j = Int_val(Field(vij, 1));

#if CHECK_MATRIX_ACCESS == 1
    if (i < 0 || i >= m->M) caml_invalid_argument("Densematrix.set: invalid i");
    if (j < 0 || j >= m->N) caml_invalid_argument("Densematrix.set: invalid j");
#endif

    DENSE_ELEM(m, i, j) = Double_val(v);
    CAMLreturn(caml_copy_double(v));
}

/* Direct dense matrix functions */

#define DDENSEMAT(v) (*((realtype ***)(Data_custom_val(v))))

static void finalize_direct_densemat(value va)
{
    destroyMat(DDENSEMAT(va));
}

CAMLprim value c_densematrix_direct_new_dense_mat(value vmn)
{
    CAMLparam1(vmn);
    CAMLlocal1(vr);

    int m = Int_val(Field(vmn, 0));
    int n = Int_val(Field(vmn, 1));

    realtype **a = newDenseMat(m, n);
    mlsize_t approx_size = m * n * sizeof(realtype);

    vr = caml_alloc_final(sizeof(realtype **),
			  &finalize_direct_densemat,
			  approx_size, approx_size * 20);
    realtype ***r = (realtype ***)Data_custom_val(vr);
    *r = a;

    CAMLreturn(vr);
}

CAMLprim value c_densematrix_direct_get(value va, value vij)
{
    CAMLparam2(va, vij);

    int i = Int_val(Field(vij, 0));
    int j = Int_val(Field(vij, 1));

    CAMLreturn(caml_copy_double(DDENSEMAT(va)[j][i]));
}

CAMLprim value c_densematrix_direct_set(value va, value vij, value vv)
{
    CAMLparam3(va, vij, vv);

    int i = Int_val(Field(vij, 0));
    int j = Int_val(Field(vij, 1));

    DDENSEMAT(va)[j][i] = Double_val(vv);

    CAMLreturn0;
}

CAMLprim value c_densematrix_direct_copy(value va, value vb, value vmn)
{
    CAMLparam3(va, vb, vmn);

    int m = Int_val(Field(vmn, 0));
    int n = Int_val(Field(vmn, 1));

    denseCopy(DDENSEMAT(va), DDENSEMAT(vb), m, n);
    CAMLreturn0;
}

CAMLprim value c_densematrix_direct_scale(value vc, value va, value vmn)
{
    CAMLparam3(vc, va, vmn);

    int m = Int_val(Field(vmn, 0));
    int n = Int_val(Field(vmn, 1));

    denseScale(Double_val(vc), DDENSEMAT(va), m, n);
    CAMLreturn0;
}

CAMLprim value c_densematrix_direct_add_identity(value va, value vn)
{
    CAMLparam2(va, vn);
    denseAddIdentity(DDENSEMAT(va), Int_val(vn));
    CAMLreturn0;
}

CAMLprim value c_densematrix_direct_getrf(value va, value vmn, value vp)
{
    CAMLparam3(va, vmn, vp);

    int m = Int_val(Field(vmn, 0));
    int n = Int_val(Field(vmn, 1));

    int r = denseGETRF(DDENSEMAT(va), m, n, INT_ARRAY(vp));

    if (r != 0) {
	caml_raise_with_arg(*caml_named_value("cvode_ZeroDiagonalElement"),
			    Val_int(r));
    }
    CAMLreturn0;
}

CAMLprim value c_densematrix_direct_getrs(value va, value vn,
	value vp, value vb)
{
    CAMLparam4(va, vn, vp, vb);
    denseGETRS(DDENSEMAT(va), Int_val(vn), INT_ARRAY(vp), REAL_ARRAY(vb));
    CAMLreturn0;
}

CAMLprim value c_densematrix_direct_potrf(value va, value vm)
{
    CAMLparam2(va, vm);
    densePOTRF(DDENSEMAT(va), Int_val(vm));
    CAMLreturn0;
}

CAMLprim value c_densematrix_direct_potrs(value va, value vm, value vb)
{
    CAMLparam3(va, vm, vb);
    densePOTRS(DDENSEMAT(va), Int_val(vm), REAL_ARRAY(vb));
    CAMLreturn0;
}

CAMLprim value c_densematrix_direct_geqrf(value va, value vmn,
	value vbeta, value vv)
{
    CAMLparam4(va, vmn, vbeta, vv);

    int m = Int_val(Field(vmn, 0));
    int n = Int_val(Field(vmn, 1));

    denseGEQRF(DDENSEMAT(va), m, n, REAL_ARRAY(vbeta), REAL_ARRAY(vv));
    CAMLreturn0;
}

CAMLprim value c_densematrix_direct_ormqr(value va, value vmn, value vormqr)
{
    CAMLparam3(va, vmn, vormqr);

    int m = Int_val(Field(vmn, 0));
    int n = Int_val(Field(vmn, 1));

    realtype *beta = REAL_ARRAY(Field(vormqr, 0));
    realtype *vv   = REAL_ARRAY(Field(vormqr, 1));
    realtype *vw   = REAL_ARRAY(Field(vormqr, 2));
    realtype *work = REAL_ARRAY(Field(vormqr, 3));

    denseORMQR(DDENSEMAT(va), m, n, beta, vv, vw, work);
    CAMLreturn0;
}

/* Band matrix functions */

CAMLprim value c_bandmatrix_new_band_mat(value vsizes)
{
    CAMLparam1(vsizes);
    CAMLlocal1(vr);

    int n   = Int_val(Field(vsizes, 0));
    int mu  = Int_val(Field(vsizes, 1));
    int ml  = Int_val(Field(vsizes, 2));
    int smu = Int_val(Field(vsizes, 3));

    DlsMat va = NewBandMat(n, mu, ml, smu);
    mlsize_t approx_size = n * (smu + ml + 2) * sizeof(realtype);

    vr = caml_alloc_final(sizeof(DlsMat), &finalize_dlsmat,
			 approx_size, approx_size * 20);
    DlsMat *r = (DlsMat *)Data_custom_val(vr);
    *r = va;

    CAMLreturn(vr);
}

CAMLprim value c_bandmatrix_copy(value va, value vb,
	value vcopymu, value vcopyml)
{
    CAMLparam4(va, vb, vcopymu, vcopyml);
    BandCopy(DLSMAT(va), DLSMAT(vb), Int_val(vcopymu), Int_val(vcopyml));
    CAMLreturn0;
}

CAMLprim value c_bandmatrix_scale(value vc, value va)
{
    CAMLparam2(vc, va);
    BandScale(Double_val(vc), DLSMAT(va));
    CAMLreturn0;
}

CAMLprim value c_bandmatrix_gbtrf(value va, value vp)
{
    CAMLparam2(va, vp);
    BandGBTRF(DLSMAT(va), INT_ARRAY(vp));
    CAMLreturn0;
}

CAMLprim value c_bandmatrix_gbtrs(value va, value vp, value vb)
{
    CAMLparam3(va, vp, vb);
    BandGBTRS(DLSMAT(va), INT_ARRAY(vp), REAL_ARRAY(vb));
    CAMLreturn0;
}

CAMLprim value c_bandmatrix_get(value vmatrix, value vij)
{
    CAMLparam2(vmatrix, vij);
    DlsMat m = DLSMAT(vmatrix);

    int i = Int_val(Field(vij, 0));
    int j = Int_val(Field(vij, 1));

#if CHECK_MATRIX_ACCESS == 1
    if (i < 0 || i >= m->M) caml_invalid_argument("Bandmatrix.get: invalid i");
    if (j < 0 || j >= m->N) caml_invalid_argument("Bandmatrix.get: invalid j");
#endif

    realtype v = BAND_ELEM(m, i, j);
    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_bandmatrix_set(value vmatrix, value vij, value v)
{
    CAMLparam3(vmatrix, vij, v);
    DlsMat m = DLSMAT(vmatrix);

    int i = Int_val(Field(vij, 0));
    int j = Int_val(Field(vij, 1));

#if CHECK_MATRIX_ACCESS == 1
    if (i < 0 || i >= m->M) caml_invalid_argument("Bandmatrix.set: invalid i");
    if (j < 0 || j >= m->N) caml_invalid_argument("Bandmatrix.set: invalid j");
#endif

    BAND_ELEM(m, i, j) = Double_val(v);
    CAMLreturn(caml_copy_double(v));
}

CAMLprim value c_bandmatrix_col_get_col(value vmatrix, value vj)
{
    CAMLparam2(vmatrix, vj);
    CAMLlocal1(r);

    DlsMat m = DLSMAT(vmatrix);

    int j = Int_val(vj);

#if CHECK_MATRIX_ACCESS == 1
    if (j < 0 || j >= m->N)
	caml_invalid_argument("Bandmatrix.Col.get_col: invalid j");

    r = caml_alloc(4, Abstract_tag);
    Store_field(r, 2, Val_int(m->mu));
    Store_field(r, 3, Val_int(m->ml));
#else
    r = caml_alloc(2, Abstract_tag);
#endif

    Store_field(r, 0, (value)BAND_COL(m, j));
    Store_field(r, 1, vmatrix); /* avoid gc of underlying matrix! */
    CAMLreturn(r);
}

CAMLprim value c_bandmatrix_col_get(value vbcol, value vij)
{
    CAMLparam2(vbcol, vij);

    realtype *bcol = (realtype *)Field(vbcol, 0);

    int i = Int_val(Field(vij, 0));
    int j = Int_val(Field(vij, 1));

#if CHECK_MATRIX_ACCESS == 1
    int mu = Int_val(Field(vbcol, 2));
    int ml = Int_val(Field(vbcol, 3));

    if (i < (j - mu) || i > (j + ml))
	caml_invalid_argument("Bandmatrix.Col.get: invalid i");
#endif

    CAMLreturn(caml_copy_double(BAND_COL_ELEM(bcol, i, j)));
}

CAMLprim value c_bandmatrix_col_set(value vbcol, value vij, value ve)
{
    CAMLparam3(vbcol, vij, ve);

    realtype *bcol = (realtype *)Field(vbcol, 0);

    int i = Int_val(Field(vij, 0));
    int j = Int_val(Field(vij, 1));

#if CHECK_MATRIX_ACCESS == 1
    int mu = Int_val(Field(vbcol, 2));
    int ml = Int_val(Field(vbcol, 3));

    if (i < (j - mu) || i > (j + ml))
	caml_invalid_argument("Bandmatrix.Col.set: invalid i");
#endif

    BAND_COL_ELEM(bcol, i, j) = Double_val(ve);

    CAMLreturn(Val_unit);
}

/* Band matrix direct functions */

#define DBANDMAT(v) (*((realtype ***)(Data_custom_val(v))))

static void finalize_direct_bandmat(value va)
{
    destroyMat(DBANDMAT(va));
}

CAMLprim value c_bandmatrix_direct_new_band_mat(value vargs)
{
    CAMLparam1(vargs);
    CAMLlocal1(vr);

    int n   = Int_val(Field(vargs, 0));
    int smu = Int_val(Field(vargs, 1));
    int ml  = Int_val(Field(vargs, 2));

    realtype **a = newBandMat(n, smu, ml);
    mlsize_t approx_size = n * (smu + ml + 2) * sizeof(realtype);

    vr = caml_alloc_final(sizeof(realtype **),
			  &finalize_direct_bandmat,
			  approx_size, approx_size * 20);
    realtype ***r = (realtype ***)Data_custom_val(vr);
    *r = a;

    CAMLreturn(vr);
}

CAMLprim value c_bandmatrix_direct_copy(value va, value vb, value vsizes)
{
    CAMLparam3(va, vb, vsizes);

    int n      = Int_val(Field(vsizes, 0));
    int a_smu  = Int_val(Field(vsizes, 1));
    int b_smu  = Int_val(Field(vsizes, 2));
    int copymu = Int_val(Field(vsizes, 3));
    int copyml = Int_val(Field(vsizes, 4));

    bandCopy(DBANDMAT(va), DBANDMAT(vb), n, a_smu, b_smu, copymu, copyml);
    CAMLreturn0;
}

CAMLprim value c_bandmatrix_direct_scale(value vc, value va, value vsizes)
{
    CAMLparam3(vc, va, vsizes);

    int n   = Int_val(Field(vsizes, 0));
    int mu  = Int_val(Field(vsizes, 1));
    int ml  = Int_val(Field(vsizes, 2));
    int smu = Int_val(Field(vsizes, 3));

    bandScale(Double_val(vc), DBANDMAT(va), n, mu, ml, smu);
    CAMLreturn0;
}

CAMLprim value c_bandmatrix_direct_add_identity(value va, value vn, value vsmu)
{
    CAMLparam3(va, vn, vsmu);

    bandAddIdentity(DBANDMAT(va), Int_val(vn), Int_val(vsmu));
    CAMLreturn0;
}

CAMLprim value c_bandmatrix_direct_gbtrf(value va, value vsizes, value vp)
{
    CAMLparam3(va, vsizes, vp);

    int n   = Int_val(Field(vsizes, 0));
    int mu  = Int_val(Field(vsizes, 1));
    int ml  = Int_val(Field(vsizes, 2));
    int smu = Int_val(Field(vsizes, 3));

    bandGBTRF(DBANDMAT(va), n, mu, ml, smu, INT_ARRAY(vp));
    CAMLreturn0;
}

CAMLprim value c_bandmatrix_direct_gbtrs(value va, value vsizes, value vp, value vb)
{
    CAMLparam4(va, vsizes, vp, vb);

    int n   = Int_val(Field(vsizes, 0));
    int smu = Int_val(Field(vsizes, 1));
    int ml  = Int_val(Field(vsizes, 2));

    bandGBTRS(DBANDMAT(va), n, smu, ml, INT_ARRAY(vp), REAL_ARRAY(vb));
    CAMLreturn0;
}

/* statistic accessor functions */

CAMLprim value c_get_num_stab_lim_order_reds(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVodeGetNumStabLimOrderReds(cvode_mem, &r);
    CHECK_FLAG("CVodeGetNumStabLimOrderReds", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_get_tol_scale_factor(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    realtype r;
    int flag = CVodeGetTolScaleFactor(cvode_mem, &r);
    CHECK_FLAG("CVodeGetTolScaleFactor", flag);

    CAMLreturn(caml_copy_double(r));
}

CAMLprim value c_get_num_nonlin_solv_iters(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVodeGetNumNonlinSolvIters(cvode_mem, &r);
    CHECK_FLAG("CVodeGetNumNonlinSolvIters", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_get_num_nonlin_solv_conv_fails(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVodeGetNumNonlinSolvConvFails(cvode_mem, &r);
    CHECK_FLAG("CVodeGetNumNonlinSolvConvFails", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_get_num_g_evals(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVodeGetNumGEvals(cvode_mem, &r);
    CHECK_FLAG("CVodeGetNumGEvals", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_dls_get_work_space(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CAMLlocal1(r);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int lenrwLS;
    long int leniwLS;

    int flag = CVDlsGetWorkSpace(cvode_mem, &lenrwLS, &leniwLS);
    CHECK_FLAG("CVDlsGetWorkSpace", flag);

    r = caml_alloc_tuple(2);

    Store_field(r, 0, Val_int(lenrwLS));
    Store_field(r, 1, Val_int(leniwLS));

    CAMLreturn(r);
}

CAMLprim value c_dls_get_num_jac_evals(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVDlsGetNumJacEvals(cvode_mem, &r);
    CHECK_FLAG("CVDlsGetNumJacEvals", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_dls_get_num_rhs_evals(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVDlsGetNumRhsEvals(cvode_mem, &r);
    CHECK_FLAG("CVDlsGetNumRhsEvals", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_diag_get_work_space(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CAMLlocal1(r);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int lenrwLS;
    long int leniwLS;

    int flag = CVDiagGetWorkSpace(cvode_mem, &lenrwLS, &leniwLS);
    CHECK_FLAG("CVDiagGetWorkSpace", flag);

    r = caml_alloc_tuple(2);

    Store_field(r, 0, Val_int(lenrwLS));
    Store_field(r, 1, Val_int(leniwLS));

    CAMLreturn(r);
}

CAMLprim value c_diag_get_num_rhs_evals(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVDiagGetNumRhsEvals(cvode_mem, &r);
    CHECK_FLAG("CVDiagGetNumRhsEvals", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_bandprec_get_work_space(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CAMLlocal1(r);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int lenrwBP;
    long int leniwBP;

    int flag = CVBandPrecGetWorkSpace(cvode_mem, &lenrwBP, &leniwBP);
    CHECK_FLAG("CVBandPrecGetWorkSpace", flag);

    r = caml_alloc_tuple(2);

    Store_field(r, 0, Val_int(lenrwBP));
    Store_field(r, 1, Val_int(leniwBP));

    CAMLreturn(r);
}

CAMLprim value c_bandprec_get_num_rhs_evals(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVBandPrecGetNumRhsEvals(cvode_mem, &r);
    CHECK_FLAG("CVBandPrecGetNumRhsEvals", flag);

    CAMLreturn(Val_long(r));
}

/* spils functions */

CAMLprim value c_spils_get_num_lin_iters(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVSpilsGetNumLinIters(cvode_mem, &r);
    CHECK_FLAG("CVSpilsGetNumLinIters", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_spils_get_num_conv_fails(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVSpilsGetNumConvFails(cvode_mem, &r);
    CHECK_FLAG("CVSpilsGetNumConvFails", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_spils_get_work_space(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CAMLlocal1(r);

    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);
    int flag;
    long int lenrw;
    long int leniw;

    flag = CVSpilsGetWorkSpace(cvode_mem, &lenrw, &leniw);
    CHECK_FLAG("CVSpilsGetWorkSpace", flag);

    r = caml_alloc_tuple(2);

    Store_field(r, 0, Val_int(lenrw));
    Store_field(r, 1, Val_int(leniw));

    CAMLreturn(r);
}

CAMLprim value c_spils_get_num_prec_evals(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVSpilsGetNumPrecEvals(cvode_mem, &r);
    CHECK_FLAG("CVSpilsGetNumPrecEvals", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_spils_get_num_prec_solves(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVSpilsGetNumPrecSolves(cvode_mem, &r);
    CHECK_FLAG("CVSpilsGetNumPrecSolves", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_spils_get_num_jtimes_evals(value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVSpilsGetNumJtimesEvals(cvode_mem, &r);
    CHECK_FLAG("CVSpilsGetNumJtimesEvals", flag);

    CAMLreturn(Val_long(r));
}

CAMLprim value c_spils_get_num_rhs_evals (value vcvode_mem)
{
    CAMLparam1(vcvode_mem);
    CVODE_MEM_FROM_ML(cvode_mem, vcvode_mem);

    long int r;
    int flag = CVSpilsGetNumRhsEvals(cvode_mem, &r);
    CHECK_FLAG("CVSpilsGetNumRhsEvals", flag);

    CAMLreturn(Val_long(r));
}

