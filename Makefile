DMD := dmd
LIBTOOL := lib
IMPDIR := import
SRCDIR := src
DOCDIR := doc
DFLAGS := -w
IFLAGS := -I$(SRCDIR) -I$(IMPDIR)
HIDE := @

ifeq ($(DEBUG),1)
	DFLAGS+=-debug -unittest -gc
	OUTDIR:=debug
else
	DFLAGS+=-release -O -inline
	OUTDIR:=release
endif

LIBFILE := $(OUTDIR)/skia.lib
SAMPLEAPP := $(OUTDIR)/SampleApp.exe
SAMPLEAPP_W := $(subst /,\\,$(SAMPLEAPP))

##############################################################################
# Private part
##############################################################################

.PHONY: all
all: skia sampleapp

.PHONY: debug
debug:
	$(HIDE)$(MAKE) -f Makefile DEBUG=1 all

.PHONY: release
release:
	$(HIDE)$(MAKE) -f Makefile DEBUG=0 all

.PHONY: clean
clean:
	$(HIDE)rm -rf debug release
	$(HIDE)rm -rf $(IMPDIR)
	$(HIDE)rm -rf $(DOCDIR)

.PHONY: help
help:
	@echo "Targets:"
	@echo "    <default>: out/libskia.a"
	@echo "    clean: removes entire out/ directory"
	@echo "    help: this text"
	@echo "Options: (after make, or in bash shell)"
	@echo "    SKIA_DEBUG=true for debug build"
	@echo "    SKIA_SCALAR=fixed for fixed-point build"
	@echo "    SKIA_BUILD_FOR=mac for mac build (e.g. CG for image decoding)"
	@echo "    SKIA_PDF_SUPPORT=true to enable the pdf generation backend"
	@echo ""

##############################################################################

ALL_LIBS :=

LIB_PREFIX :=
LIB_POSTFIX := lib

PACKAGES = core views

##############################
# Dependencies
##############################

RET:=$(shell python deps.py)
ifneq ($(RET),)
  $(error $(RET))
endif
DEP_FILE := deps.mk

include $(DEP_FILE)

define PACKAGE_TEMPLATE
include src/skia/$(1)/files.mk
$(1)_SRCS = $$(addprefix $$(SRCDIR)/skia/$(1)/, $$($(1)_SOURCE))
$(1)_LIB = $(OUTDIR)/$(LIB_PREFIX)$(1).$(LIB_POSTFIX)
$(1)_IMPDOC = -Dd$(DOCDIR)/skia/$(1) -Hd$(IMPDIR)/skia/$(1)
ALL_LIBS += $$($(1)_LIB)

.PHONY: $(1)
$(1): $$($(1)_LIB)

$$($(1)_LIB): $$($(1)_SRCS) $(DEP_FILE) $($(1)_DEP)
	@echo "L" $(1)
	$(HIDE)$(DMD) -lib -of$$@ $(DFLAGS) $(IFLAGS) $$($(1)_IMPDOC) $$($(1)_SRCS)
endef

$(foreach n,$(PACKAGES),$(eval $(call PACKAGE_TEMPLATE,$(n))))


################################################################################

.PHONY: skia
skia: $(LIBFILE)

$(LIBFILE): Makefile $(ALL_LIBS)
	@echo "L " $@
	$(HIDE)$(LIBTOOL) -c $@ $(ALL_LIBS) 1>/dev/null

################################################################################

.PHONY: sampleapp
sampleapp: skia $(SAMPLEAPP)

$(SAMPLEAPP): Makefile $(LIBFILE) SampleApp/WinMain.d SampleApp/RectView.d
	@echo "L " $@
	$(HIDE)$(DMD) -of$(SAMPLEAPP_W) $(DFLAGS) -I$(IMPDIR) $(LIBFILE) gdi32.lib SampleApp/*.d
