module psxexe;

import std.bitmanip : littleEndianToNative;
import std.exception : enforce;

enum PSX_EXE_MAGIC = "PS-X EXE";
enum PSX_EXE_HEADER_SIZE = 0x800;

class PsxExe
{
    uint pc;          // initial PC (entry point)
    uint gp;          // initial GP
    uint loadAddr;    // destination address of the text segment
    uint textSize;    // size of the code/data payload in bytes
    uint dataAddr, dataSize;   // usually unused
    uint bssAddr, bssSize;     // usually unused
    uint spBase, spOffset;     // initial SP = spBase + spOffset (0 means "leave as is")
    string region;             // marker string, e.g. "Sony Computer Entertainment Inc. for Europe area"
    uint[] code;               // payload, 4-byte aligned words

    this(const(ubyte)[] binary)
    {
        enforce(binary.length >= PSX_EXE_HEADER_SIZE, "File too small for a PSX-EXE header");
        enforce(cast(const(char)[])binary[0 .. 8] == PSX_EXE_MAGIC, "Missing PS-X EXE magic");

        uint rd(size_t off)
        {
            ubyte[4] b = binary[off .. off + 4];
            return littleEndianToNative!uint(b);
        }

        pc       = rd(0x10);
        gp       = rd(0x14);
        loadAddr = rd(0x18);
        textSize = rd(0x1C);
        dataAddr = rd(0x20);
        dataSize = rd(0x24);
        bssAddr  = rd(0x28);
        bssSize  = rd(0x2C);
        spBase   = rd(0x30);
        spOffset = rd(0x34);

        // Region/marker string at 0x4C, NUL-terminated
        size_t end = 0x4C;
        while (end < PSX_EXE_HEADER_SIZE && binary[end] != 0)
            end++;
        region = cast(string)binary[0x4C .. end].idup;

        // Some tools write a wrong size, so clamp it to what is really in the file
        size_t avail = binary.length - PSX_EXE_HEADER_SIZE;
        size_t n = textSize < avail ? textSize : avail;
        n &= ~cast(size_t)3; // whole words only

        // Copy into a real uint[] to avoid alignment issues from casting a ubyte[]
        code = new uint[n / 4];
        (cast(ubyte[])code)[] = binary[PSX_EXE_HEADER_SIZE .. PSX_EXE_HEADER_SIZE + n];
    }
    
    const(uint)[] trimmedCode() const
    {
        size_t n = code.length;
        while (n > 0 && code[n - 1] == 0)
            n--;
        if (n < code.length)
            n++;

        // Never cut off the entry point
        size_t entry = (pc - loadAddr) / 4 + 1;
        if (pc >= loadAddr && entry > n && entry <= code.length)
            n = entry;

        return code[0 .. n];
    }
}
