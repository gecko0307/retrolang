/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the software
to the public domain. We make this dedication for the benefit of the
public at large and to the detriment of our heirs and successors.
We intend this dedication to be an overt act of relinquishment in 
perpetuity of all present and future rights to this software under
copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
*/

/*
 * VAB sound bank loader.
 *
 * A VAB (instrument bank file) is split into a header part (VH) and a
 * body part (VB) with raw SPU-ADPCM samples. They can live in two files
 * (*.vh + *.vb) or in a single *.vab file.
 *
 * Header layout (little-endian):
 *   0x000  32 bytes     VabHdr, magic "pBAV"
 *   0x020  128 * 16     ProgAtr, one per program (0..127)
 *   0x820  n * 0x200    tone block (16 * 32-byte VagAtr) for every program
 *                       that has at least one tone, in program order
 *   after  256 * 2      sample sizes in 8-byte units, indexed by VAG number
 *
 * The header stays in RAM and is parsed on demand, only the samples are
 * copied to SPU RAM. Up to VAB_MAX_BANKS banks can be loaded at once.
 *
 * VagAtr (tone) fields used by the sequencer:
 *   +0x02 vol, +0x03 pan, +0x04 center key, +0x05 fine tune (1/128 semitone),
 *   +0x06 min key, +0x07 max key, +0x0C pitch bend down, +0x0D pitch bend up
 *   (semitones), +0x10 ADSR1, +0x12 ADSR2 (raw SPU register values),
 *   +0x16 VAG number.
 */

#define VAB_MAX_BANKS 4
#define VAB_MAX_VAGS 256

#if import

#import "spu.r"

// Header (VH) of every loaded bank, kept in RAM
uchar* vabHeader[VAB_MAX_BANKS];

// For each bank and program: pointer to its tone block, 0 if it has no tones
uchar* vabToneBlock[VAB_MAX_BANKS * 128];

// For each bank and VAG number: byte address of the sample in SPU RAM
uint vabVagAddr[VAB_MAX_BANKS * VAB_MAX_VAGS];

int vabCount;

// Reads a little-endian 16-bit value (no alignment requirements)
uint vabU16(uchar* p)
{
    return p[0] | (p[1] << 8);
}

// Reads a little-endian 32-bit value (no alignment requirements)
uint vabU32(uchar* p)
{
    return p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
}

/**
 * Loads a sound bank and uploads its samples to SPU RAM.
 *
 * vh - header data (*.vh), 4-byte aligned
 * vb - sample data (*.vb), 4-byte aligned, or 0 if vh is a complete *.vab
 *      file (samples follow the header)
 *
 * Returns the bank id (0..VAB_MAX_BANKS-1) or -1 on failure (bad data,
 * too many banks, out of SPU RAM). Call spuInit first.
 */
int vabLoad(uchar* vh, uchar* vb)
{
    if (vabCount >= VAB_MAX_BANKS) return -1;
    if (vh[0] != 'p' || vh[1] != 'B' || vh[2] != 'A' || vh[3] != 'V') return -1;

    int bank = vabCount;

    // Programs without tones have no tone block
    int blocks = 0;
    for (int p = 0; p < 128; p++)
    {
        if (vh[0x20 + p * 16] > 0)
        {
            vabToneBlock[bank * 128 + p] = vh + 0x820 + blocks * 0x200;
            blocks++;
        }
        else
        {
            vabToneBlock[bank * 128 + p] = 0;
        }
    }

    uchar* sizes = vh + 0x820 + blocks * 0x200;

    if (vb == 0)
        vb = sizes + 0x200;

    // The body is the concatenation of all samples
    uint total = 0;
    for (int i = 0; i < VAB_MAX_VAGS; i++)
        total += vabU16(sizes + i * 2) * 8;

    if (total == 0) return -1;

    uint base = spuAlloc(total);
    if (base == 0) return -1;

    spuUploadADPCM(vb, total, base);

    uint offset = 0;
    for (int i = 0; i < VAB_MAX_VAGS; i++)
    {
        vabVagAddr[bank * VAB_MAX_VAGS + i] = base + offset;
        offset += vabU16(sizes + i * 2) * 8;
    }

    vabHeader[bank] = vh;
    vabCount++;
    return bank;
}

// Unloads all banks and frees SPU RAM (including sounds loaded with spuLoad*)
void vabFreeAll()
{
    spuFreeAll();
    vabCount = 0;
}

// Number of tones of a program, 0 if the program does not exist
int vabToneCount(int bank, int program)
{
    if (bank < 0 || bank >= vabCount) return 0;
    if (program < 0 || program > 127) return 0;
    if (vabToneBlock[bank * 128 + program] == 0) return 0;
    int n = vabHeader[bank][0x20 + program * 16];
    if (n > 16) n = 16;
    return n;
}

// Pointer to a 32-byte tone (VagAtr) record, 0 if there is none
uchar* vabTone(int bank, int program, int index)
{
    if (index < 0 || index >= vabToneCount(bank, program)) return 0;
    return vabToneBlock[bank * 128 + program] + index * 32;
}

// Pointer to a 16-byte program (ProgAtr) record
uchar* vabProgram(int bank, int program)
{
    return vabHeader[bank] + 0x20 + program * 16;
}

// VAB master volume (0..127)
int vabMasterVolume(int bank)
{
    return vabHeader[bank][0x18];
}

// Byte address of a sample in SPU RAM
uint vabSampleAddr(int bank, int vag)
{
    return vabVagAddr[bank * VAB_MAX_VAGS + (vag & 0xFF)];
}

#endif
