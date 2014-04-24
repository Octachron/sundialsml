/***********************************************************************
 *                                                                     *
 *     OCaml interface to Sundials (serial) CVODE and IDA solvers      *
 *                                                                     *
 *  Timothy Bourke (Inria), Jun Inoue (Inria), and Marc Pouzet (LIENS) * 
 *                                                                     *
 *  Copyright 2013 Institut National de Recherche en Informatique et   *
 *  en Automatique.  All rights reserved.  This file is distributed    *
 *  under a BSD 2-Clause License, refer to the file LICENSE.           *
 *                                                                     *
 ***********************************************************************/

#include <sundials/sundials_config.h>
#include <sundials/sundials_iterative.h>
#include <sundials/sundials_spgmr.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/unixsupport.h>
#include <caml/bigarray.h>

#include "sundials_ml.h"
#include "spils_ml.h"

int spils_precond_type(value vptype)
{
    CAMLparam1(vptype);

    int ptype;
    switch (Int_val(vptype)) {
    case VARIANT_SPILS_PRECONDITIONING_TYPE_PRECNONE:
	ptype = PREC_NONE;
	break;

    case VARIANT_SPILS_PRECONDITIONING_TYPE_PRECLEFT:
	ptype = PREC_LEFT;
	break;

    case VARIANT_SPILS_PRECONDITIONING_TYPE_PRECRIGHT:
	ptype = PREC_RIGHT;
	break;

    case VARIANT_SPILS_PRECONDITIONING_TYPE_PRECBOTH:
	ptype = PREC_BOTH;
	break;
    }

    CAMLreturn(ptype);
}

int spils_gs_type(value vgstype)
{
    CAMLparam1(vgstype);

    int gstype;
    switch (Int_val(vgstype)) {
    case VARIANT_SPILS_GRAMSCHMIDT_TYPE_MODIFIEDGS:
	gstype = MODIFIED_GS;
	break;

    case VARIANT_SPILS_GRAMSCHMIDT_TYPE_CLASSICALGS:
	gstype = CLASSICAL_GS;
	break;
    }

    CAMLreturn(gstype);
}

CAMLprim value c_spils_qr_fact(value vn, value vh, value vq, value vnewjob)
{
    CAMLparam4(vn, vh, vq, vnewjob);
    int r;
    int n = Int_val(vn);

#if CHECK_MATRIX_ACCESS == 1
    struct caml_ba_array *bh = ARRAY2_DATA(vh);
    intnat hm = bh->dim[1];
    intnat hn = bh->dim[0];

    if ((hm < n + 1) || (hn < n))
	caml_invalid_argument("Spils.qr_fact: h is too small.");
    if (ARRAY1_LEN(vq) < 2 * n)
	caml_invalid_argument("Spils.qr_fact: q is too small.");
#endif

    r = QRfact(n, ARRAY2_ACOLS(vh), REAL_ARRAY(vq), Bool_val(vnewjob));

    CAMLreturn(Val_int(r));
}

CAMLprim value c_spils_qr_sol(value vn, value vh, value vq, value vb)
{
    CAMLparam4(vn, vh, vq, vb);
    int r;
    int n = Int_val(vn);

#if CHECK_MATRIX_ACCESS == 1
    struct caml_ba_array *bh = ARRAY2_DATA(vh);
    intnat hm = bh->dim[1];
    intnat hn = bh->dim[0];

    if ((hm < n + 1) || (hn < n))
	caml_invalid_argument("Spils.qr_sol: h is too small.");
    if (ARRAY1_LEN(vq) < 2 * n)
	caml_invalid_argument("Spils.qr_sol: q is too small.");
    if (ARRAY1_LEN(vb) < n + 1)
	caml_invalid_argument("Spils.qr_sol: b is too small.");
#endif

    r = QRsol(n, ARRAY2_ACOLS(vh), REAL_ARRAY(vq), REAL_ARRAY(vb));

    CAMLreturn(Val_int(r));
}

