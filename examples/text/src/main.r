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
 * Text rendering test.
 */

#import "retrolib.r"

struct GpuSettings gpu;

#define CH_WIDTH 10
#define CH_HEIGHT 12
#define CH_KERNING -2

void drawText(struct GpuTexture* fontAtlas, int x, int y, char* text)
{
    int startX = x;
    while (*text != 0)
    {
        char ch = *text++;
        if (ch == '\n')
        {
            x = startX;
            y += CH_HEIGHT;
            continue;
        }
        
        uint u = fontAtlas->px + (ch & 15) * CH_WIDTH;
        uint v = fontAtlas->py + (ch >> 4) * CH_HEIGHT;
        int* p = gpuAllocZ(5, 0);
        p[0] = GP0_SPRITE2 | fontAtlas->tpage;
        p[1] = GP0_SPRITE_TEX_RAW;
        p[2] = GP0_PACK_COORDS(x, y);
        p[3] = GP0_PACK_UV_DATA(u, v, (uint)fontAtlas->clutId);
        p[4] = (CH_HEIGHT << 16) | CH_WIDTH;
        
        x += CH_WIDTH + CH_KERNING;
    }
}

uchar fontImage[] @("assets/font.tim");

void main()
{
    gpu.videoMode = gpuDetectVMode();
    
    if (gpu.videoMode == VMODE_PAL)
        printf("Video mode: PAL\n");
    else
        printf("Video mode: NTSC\n");
    
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
    padInit();
    
    // Read TIM data
    struct GpuTexture font;
    gpuTextureInit((struct TimHeader*)fontImage, &font);
    
    printf("font.px = %d\n", font.px);
    printf("font.py = %d\n", font.py);
    printf("font.width = %d\n", font.width);
    printf("font.height = %d\n", font.height);
    
    // Upload font atlas to VRAM
    gpuTextureUpload(&font);
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
        
        gpuSortClear(0xcb0000);
        drawText(&font, 5, 5, "Hello, World!\n1234567890");
        gpuEndFrame();
    }
}
