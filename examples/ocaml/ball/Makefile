include ../../../config

SRCROOT = ../../../src

all: $(if $(OCAML_GRAPHICS_PATH),ball.byte ball.opt)

ball.byte: showball.cmi showball.cmo ball.ml
	$(OCAMLC) $(OCAMLFLAGS) -o $@ $(INCLUDES) \
	    -I $(SRCROOT) $(SUBDIRS:%=-I $(SRCROOT)/%) -dllpath $(SRCROOT) \
	    -I "$(OCAML_GRAPHICS_PATH)" \
	    unix.cma bigarray.cma graphics.cma \
	    sundials.cma showball.cmo ball.ml

ball.opt: showball.cmi showball.cmx ball.ml
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -o $@ $(INCLUDES) \
	    -I $(SRCROOT) $(SUBDIRS:%=-I $(SRCROOT)/%) \
	    -I "$(OCAML_GRAPHICS_PATH)" \
	    unix.cmxa bigarray.cmxa graphics.cmxa \
	    sundials.cmxa showball.cmx ball.ml

showball.cmi : showball.mli
	$(OCAMLC) $(OCAMLFLAGS) $^

showball.cmo : showball.ml showball.cmi
	$(OCAMLC) $(OCAMLFLAGS) -I $(OCAML_GRAPHICS_PATH) \
	    unix.cma graphics.cma -c $<

showball.cmx : showball.ml showball.cmi
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -I "$(OCAML_GRAPHICS_PATH)" \
	    unix.cmxa graphics.cmxa -c $<

clean:
	-@rm -f showball.cmi showball.cmo showball.cmx showball.o
	-@rm -f showball.cmt showball.cmti
	-@rm -f ball.cmi ball.cmo ball.cmx ball.o
	-@rm -f ball.cmt ball.cmti
	-@rm -f showball.annot ball.annot

distclean: clean
	-@rm -f ball.byte ball.opt

