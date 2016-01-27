# Make rules for examples taken from LLNL's C library (i.e. all
# examples except those in ocaml/), included from the Makefile of each
# subdirectory.

# The following variables should be defined:
#
# * SRCROOT
#   Path to the root of the source tree.
# * SUBDIR
#   Which subdirectory's Makefile included this examples.mk file.
#   cvode/serial, ida/parallel, etc.  No / allowed at the end.
# * C_SUBDIR
#   Which subdirectory of sundials' examples directory contains
#   the corresponding examples, if different from SUBDIR.
# * EXAMPLES, LAPACK_EXAMPLES, MPI_EXAMPLES, OPENMP_EXAMPLES, PTHREADS_EXAMPLES
#   List of .ml files in $(SUBDIR) that:
#     - don't use lapack or MPI
#     - use lapack
#     - use MPI
#     - use OpenMP
#     - use pthreads
#   respectively.
# * FILES_TO_CLEAN
#   Space-separated names of files (relative to current path) that should
#   be deleted upon `make clean'.
# * USELIB [optional]
#   sundials or sundials_nosensi (no extension!).  Defaults to sundials.
#
# Examples that need special execution commands (e.g. mpirun) should be
# communicated like
# $(eval $(call EXECUTION_RULE,foo,$(MPIRUN) -np 4 $$<))
# Caveats:
#  - Automatic variables like $< and $@ must have two $'s.
#  - Don't prefix $$< with ./
#  - Supply a third argument bar if foo.{out,reps,time} should be copies
#    of bar.{out,reps,time}.

SRC=$(SRCROOT)/src
include $(SRCROOT)/config

all: tests.byte tests.opt

C_EXAMPLES=$(if $(EXAMPLESROOT),,c_examples_unavailable)
c_examples_unavailable:
	@echo "C version of examples not found.  Try running configure again"
	@echo "with EXAMPLES=/path/to/sundials/examples.  You can give the examples"
	@echo "directory in the sundials C source tree or (if you installed the C library's"
	@echo "examples) the one in the installation."
	@false

USELIB ?= sundials
C_SUBDIR ?= $(SUBDIR)

## Shorthands
DIVIDER = "----------------------------------------------------------------------"
ALL_EXAMPLES=$(EXAMPLES) $(LAPACK_EXAMPLES) $(MPI_EXAMPLES)	\
	     $(OPENMP_EXAMPLES) $(PTHREADS_EXAMPLES)
ENABLED_EXAMPLES=$(EXAMPLES) $(if $(LAPACK_ENABLED),$(LAPACK_EXAMPLES))	\
	         $(if $(MPI_ENABLED),$(MPI_EXAMPLES))			\
	         $(if $(OPENMP_ENABLED),$(OPENMP_EXAMPLES))		\
	         $(if $(PTHREADS_ENABLED),$(PTHREADS_EXAMPLES))
SERIAL_EXAMPLES=$(EXAMPLES) $(LAPACK_EXAMPLES)
SUNDIALSLIB_DEPS=$(foreach x,$(SUNDIALSLIB),$(SRC)/$x)

UTILS=$(SRCROOT)/examples/utils

## Testing correctness

tests.byte: $(ENABLED_EXAMPLES:.ml=.byte)
tests.opt: $(ENABLED_EXAMPLES:.ml=.opt)

ifeq ($(LAPACK_ENABLED),1)
lapack.byte: $(LAPACK_EXAMPLES:.ml=.byte)
lapack.opt: $(LAPACK_EXAMPLES:.ml=.opt)
else
.PHONY: lapack.byte lapack.opt
lapack.byte:
	@echo "The binding was compiled without lapack."
	@false
lapack.opt:
	@echo "The binding was compiled without lapack."
	@false
endif

# Log file creation
TESTS=tests.opt.log tests.byte.log tests.self.log
LAPACK_TESTS=lapack-tests.opt.log lapack-tests.byte.log lapack-tests.self.log
.PHONY: $(TESTS) $(LAPACK_TESTS)

%.byte.diff: %.byte.out %.sundials.out
	diff -u $^ > $@ || true

%.opt.diff: %.opt.out %.sundials.out
	@diff -u $^ > $@ || true

%.self.diff: %.byte.out %.opt.out
	@diff -u $^ > $@ || true

# Note: the cd ensures the output mentions the examples' directories.
genlog =						\
    @(for f in $(1); do					\
	echo $(DIVIDER);				\
	echo "--$(SUBDIR)/$$f";				\
	cat $$f;					\
     done;						\
     echo "Summary (each should be 0):";		\
     for f in $(1); do					\
	(cd $(SRCROOT)/examples; wc -l $(SUBDIR)/$$f);	\
     done;						\
    ) > $(2)

$(TESTS): tests.%.log: $(ENABLED_EXAMPLES:.ml=.%.diff)
	$(call genlog, $^, $@)
	cat $@
	@! grep '^[0-9]' $@ | grep -q '^[^0]'

$(LAPACK_TESTS): lapack-tests.%.log: $(LAPACK_EXAMPLES:.ml=.%.diff)
	$(call genlog, $^, $@)
	cat $@
	@! grep '^[0-9]' $@ | grep -q '^[^0]'

# Build / execution rules

# Keep outputs of tests that crashed.  Those outputs are not
# automatically updated afterwards, so unless you update the test or
# binding, you need to make clean to re-run the test.
.PRECIOUS: $(ALL_EXAMPLES:.ml=.byte.out) $(ALL_EXAMPLES:.ml=.opt.out) $(ALL_EXAMPLES:.ml=.sundials.out)

# Dependence on $(USELIB) causes examples to be recompiled when the
# binding is recompiled.  However, the examples still don't recompile
# if you modify the binding but forget to recompile it.  Is there a
# way to protect against the latter without being too invasive?

$(SERIAL_EXAMPLES:.ml=.byte): %.byte: %.ml $(SRC)/$(USELIB).cma
	$(OCAMLC) $(OCAMLFLAGS) -o $@ \
	    $(INCLUDES) -I $(SRC) -dllpath $(SRC) \
	    $(SUBDIRS:%=-I $(SRC)/%) \
	    bigarray.cma unix.cma \
	    $(USELIB).cma $<

$(SERIAL_EXAMPLES:.ml=.opt): %.opt: %.ml $(SRC)/$(USELIB).cmxa
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -o $@ \
	    $(INCLUDES) -I $(SRC) bigarray.cmxa unix.cmxa \
	    $(SUBDIRS:%=-I $(SRC)/%) \
	    $(USELIB).cmxa $<

$(MPI_EXAMPLES:.ml=.byte): %.byte: %.ml $(SRC)/$(USELIB).cma \
			   $(SRC)/sundials_mpi.cma
	$(OCAMLC) $(OCAMLFLAGS) -o $@ \
	    $(INCLUDES) $(MPI_INCLUDES) -I $(SRC) -dllpath $(SRC) \
	    $(SUBDIRS:%=-I $(SRC)/%) \
	    bigarray.cma unix.cma mpi.cma $(USELIB).cma sundials_mpi.cma $<

$(MPI_EXAMPLES:.ml=.opt): %.opt: %.ml $(SRC)/$(USELIB).cmxa \
$(OPENMP_EXAMPLES:.ml=.byte): %.byte: %.ml $(SRC)/$(USELIB).cma \
			      $(SRC)/sundials_mpi.cma
	$(OCAMLC) $(OCAMLFLAGS) -o $@ \
	    $(INCLUDES) $(MPI_INCLUDES) -I $(SRC) -dllpath $(SRC) \
	    $(SUBDIRS:%=-I $(SRC)/%) \
	    bigarray.cma unix.cma mpi.cma $(USELIB).cma sundials_mpi.cma $<

$(OPENMP_EXAMPLES:.ml=.byte): %.byte: %.ml $(SRC)/$(USELIB).cma \
			   $(SRC)/sundials_mpi.cma
	$(OCAMLC) $(OCAMLFLAGS) -o $@ \
	    $(INCLUDES) $(MPI_INCLUDES) -I $(SRC) -dllpath $(SRC) \
	    $(SUBDIRS:%=-I $(SRC)/%) \
	    bigarray.cma unix.cma mpi.cma $(USELIB).cma sundials_mpi.cma $<

$(OPENMP_EXAMPLES:.ml=.opt): %.opt: %.ml $(SRC)/$(USELIB).cmxa \
			  $(SRC)/sundials_mpi.cmxa
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -o $@ \
	    $(INCLUDES) $(MPI_INCLUDES) -I $(SRC) \
	    $(SUBDIRS:%=-I $(SRC)/%) \
	    bigarray.cmxa unix.cmxa mpi.cmxa $(USELIB).cmxa sundials_mpi.cmxa $<

$(PTHREADS_EXAMPLES:.ml=.byte): %.byte: %.ml $(SRC)/$(USELIB).cma \
			        $(SRC)/sundials_mpi.cma
	$(OCAMLC) $(OCAMLFLAGS) -o $@ \
	    $(INCLUDES) $(MPI_INCLUDES) -I $(SRC) -dllpath $(SRC) \
	    $(SUBDIRS:%=-I $(SRC)/%) \
	    bigarray.cma unix.cma mpi.cma $(USELIB).cma sundials_mpi.cma $<

$(PTHREADS_EXAMPLES:.ml=.opt): %.opt: %.ml $(SRC)/$(USELIB).cmxa \
			  $(SRC)/sundials_mpi.cmxa
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -o $@ \
	    $(INCLUDES) $(MPI_INCLUDES) -I $(SRC) \
	    $(SUBDIRS:%=-I $(SRC)/%) \
	    bigarray.cmxa unix.cmxa mpi.cmxa $(USELIB).cmxa sundials_mpi.cmxa $<

# opam inserts opam's and the system's stublibs directory into
# CAML_LD_LIBRARY_PATH, which has higher precdence than -dllpath.
# Make sure we run with the shared libraries in the source tree, not
# installed ones (if any).  Native code doesn't have this problem
# because it statically links in C stubs.
CAML_LD_LIBRARY_PATH:=$(SRC):$(CAML_LD_LIBRARY_PATH)

# Rules for producing *.out files.  Subroutine of EXECUTION_RULE.
define ADD_EXECUTE_RULES
    $1.byte.out: $1.byte
	CAML_LD_LIBRARY_PATH=$(CAML_LD_LIBRARY_PATH) $(2:$$<=./$$<) > $$@
    $1.opt.out: $1.opt
	$(2:$$<=./$$<) > $$@
    ifeq ($3,)
    $1.sundials.out: $1.sundials
	$(2:$$<=./$$<) > $$@
    else
    $1.sundials.out: $3.sundials.out
	cp $$< $$@
    endif
endef


## Performance measurement

# How many times to measure each example.  Each measurement repeats
# the example several times to make it run long enough.
PERF_DATA_POINTS ?= 3

# At least how long each measurement should take.  If this value is
# too low, the measurement will be unreliable.
MIN_TIME ?= 1

PERF=perf.opt.log perf.byte.log

.PHONY: $(PERF)

.SECONDARY: $(ALL_EXAMPLES:.ml=.byte.time) $(ALL_EXAMPLES:.ml=.opt.time)     \
	    $(ALL_EXAMPLES:.ml=.sundials) $(ALL_EXAMPLES:.ml=.sundials.time) \
	    $(ALL_EXAMPLES:.ml=.reps)

$(UTILS)/perf: $(UTILS)/perf.ml
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -o $@ unix.cmxa $<

$(UTILS)/crunchperf: $(UTILS)/crunchperf.ml
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -o $@ str.cmxa unix.cmxa $<

perf.byte.log perf.opt.log: perf.%.log: $(ENABLED_EXAMPLES:.ml=.%.perf)       \
					$(UTILS)/crunchperf
	$(UTILS)/crunchperf -m $(filter-out $(UTILS)/crunchperf,$^) > $@
	$(UTILS)/crunchperf -s $@

NATIVE_TITLE='OCaml native code performance over C ($(CC) $(CFLAGS))'
BYTE_TITLE  ='OCaml byte code performance over C ($(CC) $(CFLAGS))'
PLOTTYPES=jpg png pdf eps

perf.opt.plot: perf.opt.log
	TITLE=$(NATIVE_TITLE) $(UTILS)/plot.sh $<
	@$(UTILS)/plot.sh --explain-vars

perf.byte.plot: perf.byte.log
	TITLE=$(BYTE_TITLE) $(UTILS)/plot.sh $<
	@$(UTILS)/plot.sh --explain-vars

$(foreach t,$(PLOTTYPES),perf.opt.$t): perf.opt.log
	TITLE=$(NATIVE_TITLE) \
	    TERMINAL=$(subst perf.opt.,,$@)				  \
	    OUTPUT=$@ $(UTILS)/plot.sh $<
	@printf "\nPlot saved in %s.\n" "$@"
	@$(UTILS)/plot.sh --explain-vars

$(foreach t,$(PLOTTYPES),perf.byte.$t): perf.byte.log
	TITLE=$(BYTE_TITLE) \
	    TERMINAL=$(subst perf.byte.,,$@)				  \
	    OUTPUT=$@ $(UTILS)/plot.sh $<
	@printf "\nPlot saved in %s.\n" "$@"
	@$(UTILS)/plot.sh --explain-vars

# Rules for producing *.time files.  Subroutine of EXECUTION_RULE.
define ADD_TIME_RULES
    # .reps should be updated if perf.ml was modified, but not if it
    # was just recompiled; hence perf.ml is a dependence while perf
    # is an order-only dependence.
    ifeq ($3,)
    $1.reps: $(UTILS)/perf.ml | $1.sundials $(UTILS)/perf
	$(UTILS)/perf -r $(MIN_TIME) $(2:$$<=./$$(word 1,$$|)) > $$@
    $1.sundials.time: $1.sundials $1.reps $(UTILS)/perf
	$(UTILS)/perf -m $$(word 2,$$^) $(PERF_DATA_POINTS) \
	    $(2:$$<=./$$<) | tee $$@
    else
    $1.reps: $3.reps
	cp $$< $$@
    $1.sundials.time: $3.sundials.time
	cp $$< $$@
    endif
    $1.opt.time: $1.opt $1.reps $(UTILS)/perf
	$(UTILS)/perf -m $$(word 2,$$^) $(PERF_DATA_POINTS) \
	    $(2:$$<=./$$<) | tee $$@
    $1.byte.time: $1.byte $1.reps $(UTILS)/perf
	$(UTILS)/perf -m $$(word 2,$$^) $(PERF_DATA_POINTS) \
	    $(2:$$<=./$$<) | tee $$@
    $1.opt.perf: $1.opt.time $1.sundials.time $(UTILS)/crunchperf
	$(UTILS)/crunchperf -c $$(word 1, $$^) $$(word 2, $$^) \
	    $(SUBDIR)/$$(<:.opt.time=) > $$@
    $1.byte.perf: $1.byte.time $1.sundials.time $(UTILS)/crunchperf
	$(UTILS)/crunchperf -c $$(word 1, $$^) $$(word 2, $$^) \
	    $(SUBDIR)/$$(<:.byte.time=) > $$@
endef

# Compilation of C examples with environment-handling wrappers.

MODULE=$(word 1,$(subst /, ,$(SUBDIR)))

ifeq ($(MODULE),cvode)
EG_CFLAGS=$(CVODE_CFLAGS)
EG_LDFLAGS=$(CVODE_LDFLAGS)
else ifeq ($(MODULE),cvodes)
EG_CFLAGS=$(CVODES_CFLAGS)
EG_LDFLAGS=$(CVODES_LDFLAGS)
else ifeq ($(MODULE),ida)
EG_CFLAGS=$(IDA_CFLAGS)
EG_LDFLAGS=$(IDA_LDFLAGS)
else ifeq ($(MODULE),idas)
EG_CFLAGS=$(IDAS_CFLAGS)
EG_LDFLAGS=$(IDAS_LDFLAGS)
else ifeq ($(MODULE),kinsol)
EG_CFLAGS=$(KINSOL_CFLAGS)
EG_LDFLAGS=$(KINSOL_LDFLAGS)
else ifeq ($(MODULE),arkode)
EG_CFLAGS=$(ARKODE_CFLAGS)
EG_LDFLAGS=$(ARKODE_LDFLAGS)
endif

EG_CFLAGS += $(C_SUPPRESS_WARNINGS)

$(ALL_EXAMPLES:.ml=.sundials.c): %.sundials.c: $(C_EXAMPLES)		     \
					       $(EXAMPLESROOT)/$(C_SUBDIR)/%.c\
					       $(UTILS)/sundials_wrapper.c.in
	@if grep -q 'main *( *void *)' $< || grep -q 'main *( *)' $<;	    \
	 then main_args=;						    \
	 else main_args="argc, argv";					    \
	 fi;								    \
	 sed -e 's#@sundials_src_name@#$<#' -e "s#@main_args@#$$main_args#" \
	   $(UTILS)/sundials_wrapper.c.in > $@

$(SERIAL_EXAMPLES:.ml=.sundials): %.sundials: %.sundials.c $(SRCROOT)/config
	$(CC) -o $@ -I $(EXAMPLESROOT)/$(C_SUBDIR) \
	    $(EG_CFLAGS) $< $(LIB_PATH) $(EG_LDFLAGS) $(LAPACK_LIB)

$(MPI_EXAMPLES:.ml=.sundials): %.sundials: %.sundials.c $(SRCROOT)/config
	$(MPICC) -o $@ -I $(EXAMPLESROOT)/$(C_SUBDIR) \
	    $(EG_CFLAGS) $< $(LIB_PATH) $(EG_LDFLAGS) \
	    $(LAPACK_LIB) $(MPI_LIBLINK)

## Misc

# Just remind the user to recompile the library rather than actually
# doing the recompilation.  (Or is it better to recompile?)
$(SRC)/%.cma $(SRC)/%.cmxa:
	@echo "$@ doesn't exist."
	@echo "Maybe you forgot to compile the main library?"
	@false

$(SRCROOT)/config:
	@echo "$@ doesn't exist."
	@echo "Maybe you forgot to compile the main library?"
	@false

# Generate recipes for *.out, *.time, etc.
define EXECUTION_RULE
    $(call ADD_EXECUTE_RULES,$1,$2,$3)
    $(call ADD_TIME_RULES,$1,$2,$3)
endef

# Generate a default version.
$(eval $(call EXECUTION_RULE,%,$$<))

distclean: clean
	-@rm -f $(ALL_EXAMPLES:.ml=.reps)
clean:
	-@rm -f $(ALL_EXAMPLES:.ml=.cmo) $(ALL_EXAMPLES:.ml=.cmx)
	-@rm -f $(ALL_EXAMPLES:.ml=.o) $(ALL_EXAMPLES:.ml=.cmi)
	-@rm -f $(ALL_EXAMPLES:.ml=.c.log) $(ALL_EXAMPLES:.ml=.ml.log)
	-@rm -f $(ALL_EXAMPLES:.ml=.byte) $(ALL_EXAMPLES:.ml=.opt)
	-@rm -f $(ALL_EXAMPLES:.ml=.byte.out) $(ALL_EXAMPLES:.ml=.opt.out)
	-@rm -f $(ALL_EXAMPLES:.ml=.sundials.out)
	-@rm -f $(ALL_EXAMPLES:.ml=.annot)
	-@rm -f $(ALL_EXAMPLES:.ml=.byte.diff) $(ALL_EXAMPLES:.ml=.opt.diff)
	-@rm -f $(ALL_EXAMPLES:.ml=.self.diff)
	-@rm -f $(ALL_EXAMPLES:.ml=.byte.time) $(ALL_EXAMPLES:.ml=.opt.time)
	-@rm -f $(ALL_EXAMPLES:.ml=.byte.perf) $(ALL_EXAMPLES:.ml=.opt.perf)
	-@rm -f $(ALL_EXAMPLES:.ml=.sundials) $(ALL_EXAMPLES:.ml=.sundials.c)
	-@rm -f $(ALL_EXAMPLES:.ml=.sundials.time)
	-@rm -f tests.log lapack-tests.log tests.self.log
	-@rm -f tests.byte.log lapack-tests.byte.log
	-@rm -f tests.opt.log lapack-tests.opt.log
	-@rm -f perf.byte.log perf.opt.log
	-@rm -f $(foreach t,$(PLOTTYPES),perf.opt.$t)
	-@rm -f $(foreach t,$(PLOTTYPES),perf.byte.$t) $(FILES_TO_CLEAN)
