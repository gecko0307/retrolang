module r5g5b5a1;

import rgba8;

/// 8-bit channel -> 5-bit channel, with rounding
uint to5(ubyte v)
{
    return (cast(uint)v * 31 + 127) / 255;
}

/**
 * PS1 15-bit color: bits 0-4 R, 5-9 G, 10-14 B, bit 15 = STP.
 * Pixels with alpha < alphaThreshold become 0x0000 (transparent on PS1).
 * Opaque pixels that would end up as 0x0000 (pure black) get the STP bit
 * set (0x8000) so they stay opaque.
 */
ushort rgba8ToR5G5B5A1(ubyte r, ubyte g, ubyte b, ubyte a, ubyte alphaThreshold = 128)
{
    if (a < alphaThreshold)
        return 0x0000;

    ushort c = cast(ushort)(to5(r) | (to5(g) << 5) | (to5(b) << 10));
    return c == 0 ? cast(ushort)0x8000 : c;
}

/// Converts a whole RGBA8 buffer to 15-bit direct color
ushort[] convertToDirect15(ref const RGBA8TextureBuffer src, ubyte alphaThreshold = 128)
{
    immutable size_t count = cast(size_t)src.width * src.height;
    auto result = new ushort[count];
    foreach (i; 0..count)
    {
        const(ubyte)[] p = src.data[i * 4..i * 4 + 4];
        result[i] = rgba8ToR5G5B5A1(p[0], p[1], p[2], p[3], alphaThreshold);
    }
    return result;
}
