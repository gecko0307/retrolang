/**
 * GPU test.
 * Fills the screen with a solid color and draws a rectangle.
 */

#include "pad.ri"
#include "gpu.ri"

void main()
{
    gpuInit();
    padInit();
    
    gpuWaitReady();

    // Fills the screen with blue color
    gpuColor = 0xFF0000;
    gpuClear();

    // Draws a red 100x100 rectangle
    gpuColor = 0x0000FF;
    gpuDrawSolidSprite(0, 0, 100, 100);

    while(1)
    {
        padWaitVSync();
        int pad1 = padRead1();
    }
}
