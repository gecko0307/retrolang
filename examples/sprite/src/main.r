/**
 * 2D sprite rendering test.
 */

#include "core.ri"
#include "pad.ri"
#include "gpu.ri"

struct GpuSettings gpu;

char* catImage @("assets/cat.tim");

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
    
    // Read TIM data
    struct GpuTexture tex;
    gpuTextureInit((struct TimHeader*)catImage, &tex);
    
    bios_a(0x3f, "tex.px = %d\n", tex.px);
    bios_a(0x3f, "tex.py = %d\n", tex.py);
    bios_a(0x3f, "tex.width = %d\n", tex.width);
    bios_a(0x3f, "tex.height = %d\n", tex.height);
    
    // Upload to VRAM
    gpuMemToVram(tex.image, tex.image->size);
    if (tex.clut != null)
        gpuMemToVram(tex.clut, tex.clut->size);

    // Fill the screen with middle-grey color
    gpuClear(0x808080);

    // Draw a sprite
    struct GpuSprite sprite;
    sprite.texture = &tex;
    sprite.x = 128;
    sprite.y = 88;
    sprite.u = 0;
    sprite.v = 0;
    sprite.width = tex.width;
    sprite.height = tex.height;
    sprite.color = 0x00ffffff;
    gpuDrawTexSprite(&sprite);

    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
    }
}
