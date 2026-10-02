/**
 * GPU test.
 * Fills the screen with a solid color and draws a rectangle.
 */

#include "pad.ri"
#include "gpu.ri"

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
    
    gpuWaitReady();

    // Fills the screen with blue color
    gpuClear(0xFF0000);

    // Draws a red 100x100 rectangle
    struct GpuRect rect;
    rect.x = 0;
    rect.y = 0;
    rect.width = 100;
    rect.height = 100;
    gpuDrawSolidSprite(&rect, 0x0000FF);

    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
    }
}
