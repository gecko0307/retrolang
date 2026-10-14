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
 * 2D sprite rendering + CD-ROM reading test.
 */

#include "retrolib.ri"

struct GpuSettings gpu;

// 30 KiB region for reading files
#define FILE_BUFFER_SIZE 0x7800
macro FileBuffer = (0x80050000, FILE_BUFFER_SIZE);
uchar fileBuffer[FILE_BUFFER_SIZE] @FileBuffer;

void main()
{
    padInit();
    
    gpu.videoMode = VMODE_PAL;
    gpu.display.width = 320;
    gpu.display.height = 240;
    gpu.display.x = 0;
    gpu.display.y = 0;
    gpu.clip.width = 320;
    gpu.clip.height = 240;
    gpu.clip.x = 0;
    gpu.clip.y = 0;
    gpu.interleaving = 0;
    gpu.colorDepth = COLORDEPTH_15BIT;
    
    gpuInit(&gpu);
    
    // Read TIM file from CD-ROM
    int fd = cd_open("cdrom:\\CAT.TIM;1");
    if (fd < 0)
    {
        printf("Error opening CAT.TIM\n");
        return;
    }
    int bytesRead = cd_read(fd, fileBuffer, FILE_BUFFER_SIZE);
    cd_close(fd);
    if (bytesRead == 0)
    {
        printf("Error reading CAT.TIM\n");
        return;
    }
    printf("Bytes read: %d\n", bytesRead);
    
    // Read TIM data
    struct GpuTexture tex;
    gpuTextureInit((struct TimHeader*)fileBuffer, &tex);
    
    printf("tex.px = %d\n", tex.px);
    printf("tex.py = %d\n", tex.py);
    printf("tex.width = %d\n", tex.width);
    printf("tex.height = %d\n", tex.height);
    
    // Upload to VRAM
    gpuTextureUpload(&tex);

    // Fill the screen with middle-grey color
    gpuClear(0x808080);

    // Draw a textured sprite
    struct GpuSprite2 sprite;
    sprite.texture = &tex;
    sprite.x = 128;
    sprite.y = 88;
    sprite.u = 0;
    sprite.v = 0;
    sprite.width = tex.width;
    sprite.height = tex.height;
    sprite.color = COLOR_NEUTRAL;
    gpuDrawSprite2(&sprite);

    while(1)
    {
        padWaitSync();
    }
}
