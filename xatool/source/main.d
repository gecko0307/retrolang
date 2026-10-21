module main;

/*
Interleaves 2336-byte sector XA files (usually generated with psxavenc)
into one playable XA file.

Usage:
  psxavenc -t xa -f 37800 -b 4 -c 2 channel0.mp3 channel0.xa
  psxavenc -t xa -f 37800 -b 4 -c 2 channel1.mp3 channel1.xa
  xatool -o MUSIC.XA --file 1 channel0.xa channel1.xa

Each input becomes one XA channel (input 1 -> channel 0, input 2 -> channel 1, ...).
File and channel numbers in the subheaders are overwritten, so the values
psxavenc wrote don't matter. Slots without a stream get empty padding sectors
(audio, Form 2, tagged with channel 31, which nothing should filter on).
The last real sector of each stream gets the EOF/EOR flags.

Interleave span (sectors per cycle):
  8  = 37800 Hz stereo 4-bit (default)
  16 = 18900 Hz stereo, or 37800 Hz mono
  32 = 18900 Hz mono
*/

import std.stdio;
import std.file: read;
import std.path: extension;
import std.getopt: getopt;
import std.format: format;
import std.exception: enforce;
import std.string: toLower;

import wav;
import xa;

Stream loadStream(string path)
{
    switch (path.extension.toLower)
    {
        case ".wav":
            return wavToXa(path);

        case ".xa":
            return readSectors(path);

        default:
            throw new Exception(format(
                "%s: unsupported input format (expected WAV or XA)",
                path));
    }
}

int main(string[] args)
{
    string output;
    int fileNo = 1;
    int span = 8;

    try
    {
        getopt(args,
            "o|output", &output,
            "file", &fileNo,
            "span", &span
        );
    }
    catch (Exception e)
    {
        stderr.writeln(e.msg);
        return 1;
    }

    if (output.length == 0)
    {
        stderr.writeln("Usage: xainterleave -o OUTPUT [--file N] [--span N] INPUT...");
        return 1;
    }

    // getopt removes parsed options; remaining arguments are inputs.
    if (args.length < 2)
    {
        stderr.writeln("error: at least one input file is required");
        return 1;
    }

    if (fileNo < 0 || fileNo > 255)
    {
        stderr.writeln("error: --file must be in range 0..255");
        return 1;
    }

    if (span <= 0)
    {
        stderr.writeln("error: --span must be positive");
        return 1;
    }

    auto n = args.length - 1;

    if (n > span)
    {
        stderr.writeln(format(
            "error: %s streams do not fit an interleave span of %s",
            n, span));
        return 1;
    }

    if (n > FILLER_CHANNEL)
    {
        stderr.writeln(format(
            "error: at most %s streams are supported",
            FILLER_CHANNEL));
        return 1;
    }

    Stream[] streams;
    streams.reserve(n);

    try
    {
        foreach (path; args[1..$])
            streams ~= loadStream(path);
    }
    catch (Exception e)
    {
        stderr.writeln(e.msg);
        return 1;
    }

    // All streams must use the same XA coding mode.
    ubyte coding = streams[0].sector(0)[3];

    foreach (ref stream; streams)
    {
        ubyte otherCoding = stream.sector(0)[3];

        if (otherCoding != coding)
        {
            stderr.writeln(format(
                "%s: coding byte 0x%02X differs from 0x%02X "
                ~ "(mixed rates/modes)",
                stream.path, otherCoding, coding));
            return 1;
        }
    }

    // Rewrite the duplicated XA subheaders.
    foreach (ch, ref stream; streams)
    {
        auto last = stream.length - 1;

        foreach (i; 0..stream.length)
        {
            auto sec = stream.sector(i);

            foreach (off; [0, 4])
            {
                sec[off] = cast(ubyte)fileNo;
                sec[off + 1] = cast(ubyte)ch;

                if (i == last)
                    sec[off + 2] |= 0x81; // EOF | EOR
            }
        }
    }

    // Padding sector: audio, Form 2, real-time, channel 31.
    ubyte[SECTOR] pad;

    foreach (off; [0, 4])
    {
        pad[off] = cast(ubyte) fileNo;
        pad[off + 1] = FILLER_CHANNEL;
        pad[off + 2] = 0x64;
        pad[off + 3] = coding;
    }

    size_t cycles = 0;

    foreach (ref stream; streams)
        if (stream.length > cycles)
            cycles = stream.length;

    ulong total = cast(ulong) cycles * cast(ulong) span;

    try
    {
        auto outFile = File(output, "wb");

        foreach (c; 0..cycles)
        {
            foreach (slot; 0..cast(size_t) span)
            {
                if (slot < n && c < streams[slot].length)
                {
                    outFile.rawWrite(streams[slot].sector(c));
                }
                else
                {
                    outFile.rawWrite(pad[]);
                }
            }
        }

        outFile.close();
    }
    catch (Exception e)
    {
        stderr.writeln(e.msg);
        return 1;
    }

    writefln("wrote %s: %s sectors (%s bytes), %s stream(s), "
        ~ "file %s, channels 0-%s",
        output, total, total * SECTOR, n, fileNo, n - 1);

    writefln("loop length: %s frames @60fps, "
        ~ "%s frames @50fps (sectors*fps/150)",
        total * 60 / 150,
        total * 50 / 150);

    return 0;
}
