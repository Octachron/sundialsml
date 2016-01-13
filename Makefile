
ifeq ($(wildcard config),)
$(error Please run ./configure first)
endif
include config

default: all

# To compile with profiling (with gcc):
# ./configure CFLAGS=-pg OCAMLOPTFLAGS=-p ...

### Common rules
# We can't use pattern rules here because they don't generate
# dependencies and ocamldep doesn't generate dependencies of the form
# foo.cm[iox]: foo.ml or foo.cmi: foo.mli
.SUFFIXES : .mli .ml .cmi .cmo .cmx

.ml.cmo:
	$(OCAMLC) $(OCAMLFLAGS) $(SUBDIRS:%=-I %) -c $(INCLUDES) $<

.mli.cmi:
	$(OCAMLC) $(OCAMLFLAGS) $(SUBDIRS:%=-I %) -c $(INCLUDES) $<

.ml.cmx:
	$(OCAMLOPT) $(OCAMLOPTFLAGS) $(SUBDIRS:%=-I %) -c $(INCLUDES) $<

%.o: %.c
	$(CC) -I $(OCAML_INCLUDE) $(CFLAGS) $(CSUBDIRS) -o $@ -c $<

### Objects shared between sundials.cma and sundials_no_sens.cma.

# Common to CVODE, IDA, KINSOL, and ARKODE.
COBJ_COMMON = sundials_ml$(XO)		\
	      lsolvers/dls_ml$(XO)	\
	      $(SLS_ML_XO)		\
	      nvectors/nvector_ml$(XO)	\
	      lsolvers/spils_ml$(XO)	\
	      $(NVECPTHREADS_ML_XO)	\
	      $(NVECOPENMP_ML_XO)

COBJ_MAIN = $(COBJ_COMMON) kinsol/kinsol_ml$(XO) $(ARKODE_COBJ_MAIN)

MLOBJ_MAIN =	sundials_config.cmo		\
		sundials.cmo			\
		nvectors/nvector.cmo		\
		lsolvers/dls_impl.cmo		\
		lsolvers/dls.cmo		\
		lsolvers/sls_impl.cmo		\
		$(SLS_CMO)			\
		lsolvers/spils.cmo		\
		nvectors/nvector_custom.cmo	\
		nvectors/nvector_array.cmo	\
		nvectors/nvector_serial.cmo	\
		$(NVECPTHREADS_CMO)		\
		$(NVECOPENMP_CMO) 		\
		cvode/cvode_impl.cmo		\
		ida/ida_impl.cmo		\
		kinsol/kinsol_impl.cmo		\
		cvode/cvode.cmo			\
		kinsol/kinsol.cmo		\
		ida/ida.cmo			\
		$(ARKODE_MLOBJ_MAIN)		\
		$(KLU_MLOBJ_MAIN)		\
		$(SUPERLUMT_MLOBJ_MAIN)

CMI_MAIN = $(filter-out sundials_config.cmi,$(filter-out %_impl.cmi,\
	    $(MLOBJ_MAIN:.cmo=.cmi)))

### Objects specific to sundials.cma.
COBJ_SENS  =	cvodes/cvode_ml_s$(XO)		\
		idas/ida_ml_s$(XO)		\
		cvodes/cvodes_ml$(XO)		\
		idas/idas_ml$(XO)		\
	     	$(KLU_COBJ_SENS)		\
		$(SUPERLUMT_COBJ_SENS)
MLOBJ_SENS =	cvodes/cvodes.cmo		\
		idas/idas.cmo			\
	     	$(KLU_MLOBJ_SENS)		\
		$(SUPERLUMT_MLOBJ_SENS)
CMI_SENS = $(MLOBJ_SENS:.cmo=.cmi)

### Objects specific to sundials_no_sens.cma.
COBJ_NO_SENS =	cvode/cvode_ml$(XO)		\
		ida/ida_ml$(XO)			\
		$(KLU_COBJ_NO_SENS)		\
		$(SUPERLUMT_COBJ_NO_SENS)
MLOBJ_NO_SENS =

### Objects specific to sundials_mpi.cma.
COBJ_MPI =	nvectors/nvector_parallel_ml$(XO)	\
		kinsol/kinsol_bbd_ml$(XO)		\
		$(ARKODE_COBJ_BBD)		\
	   	cvode/cvode_bbd_ml$(XO)			\
		cvodes/cvodes_bbd_ml$(XO)		\
	   	ida/ida_bbd_ml$(XO)			\
		idas/idas_bbd_ml$(XO)
MLOBJ_MPI =	nvectors/nvector_parallel.cmo	\
		kinsol/kinsol_bbd.cmo		\
		$(ARKODE_MLOBJ_BBD)		\
		cvode/cvode_bbd.cmo		\
		cvodes/cvodes_bbd.cmo		\
		ida/ida_bbd.cmo			\
		idas/idas_bbd.cmo
CMI_MPI = $(MLOBJ_MPI:.cmo=.cmi)

### Other sets of files.

# For `make clean'.  All object files, including ones that may not be
# built/updated under the current configuration.  Duplicates OK.
ALL_COBJ = $(COBJ_MAIN) $(COBJ_SENS) $(COBJ_NO_SENS) $(COBJ_MPI)
ALL_MLOBJ =dochtml.cmo $(MLOBJ_MAIN) $(MLOBJ_SENS) $(MLOBJ_NO_SENS) $(MLOBJ_MPI)
ALL_CMA = sundials.cma sundials_no_sens.cma sundials_mpi.cma \
          sundials_docs.cma sundials_docs.cmxs

# Installed files.

INSTALL_CMA=sundials.cma sundials_no_sens.cma \
	    $(if $(MPI_ENABLED),sundials_mpi.cma)

INSTALL_CMI=$(CMI_MAIN) $(CMI_SENS) $(if $(MPI_ENABLED),$(CMI_MPI))

STUBLIBS=$(foreach file,$(INSTALL_CMA:.cma=$(XS)), dllml$(file))

# Don't include $(STUBLIBS) here; they go in a different directory.
INSTALL_FILES=							\
    META							\
    $(INSTALL_CMI)						\
    $(INSTALL_CMA)						\
    $(INSTALL_CMA:.cma=.cmxa)					\
    $(INSTALL_CMA:.cma=$(XA))					\
    $(foreach file,$(INSTALL_CMA:.cma=$(XA)), libml$(file))

### Build rules.

.PHONY: all sundials install doc clean distclean

all: $(INSTALL_CMA) $(INSTALL_CMA:.cma=.cmxa)

sundials.cma sundials.cmxa: $(MLOBJ_MAIN) $(MLOBJ_SENS)			    \
			    $(MLOBJ_MAIN:.cmo=.cmx) $(MLOBJ_SENS:.cmo=.cmx) \
			    $(COBJ_MAIN) $(COBJ_SENS)
	$(OCAMLMKLIB) $(OCAMLMKLIBFLAGS)	\
	    $(if $(ENABLE_SHARED),,-custom)	\
	    -o sundials -oc mlsundials $^	\
	    $(LIB_PATH)				\
	    $(OCAML_CVODES_LIBLINK)		\
	    $(OCAML_ARKODE_LIBLINK)		\
	    $(OCAML_IDAS_LIBLINK)		\
	    $(OCAML_KINSOL_LIBLINK)		\
	    $(OCAML_ALL_LIBLINK)

sundials_no_sens.cma sundials_no_sens.cmxa:				  \
			$(MLOBJ_MAIN) $(MLOBJ_NO_SENS)			  \
			$(MLOBJ_MAIN:.cmo=.cmx) $(MLOBJ_NO_SENS:.cmo=.cmx) \
			$(COBJ_MAIN) $(COBJ_NO_SENS)
	$(OCAMLMKLIB) $(OCAMLMKLIBFLAGS)			\
	    $(if $(ENABLE_SHARED),,-custom)			\
	    -o sundials_no_sens -oc mlsundials_no_sens $^	\
	    $(LIB_PATH)						\
	    $(OCAML_CVODE_LIBLINK)				\
	    $(OCAML_ARKODE_LIBLINK)				\
	    $(OCAML_IDA_LIBLINK)				\
	    $(OCAML_KINSOL_LIBLINK)				\
	    $(OCAML_ALL_LIBLINK)

sundials_mpi.cma sundials_mpi.cmxa: $(MLOBJ_MPI) $(MLOBJ_MPI:.cmo=.cmx) \
				    $(COBJ_MPI)
	$(OCAMLMKLIB) $(OCAMLMKLIBFLAGS)		\
	    $(if $(ENABLE_SHARED),,-custom)		\
	    -o sundials_mpi -oc mlsundials_mpi $^	\
	    $(LIB_PATH) $(MPI_LIBLINK)

$(MLOBJ_MPI) $(CMI_MPI) $(MLOBJ_MPI:.cmo=.cmx)	\
	     doc/html/index.html :				\
    INCLUDES += $(MPI_INCLUDES)

# The CFLAGS settings for CVODE works for modules common to CVODE and IDA.
$(COBJ_COMMON): %.o: %.c
	$(CC) -I $(OCAML_INCLUDE) $(CVODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

nvectors/nvector_parallel_ml.o: nvectors/nvector_parallel_ml.c
	$(MPICC) -I $(OCAML_INCLUDE) $(CVODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

# KINSOL-specific C files.
kinsol/kinsol_ml.o: kinsol/kinsol_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(KINSOL_CFLAGS) $(CSUBDIRS) -o $@ -c $<

kinsol/kinsol_bbd_ml.o: kinsol/kinsol_bbd_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(KINSOL_CFLAGS) $(CSUBDIRS) -o $@ -c $<

kinsol/kinsol_klu_ml.o: kinsol/kinsol_klu_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(KINSOL_CFLAGS) $(CSUBDIRS) -o $@ -c $<

kinsol/kinsol_superlumt_ml.o: kinsol/kinsol_superlumt_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(KINSOL_CFLAGS) $(CSUBDIRS) -o $@ -c $<

# ARKODE-specific C files.
arkode/arkode_ml.o: arkode/arkode_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(ARKODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

arkode/arkode_bbd_ml.o: arkode/arkode_bbd_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(ARKODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

arkode/arkode_klu_ml.o: arkode/arkode_klu_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(ARKODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

arkode/arkode_superlumt_ml.o: arkode/arkode_superlumt_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(ARKODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

# CVODE[S]-specific C files.
cvode/cvode_ml.o: cvode/cvode_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(CVODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

cvodes/cvode_ml_s.o: cvode/cvode_ml.c
	$(CC) -DSUNDIALSML_WITHSENS -I $(OCAML_INCLUDE) \
	    $(CVODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

cvodes/cvodes_ml.o: cvodes/cvodes_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(CVODES_CFLAGS) \
	    $(CSUBDIRS) -Icvode -o $@ -c $<

cvode/cvode_bbd_ml.o: cvode/cvode_bbd_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(CVODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

cvodes/cvodes_bbd_ml.o: cvodes/cvodes_bbd_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(CVODES_CFLAGS) \
	    $(CSUBDIRS) -Icvode -o $@ -c $<

cvode/cvode_klu_ml.o: cvode/cvode_klu_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(CVODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

cvodes/cvode_klu_ml_s.o: cvode/cvode_klu_ml.c
	$(CC) -DSUNDIALSML_WITHSENS -I $(OCAML_INCLUDE) \
	    $(CVODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

cvodes/cvodes_klu_ml.o: cvodes/cvodes_klu_ml.c
	$(CC) -I $(OCAML_INCLUDE) \
	    $(CVODES_CFLAGS) $(CSUBDIRS) -Icvode -o $@ -c $<

cvode/cvode_superlumt_ml.o: cvode/cvode_superlumt_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(CVODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

cvodes/cvode_superlumt_ml_s.o: cvode/cvode_superlumt_ml.c
	$(CC) -DSUNDIALSML_WITHSENS -I $(OCAML_INCLUDE) \
	    $(CVODE_CFLAGS) $(CSUBDIRS) -o $@ -c $<

cvodes/cvodes_superlumt_ml.o: cvodes/cvodes_superlumt_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(CVODES_CFLAGS) \
	    $(CSUBDIRS) -Icvode -o $@ -c $<

# IDA[S]-specific C files.
ida/ida_ml.o: ida/ida_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(IDA_CFLAGS) $(CSUBDIRS) -o $@ -c $<

idas/ida_ml_s.o: ida/ida_ml.c
	$(CC) -DSUNDIALSML_WITHSENS -I $(OCAML_INCLUDE) \
	    $(IDA_CFLAGS) $(CSUBDIRS) -o $@ -c $<

idas/idas_ml.o: idas/idas_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(IDAS_CFLAGS) $(CSUBDIRS) -Iida -o $@ -c $<

ida/ida_bbd_ml.o: ida/ida_bbd_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(IDA_CFLAGS) $(CSUBDIRS) -o $@ -c $<

idas/idas_bbd_ml.o: idas/idas_bbd_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(IDAS_CFLAGS) $(CSUBDIRS) -Iida -o $@ -c $<

ida/ida_klu_ml.o: ida/ida_klu_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(IDA_CFLAGS) $(CSUBDIRS) -o $@ -c $<

idas/ida_klu_ml_s.o: ida/ida_klu_ml.c
	$(CC) -DSUNDIALSML_WITHSENS -I $(OCAML_INCLUDE) \
	    $(IDA_CFLAGS) $(CSUBDIRS) -o $@ -c $<

idas/idas_klu_ml.o: idas/idas_klu_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(IDAS_CFLAGS) $(CSUBDIRS) -Iida -o $@ -c $<

ida/ida_superlumt_ml.o: ida/ida_superlumt_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(IDA_CFLAGS) $(CSUBDIRS) -o $@ -c $<

idas/ida_superlumt_ml_s.o: ida/ida_superlumt_ml.c
	$(CC) -DSUNDIALSML_WITHSENS -I $(OCAML_INCLUDE) \
	    $(IDA_CFLAGS) $(CSUBDIRS) -o $@ -c $<

idas/idas_superlumt_ml.o: idas/idas_superlumt_ml.c
	$(CC) -I $(OCAML_INCLUDE) $(IDAS_CFLAGS) $(CSUBDIRS) -Iida -o $@ -c $<

# Docs.

DOCHTML_PP=$(CPP) $(ML_CPPFLAGS) -DOCAML_3X=$(OCAML_3X)
DOCHTML_PLUGIN_PP=$(DOCHTML_PP)					\
                  -DCVODE_DOC_ROOT=\"$(CVODE_DOC_ROOT_DEFAULT)\"	\
                  -DCVODES_DOC_ROOT=\"$(CVODES_DOC_ROOT_DEFAULT)\"	\
                  -DARKODE_DOC_ROOT=\"$(ARKODE_DOC_ROOT_DEFAULT)\"	\
                  -DIDA_DOC_ROOT=\"$(IDA_DOC_ROOT_DEFAULT)\"	\
                  -DIDAS_DOC_ROOT=\"$(IDAS_DOC_ROOT_DEFAULT)\"	\
                  -DKINSOL_DOC_ROOT=\"$(KINSOL_DOC_ROOT_DEFAULT)\"	\
                  -DMATHJAX_URL=\"$(MATHJAX_URL_DEFAULT)\"
dochtml.cmo: INCLUDES += -I +ocamldoc
dochtml.cmo: OCAMLFLAGS += -pp '$(DOCHTML_PLUGIN_PP)'
dochtml.cmo: config

dochtml.cmx: INCLUDES += -I +ocamldoc
dochtml.cmx: OCAMLOPTFLAGS += -pp '$(DOCHTML_PLUGIN_PP)'
dochtml.cmx: config

SUNDIALS_DOCS=sundials_docs$(OCAMLDOC_PLUGIN)

sundials_docs.cma: sundials_config.cmo dochtml.cmo
	$(OCAMLC) $(OCAMLFLAGS) -o $@ -a $^

sundials_docs.cmxs: sundials_config.cmx dochtml.cmx
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -shared -o $@ $^


META: META.in config
	$(CPP) $(if $(MPI_ENABLED),-DMPI_ENABLED) -DVERSION=\"$(VERSION)\" $< \
	    | grep -v '^#' > $@

doc: doc/html/index.html
	for f in cvode_skel.ml ida_skel.ml kinsol_skel.ml; do \
	    cp examples/ocaml/skeletons/$$f doc/html/; \
	done

DOC_URLS=$(if $(CVODE_DOC_ROOT),-cvode-doc-root "$(CVODE_DOC_ROOT)")	   \
	 $(if $(CVODES_DOC_ROOT),-cvodes-doc-root "$(CVODES_DOC_ROOT)")    \
	 $(if $(ARKODE_DOC_ROOT),-arkode-doc-root "$(ARKODE_DOC_ROOT)")    \
	 $(if $(IDA_DOC_ROOT),-ida-doc-root "$(IDA_DOC_ROOT)")	           \
	 $(if $(IDAS_DOC_ROOT),-idas-doc-root "$(IDAS_DOC_ROOT)")	   \
	 $(if $(KINSOL_DOC_ROOT),-kinsol-doc-root "$(KINSOL_DOC_ROOT)")    \
	 $(if $(MATHJAX_URL),-mathjax "$(MATHJAX_URL)")
doc/html/index.html: OCAML_DOC_ROOT="$(OCAML_DOC_ROOT_DEFAULT)"
doc/html/index.html: doc/html $(SUNDIALS_DOCS) intro.doc		\
		     $(filter-out %_impl.cmi, $(CMI_MAIN))		\
		     $(CMI_SENS) $(if $(MPI_ENABLED), $(CMI_MPI))
	$(OCAMLDOC) -g $(SUNDIALS_DOCS) $(INCLUDES) $(SUBDIRS:%=-I %)	\
	    -charset utf-8						\
	    -short-functors						\
	    -colorize-code						\
	    -css-style docstyle.css					\
	    $(DOC_URLS)							\
	    -pp "$(DOCHTML_PP)						\
		-D'OCAML_DOC_ROOT(x)=$(OCAML_DOC_ROOT)x'		\
		-D'VERSION()=$(VERSION)'"				\
	    -d ./doc/html/						\
	    -hide Cvode_impl,Ida_impl,Kinsol_impl,Arkode_impl		\
	    -t "Sundials/ML $(VERSION)p$(VERSIONP)"			\
	    -intro intro.doc						\
	    $(filter-out %_impl.mli, $(CMI_MAIN:.cmi=.mli))		\
	    $(if $(MPI_ENABLED), $(CMI_MPI:.cmi=.mli))			\
	    $(CMI_SENS:.cmi=.mli)

doc/html:
	mkdir $@

doc/html/perf.opt.png: examples/perf.opt.log
	TITLE="OCaml native code performance over C ($(CC) $(CFLAGS))" \
	    TERMINAL=png \
	    FONT=FreeSans,16 \
	    SIZE=2000,1200 \
	    BMARGIN=1600 \
	    DOTSIZE=2.5 DOTTYPE=7 \
	    OUTPUT=$@ examples/utils/plot.sh $<

# Testing the examples

tests.opt.log: examples/tests.opt.log

examples/tests.opt.log: $(INSTALL_CMA:.cma=.cmxa)
	$(MAKE) -C examples PERF_DATA_POINTS=10 $(subst examples/,,$@)

examples/tests.byte.log: $(INSTALL_CMA:.cma=.cmxa)
	$(MAKE) -C examples PERF_DATA_POINTS=10 $(subst examples/,,$@)

examples/perf.opt.log: $(INSTALL_CMA:.cma=.cmxa)
	$(MAKE) -C examples PERF_DATA_POINTS=10 $(subst examples/,,$@)

examples/perf.byte.log: $(INSTALL_CMA:.cma=.cmxa)
	$(MAKE) -C examples PERF_DATA_POINTS=10 $(subst examples/,,$@)

### Install / Uninstall

install: install-sys $(if $(INSTALL_DOCS),install-doc)

# Install to OCaml's system directory -- /usr/lib/ocaml on Debian derivatives.
install-sys: META $(INSTALL_CMA) $(INSTALL_CMA:.cma=.cmxa)
	[ -d $(PKGDIR) ] || $(MKDIR) $(PKGDIR)
	$(CP) $(INSTALL_FILES) $(PKGDIR)
	$(if $(ENABLE_SHARED),[ -d $(STUBDIR) ] || $(MKDIR) $(STUBDIR))
	$(if $(ENABLE_SHARED),$(CP) $(STUBLIBS) $(STUBDIR))

install-doc: doc
	[ -d $(DOCDIR) ] || $(MKDIR) $(DOCDIR)
	[ -d $(DOCDIR)/html ] || $(MKDIR) $(DOCDIR)/html
	$(CP) doc/html/docstyle.css doc/html/*.html $(DOCDIR)/html/

install-ocamlfind: install-findlib
install-findlib: META $(INSTALL_CMA) $(INSTALL_CMA:.cma=.cmxa)
	@ocamlfind install sundialsml $(INSTALL_FILES) -optional $(STUBLIBS)


uninstall: uninstall-sys

uninstall-sys:
	-$(RM) -f $(foreach f,$(STUBLIBS),$(STUBDIR)$f)
	-$(RM) -f $(foreach f,$(INSTALL_FILES),$(PKGDIR)$f)
	-$(RMDIR) $(PKGDIR)

uninstall-doc:
	-$(RM) $(DOCDIR)/html/docstyle.css $(DOCDIR)/html/*.html
	-$(RMDIR) $(DOCDIR)/html
	-$(RMDIR) $(DOCDIR)

uninstall-ocamlfind: uninstall-findlib
uninstall-findlib:
	@ocamlfind remove sundialsml

### Preparing Releases

# Sets up a sandbox and makes sure everything compiles.  You need
# everything to do this: gcc, git, OCaml >= 4, OCamlMPI, lapack, etc.
# The sandbox is configured with $(CONFIG_COMMAND), which defaults to
# the command you used to configure the current repository.
distcheck:
	git clone . sandbox
	cd sandbox && $(CONFIG_COMMAND) > config.log
	@ # Make sure everything is enabled.
	! grep "NOT FOUND" sandbox/config.log
	! grep "DISABLED" sandbox/config.log
	! grep "without lapack" sandbox/config.log
	@ # Tests.  Important ones and short ones first.
	$(MAKE) -C sandbox all
	$(MAKE) -C sandbox/examples tests.opt.log
	$(MAKE) -C sandbox/examples/ocaml
	$(MAKE) -C sandbox doc
	@ # Because perf.opt.log repeats tests, it sometimes uncovers
	@ # GC bugs that test.opt.log doesn't.
	$(MAKE) -C sandbox/examples PERF_DATA_POINTS=1 perf.opt.log
	$(MAKE) -C sandbox/examples tests.byte.log
	rm -rf sandbox

### Misc

depend: .depend
.depend:
	$(OCAMLDEP) -pp '$(DOCHTML_PP)' *.mli *.ml */*.mli */*.ml > .depend
	$(CC) -MM $(CPPFLAGS) *.c >> .depend

clean:
	-@($(MAKE) -C examples clean)
	-@$(RM) -f $(ALL_MLOBJ) $(ALL_MLOBJ:.cmo=.cmx) $(ALL_MLOBJ:.cmo=$(XO))
	-@$(RM) -f $(ALL_MLOBJ:.cmo=.cmi) $(ALL_MLOBJ:.cmo=.annot) $(ALL_COBJ)
	-@$(RM) -f $(ALL_CMA) $(ALL_CMA:.cma=.cmxa) $(ALL_CMA:.cma=.a)
	-@$(RM) -f $(foreach file,$(INSTALL_CMA:.cma=$(XA)),libml$(file))
	-@$(RM) -f $(foreach file,$(INSTALL_CMA:.cma=$(XS)),dllml$(file))
	-@$(RM) -f $(STUBLIBS)

cleandoc:
	-@$(RM) -f doc/html/*.html

distclean: clean cleandoc
	-@($(MAKE) -C examples distclean)
	-@$(RM) -f META
	-@$(RM) -f config config.h

-include .depend
