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

#ifndef _IDAS_ML_H__
#define _IDAS_ML_H__

/* The sessions of IDAS work almost exactly as described in ida_ml.h.
 *
 * 1. Standard (quadrature, sensitivity, sensitivity/quadrature,
 *    adjoint-forward) sessions are created by the basic ida code. Extra
 *    details are added and accessed through the sensext field.
 *
 * 2. In IDAS backward sessions are 'piggy-backed' onto parent sessions;
 *    the parent maintains a linked list and each session is identified by a
 *    'which-id' (basically its order in the list). For all set* functions,
 *    one must pass the pair of parent and which-id, but for many get*
 *    functions, one passes the underlying ida_mem record associated with
 *    the backward session (normally accessed through IDAGetAdjIDABmem).
 *
 *    In the OCaml interface to IDAS we create a session object for each
 *    backward session that works almost exactly like the basic IDA
 *    sessions (as described in ida_ml.h); i.e., we set the user-data for
 *    the backward session (IDASetUserDataB) to a weak pointer to a
 *    session object on the OCaml side. The sensext field is used to track
 *    parent, which-id, and callbacks. The first two are used for set*
 *    interface functions and the session itself is used for get* interface
 *    functions.
 *
 *    There are two small differences. First, on the OCaml side, we type
 *    each such session as a 'bsession' (rather than as a 'session'), even
 *    though the underlying representation is compatible with a standard
 *    session (excepting the sensext field). Second, the finalizer neither
 *    calls IDAFree, since the parent takes care of this, nor closes an
 *    error file, since one cannot be created (backward sessions inherit
 *    from the parent at the time of their creation). In the parent we
 *    maintain a list of child (backward) sessions and in each child we
 *    maintain a reference to the parent so that all are garbage collected
 *    at once (such loops are not a problem since they are completely on the
 *    OCaml side). If we did not maintain a link from the parent to a child,
 *    a child could be garbage collected and then the callback (triggered by
 *    a IDAB on the parent) would fail.
 *
 */

void idas_ml_check_flag(const char *call, int flag);

// NB: overrides CHECK_FLAG macro in ida_ml.h
#define SCHECK_FLAG(call, flag) if (flag != IDA_SUCCESS) \
				  idas_ml_check_flag(call, flag)

enum idas_fwd_session_index {
    RECORD_IDAS_FWD_SESSION_QUADRHSFN = 0,
    RECORD_IDAS_FWD_SESSION_NUMSENSITIVITIES,
    RECORD_IDAS_FWD_SESSION_SENSARRAY1,
    RECORD_IDAS_FWD_SESSION_SENSARRAY2,
    RECORD_IDAS_FWD_SESSION_SENSARRAY3,
    RECORD_IDAS_FWD_SESSION_SENSPVALS,
    RECORD_IDAS_FWD_SESSION_SENSRESFN,
    RECORD_IDAS_FWD_SESSION_QUADSENSRHSFN,
    RECORD_IDAS_FWD_SESSION_BSESSIONS,
    RECORD_IDAS_FWD_SESSION_SIZE
};

#define IDAS_SENSARRAY1_FROM_EXT(v)    Field((v), RECORD_IDAS_FWD_SESSION_SENSARRAY1)
#define IDAS_SENSARRAY2_FROM_EXT(v)    Field((v), RECORD_IDAS_FWD_SESSION_SENSARRAY2)
#define IDAS_SENSARRAY3_FROM_EXT(v)    Field((v), RECORD_IDAS_FWD_SESSION_SENSARRAY3)
#define IDAS_SENSRESFN_FROM_EXT(v)     Field((v), RECORD_IDAS_FWD_SESSION_SENSRESFN)
#define IDAS_QUADSENSRHSFN_FROM_EXT(v) Field((v), RECORD_IDAS_FWD_SESSION_QUADSENSRHSFN)

enum idas_bwd_session_index {
    RECORD_IDAS_BWD_SESSION_PARENT = 0,
    RECORD_IDAS_BWD_SESSION_WHICH,
    RECORD_IDAS_BWD_SESSION_NUMSENSITIVITIES,
    RECORD_IDAS_BWD_SESSION_BSENSARRAY1,
    RECORD_IDAS_BWD_SESSION_BSENSARRAY2,
    RECORD_IDAS_BWD_SESSION_RESFNB,
    RECORD_IDAS_BWD_SESSION_RESFNBS,
    RECORD_IDAS_BWD_SESSION_BQUADRHSFN,
    RECORD_IDAS_BWD_SESSION_BQUADRHSFN1,
    RECORD_IDAS_BWD_SESSION_SIZE
};

/* FIXME: change to PARENT_FROM_BEXT etc.  */

#define IDAS_BPARENT_FROM_EXT(v) Field((v), RECORD_IDAS_BWD_SESSION_PARENT)
#define IDAS_BWHICH_FROM_EXT(v)  Field((v), RECORD_IDAS_BWD_SESSION_WHICH)

#define IDAS_BSENSARRAY1_FROM_EXT(v)  Field((v), RECORD_IDAS_BWD_SESSION_BSENSARRAY1)
#define IDAS_BSENSARRAY2_FROM_EXT(v)  Field((v), RECORD_IDAS_BWD_SESSION_BSENSARRAY2)

#define IDAS_RESFNB_FROM_EXT(v) Field((v), RECORD_IDAS_BWD_SESSION_RESFNB)
#define IDAS_RESFNBS_FROM_EXT(v) Field((v), RECORD_IDAS_BWD_SESSION_RESFNBS)

#define IDAS_BRHSFN1_FROM_EXT(v)     Field((v), RECORD_IDAS_BWD_SESSION_BRHSFN1)
#define IDAS_BQUADRHSFN1_FROM_EXT(v) Field((v), RECORD_IDAS_BWD_SESSION_BQUADRHSFN1)

enum idas_sens_method {
    VARIANT_IDAS_SENS_METHOD_SIMULTANEOUS = 0,
    VARIANT_IDAS_SENS_METHOD_STAGGERED,
    VARIANT_IDAS_SENS_METHOD_STAGGERED1
};

enum idas_sens_params_index {
    RECORD_IDAS_SENS_PARAMS_PVALS   = 0,
    RECORD_IDAS_SENS_PARAMS_PBAR,
    RECORD_IDAS_SENS_PARAMS_PLIST,
    RECORD_IDAS_SENS_PARAMS_SIZE
};

enum idas_sens_dq_method {
    VARIANT_IDAS_SENS_DQ_METHOD_CENTERED = 0,
    VARIANT_IDAS_SENS_DQ_METHOD_FORWARD
};

enum idas_sens_stats_index {
    RECORD_IDAS_SENS_STATS_NUM_RES_EVALS = 0,
    RECORD_IDAS_SENS_STATS_NUM_SENS_EVALS,
    RECORD_IDAS_SENS_STATS_NUM_ERR_TEST_FAILS,
    RECORD_IDAS_SENS_STATS_NUM_LIN_SOLV_SETUPS,
    RECORD_IDAS_SENS_STATS_SIZE
};

enum idas_adj_interpolation {
    VARIANT_IDAS_ADJ_INTERPOLATION_POLYNOMIAL = 0,
    VARIANT_IDAS_ADJ_INTERPOLATION_HERMITE
};

enum idas_adj_jacobian_arg_index {
    RECORD_IDAS_ADJ_JACOBIAN_ARG_JAC_T   = 0,
    RECORD_IDAS_ADJ_JACOBIAN_ARG_JAC_Y,
    RECORD_IDAS_ADJ_JACOBIAN_ARG_JAC_YP,
    RECORD_IDAS_ADJ_JACOBIAN_ARG_JAC_YB,
    RECORD_IDAS_ADJ_JACOBIAN_ARG_JAC_YPB,
    RECORD_IDAS_ADJ_JACOBIAN_ARG_JAC_RESB,
    RECORD_IDAS_ADJ_JACOBIAN_ARG_JAC_COEF,
    RECORD_IDAS_ADJ_JACOBIAN_ARG_JAC_TMP,
    RECORD_IDAS_ADJ_JACOBIAN_ARG_SIZE
};

enum idas_adj_bandrange_index {
    RECORD_IDAS_ADJ_BANDRANGE_MUPPER = 0,
    RECORD_IDAS_ADJ_BANDRANGE_MLOWER,
    RECORD_IDAS_ADJ_BANDRANGE_SIZE
};

enum idas_adj_solve_arg_index {
    RECORD_IDAS_ADJ_SPILS_SOLVE_ARG_RVEC   = 0,
    RECORD_IDAS_ADJ_SPILS_SOLVE_ARG_GAMMA,
    RECORD_IDAS_ADJ_SPILS_SOLVE_ARG_DELTA,
    RECORD_IDAS_ADJ_SPILS_SOLVE_ARG_LR,
    RECORD_IDAS_ADJ_SPILS_SOLVE_ARG_SIZE
};

#undef IDATYPE
#undef DOQUOTE
#undef QUOTE
#undef IDATYPESTR
#define IDATYPE(fname) c_ida_ ## fname
#define DOQUOTE(text) #text
#define QUOTE(val) DOQUOTE(val)
#define IDATYPESTR(fname) QUOTE(IDATYPE(fname))

#define CAML_FN(name)					\
    static value *name;					\
    if (name == NULL)					\
	name = caml_named_value (IDATYPESTR (name)) /* no semicolon */

#endif
