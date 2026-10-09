module main;

import std.stdio;
import std.algorithm: min, max;
import std.getopt;
import std.path: setExtension;
import dlib.core.memory;
import dlib.filesystem.local;
import rgba8;
import png;
import r5g5b5a1;
import tim;
import quantize;

version (LittleEndian) {}
else static assert(0, "png2tim assumes a little-endian host (TIM is little-endian)");

void printUsage()
{
    stderr.writeln("Usage: png2tim [options] input.png");
    stderr.writeln("  -b, --bpp <4|8|16>       output color depth (default 8)");
    stderr.writeln("  -o, --output <file>      output file (default: input with .tim)");
    stderr.writeln("  -t, --alpha <0-255>      alpha below this is transparent (default 128)");
    stderr.writeln("      --ix, --iy <n>       image position in VRAM (default 0,0)");
    stderr.writeln("      --cx, --cy <n>       CLUT position in VRAM (default 0,480)");
}

int main(string[] args)
{
    uint bpp = 8;
    string outputFilename;
    int alpha = 128;
    int imgX = 0, imgY = 0;
    int clutX = 0, clutY = 480;

    try
    {
        getopt(args,
            "bpp|b", &bpp,
            "output|o", &outputFilename,
            "alpha|t", &alpha,
            "ix", &imgX,
            "iy", &imgY,
            "cx", &clutX,
            "cy", &clutY);
    }
    catch (Exception e)
    {
        stderr.writeln(e.msg);
        printUsage();
        return 1;
    }

    if (args.length < 2)
    {
        printUsage();
        return 1;
    }

    if (bpp != 4 && bpp != 8 && bpp != 16)
    {
        stderr.writeln("Unsupported bit depth: ", bpp, ". Supported values are 4, 8 or 16");
        return 1;
    }

    // The GPU requires the CLUT X position to be a multiple of 16 halfwords
    // Anything else is silently rounded down at runtime.
    if (bpp != 16 && clutX % 16 != 0)
    {
        stderr.writefln("Invalid CLUT X position %s: must be a multiple of 16", clutX);
        return 1;
    }

    ubyte alphaThreshold = cast(ubyte)max(0, min(255, alpha));

    string inputFilename = args[1];
    if (outputFilename.length == 0)
        outputFilename = setExtension(inputFilename, "tim");

    auto istrm = openForInput(inputFilename);

    RGBA8TextureBuffer buffer;
    if (!loadPNG(istrm, &buffer))
    {
        stderr.writefln("Failed to load \"%s\"", inputFilename);
        return 1;
    }

    writefln("Loaded \"%s\" (%sx%s)", inputFilename, buffer.width, buffer.height);

    if (bpp == 16)
    {
        ushort[] direct = convertToDirect15(buffer, alphaThreshold);
        writeTIM(outputFilename, 16, null, cast(const(ubyte)[])direct,
                 buffer.width, buffer.height,
                 cast(ushort)imgX, cast(ushort)imgY, 0, 0);
    }
    else
    {
        IndexedImage img = quantizeToIndexed(buffer, bpp == 4 ? 16 : 256, alphaThreshold);

        uint multiple = bpp == 4 ? 4 : 2;
        if (img.width % multiple != 0)
        {
            writefln("Note: width padded from %s to a multiple of %s", img.width, multiple);
            padWidth(img, multiple);
        }

        ubyte[] data = bpp == 4 ? packIndexed4(img) : packIndexed8(img);
        uint pixelWords = img.width / multiple;

        writeTIM(outputFilename, bpp, img.palette, data,
                 pixelWords, img.height,
                 cast(ushort)imgX, cast(ushort)imgY,
                 cast(ushort)clutX, cast(ushort)clutY);
    }

    writefln("Wrote \"%s\" @ %s bpp", outputFilename, bpp);
    
    if (buffer.data.length)
        Delete(buffer.data);
    
    return 0;
}
