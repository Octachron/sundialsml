# Invoke `make' with USELIB=sundials to run the tests with the
# sensitivity-agnostic subset of CVODES.  Note that memory usage
# statistics will differ from the versions in sundials/C, unless those
# are recompiled to link against CVODES.
USELIB ?= sundials_no_sens
SRCROOT=../../..
SUBDIR=matrix/band
C_SUBDIR=sunmatrix/band

EXAMPLES = test_sunmatrix_band.ml

include ../matrix.mk

MATRIX_COLS ?= 5000
MATRIX_UBAND ?= 100
MATRIX_LBAND ?= 100
$(eval $(call EXECUTION_RULE,test_sunmatrix_band,$$< $(MATRIX_COLS) $(MATRIX_UBAND) $(MATRIX_LBAND) 0))

