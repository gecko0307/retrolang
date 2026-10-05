/**
 * DMA triangle rendering test.
 */

#include "../../include/core.ri"
#include "../../include/pad.ri"
#include "../../include/gpu.ri"

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
        
        gpuQueueClear(0x808080);
        gpuQueueDrawTriangle2(&tri, 0);
        gpuEndFrame();
    }
}
