module main;

import std.exception, std.file, std.getopt, std.path, std.string;
import graphics.svg;

// Usage: svg-test-application [-z|--zoom <factor>] <file.svg>[#frag] ...
// -z/--zoom scales the canvas (and thus the rendering) uniformly. A '#'
// in a file argument is an SVG fragment identifier (SVG 1.1 §17.3.2):
// #view-id, #svgView(...) or #xywh= picks the initial view into the
// document. It never reaches the file name, and the PNG is named for the
// file without it.
void main(string[] args)
{
    float zoom = 1.0f;
    auto rslt = getopt(args, "zoom|z", "scale the canvas (default: 1)", &zoom);
    if (rslt.helpWanted)
        defaultGetoptPrinter("Render SVG files to PNG files.", rslt.options);
    enforce(zoom > 0, "zoom factor must be positive");
    foreach (arg; args[1 .. $])
    {
        // §17.3.2: the fragment is addressing, not a path. Where '#' is a
        // legal filename character the first one still wins, because that
        // is what it means in an IRI.
        immutable cut = arg.indexOf('#');
        immutable file = cut < 0 ? arg : arg[0 .. cut];
        immutable view = cut < 0 ? "" : arg[cut + 1 .. $];
        renderSVG(cast(string) read(file), zoom, file.dirName ~ "/", file, view)
            .save(file.setExtension("png"));
    }
}
