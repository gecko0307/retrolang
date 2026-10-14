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
 * Memory card I/O test.
 */

#include "core.ri"
#include "bios.ri"
#include "pad.ri"

#define MEMCARD_BLOCK_SIZE 8192
char memcardBufferW[MEMCARD_BLOCK_SIZE];
char memcardBufferR[MEMCARD_BLOCK_SIZE];

void main()
{
    padInit();
    card_init();
    card_start();
    _bu_init();
    
    // Initialize buffers with zeros
    memset(memcardBufferW, 0, MEMCARD_BLOCK_SIZE);
    memset(memcardBufferR, 0, MEMCARD_BLOCK_SIZE);
    
    char* blockName = "bu00:BASCUS-94163SAVE01";
    
    // Delete the old block, if it exists
    delete(blockName);
    
    // Make a block header
    memcardBufferW[0] = 'S';
    memcardBufferW[1] = 'C';
    memcardBufferW[2] = 0x11;   // 1 icon frame
    memcardBufferW[3] = 1;      // blocks used
    // 0x04: title, 64 bytes Shift-JIS, zero padded
    memcpy(&memcardBufferW[0x04], "TEST SAVE", 9);
    
    // CLUT at 0x60: 16 entries, 16-bit little-endian, 15-bit color (R | G<<5 | B<<10 | STP<<15)
    // Entry 0x0000 is fully transparent. Opaque black needs bit 15 set (0x8000).
    // Write bytes rather than casting to ushort*, in case the buffer isn't 2-byte aligned.
    memcardBufferW[0x60 + 2] = 0x1F;  // entry 1: red = 0x801F
    memcardBufferW[0x60 + 3] = 0x80;
    memcardBufferW[0x60 + 4] = 0xFF;  // entry 2: white = 0xFFFF
    memcardBufferW[0x60 + 5] = 0xFF;

    // Icon frame at 0x80: 16x16, 4bpp = 128 bytes. Two pixels per byte,
    // low nibble is the left pixel.
    // This will draw a red square with a white border.
    memset(&memcardBufferW[0x80], 0x11, 128);        // all red (palette index 1)
    memset(&memcardBufferW[0x80], 0x22, 8);          // top row white (index 2)
    memset(&memcardBufferW[0x80 + 120], 0x22, 8);    // bottom row white
    for (int y = 1; y < 15; y++)
    {
        memcardBufferW[0x80 + y * 8]     = 0x12;  // leftmost pixel white
        memcardBufferW[0x80 + y * 8 + 7] = 0x21;  // rightmost pixel white
    }
    
    // Put data
    memcpy(&memcardBufferW[0x200], "Hello, World!", 13);
    
    // Write a test string to the memory card slot 1:
    int fd = open(blockName, FCREATE | (1 << 16));
    write(fd, memcardBufferW, MEMCARD_BLOCK_SIZE);
    close(fd);
    printf("Writing done!\n");
    
    // Read back
    memset(memcardBufferR, 0, MEMCARD_BLOCK_SIZE);
    fd = open(blockName, FREAD);
    read(fd, memcardBufferR, MEMCARD_BLOCK_SIZE);
    close(fd);
    printf("Reading done!\n");
    printf("%s\n", &memcardBufferR[0x200]); // prints the data from the block
}
