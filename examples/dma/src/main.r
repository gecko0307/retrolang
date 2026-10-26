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
 * DMA triangle rendering test.
 */

#import "retrolib_mini.r"

struct GpuSettings gpu;

void main()
{
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
    padInit();
    
    int x = 160;
    int y = 40;
    
    struct GpuTriangle2 tri;
    tri.x1 = x;
    tri.y1 = y;
    tri.color1 = 0x000000ff; // red
    tri.x2 = x - 80;
    tri.y2 = y + 140;
    tri.color2 = 0x0000ff00; // green
    tri.x3 = x + 80;
    tri.y3 = y + 140;
    tri.color3 = 0x00ff0000; // blue
    
    int speed = 1;
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
             if (pad1 & PAD_UP)    y -= speed;
        else if (pad1 & PAD_DOWN)  y += speed;
             if (pad1 & PAD_LEFT)  x -= speed;
        else if (pad1 & PAD_RIGHT) x += speed;
        
        // Move the triangle
        tri.x1 = x;
        tri.y1 = y;
        tri.x2 = x - 80;
        tri.y2 = y + 140;
        tri.x3 = x + 80;
        tri.y3 = y + 140;
        
        gpuSortClear(0x808080);
        gpuSortTriangle2(&tri, 0);
        gpuEndFrame();
    }
}
