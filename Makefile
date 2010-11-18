# Simple makefile for skia library and test apps

# setup our defaults
DMD := dmd
LIBTOOL := lib
IMPORTDIR := import
DOCDIR := doc
DFLAGS := -w

ifdef DEBUG
	DFLAGS += -debug -unittest
	OUTDIR := debug
else
	DFLAGS += -release -O -inline
	OUTDIR := release
endif

LIBNAME := skia.lib
LIBFILE := $(OUTDIR)/$(LIBNAME)

#CFLAGS_SSE2 = $(CFLAGS) -msse2
#LINKER_OPTS := -lpthread
#DEFINES :=
#HIDE = @
# start with the core (required)
include src/skia/core/core_files.mk
SRC_LIST := $(addprefix skia/core/, $(SOURCE))

# start with the core (required)
include src/skia/views/views_files.mk
SRC_LIST += $(addprefix skia/views/, $(SOURCE))

$(OUTDIR)/%.o : src/%.d
	@echo $*
	@mkdir -p $(dir $@)
	$(HIDE)$(DMD) $(DFLAGS) -I$(IMPORTDIR) -c $< -of$@ -Hf$(IMPORTDIR)/$*.di -Df$(DOCDIR)/$*.html
	@echo "compiling $@"

# now build out objects
OBJ_LIST := $(SRC_LIST:.d=.o)
OBJ_LIST := $(addprefix $(OUTDIR)/, $(OBJ_LIST))

##############################################################################

.PHONY: all
all: lib sampleapp

$(LIBFILE): Makefile $(OBJ_LIST)
	$(HIDE)$(LIBTOOL) -c $(LIBFILE) $(OBJ_LIST)

.PHONY: lib
lib: $(LIBFILE)

$(OUTDIR)/WinMain.exe: Makefile $(LIBFILE) SampleApp/WinMain.d
	$(DMD) SampleApp/WinMain.d $(LIBFILE) gdi32.lib -I$(IMPORTDIR) $(DFLAGS)
	$(HIDE) mv WinMain.exe $@
	$(HIDE) rm WinMain.*

.PHONY: sampleapp
sampleapp: $(OUTDIR)/WinMain.exe

.PHONY: clean
clean:
	$(HIDE)rm -rf debug release
	$(HIDE)rm -rf $(IMPORTDIR)
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
