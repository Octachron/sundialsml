# This files is a wrapper around examples.mk that adds build rules for
# test_sunnonlinsol_*.ml.

FILES_TO_CLEAN=

USELIB ?= sundials_no_sens
SRCROOT=../../..
SUBDIR=nonlinsol/fixedpoint
C_SUBDIR=sunnonlinsol/fixedpoint

EXAMPLES = $(if $(AT_LEAST_4_0_0), test_sunnonlinsol_fixedpoint.ml)

include ../nonlinsol.mk
