module main;

import std.exception, std.file, std.getopt, std.path;
import graphics.svg;

// Usage: svg-test-application [-z|--zoom <factor>] <file.svg> ...
// -z/--zoom scales the canvas (and thus the rendering) uniformly.
void main(string[] args)
{
    float zoom = 1.0f;
    auto rslt = getopt(args, "zoom|z", "scale the canvas (default: 1)", &zoom);
    if (rslt.helpWanted)
        defaultGetoptPrinter("Render SVG files to PNG files.", rslt.options);
    enforce(zoom > 0, "zoom factor must be positive");
    foreach (file; args[1 .. $])
        renderSVG(cast(string) read(file), zoom, file.dirName ~ "/", file)
            .save(file.setExtension("png"));
}
