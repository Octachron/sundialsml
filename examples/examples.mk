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
# * EXAMPLES, LAPACK_EXAMPLES, MPI_EXAMPLES
#   List of .ml files in $(SUBDIR) that:
#     - don't use lapack or MPI
#     - use lapack
#     - use MPI
#   respectively.
# * USELIB [optional]
#   sundials or sundials_nosensi (no extension!).  Defaults to sundials.

include $(SRCROOT)/config

USELIB ?= sundials

## Shorthands
DIVIDER = "----------------------------------------------------------------------"
ALL_EXAMPLES=$(EXAMPLES) $(LAPACK_EXAMPLES) $(MPI_EXAMPLES)
ENABLED_EXAMPLES=$(EXAMPLES) $(if $(LAPACK_ENABLED),$(LAPACK_EXAMPLES)) \
	         $(if $(MPI_ENABLED),$(MPI_EXAMPLES))
SERIAL_EXAMPLES=$(EXAMPLES) $(LAPACK_EXAMPLES)
SUNDIALSLIB_DEPS=$(foreach x,$(SUNDIALSLIB),$(SRCROOT)/$x)

UTILS=$(SRCROOT)/examples/utils

## Testing correctness
all: $(ENABLED_EXAMPLES:.ml=.byte) $(ENABLED_EXAMPLES:.ml=.opt)

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

$(SERIAL_EXAMPLES:.ml=.byte): %.byte: %.ml $(SRCROOT)/$(USELIB).cma
	$(OCAMLC) $(OCAMLFLAGS) -o $@ \
	    $(INCLUDES) -I $(SRCROOT) -dllpath $(SRCROOT) bigarray.cma unix.cma \
	    $(USELIB).cma $<

$(SERIAL_EXAMPLES:.ml=.opt): %.opt: %.ml $(SRCROOT)/$(USELIB).cmxa
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -o $@ \
	    $(INCLUDES) -I $(SRCROOT) bigarray.cmxa unix.cmxa \
	    $(USELIB).cmxa $<

$(MPI_EXAMPLES:.ml=.byte): %.byte: %.ml $(SRCROOT)/$(USELIB).cma
	$(OCAMLC) $(OCAMLFLAGS) -o $@ \
	    $(INCLUDES) -I $(SRCROOT) -dllpath $(SRCROOT) bigarray.cma unix.cma \
	    mpi.cma $(USELIB).cma sundials_mpi.cma $<

$(MPI_EXAMPLES:.ml=.opt): %.opt: %.ml $(SRCROOT)/$(USELIB).cmxa
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -o $@ \
	    $(INCLUDES) -I $(SRCROOT) bigarray.cmxa unix.cmxa \
	    mpi.cmxa $(USELIB).cmxa sundials_mpi.cmxa $<

# opam inserts opam's and the system's stublibs directory into
# CAML_LD_LIBRARY_PATH, which has precdence over -dllpath.  Make sure
# we run with the shared libraries in the source tree, not installed
# ones (if any).
CAML_LD_LIBRARY_PATH:=$(SRCROOT):$(CAML_LD_LIBRARY_PATH)
%.byte.out: %.byte
	CAML_LD_LIBRARY_PATH=$(CAML_LD_LIBRARY_PATH) ./$< > $@

%.byte.diff: %.byte.out %.sundials.out
	diff -u $^ > $@ || true

# Native code has C stubs statically linked in, so no need to modify
# LD_LIBRARY_PATH (which would be a platform-dependent nightmare).
%.opt.out: %.opt
	./$< > $@

%.opt.diff: %.opt.out %.sundials.out
	@diff -u $^ > $@ || true

%.sundials.out: $(EXAMPLESROOT)/$(SUBDIR)/%
	$< > $@

%.self.diff: %.byte.out %.opt.out
	@diff -u $^ > $@ || true

## Performance measurement

# How many times to measure each example.  Each measurement repeats
# the example several times to make it run long enough.
PERF_REPS ?= 3

# At least how long each measurement should take.  If this value is
# too low, the measurement will be unreliable.
MIN_TIME ?= 1

PERF=perf.opt.log perf.byte.log

.PHONY: $(PERF)

.SECONDARY: $(ALL_EXAMPLES:.ml=.byte.time) $(ALL_EXAMPLES:.ml=.opt.time)     \
	    $(ALL_EXAMPLES:.ml=.sundials) $(ALL_EXAMPLES:.ml=.sundials.time) \
	    $(ALL_EXAMPLES:.ml=.byte.perf) $(ALL_EXAMPLES:.ml=.opt.perf)

$(UTILS)/perf: $(UTILS)/perf.ml
	$(OCAMLOPT) -o $@ unix.cmxa $<

$(PERF): perf.%.log: $(ENABLED_EXAMPLES:.ml=.%) $(ENABLED_EXAMPLES:.ml=.%.perf)
	@grep '^#' $(lastword $^) >$@
	@sed -n '/^[^#]/ p' $(filter %.perf,$^) >> $@
	cat $@

%.opt.perf: %.opt.time %.sundials.time $(UTILS)/perf
	$(UTILS)/perf -s $(<:.opt.time=) $(filter-out $(UTILS)/perf,$^) > $@

%.byte.perf: %.byte.time %.sundials.time
	$(UTILS)/perf -s $(<:.byte.time=) $(filter-out $(UTILS)/perf,$^) > $@

# .sundials should be run before .opt or .byte - it determines NUM_REPS.
%.sundials.time: %.sundials $(UTILS)/perf
	$(UTILS)/perf -m $(MIN_TIME) $(PERF_REPS) ./$< \
	    | tee $@ 

%.opt.time: %.opt %.sundials.time $(UTILS)/perf
	$(UTILS)/perf -i $(word 2,$^) $(PERF_REPS) ./$< \
	    | tee $@

%.byte.time: %.byte %.sundials.time $(UTILS)/perf
	$(UTILS)/perf -i $(word 2,$^) $(PERF_REPS) ./$< \
	    | tee $@

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
endif

$(ALL_EXAMPLES:.ml=.sundials.c): %.sundials.c: $(EXAMPLESROOT)/$(SUBDIR)/%.c \
					       $(UTILS)/sundials_wrapper.c.in
	@if grep -q 'main *( *void *)' $< || grep -q 'main *( *)' $<;	    \
	 then main_args=;						    \
	 else main_args="argc, argv";					    \
	 fi;								    \
	 sed -e 's#@sundials_src_name@#$<#' -e "s#@main_args@#$$main_args#" \
	   $(UTILS)/sundials_wrapper.c.in > $@

$(SERIAL_EXAMPLES:.ml=.sundials): %.sundials: %.sundials.c
	$(CC) -o $@ -I $(EXAMPLESROOT)/$(SUBDIR) \
	    $(EG_CFLAGS) $< $(LIB_PATH) $(EG_LDFLAGS) $(LAPACK_LIB)

$(MPI_EXAMPLES:.ml=.sundials): %.sundials: %.sundials.c
	$(MPICC) -o $@ -I $(EXAMPLESROOT)/$(SUBDIR) \
	    $(EG_CFLAGS) $< $(LIB_PATH) $(EG_LDFLAGS) $(LAPACK_LIB)

## Dependences to files living outside of the examples directory

# Just remind the user to recompile the library rather than actually
# doing the recompilation.  (Or is it better to recompile?)
$(SRCROOT)/%.cma $(SRCROOT)/%.cmxa:
	@echo "$@ doesn't exist."
	@echo "Maybe you forgot to compile the main library?"
	@false

$(EXAMPLESROOT)/$(SUBDIR)/%:
	@echo "The C version of the example $@ is missing or out of date"
	@false

## Misc

distclean: clean
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
	-@rm -f $(ALL_EXAMPLES:.ml=.sundials) $(ALL_EXAMPLES:.ml=.sundials.c)
	-@rm -f $(ALL_EXAMPLES:.ml=.sundials.time) $(ALL_EXAMPLES:.ml=.reps)
	-@rm -f $(ALL_EXAMPLES:.ml=.byte.perf) $(ALL_EXAMPLES:.ml=.opt.perf)
	-@rm -f tests.log lapack-tests.log tests.self.log
	-@rm -f tests.byte.log lapack-tests.byte.log
	-@rm -f tests.opt.log lapack-tests.opt.log
	-@rm -f perf.byte.log perf.opt.log
