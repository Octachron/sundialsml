include ../config

### Common rules
# We can't use pattern rules here because they don't imply
# dependencies and ocamldep doesn't generate dependencies of the form
# foo.cm[iox]: foo.ml or foo.cmi: foo.mli
.SUFFIXES : .mli .ml .cmi .cmo .cmx

.ml.cmo:
	$(OCAMLC) $(OCAMLFLAGS) $(SUBDIRS:%=-I %) $(INCLUDES) -c $<

.mli.cmi:
	$(OCAMLC) $(OCAMLFLAGS) $(SUBDIRS:%=-I %) $(INCLUDES) -c $<

.ml.cmx:
	$(OCAMLOPT) $(OCAMLOPTFLAGS) $(SUBDIRS:%=-I %) $(INCLUDES) -c $<

%.o: %.c
	$(CC) -I $(OCAML_INCLUDE) $(CFLAGS) $(CSUBDIRS) -o $@ -c $<

### Objects shared between sundials.cma and sundials_no_sens.cma.

# Common to CVODE, IDA, KINSOL, and ARKODE.
COBJ_COMMON = sundials/sundials_ml$(XO)	\
	      lsolvers/sundials_matrix_ml$(XO)	\
	      lsolvers/sundials_linearsolver_ml$(XO)	\
	      lsolvers/sundials_nonlinearsolver_ml$(XO)	\
	      nvectors/nvector_ml$(XO)

COBJ_MAIN = $(COBJ_COMMON) kinsol/kinsol_ml$(XO) $(ARKODE_COBJ_MAIN)

MLOBJ_MAIN =	sundials/sundials_configuration.cmo	\
		sundials/sundials_Index.cmo		\
		sundials/sundials_Config.cmo		\
		sundials/sundials_RealArray.cmo		\
		sundials/sundials_RealArray2.cmo	\
		sundials/sundials_LintArray.cmo		\
		sundials/sundials_Logfile.cmo		\
	     	sundials/sundials.cmo			\
		nvectors/nvector.cmo			\
		nvectors/nvector_serial.cmo		\
		lsolvers/sundials_Matrix.cmo		\
		lsolvers/sundials_LinearSolver_impl.cmo	\
		lsolvers/sundials_LinearSolver.cmo	\
		lsolvers/sundials_NonlinearSolver_impl.cmo \
		lsolvers/sundials_NonlinearSolver.cmo	\
		nvectors/nvector_custom.cmo		\
		nvectors/nvector_array.cmo		\
		cvode/cvode_impl.cmo			\
		ida/ida_impl.cmo			\
		kinsol/kinsol_impl.cmo			\
		cvode/cvode.cmo				\
		kinsol/kinsol.cmo			\
		ida/ida.cmo				\
		$(ARKODE_MLOBJ_MAIN)

CMI_MAIN = $(filter-out sundials/sundials_configuration.cmi,$(filter-out %_impl.cmi,\
	    $(MLOBJ_MAIN:.cmo=.cmi)))

### Objects specific to sundials.cma.
COBJ_SENS  =	cvodes/cvode_ml_s$(XO)		\
		cvodes/cvodes_ml$(XO)		\
		cvodes/cvode_klu_ml_s${XO}	\
		cvodes/cvodes_klu_ml${XO}	\
		cvodes/cvode_superlumt_ml_s${XO}\
		cvodes/cvodes_superlumt_ml${XO}	\
		idas/ida_ml_s$(XO)		\
		idas/idas_ml$(XO)		\
		idas/ida_klu_ml_s${XO}		\
		idas/idas_klu_ml${XO}		\
		idas/ida_superlumt_ml_s${XO}	\
		idas/idas_superlumt_ml${XO}	\
		arkode/arkode_klu_ml$(XO)	\
		arkode/arkode_superlumt_ml$(XO)	\
		kinsol/kinsol_klu_ml${XO}	\
		kinsol/kinsol_superlumt_ml${XO}
MLOBJ_SENS =	cvodes/cvodes.cmo		\
		idas/idas.cmo
CMI_SENS = $(MLOBJ_SENS:.cmo=.cmi)

### Objects specific to sundials_no_sens.cma.
COBJ_NO_SENS =	cvode/cvode_ml$(XO)		\
		cvode/cvode_klu_ml${XO}		\
		cvode/cvode_superlumt_ml${XO}	\
		ida/ida_ml$(XO)			\
		ida/ida_klu_ml${XO}		\
		ida/ida_superlumt_ml${XO}	\
		arkode/arkode_klu_ml$(XO)	\
		arkode/arkode_superlumt_ml$(XO)	\
		kinsol/kinsol_klu_ml${XO}	\
		kinsol/kinsol_superlumt_ml${XO}
MLOBJ_NO_SENS =

### Objects specific to sundials_mpi.cma.
COBJ_MPI =	nvectors/nvector_parallel_ml$(XO)	\
		kinsol/kinsol_bbd_ml$(XO)		\
		$(ARKODE_COBJ_BBD)			\
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

### Objects specific to sundials_pthreads.cma.
COBJ_PTHREADS =	nvectors/nvector_pthreads_ml$(XO)
MLOBJ_PTHREADS=	nvectors/nvector_pthreads.cmo
CMI_PTHREADS =	$(MLOBJ_PTHREADS:.cmo=.cmi)

### Objects specific to sundials_pthreads.cma.
COBJ_OPENMP =	nvectors/nvector_openmp_ml$(XO)
MLOBJ_OPENMP =	nvectors/nvector_openmp.cmo
CMI_OPENMP =	$(MLOBJ_OPENMP:.cmo=.cmi)

### Objects specific to sundials_top_*.cma.

MLOBJ_TOP = sundials/sundials_top.cmo		\
	    lsolvers/matrix_top.cmo		\
	    nvectors/nvector_serial_top.cmo

MLOBJ_TOP_MPI = nvectors/nvector_parallel_top.cmo

MLOBJ_TOP_OPENMP = nvectors/nvector_openmp_top.cmo

MLOBJ_TOP_PTHREADS = nvectors/nvector_pthreads_top.cmo

MLOBJ_TOP_FINDLIB = sundials/sundials_top_findlib.cmo

MLOBJ_TOP_ALL = $(MLOBJ_TOP) $(MLOBJ_TOP_MPI) $(MLOBJ_TOP_OPENMP)	\
		$(MLOBJ_TOP_PTHREADS) $(MLOBJ_TOP_FINDLIB)

# Only sundials_top has a meaningful .cmi file.
CMI_TOP = sundials/sundials_top.cmi

# Modules that are generated by collecting pretty-printers.
MLOBJ_TOP_PP = $(filter-out sundials/sundials_top_findlib.cmo	\
			     sundials/sundials_top.cmo,		\
			$(MLOBJ_TOP_ALL))

CMA_TOP_ALL = sundials_top.cma sundials_top_mpi.cma		\
	      sundials_top_openmp.cma sundials_top_pthreads.cma	\
	      sundials_top_findlib.cma

### Other sets of files.

# For `make clean'.  All object files, including ones that may not be
# built/updated under the current configuration.  Duplicates OK.
ALL_COBJ = $(COBJ_MAIN) $(COBJ_SENS) $(COBJ_NO_SENS) $(COBJ_MPI) \
	   $(COBJ_OPENMP) $(COBJ_PTHREADS)
ALL_MLOBJ =doc/dochtml.cmo					\
	   $(MLOBJ_MAIN)					\
	   $(MLOBJ_SENS) $(MLOBJ_NO_SENS) $(MLOBJ_MPI)		\
	   $(MLOBJ_OPENMP) $(MLOBJ_PTHREADS)			\
	   $(MLOBJ_TOP_ALL)
ALL_CMA = sundials.cma sundials_no_sens.cma sundials_mpi.cma	\
	  sundials_openmp.cma sundials_pthreads.cma		\
	  sundials_docs.cma sundials_docs.cmxs			\
	  $(CMA_TOP_ALL)

# Installed files.

# Libraries made by linking .cmo, .cmx, and .o files, yielding
# foo.cma, foo.cmxa, foo.a, libmlfoo.a, and dllmlfoo.so.
CMA_OF_CMO_CMX_COBJ=sundials.cma sundials_no_sens.cma			\
		    $(if $(MPI_ENABLED),sundials_mpi.cma)		\
		    $(if $(OPENMP_ENABLED),sundials_openmp.cma)		\
		    $(if $(PTHREADS_ENABLED),sundials_pthreads.cma)

# Libraries made by linking .cmo files, yielding foo.cma.
# sundials_top_findlib.cma is built and installed only when the
# install target is install-findlib, so it's not listed here.
CMA_OF_CMO=$(if $(TOP_ENABLED),						\
		sundials_top.cma					\
		$(if $(MPI_ENABLED),sundials_top_mpi.cma)		\
		$(if $(OPENMP_ENABLED),sundials_top_openmp.cma)		\
		$(if $(PTHREADS_ENABLED),sundials_top_pthreads.cma)	\
	    )

INSTALL_CMA= $(CMA_OF_CMO_CMX_COBJ) $(CMA_OF_CMO)
INSTALL_CMXA=$(CMA_OF_CMO_CMX_COBJ:.cma=.cmxa)

INSTALL_LIBS=$(foreach file,$(CMA_OF_CMO_CMX_COBJ:.cma=$(XA)),libml$(file))

INSTALL_CMI=$(CMI_MAIN) $(CMI_SENS)			\
	    $(if $(TOP_ENABLED),$(CMI_TOP))		\
	    $(if $(MPI_ENABLED),$(CMI_MPI))		\
	    $(if $(PTHREADS_ENABLED),$(CMI_PTHREADS))	\
	    $(if $(OPENMP_ENABLED),$(CMI_OPENMP))

INSTALL_CMX=$(MLOBJ_MAIN:.cmo=.cmx) $(MLOBJ_SENS:.cmo=.cmx)	  \
	    $(MLOBJ_NO_SENS:.cmo=.cmx)				  \
	    $(if $(MPI_ENABLED),$(MLOBJ_MPI:.cmo=.cmx))		  \
	    $(if $(PTHREADS_ENABLED),$(MLOBJ_PTHREADS:.cmo=.cmx)) \
	    $(if $(OPENMP_ENABLED),$(MLOBJ_OPENMP:.cmo=.cmx))

INSTALL_MLI=$(CMI_MAIN:.cmi=.mli) $(CMI_SENS:.cmi=.mli)

INSTALL_CMA_FINDLIB = $(if $(TOP_ENABLED),sundials_top_findlib.cma)

STUBLIBS=$(foreach file,$(CMA_OF_CMO_CMX_COBJ:.cma=$(XS)), dllml$(file))

# Don't include $(STUBLIBS) here; they go in a different directory.
INSTALL_FILES=								\
    META								\
    $(INSTALL_CMI)							\
    $(INSTALL_MLI)							\
    $(INSTALL_CMX)							\
    $(INSTALL_CMA)							\
    $(INSTALL_CMXA)							\
    $(INSTALL_CMXA:.cmxa=$(XA))						\
    $(INSTALL_LIBS)

INSTALL_FILES_FINDLIB=$(INSTALL_CMA_FINDLIB)
