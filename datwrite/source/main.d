/**
 * datwrite - generates a PlayStation license/system area patch (DAT file) for mkpsxiso.
 *
 * Output: 12 sectors x 2336 bytes = 28032 bytes (CD-ROM XA Mode 2 Form 1 sectors
 * without the 12-byte sync and 4-byte header).
 *
 *   sectors 0-3   : zero-filled
 *   sector  4     : null-terminated license text
 *   sectors 5-11  : TMD model shown by the BIOS on the boot splash screen
 *
 * EDC and ECC (P/Q parity) are computed for every sector.
 *
 * Usage:
 *   datwrite -o license.dat -t logo.tmd -r e
 *   datwrite -o license.dat -t logo.tmd -l "My custom license text"
 *   datwrite --verify license.dat
 */
module main;

import std.stdio;
import std.file: read, write;
import std.getopt;
import std.string: toStringz;
import core.stdc.string: memcpy;

enum SECTOR_RAW     = 2352;                 // full raw CD sector
enum SECTOR_DAT     = 2336;                 // sector as stored in the DAT (no sync/header)
enum RAW_PREFIX     = SECTOR_RAW - SECTOR_DAT; // 16 = sync(12) + header(4)
enum SECTOR_COUNT   = 12;
enum DAT_SIZE       = SECTOR_DAT * SECTOR_COUNT; // 28032
enum DATA_SIZE      = 2048;
enum LICENSE_SECTOR = 4;
enum MODEL_FIRST    = 5;
enum MODEL_SECTORS  = SECTOR_COUNT - MODEL_FIRST; // 7
enum MODEL_MAX      = MODEL_SECTORS * DATA_SIZE;  // 14336
enum TMD_ID         = 0x41;

// Offsets inside a raw 2352-byte sector
enum OFF_SUBHEADER = 16;
enum OFF_DATA      = 24;
enum OFF_EDC       = 2072; // 0x818
enum OFF_ECC_P     = 2076; // 0x81C
enum OFF_ECC_Q     = 2248; // 0x8C8
enum OFF_END       = 2352; // 0x930

align(1) struct DatSector
{
align(1):
    uint subheader1;
    uint subheader2;
    ubyte[2048] data;
    uint edc;
    ubyte[276] ecc;
}
static assert(DatSector.sizeof == SECTOR_DAT);

// Commonly used license strings (region presets).
// The BIOS does not validate this text on its own, so it can be arbitrary.
immutable string[char] licenseText;
shared static this()
{
    licenseText = [
        'j': "          Licensed  by          Sony Computer Entertainment Inc.",
        'a': "          Licensed  by          Sony Computer Entertainment Amer  ica ",
        'e': "          Licensed  by          Sony Computer Entertainment Euro  pe   ",
    ];
}

// EDC / ECC

struct Tables
{
    ubyte[256] f;   // GF(2^8) multiply by 2
    ubyte[256] b;   // inverse helper
    uint[256]  edc; // CRC-32 variant with polynomial 0xD8018001
}

Tables makeTables() pure nothrow @safe
{
    Tables t;
    foreach (uint i; 0 .. 256)
    {
        uint j = (i << 1) ^ ((i & 0x80) ? 0x11D : 0);
        t.f[i]      = cast(ubyte) j;
        t.b[i ^ j]  = cast(ubyte) i;

        uint e = i;
        foreach (k; 0 .. 8)
            e = (e >> 1) ^ ((e & 1) ? 0xD8018001 : 0);
        t.edc[i] = e;
    }
    return t;
}

immutable Tables T = makeTables();

uint edcCompute(const(ubyte)[] src) pure nothrow @safe
{
    uint edc = 0;
    foreach (b; src)
        edc = (edc >> 8) ^ T.edc[(edc ^ b) & 0xFF];
    return edc;
}

void eccBlock(const(ubyte)[] src, uint majorCount, uint minorCount,
              uint majorMult, uint minorInc, ubyte[] dest) pure nothrow @safe
{
    immutable uint size = majorCount * minorCount;
    foreach (major; 0 .. majorCount)
    {
        uint index = (major >> 1) * majorMult + (major & 1);
        ubyte a = 0, b = 0;
        foreach (minor; 0 .. minorCount)
        {
            immutable ubyte t = src[index];
            index += minorInc;
            if (index >= size)
                index -= size;
            a ^= t;
            b ^= t;
            a = T.f[a];
        }
        a = T.b[T.f[a] ^ b];
        dest[major]              = a;
        dest[major + majorCount] = a ^ b;
    }
}

void putLE32(ubyte[] d, uint v) pure nothrow @safe
{
    d[0] = cast(ubyte)  v;
    d[1] = cast(ubyte) (v >> 8);
    d[2] = cast(ubyte) (v >> 16);
    d[3] = cast(ubyte) (v >> 24);
}

uint getLE32(const(ubyte)[] d) pure nothrow @safe
{
    return d[0] | (d[1] << 8) | (d[2] << 16) | (cast(uint) d[3] << 24);
}

/// Fills EDC and ECC of a Mode 2 Form 1 sector in place.
/// Sync and header bytes (0..15) must be zero: for XA the address is excluded
/// from the ECC calculation, and the DAT does not store it anyway.
void finalizeSector(ref ubyte[SECTOR_RAW] raw) pure nothrow @safe
{
    putLE32(raw[OFF_EDC .. OFF_EDC + 4], edcCompute(raw[OFF_SUBHEADER .. OFF_EDC]));
    eccBlock(raw[12 .. $], 86, 24,  2,  86, raw[OFF_ECC_P .. OFF_ECC_Q]);
    eccBlock(raw[12 .. $], 52, 43, 86,  88, raw[OFF_ECC_Q .. OFF_END]);
}

// ---------------------------------------------------------------------------
// DAT building
// ---------------------------------------------------------------------------

uint makeSubheader(ubyte file, ubyte channel, ubyte submode, ubyte coding) pure nothrow @safe
{
    return file | (channel << 8) | (submode << 16) | (cast(uint) coding << 24);
}

DatSector buildSector(const(ubyte)[] payload, uint subheader) @trusted
{
    assert(payload.length <= DATA_SIZE);

    ubyte[SECTOR_RAW] raw; // zero-initialised
    putLE32(raw[OFF_SUBHEADER .. OFF_SUBHEADER + 4], subheader);
    putLE32(raw[OFF_SUBHEADER + 4 .. OFF_SUBHEADER + 8], subheader); // subheader is duplicated
    raw[OFF_DATA .. OFF_DATA + payload.length] = payload[];
    finalizeSector(raw);

    DatSector s;
    memcpy(&s, raw.ptr + RAW_PREFIX, SECTOR_DAT);
    return s;
}

int verifyDat(string path)
{
    auto data = cast(const(ubyte)[]) read(path);
    if (data.length != DAT_SIZE)
    {
        stderr.writefln("error: %s is %s bytes, expected %s", path, data.length, DAT_SIZE);
        return 1;
    }

    int bad = 0;
    foreach (n; 0 .. SECTOR_COUNT)
    {
        ubyte[SECTOR_RAW] raw;
        raw[RAW_PREFIX .. $] = data[n * SECTOR_DAT .. (n + 1) * SECTOR_DAT];

        ubyte[SECTOR_RAW] chk = raw;
        finalizeSector(chk);

        immutable edcOk = raw[OFF_EDC .. OFF_ECC_P] == chk[OFF_EDC .. OFF_ECC_P];
        immutable eccOk = raw[OFF_ECC_P .. OFF_END] == chk[OFF_ECC_P .. OFF_END];
        writefln("sector %2d: subheader %08X/%08X  EDC %s  ECC %s", n,
                 getLE32(raw[16 .. 20]), getLE32(raw[20 .. 24]),
                 edcOk ? "ok" : "BAD", eccOk ? "ok" : "BAD");
        if (!edcOk || !eccOk)
            bad++;
    }
    return bad ? 1 : 0;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

int main(string[] args)
{
    string output = "license.dat";
    string tmdPath;
    string text;
    string textFile;
    string region = "e";
    string verifyPath;
    uint submode = 0x08;

    GetoptResult help;
    try
    {
        help = getopt(args,
            "output|o",       "Output DAT file (default: license.dat)", &output,
            "tmd|t",          "TMD model for the boot splash (max 14336 bytes)", &tmdPath,
            "region|r",       "License text preset: j, a or e (default: e)", &region,
            "license-text|l", "Custom license text (overrides --region)", &text,
            "license-file|f", "Read license text from a file (overrides --region)", &textFile,
            "submode",        "Subheader submode byte (default: 8)", &submode,
            "verify|v",       "Verify EDC/ECC of an existing DAT file and exit", &verifyPath);
    }
    catch (Exception e)
    {
        stderr.writeln("error: ", e.msg);
        return 2;
    }

    if (help.helpWanted)
    {
        defaultGetoptPrinter("psxdat - PS1 license DAT generator for mkpsxiso", help.options);
        return 0;
    }

    try
    {
        if (verifyPath.length)
            return verifyDat(verifyPath);

        // License text
        const(ubyte)[] license;
        if (textFile.length)
            license = cast(const(ubyte)[]) read(textFile);
        else if (text.length)
            license = cast(const(ubyte)[]) text;
        else
        {
            if (region.length != 1 || region[0] !in licenseText)
            {
                stderr.writeln("error: region must be one of: j, a, e");
                return 2;
            }
            license = cast(const(ubyte)[]) licenseText[region[0]];
        }
        // Reserve space for the null terminator
        if (license.length >= DATA_SIZE)
        {
            stderr.writefln("error: license text is %s bytes, max is %s", license.length, DATA_SIZE - 1);
            return 1;
        }

        // TMD
        const(ubyte)[] tmd;
        if (tmdPath.length)
        {
            tmd = cast(const(ubyte)[]) read(tmdPath);
            if (tmd.length > MODEL_MAX)
            {
                stderr.writefln("error: TMD is %s bytes, only %s fit into sectors 5-11",
                                tmd.length, MODEL_MAX);
                return 1;
            }
            if (tmd.length < 4 || getLE32(tmd[0 .. 4]) != TMD_ID)
                stderr.writeln("warning: file does not start with a TMD header (ID 0x41)");
        }
        else
            stderr.writeln("warning: no TMD given, boot splash area will be empty");

        immutable uint sh = makeSubheader(0, 0, cast(ubyte) submode, 0);

        DatSector[SECTOR_COUNT] sectors;
        foreach (n; 0 .. SECTOR_COUNT)
        {
            const(ubyte)[] payload;
            ubyte[DATA_SIZE] tmp; // zero-padded payload

            if (n == LICENSE_SECTOR)
            {
                tmp[0 .. license.length] = license[];
                // tmp[license.length] is already 0 -> null terminator
                payload = tmp[];
            }
            else if (n >= MODEL_FIRST)
            {
                immutable size_t from = (n - MODEL_FIRST) * DATA_SIZE;
                if (from < tmd.length)
                {
                    immutable size_t to = from + DATA_SIZE < tmd.length ? from + DATA_SIZE : tmd.length;
                    tmp[0 .. to - from] = tmd[from .. to];
                }
                payload = tmp[];
            }
            else
                payload = tmp[];

            sectors[n] = buildSector(payload, sh);
        }

        auto f = File(output, "wb");
        f.rawWrite(sectors[]);
        f.close();

        writefln("%s: %s bytes written (%s sectors x %s)", output, DAT_SIZE, SECTOR_COUNT, SECTOR_DAT);
        return 0;
    }
    catch (Exception e)
    {
        stderr.writeln("error: ", e.msg);
        return 1;
    }
}
