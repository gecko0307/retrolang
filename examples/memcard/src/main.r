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

#import "retrolib.r"

#define DATA_SIZE 14

uchar saveBuffer[DATA_SIZE];
uchar loadBuffer[DATA_SIZE];

uchar iconImage[] @("assets/icon.tim");

void main()
{
    padInit();
    saveInit();
    
    // Read the icon TIM file
    struct TimHeader* tim = (struct TimHeader*)iconImage;
    char* p = (char*)tim;
    p += sizeof(struct TimHeader);
    struct TimData* clut = 0;
    struct TimData* image = 0;
    uchar* iconData = 0;
    uchar* clutData = 0;
    if ((tim->flags & 0x08) == 0)
    {
        // No CLUT present
        image = (struct TimData*)p;
        iconData = p + sizeof(struct TimData);
    }
    else
    {
        clut = (struct TimData*)p;
        clutData = p + sizeof(struct TimData);
        p += clut->size;
        image = (struct TimData*)p;
        iconData = p + sizeof(struct TimData);
    }
    
    // CLUT: 16 entries, 16-bit little-endian, 15-bit color.
    // Icon frame: 16x16, 4bpp = 128 bytes.
    saveSetIcon(clutData, iconData, 1);
    
    // Save to the memory card
    memcpy(saveBuffer, "Hello, World!", DATA_SIZE);
    saveBuffer[DATA_SIZE-1] = 0; // null-terminate
    struct Save save;
    save.slot = 0;
    save.name = "RETROLANG";
    save.blocks = 1;
    save.data = &saveBuffer[0];
    save.size = DATA_SIZE;
    save.version = 1;
    printf("Saved data: \"%s\"\n", save.data);
    printf("Saving...\n");
    int err = saveWrite(&save);
    if (err == SAVE_OK)
        printf("Done!\n");
    else
    {
        printf("Error %d\n", err);
        return;
    }
    
    // Load from the memory card
    struct Save load;
    load.slot = 0;
    load.name = "RETROLANG";
    load.data = &loadBuffer[0];
    load.size = DATA_SIZE;
    load.version = 1;
    printf("Loading...\n");
    err = saveRead(&load);
    if (err == SAVE_OK)
        printf("Done!\n");
    else
    {
        printf("Error %d\n", err);
        return;
    }
    
    printf("Loaded data: \"%s\"\n", load.data);
}
