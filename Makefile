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
  SEQ_BUILD := 0
else
  DFLAGS+=-release -O -inline
  OUTDIR:=release
  SEQ_BUILD := 1
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

RET:=$(shell python deps.py $(SEQ_BUILD))

ifneq ($(RET),)
  $(error $(RET))
endif

DEP_FILE := deps.mk

include $(DEP_FILE)

define BUNDLE_TARGET
$(2)_SKSRCS := $(addprefix $(SRCDIR)/skia/$(1)/, $($(2)_SRCS))
$(1)_OBJS += $(patsubst %.d,%.obj, $(addprefix $(OUTDIR)/skia/$(1)/, $($(2)_SRCS)))


$(2): $$($(2)_SKSRCS) $($(1)_OBJS)
	@echo "D" $(2)
	$(HIDE)$(DMD) -c -od$(OUTDIR)/skia/$(1) $(DFLAGS) $(IFLAGS) $$($(1)_IMPDOC) $$($(2)_SKSRCS)

endef

define PACKAGE_TEMPLATE
include src/skia/$(1)/files.mk
$(1)_LIB = $(OUTDIR)/$(LIB_PREFIX)$(1).$(LIB_POSTFIX)
$(1)_IMPDOC = -Dd$(DOCDIR)/skia/$(1) -Hd$(IMPDIR)/skia/$(1)
ALL_LIBS += $$($(1)_LIB)
$(1)_OBJS :=
$$(foreach n,$$($(1)_BUNDLES),$$(eval $$(call BUNDLE_TARGET,$(1),$$(n))))
endef

define LIB_TARGET
.PHONY: $(1)
$(1): $$($(1)_LIB)

$$($(1)_LIB): $$($(1)_BUNDLES) $(DEP_FILE) $($(1)_DEP)
	@echo "L" $(1)
	$(HIDE)$(LIBTOOL) -c $$@ $$($(1)_OBJS) 1>/dev/null
endef

$(foreach n,$(PACKAGES),$(eval $(call PACKAGE_TEMPLATE,$(n))))
$(foreach n,$(PACKAGES),$(eval $(call LIB_TARGET,$(n))))


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
