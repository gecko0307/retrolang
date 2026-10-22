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
 * GPU test.
 * Clears the screen with a solid color and draws a triangle.
 */

#import "retrolib.r"

// Global GPU config
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
    
    gpuWaitIdle();

    // Fills the screen with middle-gray color
    gpuClear(0x808080);

    // Draws a shaded triangle
    struct GpuTriangle2 tri;
    tri.x1 = 160;
    tri.y1 = 40;
    tri.color1 = 0x000000ff; // red
    tri.x2 = 80;
    tri.y2 = 180;
    tri.color2 = 0x0000ff00; // green
    tri.x3 = 240;
    tri.y3 = 180;
    tri.color3 = 0x00ff0000; // blue
    gpuDrawTriangle2(&tri);

    while(1)
    {
        
    }
}
