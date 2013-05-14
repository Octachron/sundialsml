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

/* The parts of the Sundials IDA interface that distinguish between Serial
   NVectors (handled by Bigarrays) and generic NVectors (handled by a wrapper
   type). */

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/bigarray.h>

#include <ida/ida.h>
#include <ida/ida_dense.h>

#include "ida_ml.h"
#include "nvector_ml.h"

// Call with IDA_ML_BIGARRAYS to compile for the Serial NVector to
// Bigarray interface code.

#ifdef IDA_ML_BIGARRAYS

#define IDATYPE(fname) c_ba_ida_ ## fname
#include <nvector/nvector_serial.h>

#define WRAP_NVECTOR(v) caml_ba_alloc(BIGARRAY_FLOAT, 1, NV_DATA_S(v), &(NV_LENGTH_S(v)))
#define RELINQUISH_WRAPPEDNV(v_ba) Caml_ba_array_val(v_ba)->dim[0] = 0

#define NVECTORIZE_VAL(ba) N_VMake_Serial(Caml_ba_array_val(ba)->dim[0], (realtype *)Caml_ba_data_val(ba))
#define RELINQUISH_NVECTORIZEDVAL(nv) N_VDestroy(nv)

#else

#define IDATYPE(fname) c_nvec_ida_ ## fname
#include <sundials/sundials_nvector.h>

#define WRAP_NVECTOR(v) NVEC_DATA(v)
#define RELINQUISH_WRAPPEDNV(v) {}

#define NVECTORIZE_VAL(v) NVEC_VAL(v)
#define RELINQUISH_NVECTORIZEDVAL(nv) {}

#endif

#define DOQUOTE(text) #text
#define QUOTE(val) DOQUOTE(val)
#define IDATYPESTR(fname) QUOTE(IDATYPE(fname))

/* * * * * * * * * * * * * * * * * * * * * * * * *
 * Trampolines
 */

static void errh(
	int error_code,
	const char *module,
	const char *func,
	char *msg,
	void *eh_data)
{
    CAMLparam0();
    CAMLlocal1(a);

    static value *ida_ml_errh;
    if (ida_ml_errh == NULL)
	ida_ml_errh = caml_named_value(IDATYPESTR(ida_ml_errh));

    a = caml_alloc_tuple(4);
    Store_field(a, RECORD_IDA_ERROR_DETAILS_ERROR_CODE,
		Val_int(error_code));
    Store_field(a, RECORD_IDA_ERROR_DETAILS_MODULE_NAME,
		caml_copy_string(module));
    Store_field(a, RECORD_IDA_ERROR_DETAILS_FUNCTION_NAME,
		caml_copy_string(func));
    Store_field(a, RECORD_IDA_ERROR_DETAILS_ERROR_MESSAGE,
		caml_copy_string(msg));

    caml_callback2(*ida_ml_errh, Val_long((long int)eh_data), a);

    CAMLreturn0;
}

CAMLprim void IDATYPE(set_err_handler_fn)(value vdata)
{
    CAMLparam1(vdata);
 
    int flag = IDASetErrHandlerFn(IDA_MEM_FROM_ML(vdata), errh, NULL);
    CHECK_FLAG("IDASetErrHandlerFn", flag);

    CAMLreturn0;
}

CAMLprim void IDATYPE(clear_err_handler_fn)(value vdata)
{
    CAMLparam1(vdata);

    int flag = IDASetErrHandlerFn(IDA_MEM_FROM_ML(vdata), NULL, NULL);
    CHECK_FLAG("IDASetErrHandlerFn", flag);

    CAMLreturn0;
}

static int check_exception(value r)
{
    CAMLparam1(r);
    CAMLlocal1(exn);

    static value *recoverable_failure = NULL;

    if (!Is_exception_result(r)) return 0;

    if (recoverable_failure == NULL) {
	recoverable_failure =
	    caml_named_value("ida_RecoverableFailure");
    }

    exn = Extract_exception(r);
    CAMLreturn((Field(exn, 0) == *recoverable_failure) ? 1 : -1);
}


static int resfn (realtype tres, N_Vector yy, N_Vector yp, 
		  N_Vector resval, void *user_data)
{
    caml_failwith ("to be implemented");
}

static int jacfn (long int neq, realtype t, realtype coef,
		  N_Vector y, N_Vector yp, N_Vector res,
		  DlsMat jac, void *user_data,
		  N_Vector tmp1, N_Vector tmp2, N_Vector tmp3)
{
    value *data = (value *)user_data;
    caml_failwith ("to be implemented");
    IDASetUserData (IDA_MEM_FROM_ML (*data), user_data);
}

static int bandjacfn (long int neq, long int mupper, long int mlower,
		      realtype t, realtype coef, N_Vector y, N_Vector yp,
		      N_Vector res, DlsMat jac, void *user_data,
		      N_Vector tmp1, N_Vector tmp2, N_Vector tmp3)
{
    value *data = (value *)user_data;
    caml_failwith ("to be implemented");
    IDASetUserData (IDA_MEM_FROM_ML (*data), user_data);
}

static int rootsfn (realtype t, N_Vector yy, N_Vector yp,
		    realtype *gout, void *user_data)
{
    value *data = (value *)user_data;
    caml_failwith ("to be implemented");
    IDASetUserData (IDA_MEM_FROM_ML (*data), data);
}

static int errw(N_Vector y, N_Vector ewt, void *user_data)
{
    CAMLparam0();
    CAMLlocal3(y_d, ewt_d, r);

    value *session = user_data;

    y_d = WRAP_NVECTOR(y);
    ewt_d = WRAP_NVECTOR(ewt);

    r = caml_callback2_exn(IDA_ERRW_FROM_ML (*session), y_d, ewt_d);

    RELINQUISH_WRAPPEDNV(y_d);
    RELINQUISH_WRAPPEDNV(ewt_d);

    IDASetUserData (IDA_MEM_FROM_ML (*session), session);

    CAMLreturn(check_exception(r));
}

static value make_jac_arg(realtype t, double coef, N_Vector y, N_Vector yp,
			  N_Vector res, value tmp)
{
    CAMLparam0();
    CAMLlocal1(r);

    r = caml_alloc_tuple(4);
    Store_field(r, RECORD_IDA_JACOBIAN_ARG_JAC_T, caml_copy_double(t));
    Store_field(r, RECORD_IDA_JACOBIAN_ARG_JAC_COEF, caml_copy_double(coef));
    Store_field(r, RECORD_IDA_JACOBIAN_ARG_JAC_Y, WRAP_NVECTOR(y));
    Store_field(r, RECORD_IDA_JACOBIAN_ARG_JAC_YP, WRAP_NVECTOR(yp));
    Store_field(r, RECORD_IDA_JACOBIAN_ARG_JAC_RES, WRAP_NVECTOR(res));
    Store_field(r, RECORD_IDA_JACOBIAN_ARG_JAC_TMP, tmp);

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

static void relinquish_jac_arg(value arg, int triple)
{
    CAMLparam0();
    CAMLlocal1(tmp);

    RELINQUISH_WRAPPEDNV(Field(arg, RECORD_IDA_JACOBIAN_ARG_JAC_Y));
    RELINQUISH_WRAPPEDNV(Field(arg, RECORD_IDA_JACOBIAN_ARG_JAC_YP));
    RELINQUISH_WRAPPEDNV(Field(arg, RECORD_IDA_JACOBIAN_ARG_JAC_RES));

    tmp = Field(arg, RECORD_IDA_JACOBIAN_ARG_JAC_TMP);

    if (triple) {
	RELINQUISH_WRAPPEDNV(Field(tmp, 0));
	RELINQUISH_WRAPPEDNV(Field(tmp, 1));
	RELINQUISH_WRAPPEDNV(Field(tmp, 2));
    } else {
	RELINQUISH_WRAPPEDNV(tmp);
    }

    CAMLreturn0;
}

CAMLprim void IDATYPE(wf_tolerances)(value vdata)
{
    CAMLparam1(vdata);
 
    int flag = IDAWFtolerances(IDA_MEM_FROM_ML(vdata), errw);
    CHECK_FLAG("IDAWFtolerances", flag);

    CAMLreturn0;
}

CAMLprim void IDATYPE(dls_set_dense_jac_fn)(value vdata)
{
    CAMLparam1(vdata);
    int flag = IDADlsSetDenseJacFn(IDA_MEM_FROM_ML(vdata), jacfn);
    CHECK_FLAG("IDADlsSetDenseJacFn", flag);
    CAMLreturn0;
}

CAMLprim void IDATYPE(dls_clear_dense_jac_fn)(value vdata)
{
    CAMLparam1(vdata);
    int flag = IDADlsSetDenseJacFn(IDA_MEM_FROM_ML(vdata), NULL);
    CHECK_FLAG("IDADlsSetDenseJacFn", flag);
    CAMLreturn0;
}

CAMLprim void IDATYPE(dls_set_band_jac_fn)(value vdata, value fbandjacfn)
{
    CAMLparam1(vdata);
    int flag = IDADlsSetBandJacFn(IDA_MEM_FROM_ML(vdata), bandjacfn);
    CHECK_FLAG("IDADlsSetBandJacFn", flag);
    CAMLreturn0;
}

CAMLprim void IDATYPE(dls_clear_band_jac_fn)(value vdata)
{
    CAMLparam1(vdata);
    int flag = IDADlsSetBandJacFn(IDA_MEM_FROM_ML(vdata), NULL);
    CHECK_FLAG("IDADlsSetBandJacFn", flag);
    CAMLreturn0;
}


/* IDAInit + IDARootInit.  The residual and root functions are set to
 * trampolines; the actual functions should be assigned to the ida_session
 * record to be created on the OCaml side.  */
CAMLprim value IDATYPE (init) (value vy, value vyp, value vneqs,
			       value vnroots, value vt0)
{
    CAMLparam5 (vy, vyp, vneqs, vnroots, vt0);
    CAMLlocal1 (r);
    int flag;
    N_Vector y, yp;

    void *ida_mem = IDACreate ();
    if (ida_mem == NULL) {
	caml_failwith ("IDACreate failed");
    }

    y = NVECTORIZE_VAL (vy);
    yp = NVECTORIZE_VAL (vyp);
    flag = IDAInit ((void *)ida_mem, resfn, Double_val (vt0), y, yp);
    RELINQUISH_NVECTORIZEDVAL (y);
    RELINQUISH_NVECTORIZEDVAL (yp);
    CHECK_FLAG ("IDAInit", flag);

    flag = IDARootInit ((void *)ida_mem, Int_val (vneqs), rootsfn);
    CHECK_FLAG ("IDARootInit", flag);

    r = caml_alloc_tuple(2);
    Store_field(r, 0, (value)ida_mem);
    Store_field(r, 1, (value)NULL); // no err_file = NULL

    CAMLreturn (r);
}

CAMLprim void IDATYPE (sv_tolerances) (value ida_mem, value vrtol, value vavtol)
{
    CAMLparam3 (ida_mem, vrtol, vavtol);
    N_Vector avtol;
    int flag;

    avtol = NVECTORIZE_VAL (vavtol);
    flag = IDASVtolerances ((void *)ida_mem, Double_val (vrtol), avtol);
    RELINQUISH_NVECTORIZEDVAL (avtol);
    CHECK_FLAG ("IDASVtolerances", flag);

    CAMLreturn0;
}

CAMLprim void IDATYPE(reinit)(value vdata, value t0, value y0, value yp0)
{
    CAMLparam4(vdata, t0, y0, yp0);

    N_Vector y0_nv = NVECTORIZE_VAL(y0);
    N_Vector yp0_nv = NVECTORIZE_VAL(yp0);
    int flag = IDAReInit(IDA_MEM_FROM_ML(vdata), Double_val(t0), y0_nv, yp0_nv);
    RELINQUISH_NVECTORIZEDVAL(yp0_nv);
    RELINQUISH_NVECTORIZEDVAL(y0_nv);
    CHECK_FLAG("IDAReInit", flag);

    CAMLreturn0;
}

static value solver(value vdata, value nextt, value y, value yp, int onestep)
{
    caml_failwith ("to be implemented");
}


CAMLprim value IDATYPE(normal)(value vdata, value nextt, value y, value yp)
{
    CAMLparam4(vdata, nextt, y, yp);
    CAMLreturn(solver(vdata, nextt, y, yp, 0));
}

CAMLprim value IDATYPE(one_step)(value vdata, value nextt, value y, value yp)
{
    CAMLparam4(vdata, nextt, y, yp);
    CAMLreturn(solver(vdata, nextt, y, yp, 1));
}

CAMLprim value IDATYPE(get_dky)(value vdata, value vt, value vk, value vy)
{
    CAMLparam4(vdata, vt, vk, vy);

    N_Vector y_nv = NVECTORIZE_VAL(vy);

    int flag = IDAGetDky(IDA_MEM_FROM_ML(vdata), Double_val(vt),
			   Int_val(vk), y_nv);
    CHECK_FLAG("IDAGetDky", flag);
    RELINQUISH_NVECTORIZEDVAL(y_nv);
    
    CAMLreturn0;
}

CAMLprim value IDATYPE(get_err_weights)(value vida_mem, value verrws)
{
    CAMLparam2(vida_mem, verrws);

    N_Vector errws_nv = NVECTORIZE_VAL(verrws);

    int flag = IDAGetErrWeights(IDA_MEM_FROM_ML(vida_mem), errws_nv);
    RELINQUISH_NVECTORIZEDVAL(errws_nv);
    CHECK_FLAG("IDAGetErrWeights", flag);

    CAMLreturn0;
}

CAMLprim value IDATYPE(get_est_local_errors)(value vida_mem, value vele)
{
    CAMLparam2(vida_mem, vele);

    N_Vector ele_nv = NVECTORIZE_VAL(vele);

    int flag = IDAGetEstLocalErrors(IDA_MEM_FROM_ML(vida_mem), ele_nv);
    RELINQUISH_NVECTORIZEDVAL(ele_nv);
    CHECK_FLAG("IDAGetEstLocalErrors", flag);

    CAMLreturn0;
}

