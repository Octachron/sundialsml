/***********************************************************************
 *                                                                     *
 *                   OCaml interface to Sundials                       *
 *                                                                     *
 *  Timothy Bourke (Inria), Jun Inoue (Inria), and Marc Pouzet (LIENS) *
 *                                                                     *
 *  Copyright 2014 Institut National de Recherche en Informatique et   *
 *  en Automatique.  All rights reserved.  This file is distributed    *
 *  under a BSD 2-Clause License, refer to the file LICENSE.           *
 *                                                                     *
 ***********************************************************************/

#include <cvodes/cvodes.h>
#include <sundials/sundials_config.h>
#include <sundials/sundials_types.h>
#include <sundials/sundials_band.h>
#include <sundials/sundials_nvector.h>
#include <cvodes/cvodes_bbdpre.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/unixsupport.h>
#include <caml/bigarray.h>

#include "dls_ml.h"
#include "spils_ml.h"
#include "sundials_ml.h"
#include "cvode_ml.h"
#include "cvodes_ml.h"
#include "nvector_ml.h"

static int bbbdlocal(long int nlocal, realtype t, N_Vector y, N_Vector yb,
		     N_Vector glocal, void *user_data)
{
    CAMLparam0();
    CAMLlocalN(args, 5);
    int r;
    value *backref = user_data;
    CAML_FN (call_bbbdlocal);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = NVEC_BACKLINK(y);
    args[3] = NVEC_BACKLINK(yb);
    args[4] = NVEC_BACKLINK(glocal);

    r = Int_val (caml_callbackN(*call_bbbdlocal,
                                sizeof (args) / sizeof (*args),
                                args));

    CAMLreturnT(int, r);
}

static int bbbdcomm(long int nlocal, realtype t, N_Vector y, N_Vector yb,
		    void *user_data)
{
    CAMLparam0();
    CAMLlocalN(args, 4);
    int r;
    value *backref = user_data;
    CAML_FN (call_bbbdcomm);

    args[0] = *backref;
    args[1] = caml_copy_double(t);
    args[2] = NVEC_BACKLINK(y);
    args[3] = NVEC_BACKLINK(yb);

    r = Int_val (caml_callbackN(*call_bbbdcomm,
                                sizeof (args) / sizeof (*args),
                                args));

    CAMLreturnT(int, r);
}

CAMLprim value c_cvodes_bbd_prec_initb (value vparentwhich, value vlocaln,
					value vbandwidths, value vdqrely,
					value vhascomm)
{
    CAMLparam5(vparentwhich, vlocaln, vbandwidths, vdqrely, vhascomm);
    void *cvode_mem = CVODE_MEM_FROM_ML (Field(vparentwhich, 0));
    int flag;

    flag = CVBBDPrecInitB (cvode_mem, Int_val(Field(vparentwhich, 1)),
	Long_val(vlocaln),
	Long_val(Field(vbandwidths, RECORD_CVODE_BANDBLOCK_BANDWIDTHS_MUDQ)),
	Long_val(Field(vbandwidths, RECORD_CVODE_BANDBLOCK_BANDWIDTHS_MLDQ)),
	Long_val(Field(vbandwidths, RECORD_CVODE_BANDBLOCK_BANDWIDTHS_MUKEEP)),
	Long_val(Field(vbandwidths, RECORD_CVODE_BANDBLOCK_BANDWIDTHS_MLKEEP)),
	Double_val(vdqrely),
	bbbdlocal,
	Bool_val(vhascomm) ? bbbdcomm : NULL);
    CHECK_FLAG ("CVBBDPrecInitB", flag);

    CAMLreturn (Val_unit);
}

CAMLprim value c_cvodes_bbd_prec_reinitb (value vparent, value vwhich,
					  value vmudq, value vmldq,
					  value vdqrely)
{
    CAMLparam5(vparent, vwhich, vmudq, vmldq, vdqrely);
    void *cvode_mem = CVODE_MEM_FROM_ML (vparent);
    int flag;

    flag = CVBBDPrecReInitB (cvode_mem, Int_val(vwhich),
			     Long_val(vmudq), Long_val(vmldq),
			     Double_val(vdqrely));
    CHECK_FLAG ("CVBBDPrecReInitB", flag);

    CAMLreturn (Val_unit);
}

