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
 * Memory card save/load API (implementation module).
 *
 * Layout of a save file (blocks * 8192 bytes):
 *   0x000  BIOS header: "SC", icon flag, block count, title, CLUT, icon frames
 *   0x200  payload header (16 bytes): magic u32, version u16, reserved u16,
 *                                     size u32, crc32 u32
 *   0x210  payload data (your save struct)
 *
 * Usage:
 *   save_init();                                  // once, after padInit()
 *   save_set_title("MY GAME");
 *   save_set_icon(clut32, frame128, 1);           // optional but recommended
 *   save_write(0, "BASCUS-94163SAVE01", 1, &mySave, sizeof(mySave), 1);
 *   save_read (0, "BASCUS-94163SAVE01", &mySave, sizeof(mySave), 1, &got);
 *
 * Notes:
 *  - File names are at most 20 characters (region+product code + suffix).
 *  - The block count of an existing save is fixed. To change it, call
 *    save_delete() first, then save_write().
 *  - An existing save is overwritten in place (no delete/create window where
 *    power loss would destroy it).
 *  - open() failing can mean "file missing" or "no card"; the BIOS file API
 *    does not let us tell them apart here.
 */

#include "core.ri"
#include "bios.ri"
#include "save.ri"

struct Save
{
    int slot;
    char* name;
    int blocks;
    char* data;
    int size;
    int version;
};

// Internal state
uchar saveBuf[SAVE_MAX_BLOCKS * SAVE_BLOCK_SIZE];
char  savePathBuf[32];
char  saveTitle[64];
uchar* saveIconClut = 0;               // 32 bytes
uchar* saveIconFrames = 0;             // 128 bytes per frame
int    saveIconCount = 1;              // 1..3

/*
 * Helpers
 */
void savePut16(uchar* p, int v)
{
    p[0] = v & 0xFF;
    p[1] = (v >> 8) & 0xFF;
}

void savePut32(uchar* p, uint v)
{
    p[0] = v & 0xFF;
    p[1] = (v >> 8) & 0xFF;
    p[2] = (v >> 16) & 0xFF;
    p[3] = (v >> 24) & 0xFF;
}

int saveGet16(uchar* p)
{
    return p[0] | (p[1] << 8);
}

uint saveGet32(uchar* p)
{
    return p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
}

uint saveCrc32(uchar* p, int n)
{
    uint crc = 0xFFFFFFFF;
    int i, b;
    for (i = 0; i < n; i++)
    {
        crc ^= p[i];
        for (b = 0; b < 8; b++)
        {
            if (crc & 1) crc = (crc >> 1) ^ 0xEDB88320;
            else         crc = crc >> 1;
        }
    }
    return crc ^ 0xFFFFFFFF;
}

// Builds "bu00:NAME" / "bu10:NAME" in savePathBuf. Returns 1 on success.
int savePath(int slot, char* name)
{
    int i = 0;
    if (slot < 0 || slot > 1 || name == 0)
        return 0;
    savePathBuf[0] = 'b';
    savePathBuf[1] = 'u';
    savePathBuf[2] = '0' + slot;
    savePathBuf[3] = '0';
    savePathBuf[4] = ':';
    while (name[i] != 0)
    {
        if (i >= SAVE_NAME_MAX)
            return 0;
        savePathBuf[5 + i] = name[i];
        i++;
    }
    savePathBuf[5 + i] = 0;
    return 1;
}

/// Call this before using other functions.
void saveInit()
{
    card_init();
    card_start();
    _bu_init();
    memset(saveTitle, 0, 64);
    memcpy(saveTitle, "SAVE", 4);
}

/// ASCII title, up to 63 characters.
void saveSetTitle(char* title)
{
    int i = 0;
    memset(saveTitle, 0, 64);
    while (title[i] != 0 && i < 63)
    {
        saveTitle[i] = title[i];
        i++;
    }
}

/**
 * CLUT: 32 bytes (16 x 15-bit colors);
 * icon frames: 128 bytes per 16x16 4bpp frame.
 * The pointers must stay valid until the last saveWrite() call.
 */
void saveSetIcon(uchar* clut, uchar* frames, int frameCount)
{
    saveIconClut = clut;
    saveIconFrames = frames;
    if (frameCount < 1) frameCount = 1;
    if (frameCount > 3) frameCount = 3;
    saveIconCount = frameCount;
}

/// Returns 1 if the save can be opened for reading, 0 otherwise.
int saveExists(int slot, char* name)
{
    int fd;
    if (!savePath(slot, name))
        return 0;
    fd = open(savePathBuf, FREAD);
    if (fd < 0)
        return 0;
    close(fd);
    return 1;
}

///
int saveDelete(int slot, char* name)
{
    if (!savePath(slot, name)) return SAVE_ERR_ARGS;
    delete(savePathBuf);               // use erase() if that is what bios.ri exposes
    return SAVE_OK;
}

///
int saveWrite(struct Save* save)
{
    int total, fd, w, tries;
    uchar* hdr;

    if (save->blocks < 1 || save->blocks > SAVE_MAX_BLOCKS || save->data == 0 || save->size < 0)
        return SAVE_ERR_ARGS;
    if (!savePath(save->slot, save->name))
        return SAVE_ERR_ARGS;

    total = save->blocks * SAVE_BLOCK_SIZE;
    if (save->size > total - SAVE_DATA_OFFSET)
        return SAVE_ERR_TOO_BIG;

    // Build the whole image in RAM first
    memset(saveBuf, 0, total);

    hdr = saveBuf;
    hdr[0] = 'S';
    hdr[1] = 'C';
    hdr[2] = 0x10 + saveIconCount; // 0x11 / 0x12 / 0x13
    hdr[3] = save->blocks;
    memcpy(&hdr[0x04], saveTitle, 64);
    if (saveIconClut != 0)
        memcpy(&hdr[0x60], saveIconClut, 32);
    if (saveIconFrames != 0)
        memcpy(&hdr[0x80], saveIconFrames, 128 * saveIconCount);

    savePut32(&saveBuf[SAVE_HEADER_SIZE + 0],  SAVE_MAGIC);
    savePut16(&saveBuf[SAVE_HEADER_SIZE + 4],  save->version);
    savePut16(&saveBuf[SAVE_HEADER_SIZE + 6],  0);
    savePut32(&saveBuf[SAVE_HEADER_SIZE + 8],  save->size);
    savePut32(&saveBuf[SAVE_HEADER_SIZE + 12], saveCrc32((uchar*)save->data, save->size));
    memcpy(&saveBuf[SAVE_DATA_OFFSET], save->data, save->size);

    // Overwrite in place if the save exists, create it otherwise.
    // Retry once: the first card access after a swap often reports an error
    fd = -1;
    for (tries = 0; tries < 2 && fd < 0; tries++)
    {
        fd = open(savePathBuf, FWRITE);
        if (fd < 0)
            fd = open(savePathBuf, FCREATE | (save->blocks << 16));
    }
    if (fd < 0)
        return SAVE_ERR_OPEN;

    w = write(fd, saveBuf, total);
    close(fd);
    if (w != total)
        return SAVE_ERR_IO;
    return SAVE_OK;
}

/**
 * Reads a save into save->data.
 * save->size receives the payload size.
 */
int saveRead(struct Save* save)
{
    int fd, r, size, total, blocks, tries, b;
    uint crc;

    if (save->data == 0)
        return SAVE_ERR_ARGS;
    if (!savePath(save->slot, save->name))
        return SAVE_ERR_ARGS;

    fd = -1;
    for (tries = 0; tries < 2 && fd < 0; tries++)
        fd = open(savePathBuf, FREAD);
    if (fd < 0)
        return SAVE_ERR_OPEN;

    // First block carries the headers
    r = read(fd, saveBuf, SAVE_BLOCK_SIZE);
    if (r != SAVE_BLOCK_SIZE)
    {
        close(fd);
        return SAVE_ERR_IO;
    }

    if (saveBuf[0] != 'S' || saveBuf[1] != 'C' ||
        saveGet32(&saveBuf[SAVE_HEADER_SIZE]) != SAVE_MAGIC)
    {
        close(fd);
        return SAVE_ERR_CORRUPT;
    }
    if (saveGet16(&saveBuf[SAVE_HEADER_SIZE + 4]) != save->version)
    {
        close(fd);
        return SAVE_ERR_VERSION;
    }

    size = saveGet32(&saveBuf[SAVE_HEADER_SIZE + 8]);
    crc  = saveGet32(&saveBuf[SAVE_HEADER_SIZE + 12]);
    total = SAVE_DATA_OFFSET + size;
    blocks = (total + SAVE_BLOCK_SIZE - 1) / SAVE_BLOCK_SIZE;

    if (size < 0 || blocks > SAVE_MAX_BLOCKS)
    {
        close(fd);
        return SAVE_ERR_CORRUPT;
    }
    if (size > save->size)
    {
        close(fd);
        return SAVE_ERR_TOO_BIG;
    }

    // Remaining blocks, if the payload spans more than one
    for (b = 1; b < blocks; b++)
    {
        r = read(fd, &saveBuf[b * SAVE_BLOCK_SIZE], SAVE_BLOCK_SIZE);
        if (r != SAVE_BLOCK_SIZE)
        {
            close(fd);
            return SAVE_ERR_IO;
        }
    }
    close(fd);

    if (saveCrc32(&saveBuf[SAVE_DATA_OFFSET], size) != crc)
        return SAVE_ERR_CORRUPT;

    memcpy(save->data, &saveBuf[SAVE_DATA_OFFSET], size);
    if (save->size != 0)
        save->size = size;
    return SAVE_OK;
}
