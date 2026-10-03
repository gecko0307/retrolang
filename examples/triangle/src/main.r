/**
 * GPU test.
 * Clears the screen with a solid color and draws a triangle.
 */

#include "../../include/core.ri"
#include "../../include/pad.ri"
#include "../../include/gpu.ri"

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
    padInit();
    
    gpuWaitIdle();

    // Fills the screen with middle-gray color
    gpuClear(0x808080);

    // Draws a colored triangle
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
        padWaitSync();
        int pad1 = padRead1();
    }
}
