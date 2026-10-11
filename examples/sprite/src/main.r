/**
 * 2D sprite rendering test.
 */

#include "core.ri"
#include "bios.ri"
#include "pad.ri"
#include "gpu.ri"

struct GpuSettings gpu;

uchar catImage[] @("assets/cat.tim");

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
    
    // Read TIM data
    struct GpuTexture tex;
    gpuTextureInit((struct TimHeader*)catImage, &tex);
    
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
    sprite.color = 0x00ffffff;
    gpuDrawSprite2(&sprite);

    while(1)
    {
    }
}
