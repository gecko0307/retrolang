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

/**
 * ISO9660 file lookup.
 *
 * Usage:
 *     int lba = isoFindFile("cdrom:\\STR\\VIDEO.STR;1");
 *     if (lba >= 0)
 *         strStart(lba); // isoFileSize has the size in bytes
 *
 * The path may start with "cdrom:", the separator is '\' or '/', the match is
 * case-insensitive and the ";1" version suffix is optional.
 *
 * The lookup leaves the drive in the plain data mode (single speed, 2048-byte
 * sectors, no XA), so call it before streaming. It polls the controller,
 * so it blocks for a moment (about one seek per directory level).
 */

#define ISO_CD_SETLOC       0x02
#define ISO_CD_READN        0x06
#define ISO_CD_PAUSE        0x09
#define ISO_CD_SETMODE      0x0e

#define ISO_DMA3_ENABLE     0x00008000
#define ISO_DMA3_START      0x11000000 // CD-ROM -> RAM, sync mode 0, start + trigger

#define ISO_SECTOR_WORDS    512
#define ISO_WAIT_LIMIT      400000

#define ISO_PVD_LBA         16
#define ISO_MAX_DIR_SECTORS 64        // sanity limit for a directory

#if import

#import "core.r"
#import "bios.r"
#import "dma.r"
#import "cd.r"

// One sector of the file system (2048 bytes)
uint isoSector[ISO_SECTOR_WORDS];

// Results and diagnostics
int isoFileSize = 0;      // size in bytes of the file found by the last isoFindFile
int isoTrace = 1;         // 1 = log failures to the TTY with printf, 0 = silent
int isoMaskSaved = 0;     // CD-ROM bit of the CPU interrupt mask before the lookup

// CPU interrupt mask register
int* isoIMask = 0x1F801074;

int isoBcd(int v)
{
    int tens = v / 10;
    return (tens << 4) | (v - tens * 10);
}

// 32-bit little-endian value at any (also unaligned) address
uint isoU32(uchar* p)
{
    uint a = p[0];
    uint b = p[1];
    uint c = p[2];
    uint d = p[3];
    return a | (b << 8) | (c << 16) | (d << 24);
}

int isoUpper(int c)
{
    if (c >= 97 && c <= 122)
        return c - 32;
    return c;
}

// Pauses the drive and throws away what is left of the interrupts
void isoStopRead()
{
    cdCommand(ISO_CD_PAUSE, 0, 0);
    for (int i = 0; i < 20000; i++) {}
    cdDrain();
}

/**
 * Reads one 2048-byte sector (logical block address, sector 0 of the disc = 0)
 * to dst. Returns 0, or -1 on error or timeout.
 */
int isoReadSector(uint* dst, int lba)
{
    int f = lba + 150;
    int m = f / 4500;
    int s = (f - m * 4500) / 75;
    int fr = f - m * 4500 - s * 75;
    int guard = 0;
    int n = 0;

    while ((*CD_INDEX & 0x80) != 0 && guard < 50000)
        guard++;

    *CD_INDEX = 0;
    *CD_REG2 = isoBcd(m);
    *CD_REG2 = isoBcd(s);
    *CD_REG2 = isoBcd(fr);
    if (cdCommand(ISO_CD_SETLOC, 0, 0) < 0)
        return -1;
    if (cdCommand(ISO_CD_READN, 0, 0) < 0)
        return -1;

    // Wait for INT1 (the sector is ready). Other interrupts are dropped,
    // INT5 means that the read failed.
    guard = 0;
    while (n != 1 && guard < ISO_WAIT_LIMIT)
    {
        n = cdIntPending();
        if (n != 0 && n != 1)
        {
            cdReadResponse();
            cdAck();
            if (n == 5)
            {
                isoStopRead();
                return -1;
            }
            n = 0;
        }
        guard++;
    }
    if (n != 1)
    {
        isoStopRead();
        return -1;
    }
    cdReadResponse();

    // Ask the controller to load its data FIFO and wait until it has the data
    *CD_INDEX = 0;
    *CD_REG3 = 0;
    *CD_REG3 = 0x80;
    guard = 0;
    while ((*CD_INDEX & 0x40) == 0 && guard < ISO_WAIT_LIMIT)
        guard++;
    if (guard >= ISO_WAIT_LIMIT)
    {
        *CD_REG3 = 0;
        cdAck();
        isoStopRead();
        return -1;
    }

    *dma3Madr = (uint)dst & 0xffffff;
    *dma3Bcr = ISO_SECTOR_WORDS | 0x10000;
    *dma3Chcr = ISO_DMA3_START;

    guard = 0;
    while ((*dma3Chcr & DMA_BUSY) != 0 && guard < ISO_WAIT_LIMIT)
        guard++;

    *CD_INDEX = 0;
    *CD_REG3 = 0;
    cdAck();

    if (guard >= ISO_WAIT_LIMIT)
    {
        *dma3Chcr = 0;
        isoStopRead();
        return -1;
    }

    isoStopRead();
    return 0;
}

/**
 * Compares a name from a directory record (nameLen bytes, with the ";1"
 * version suffix and the trailing '.' of names without an extension) with a
 * path component of compLen characters (the ";1" suffix is optional).
 */
int isoNameMatch(uchar* name, int nameLen, uchar* comp, int compLen)
{
    int n = nameLen;
    int c = compLen;
    int i;

    for (i = 0; i < n; i++)
    {
        if (name[i] == 59) // ';'
        {
            n = i;
            break;
        }
    }
    for (i = 0; i < c; i++)
    {
        if (comp[i] == 59)
        {
            c = i;
            break;
        }
    }

    if (n > 0 && name[n - 1] == 46) // "NAME." means a file without an extension
        n = n - 1;
    if (c > 0 && comp[c - 1] == 46)
        c = c - 1;

    if (n != c || n == 0)
        return 0;

    for (i = 0; i < n; i++)
    {
        if (isoUpper(name[i]) != isoUpper(comp[i]))
            return 0;
    }
    return 1;
}

// Result of isoSearchDir
int isoFoundLba = 0;
int isoFoundSize = 0;
int isoFoundFlags = 0;

/**
 * Looks for a path component in a directory that starts at dirLba and is
 * dirSize bytes long. Returns 1 and sets isoFoundLba, isoFoundSize and
 * isoFoundFlags if the entry exists, 0 if not, -1 on a read error.
 */
int isoSearchDir(int dirLba, int dirSize, uchar* comp, int compLen)
{
    uint* sec = isoSector;
    uchar* b = (uchar*)sec;
    int sectors = (dirSize + 2047) >> 11;
    int d;
    int o;
    int len;

    if (sectors > ISO_MAX_DIR_SECTORS)
        sectors = ISO_MAX_DIR_SECTORS;

    for (d = 0; d < sectors; d++)
    {
        if (isoReadSector(sec, dirLba + d) < 0)
            return -1;

        o = 0;
        while (o < 2048)
        {
            len = b[o];
            if (len == 0)
                break; // records don't cross a sector, the rest is padding
            if (o + len > 2048 || len < 34)
                break;

            if (isoNameMatch(b + o + 33, b[o + 32], comp, compLen) != 0)
            {
                isoFoundLba = isoU32(b + o + 2);
                isoFoundSize = isoU32(b + o + 10);
                isoFoundFlags = b[o + 25];
                return 1;
            }
            o += len;
        }
    }
    return 0;
}

// Gives the CD-ROM interrupt back to the BIOS if it was enabled before
void isoRelease()
{
    cdDrain();
    *I_STAT = ~4;
    if (isoMaskSaved != 0)
        *isoIMask = *isoIMask | 4;
}

/**
 * Finds a file on the disc. Returns its logical block address, or -1 if it
 * doesn't exist or the disc can't be read. The size in bytes is in isoFileSize.
 */
int isoFindFile(uchar* path)
{
    uint* sec = isoSector;
    uchar* b = (uchar*)sec;
    int pos = 0;
    int end;
    int dirLba;
    int dirSize;
    int r;

    *dmaDpcr = *dmaDpcr | ISO_DMA3_ENABLE;

    // The BIOS may have its own CD-ROM interrupt handler, keep it away from
    // the interrupts that are read here by polling
    isoMaskSaved = *isoIMask & 4;
    *isoIMask = *isoIMask & ~4;
    *I_STAT = ~4;

    cdDrain();

    // Data sectors only: single speed, 2048 bytes, no XA, no CD-DA report
    if (cdCommand(ISO_CD_SETMODE, 0, 1) < 0)
    {
        if (isoTrace != 0)
            printf("iso: setmode failed\n");
        isoRelease();
        return -1;
    }

    // Primary volume descriptor: type 1, "CD001"; the root directory record
    // is at offset 156 (extent at +2, size at +10)
    if (isoReadSector(sec, ISO_PVD_LBA) < 0)
    {
        if (isoTrace != 0)
            printf("iso: can't read sector %d\n", ISO_PVD_LBA);
        isoRelease();
        return -1;
    }
    if (b[0] != 1 || b[1] != 67 || b[2] != 68 || b[3] != 48 || b[4] != 48 || b[5] != 49)
    {
        if (isoTrace != 0)
            printf("iso: no volume descriptor, first bytes %x\n", isoU32(b));
        isoRelease();
        return -1;
    }
    dirLba = isoU32(b + 158);
    dirSize = isoU32(b + 166);

    // Skip "cdrom:" and the leading separators
    if (path[0] != 0 && path[1] != 0 && path[2] != 0 && path[3] != 0 && path[4] != 0 && path[5] == 58)
        pos = 6;
    while (path[pos] == 92 || path[pos] == 47)
        pos = pos + 1;

    isoFileSize = 0;

    while (path[pos] != 0)
    {
        end = pos;
        while (path[end] != 0 && path[end] != 92 && path[end] != 47)
            end = end + 1;

        r = isoSearchDir(dirLba, dirSize, path + pos, end - pos);
        if (r <= 0)
        {
            if (isoTrace != 0)
                printf("iso: not found (result %d)\n", r);
            isoRelease();
            return -1;
        }

        dirLba = isoFoundLba;
        dirSize = isoFoundSize;

        pos = end;
        while (path[pos] == 92 || path[pos] == 47)
            pos = pos + 1;

        // anything left must be inside a directory
        if (path[pos] != 0 && (isoFoundFlags & 2) == 0)
        {
            if (isoTrace != 0)
                printf("iso: not a directory\n");
            isoRelease();
            return -1;
        }
    }

    isoFileSize = dirSize;
    isoRelease();
    return dirLba;
}

#endif
