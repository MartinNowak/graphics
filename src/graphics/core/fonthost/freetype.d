module graphics.core.fonthost.freetype;

import core.atomic, core.sync.rwmutex, std.exception, std.string, std.traits;
import std.algorithm, std.conv, std.utf;
import freetype.freetype, freetype.outline, guip.bitmap, guip.point, guip.size;
import graphics.core.glyph, graphics.core.fonthost.fontconfig, graphics.core.paint, graphics.core.path;

// No module @safe: default: GlyphStream.apply is an attribute-generic
// walk slot (Dg template parameter, the policy of Path.apply), and GDC
// pins templates to the module default rather than inferring per
// instantiation - a @safe: default would reject @system delegates from
// the untagged renderer. Safety is carried by explicit tags on the
// concrete members below, @trusted islands for the FT_* C calls, and a
// @system extern(C) block for the outline callbacks that run under
// FT_Outline_Decompose's C signature.

private shared FreeType _freeType;

// @trusted: double-checked singleton over a shared mutable global
// (cas on the reference, synchronized on the fresh instance, init()
// runs exactly once); shared/global access is @system by attribute.
@property shared(FreeType) freeType() @trusted
{
    if (_freeType is null)
    {
        auto ft = new shared(FreeType)();
        synchronized(ft)
        {
            if (cas(&_freeType, cast(shared FreeType)null, ft))
                ft.init();
        }
    }
    return _freeType;
}

private synchronized class FreeType
{
    // @trusted islands: library is this singleton's raw FT_Library
    // handle; init creates it once (after the getter's cas), done
    // destroys it on shutdown, and enforce turns FT failures into
    // exceptions. toStringz's NUL-probe on a fontconfig path is the
    // only @system-adjacent step in newFace; FT writes the face out
    // through &face.
    void init() @trusted
    {
        enforce(!FT_Init_FreeType(cast(FT_Library*)&library),
                new Exception("Error during initialization of FreeType"));
    }

    ~this() @trusted
    {
        FT_Done_FreeType(cast(FT_Library)library);
        _freeType = null;
    }

    FT_Face newFace(string path) @trusted
    {
        FT_Face face;
        enforce(!FT_New_Face(cast(FT_Library)library, toStringz(path), 0, &face));
        return face;
    }

    private FT_Library library;
}

enum Scale26D6 = 1.0f / 64;
@safe FPoint ScaleFT_Vector(FT_Vector vec) {
  return FPoint(vec.x, vec.y) * Scale26D6;
}

shared(GlyphStore) _glyphStore;

// @trusted: same double-checked-cas singleton as freeType().
@property shared(GlyphStore) glyphStore() @trusted
{
    if (_glyphStore is null)
    {
        auto gs = new shared(GlyphStore)();
        synchronized(gs)
        {
            if (cas(&_glyphStore, cast(shared GlyphStore)null, gs))
                gs.init();
        }
    }
    return _glyphStore;
}

synchronized class GlyphStore
{
    void init()
    {
    }

    ~this() @trusted  // FT_Done_Face on the store's own face handles
    {
        foreach(faceData; data)
            foreach(sizeData; faceData)
                FT_Done_Face(cast(FT_Face)sizeData.face);
    }

    // TODO: consider removing size based caches now that every text
    // is rendered as path
    // @trusted: GlyphStore is a synchronized class, so this runs under
    // the instance monitor; the @system drmem calls are only shared-
    // qualified AA operators (the shared AA ops lose their @safe).
    shared(Data) getData(TypeFace typeFace, float textSize) @trusted
    {
        if (auto faceData = typeFace.filename in data)
        {
            if (auto sizeData = textSize in *faceData)
            {
                return *sizeData;
            }
            else
            {
                auto sizeData = newData(typeFace.filename, textSize);
                (*faceData)[textSize] = sizeData;
                return sizeData;
            }
        }
        else
        {
            shared(Data[float]) faceData;
            auto sizeData = newData(typeFace.filename, textSize);
            faceData[textSize] = sizeData;
            data[typeFace.filename] = faceData;
            return sizeData;
        }
    }

    // @trusted: FT_Set_Char_Size writes through the raw face handle the
    // store owns; the cast(shared) tags the handle for storage.
    shared(Data) newData(string path, float textSize) @trusted
    {
        shared(Data) d;
        d.glyphs[0] = Glyph(); // HACK needed to force creation of internal AA
        d.face = cast(shared)freeType.newFace(path);
        enforce(!FT_Set_Char_Size(cast(FT_Face)d.face, 0, to!FT_F26Dot6(textSize*64), 72, 72));
        d.mtx = cast(shared)new ReadWriteMutex();
        return d;
    }

    struct Data
    {
        Glyph[dchar] glyphs;
        FT_Face face;
        ReadWriteMutex mtx;
    }

    private Data[float][string] data;
}

// @safe: the fontconfig entry points (valid/defaultFace) and the
// store's getData carry their own tags/islands now, so nothing here
// needs to see @system.
@safe GlyphCache getGlyphCache(TypeFace typeFace, float textSize)
{
    if (!typeFace.valid())
        typeFace = TypeFace.defaultFace();
    assert(typeFace.valid());
    return GlyphCache(glyphStore.getData(typeFace, textSize));
}

struct GlyphCache
{
    shared(GlyphStore.Data) data;

    // @trusted: &this hands the stream a borrowed pointer to the
    // enclosing cache - the caller keeps the stream no longer than
    // the cache it came from (the measureText/render callers hold
    // both), and &this of a member is the @system part.
    GlyphStream glyphStream(string text, Glyph.LoadFlag loadFlags) @trusted
    {
        return GlyphStream(text, loadFlags, &this);
    }

    // @trusted: reads FT_FaceRec fields through the store's raw
    // handle; the face is alive (owned by GlyphStore) and FT has
    // filled the size/bbox data since FT_Set_Char_Size.
    TextPaint.FontMetrics fontMetrics() @trusted
    {
        auto face = data.face;
        auto emScale = 1.0 / face.units_per_EM;
        auto xscale = face.size.metrics.x_ppem * emScale;
        auto yscale = face.size.metrics.y_ppem * emScale;

        TextPaint.FontMetrics result;
        result.top = yscale * face.bbox.yMax;
        result.ascent = yscale * face.ascender;
        result.descent = yscale * face.descender;
        result.bottom = yscale * face.bbox.yMin;
        result.leading = yscale * max(0, face.height - (face.ascender - face.descender));
        result.xmin = xscale * face.bbox.xMin;
        result.xmax = xscale * face.bbox.xMax;
        result.underlinePos = yscale * face.underline_position;
        result.underlineThickness = yscale * face.underline_thickness;

        return result;
    }
}

struct GlyphStream
{
    alias int delegate(const ref Glyph) GlyphDg;

    // @trusted: drops the shared wrapper to drive the store's RW
    // mutex; the lock discipline is this file's (reader walk with a
    // writer upgrade inside getGlyph).
    private auto mtxReader() @trusted
    {
        return (cast(ReadWriteMutex)cache.data.mtx).reader;
    }

    // Dg is a template parameter (defaulting to GlyphDg) so the slot
    // is attribute-generic, the policy of Path.apply. foreach keeps a
    // concrete alias for the same reason: a templated opApply breaks
    // the foreach rewrite's type inference.
    int apply(Dg = GlyphDg)(scope Dg dg)
    {
        if (text.length == 0)
            return 0;
        auto reader = mtxReader();
        reader.lock();
        scope(exit) { reader.unlock(); }

        size_t i;
        while (i < text.length)
        {
            immutable c = decode(text, i);
            auto gl = getGlyph(c, reader);
            if (auto res = dg(gl))
                return res;
        }
        return 0;
    }

    alias apply!() opApply;

    // @trusted: reads through the borrowed cache pointer (raw AA
    // lookups whose element addresses the writer dance re-validates),
    // drives the shared mutex's upgrade, and calls FT_Get_Char_Index
    // and the @system updateGlyph specializations through the face
    // handle the store owns.
    Glyph getGlyph(dchar c, ref ReadWriteMutex.Reader reader) @trusted
    {
        auto cached = cast(Glyph*)(c in cache.data.glyphs);

        if (cached is null || (cached.loaded & loadFlags) != 0)
        {
            reader.unlock();
            auto writer = (cast(ReadWriteMutex)cache.data.mtx).writer;
            writer.lock();
            scope(exit) { writer.unlock(); reader.lock(); }

            if (cached is null)
            {
                cache.data.glyphs[c] = Glyph();
                cached = cast(Glyph*)(c in cache.data.glyphs);
            }

            auto charIdx = FT_Get_Char_Index(cast(FT_Face)cache.data.face, c);
            foreach(e; EnumMembers!(Glyph.LoadFlag))
            {
                if ((loadFlags & e) && !(cached.loaded & e))
                    updateGlyph!(e)(cast(FT_Face)cache.data.face, cached, charIdx);
            }
        }
        return *cached;
    }

    string text;
    Glyph.LoadFlag loadFlags;
    private GlyphCache* cache;
}

private:

void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.NoFlag)(FT_Face face, Glyph* glyph, FT_UInt charIdx)
{
}

// @system: FT_Load_Glyph + face.glyph reads through the raw handle.
void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.Metrics)(FT_Face face, Glyph* glyph, FT_UInt charIdx) @system
{
    enforce(!FT_Load_Glyph(face, charIdx, FT_LOAD.NO_BITMAP));

    glyph.advance = ScaleFT_Vector(face.glyph.advance);
    glyph.lsbDelta = face.glyph.lsb_delta * Scale26D6;
    glyph.rsbDelta = face.glyph.rsb_delta * Scale26D6;
    glyph.size = FSize(face.glyph.metrics.width * Scale26D6, face.glyph.metrics.height * Scale26D6);
    glyph.loaded |= Glyph.LoadFlag.Metrics;
}

// @system: FT_Load_Glyph + FT_Outline_Decompose through the raw
// handle; the callbacks it invokes are the @system extern(C) block.
void updateGlyph(Glyph.LoadFlag f : Glyph.LoadFlag.Path)(FT_Face face, Glyph* glyph, FT_UInt charIdx) @system
{
    enforce(!FT_Load_Glyph(face, charIdx, FT_LOAD.NO_BITMAP));

    assert(glyph.path.empty);
    enforce(!FT_Outline_Decompose(&face.glyph.outline, &outlineCallbacks, &glyph.path));
    glyph.path.close();

    glyph.loaded |= Glyph.LoadFlag.Path;
}

/*
 * Callback for transforming freetype outlines to paths.
 */
immutable outlineCallbacks =
{
    FT_Outline_Funcs funcs;

    funcs.move_to = &moveTo;
    funcs.line_to = &lineTo;
    funcs.conic_to = &quadTo;
    funcs.cubic_to = &cubicTo;
    funcs.shift = 0;
    funcs.delta = 0;
    return funcs;
}();

@system FPoint ConvFT_Vector(const FT_Vector* v)
{
    auto fp = ScaleFT_Vector(*v);
    fp.y = -fp.y;
    return fp;
}

// The outline callbacks run under FT_Outline_Decompose's C signature:
// they receive raw pointers (the FT vectors and the void* user data
// this file smuggles a Path* through) and must stay @system.
extern(C):
@system:

int moveTo(const FT_Vector* to, void* user)
{
    auto path = cast(Path*)user;
    path.close();
    path.moveTo(ConvFT_Vector(to));
    return 0;
}

int lineTo(const FT_Vector* to, void* user)
{
    auto path = cast(Path*)user;
    path.lineTo(ConvFT_Vector(to));
    return 0;
}

int quadTo(const FT_Vector* c1, const FT_Vector* to, void* user)
{
    auto path = cast(Path*)user;
    path.quadTo(ConvFT_Vector(c1), ConvFT_Vector(to));
    return 0;
}

int cubicTo(const FT_Vector* c1, const FT_Vector* c2,
             const FT_Vector* to, void* user)
{
    auto path = cast(Path*)user;
    path.cubicTo(ConvFT_Vector(c1), ConvFT_Vector(c2), ConvFT_Vector(to));
    return 0;
}
