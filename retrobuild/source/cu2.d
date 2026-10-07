/**
 * CUE sheet to CU2 conversion (PSIO).
 *
 * It is a port of cue2cu2.py by NRGDEAD (https://github.com/NRGDEAD/Cue2cu2),
 * Copyright 2019-2020 NRGDEAD, licensed under the Apache License 2.0
 * (http://www.apache.org/licenses/LICENSE-2.0).
 * Only the script's default behavior is implemented (compatibility mode,
 * CU2 format revision 2, no offsets): the output is byte-identical to
 * `cue2cu2.py <sheet>` for the same input.
 */
module cu2;

import std.algorithm: min;
import std.array: split;
import std.conv: ConvException, to;
import std.file: exists, getSize, readText;
import std.format: format;
import std.path: buildPath, dirName;
import std.string: indexOf, splitLines, strip, stripLeft, toLower;
import std.algorithm: canFind;
import std.uni: icmp;

private enum sectorSize = 2352; // MODE2/2352
private enum framesPerSec = 75;
private enum maxSectors = 449_999; // 99:59:74, the largest representable position
private enum psioOffset = 150; // the "famous two seconds" PSIO expects

/// Error in the CUE sheet, the binary image, or the requested conversion.
class Cu2Exception : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow
    {
        super(msg, file, line);
    }
}

struct Cu2Result
{
    string text;       // contents of the CU2 file
    string[] warnings; // non-fatal problems the caller should report
}

/// Reads a CUE sheet and the BIN it references (resolved relative to the
/// CUE sheet's directory) and converts them.
Cu2Result convertCueFile(string cuePath)
{
    string content;
    try
        content = readText(cuePath);
    catch (Exception e)
        throw new Cu2Exception("Could not read " ~ cuePath ~ ": " ~ e.msg);

    auto lines = content.splitLines();
    auto binName = binaryFileName(lines);
    auto binPath = buildPath(dirName(cuePath), binName);
    if (!exists(binPath))
        throw new Cu2Exception("Cue sheet refers to a binary file, " ~ binName ~ ", that could not be found");

    return convertCue(lines, getSize(binPath));
}

/// Returns the name of the binary file the sheet refers to. Exactly one
/// FILE statement of type BINARY is supported.
string binaryFileName(const(string)[] lines)
{
    int count;
    string name, type;
    foreach (line; lines)
    {
        string l = line;
        if (!isKeyword(l, "FILE"))
            continue;
        if (++count > 1)
            break;

        auto rest = l.stripLeft()[4 .. $].stripLeft();
        if (rest.length && rest[0] == '"')
        {
            auto end = rest[1 .. $].indexOf('"');
            if (end < 0)
                throw new Cu2Exception("Unterminated file name in FILE statement");
            name = rest[1 .. 1 + end];
            type = rest[2 + end .. $].strip();
        }
        else
        {
            auto parts = rest.split();
            if (parts.length != 2)
                throw new Cu2Exception("Could not parse FILE statement");
            name = parts[0];
            type = parts[1];
        }
    }
    if (count != 1)
        throw new Cu2Exception(
            "The cue sheet is either invalid or part of an image with multiple binary files, "
            ~ "which are not supported");
    if (icmp(type, "BINARY") != 0)
        throw new Cu2Exception("Could not find binary file");
    return name;
}

/// Converts CUE sheet lines for a binary image of `binSize` bytes.
Cu2Result convertCue(const(string)[] lines, ulong binSize)
{
    Cu2Result result;

    bool modeOk;
    foreach (line; lines)
        if ((cast(string) line).toLower().canFind("mode2/2352"))
        {
            modeOk = true;
            break;
        }
    if (!modeOk)
        throw new Cu2Exception("Cue sheet indicates this image is not in MODE2/2352");

    if (binSize % sectorSize != 0)
        throw new Cu2Exception(
            "The filesize of the binary file indicates that this is not a valid image in MODE2/2352");
    long sectors = binSize / sectorSize;
    if (sectors > maxSectors)
        throw new Cu2Exception("The image is too large for the CU2 format");

    int ntracks;
    foreach (line; lines)
        if (isKeyword(line, "TRACK"))
            ++ntracks;

    string text = format("ntracks %d\r\n", ntracks);
    text ~= "size      " ~ timecode(sectors) ~ "\r\n";
    text ~= "data1     " ~ timecode(psioOffset) ~ "\r\n";

    bool pregapCommandSeen;
    foreach (track; 2 .. ntracks + 1)
    {
        auto at = findTrackLine(lines, track);
        string next  = lineAt(lines, at + 1);
        string after = lineAt(lines, at + 2);
        string num   = format("%02d", track);

        // Pregap. An INDEX 01 right after TRACK (no INDEX 00) yields a
        // pregap equal to the track start, exactly as cue2cu2.py does.
        int n = indexNumber(next);
        if (n == 0 || n == 1)
        {
            text ~= "pregap" ~ num ~ "  " ~ psioPosition(linePosition(next, track)) ~ "\r\n";
        }
        else if (isKeyword(next, "PREGAP"))
        {
            result.warnings ~= pregapCommandSeen
                ? format("The PREGAP command is also used for track %d", track)
                : format("The PREGAP command is used for track %d, which requires inserting data "
                    ~ "into the image. This is not supported, so the resulting bin/CU2 set might "
                    ~ "not work as expected. If possible, try a Redump-compatible version of this image",
                    track);
            pregapCommandSeen = true;
            if (indexNumber(after) == 1)
                text ~= "pregap" ~ num ~ "  " ~ psioPosition(linePosition(after, track)) ~ "\r\n";
        }
        else
            throw new Cu2Exception(format("Could not find pregap position (index 00) for track %d", track));

        // Track start (INDEX 01), on the line after TRACK or the one after that.
        long start;
        if (indexNumber(next) == 1)
            start = linePosition(next, track);
        else if (indexNumber(after) == 1)
            start = linePosition(after, track);
        else
            throw new Cu2Exception(format("Could not find starting position (index 01) for track %d", track));
        text ~= "track" ~ num ~ "   " ~ psioPosition(start) ~ "\r\n";
    }

    text ~= "\r\ntrk end   " ~ altTimecode(min(sectors + psioOffset, cast(long) maxSectors));

    result.text = text;
    return result;
}

// --- helpers ----------------------------------------------------------------

/// MM:SS:FF
private string timecode(long sectors)
{
    long totalSeconds = sectors / framesPerSec;
    return format("%02d:%02d:%02d", totalSeconds / 60, totalSeconds % 60, sectors % framesPerSec);
}

/// MM:SS:FF, but a zero frame count is written as the previous second's
/// frame 75 (MM:SS-1:75), the notation Systems Console uses.
private string altTimecode(long sectors)
{
    long totalSeconds = sectors / framesPerSec;
    long frames  = sectors % framesPerSec;
    long minutes = totalSeconds / 60;
    long seconds = totalSeconds % 60;
    if (frames == 0)
    {
        frames = framesPerSec;
        if (seconds != 0)
            --seconds;
        else
        {
            seconds = 59;
            --minutes;
        }
    }
    return format("%02d:%02d:%02d", minutes, seconds, frames);
}

/// A CUE position as written to CU2: shifted by two seconds, clamped, alt notation.
private string psioPosition(long sectors)
{
    return altTimecode(min(sectors + psioOffset, cast(long) maxSectors));
}

private long parseTimecode(string tc, int track)
{
    auto p = tc.split(":");
    if (p.length == 3)
    {
        try
        {
            long m = p[0].to!long, s = p[1].to!long, f = p[2].to!long;
            if (m >= 0 && s >= 0 && s < 60 && f >= 0 && f < framesPerSec)
                return (m * 60 + s) * framesPerSec + f;
        }
        catch (ConvException) {}
    }
    throw new Cu2Exception(format("Invalid timecode \"%s\" for track %d", tc, track));
}

/// Position (last word) of an INDEX line, in sectors.
private long linePosition(string line, int track)
{
    auto t = line.split();
    return parseTimecode(t[$ - 1], track);
}

private string lineAt(const(string)[] lines, size_t i)
{
    return i < lines.length ? lines[i] : "";
}

private bool isKeyword(string line, string keyword)
{
    auto t = line.split();
    return t.length > 0 && icmp(t[0], keyword) == 0;
}

/// Index number of an "INDEX nn mm:ss:ff" line, or -1 for any other line.
private int indexNumber(string line)
{
    auto t = line.split();
    if (t.length >= 2 && icmp(t[0], "INDEX") == 0)
    {
        try
            return t[1].to!int;
        catch (ConvException) {}
    }
    return -1;
}

/// Line number of "TRACK <track> ...".
private size_t findTrackLine(const(string)[] lines, int track)
{
    foreach (i, line; lines)
    {
        auto t = (cast(string) line).split();
        if (t.length >= 2 && icmp(t[0], "TRACK") == 0)
        {
            try
            {
                if (t[1].to!int == track)
                    return i;
            }
            catch (ConvException) {}
        }
    }
    throw new Cu2Exception(format("Could not find track %d", track));
}

// --- tests ------------------------------------------------------------------
// Expected strings were produced by running the reference cue2cu2.py.

version (unittest)
{
    import std.exception : assertThrown;

    private enum sec = sectorSize;
    private immutable dataTrack = [`FILE "game.bin" BINARY`, "  TRACK 01 MODE2/2352", "    INDEX 01 00:00:00"];
}

unittest // single data track
{
    auto r = convertCue(dataTrack, 1000UL * sec);
    assert(r.text == "ntracks 1\r\nsize      00:13:25\r\ndata1     00:02:00\r\n\r\ntrk end   00:15:25");
    assert(r.warnings.length == 0);
}

unittest // zero frame count uses the MM:SS-1:75 notation
{
    auto r = convertCue(dataTrack, 1350UL * sec);
    assert(r.text == "ntracks 1\r\nsize      00:18:00\r\ndata1     00:02:00\r\n\r\ntrk end   00:19:75");
}

unittest // audio track with pregap (INDEX 00)
{
    auto lines = dataTrack ~ ["  TRACK 02 AUDIO", "    INDEX 00 00:10:00", "    INDEX 01 00:12:00"];
    auto r = convertCue(lines, 2000UL * sec);
    assert(r.text == "ntracks 2\r\nsize      00:26:50\r\ndata1     00:02:00\r\n"
        ~ "pregap02  00:11:75\r\ntrack02   00:13:75\r\n\r\ntrk end   00:28:50");
}

unittest // PREGAP command: warns, pregap line equals the track start
{
    auto lines = dataTrack ~ ["  TRACK 02 AUDIO", "    PREGAP 00:02:00", "    INDEX 01 00:12:00"];
    auto r = convertCue(lines, 2000UL * sec);
    assert(r.text == "ntracks 2\r\nsize      00:26:50\r\ndata1     00:02:00\r\n"
        ~ "pregap02  00:13:75\r\ntrack02   00:13:75\r\n\r\ntrk end   00:28:50");
    assert(r.warnings.length == 1);
}

unittest // INDEX 01 right after TRACK: pregap equals the track start
{
    auto lines = dataTrack ~ ["  TRACK 02 AUDIO", "    INDEX 01 00:12:00"];
    auto r = convertCue(lines, 2000UL * sec);
    assert(r.text == "ntracks 2\r\nsize      00:26:50\r\ndata1     00:02:00\r\n"
        ~ "pregap02  00:13:75\r\ntrack02   00:13:75\r\n\r\ntrk end   00:28:50");
}

unittest // errors
{
    assertThrown!Cu2Exception(convertCue(dataTrack, 100));                       // not a multiple of 2352
    assertThrown!Cu2Exception(convertCue(["FILE \"a.bin\" BINARY", "  TRACK 01 MODE1/2352"], 2352)); // wrong mode
    assertThrown!Cu2Exception(convertCue(dataTrack ~ ["  TRACK 02 AUDIO", "    REM nothing"], 2352)); // no index
}

unittest // FILE statement parsing
{
    assert(binaryFileName([`FILE "my game.bin" BINARY`]) == "my game.bin");
    assert(binaryFileName(["  file game.bin binary"]) == "game.bin");
    assertThrown!Cu2Exception(binaryFileName([`FILE "a.bin" BINARY`, `FILE "b.bin" BINARY`]));
    assertThrown!Cu2Exception(binaryFileName([`FILE "a.wav" WAVE`]));
    assertThrown!Cu2Exception(binaryFileName(["TRACK 01 MODE2/2352"]));
}
