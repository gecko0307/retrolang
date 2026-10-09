module tim;

import std.stdio;

enum ubyte TIM_TAG = 0x10;

// Bits of TIMHeader.flags
enum uint TIM_PMODE_4BPP  = 0;
enum uint TIM_PMODE_8BPP  = 1;
enum uint TIM_PMODE_16BPP = 2;
enum uint TIM_FLAG_CLUT   = 1 << 3;

struct TIMHeader
{
   align(1):
    ubyte tag = TIM_TAG;
    ubyte ver = 0;
    ushort _padding = 0;
    uint flags;
}

struct CLUTHeader
{
   align(1):
    uint length; // header (12) + data, in bytes
    ushort cx;
    ushort cy;
    ushort cw;   // colors per palette (16 or 256)
    ushort ch;   // number of palettes
}

struct IMGHeader
{
   align(1):
    uint length; // header (12) + data, in bytes
    ushort px;
    ushort py;
    ushort pw;   // width in 16-bit VRAM words (NOT pixels, except for 16bpp)
    ushort ph;   // height in pixels
}

static assert(TIMHeader.sizeof == 8);
static assert(CLUTHeader.sizeof == 12);
static assert(IMGHeader.sizeof == 12);

void writeStruct(T)(File f, ref const T s)
{
    f.rawWrite((cast(const(ubyte)*)&s)[0 .. T.sizeof]);
}

/**
 * bpp = 4, 8 or 16. clut may be empty for 16bpp.
 * pixelWords = image width in 16-bit VRAM words.
 */
void writeTIM(
    string path,
    uint bpp,
    const(ushort)[] clut,
    const(ubyte)[] imageData,
    uint pixelWords,
    uint height,
    ushort imgX,
    ushort imgY,
    ushort clutX,
    ushort clutY)
{
    TIMHeader hdr;
    switch (bpp)
    {
        case 4:  hdr.flags = TIM_PMODE_4BPP  | TIM_FLAG_CLUT; break;
        case 8:  hdr.flags = TIM_PMODE_8BPP  | TIM_FLAG_CLUT; break;
        default: hdr.flags = TIM_PMODE_16BPP; break;
    }

    auto f = File(path, "wb");
    scope(exit) f.close();

    writeStruct(f, hdr);

    if (hdr.flags & TIM_FLAG_CLUT)
    {
        CLUTHeader ch;
        ch.length = cast(uint)(CLUTHeader.sizeof + clut.length * 2);
        ch.cx = clutX;
        ch.cy = clutY;
        ch.cw = cast(ushort)clut.length;
        ch.ch = 1;
        writeStruct(f, ch);
        f.rawWrite(cast(const(ubyte)[])clut);
    }

    IMGHeader ih;
    ih.length = cast(uint)(IMGHeader.sizeof + imageData.length);
    ih.px = imgX;
    ih.py = imgY;
    ih.pw = cast(ushort)pixelWords;
    ih.ph = cast(ushort)height;
    writeStruct(f, ih);
    f.rawWrite(imageData);
}
