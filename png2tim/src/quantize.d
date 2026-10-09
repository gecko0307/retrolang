module quantize;

import std.algorithm: sort, min, max;
import rgba8;
import r5g5b5a1;

struct IndexedImage
{
    uint width;
    uint height;
    ubyte[] pixels;   // one index per byte
    ushort[] palette; // PS1 15-bit colors, padded to maxColors entries
}

struct ColorBin
{
    ubyte r, g, b; // 5-bit values
    uint count;
}

struct Box
{
    size_t start, end; // range in the bin array
}

int chan(const ColorBin c, int ch)
{
    return ch == 0 ? c.r : (ch == 1 ? c.g : c.b);
}

ushort binToPS1(const ColorBin c)
{
    ushort v = cast(ushort)(c.r | (c.g << 5) | (c.b << 10));
    return v == 0 ? cast(ushort)0x8000 : v;
}

Box[] medianCut(ColorBin[] bins, size_t target)
{
    Box[] boxes = [Box(0, bins.length)];

    while (boxes.length < target)
    {
        // Pick the splittable box with the widest channel extent
        int bestBox = -1;
        int bestRange = 0;
        int bestChan = 0;

        foreach (i, bx; boxes)
        {
            if (bx.end - bx.start < 2)
                continue;

            int[3] lo = 31;
            int[3] hi = 0;
            
            foreach (ref c; bins[bx.start..bx.end])
            {
                foreach (ch; 0..3)
                {
                    int v = chan(c, ch);
                    lo[ch] = min(lo[ch], v);
                    hi[ch] = max(hi[ch], v);
                }
            }

            foreach (ch; 0..3)
            {
                int range = hi[ch] - lo[ch];
                if (range > bestRange)
                {
                    bestRange = range;
                    bestBox = cast(int)i;
                    bestChan = ch;
                }
            }
        }

        if (bestBox < 0)
            break; // nothing left to split

        Box bx = boxes[bestBox];
        auto slice = bins[bx.start .. bx.end];
        int sortChan = bestChan;
        slice.sort!((a, b) => chan(a, sortChan) < chan(b, sortChan));

        // Split at the weighted median
        ulong total = 0;
        foreach (ref c; slice)
            total += c.count;

        ulong acc = 0;
        size_t splitAt = 1;
        foreach (i, ref c; slice)
        {
            acc += c.count;
            if (acc * 2 >= total)
            {
                splitAt = i + 1;
                break;
            }
        }
        splitAt = max(1, min(splitAt, slice.length - 1));

        boxes[bestBox] = Box(bx.start, bx.start + splitAt);
        boxes ~= Box(bx.start + splitAt, bx.end);
    }

    return boxes;
}

/**
 * Quantizes an RGBA8 image to an indexed image with at most maxColors
 * palette entries (16 or 256). If the image has transparent pixels,
 * palette index 0 is reserved for them (color 0x0000).
 */
IndexedImage quantizeToIndexed(
    ref const RGBA8TextureBuffer src,
    uint maxColors,
    ubyte alphaThreshold = 128)
{
    enum uint NBINS = 32768;
    immutable size_t npix = cast(size_t)src.width * src.height;

    auto counts = new uint[NBINS];
    bool hasTransparent = false;

    foreach (i; 0..npix)
    {
        const(ubyte)[] p = src.data[i * 4..i * 4 + 4];
        
        if (p[3] < alphaThreshold)
        {
            hasTransparent = true;
            continue;
        }
        
        counts[to5(p[0]) | (to5(p[1]) << 5) | (to5(p[2]) << 10)]++;
    }

    ColorBin[] bins;
    foreach (k; 0..NBINS)
    {
        if (counts[k] != 0)
        {
            bins ~= ColorBin(cast(ubyte)(k & 31),
                             cast(ubyte)((k >> 5) & 31),
                             cast(ubyte)((k >> 10) & 31),
                             counts[k]);
        }
    }

    immutable(uint) firstIndex = hasTransparent ? 1 : 0;
    immutable(size_t) opaqueSlots = maxColors - firstIndex;

    ushort[] palette;
    
    if (hasTransparent)
        palette ~= 0x0000;

    if (bins.length <= opaqueSlots)
    {
        // Few enough colors: lossless
        foreach (ref c; bins)
            palette ~= binToPS1(c);
    }
    else
    {
        foreach (bx; medianCut(bins, opaqueSlots))
        {
            ulong total = 0, sr = 0, sg = 0, sb = 0;
            foreach (ref c; bins[bx.start..bx.end])
            {
                total += c.count;
                sr += cast(ulong)c.r * c.count;
                sg += cast(ulong)c.g * c.count;
                sb += cast(ulong)c.b * c.count;
            }
            ColorBin avg;
            avg.r = cast(ubyte)((sr + total / 2) / total);
            avg.g = cast(ubyte)((sg + total / 2) / total);
            avg.b = cast(ubyte)((sb + total / 2) / total);
            palette ~= binToPS1(avg);
        }
    }

    // Map every used 555 color to its nearest palette entry
    auto lut = new int[NBINS];
    lut[] = -1;
    
    foreach (ref c; bins)
    {
        int bestIdx = cast(int)firstIndex;
        int bestDist = int.max;
        
        foreach (i; firstIndex..palette.length)
        {
            ushort pc = palette[i] & 0x7FFF;
            int dr = c.r - (pc & 31);
            int dg = c.g - ((pc >> 5) & 31);
            int db = c.b - ((pc >> 10) & 31);
            int d = dr * dr + dg * dg + db * db;
            if (d < bestDist)
            {
                bestDist = d;
                bestIdx = cast(int)i;
                if (d == 0)
                    break;
            }
        }
        
        lut[c.r | (c.g << 5) | (c.b << 10)] = bestIdx;
    }

    IndexedImage result;
    result.width = src.width;
    result.height = src.height;
    result.pixels = new ubyte[npix];
    foreach (i; 0..npix)
    {
        const(ubyte)[] p = src.data[i * 4..i * 4 + 4];
        if (p[3] < alphaThreshold)
            result.pixels[i] = 0;
        else
            result.pixels[i] = cast(ubyte)lut[to5(p[0]) | (to5(p[1]) << 5) | (to5(p[2]) << 10)];
    }

    palette.length = maxColors; // pad with 0x0000
    result.palette = palette;
    return result;
}

/// Widens the image to a multiple of `multiple` pixels (new pixels use index 0)
void padWidth(ref IndexedImage img, uint multiple)
{
    uint newW = (img.width + multiple - 1) / multiple * multiple;
    if (newW == img.width)
        return;

    auto padded = new ubyte[cast(size_t)newW * img.height]; // zero-filled
    foreach (y; 0..img.height)
        padded[y * newW..y * newW + img.width] = img.pixels[y * img.width..(y + 1) * img.width];

    img.pixels = padded;
    img.width = newW;
}

/// 8-bit indexed: already one byte per pixel
ubyte[] packIndexed8(ref const IndexedImage img)
{
    return img.pixels.dup;
}

/**
 * 4-bit indexed: two pixels per byte, leftmost pixel in the low nibble.
 * img.width must be even.
 */
ubyte[] packIndexed4(ref const IndexedImage img)
{
    auto result = new ubyte[cast(size_t)img.width / 2 * img.height];
    size_t o = 0;
    foreach (y; 0..img.height)
    {
        foreach (x; 0..img.width / 2)
        {
            ubyte lo = img.pixels[y * img.width + x * 2] & 0x0F;
            ubyte hi = img.pixels[y * img.width + x * 2 + 1] & 0x0F;
            result[o++] = cast(ubyte)(lo | (hi << 4));
        }
    }
    return result;
}
