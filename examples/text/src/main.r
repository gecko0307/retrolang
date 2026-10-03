/**
 * Text rendering test.
 */

#include "../../include/core.ri"
#include "../../include/pad.ri"
#include "../../include/gpu.ri"

struct GpuSettings gpu;

struct GpuSprite2 __charSprite;

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
        int* p = gpuAlloc(5);
        p[0] = GP0_SPRITE2 | fontAtlas->tpage;
        p[1] = GP0_SPRITE_TEX2;
        p[2] = (y << 16) | (x & 0xffff);
        p[3] = ((uint)fontAtlas->clutId << 16) | (v << 8) | u;
        p[4] = (CH_HEIGHT << 16) | CH_WIDTH;
        
        x += CH_WIDTH + CH_KERNING;
    }
}

char* fontImage @("assets/font.tim");

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
    struct GpuTexture font;
    gpuTextureInit((struct TimHeader*)fontImage, &font);
    
    bios_a(0x3f, "font.px = %d\n", font.px);
    bios_a(0x3f, "font.py = %d\n", font.py);
    bios_a(0x3f, "font.width = %d\n", font.width);
    bios_a(0x3f, "font.height = %d\n", font.height);
    
    // Upload font atlas to VRAM
    gpuTextureUpload(&font);
    
    while(1)
    {
        int pad1 = padRead1();
        
        gpuQueueClear(0xcb0000);
        drawText(&font, 5, 5, "Hello, World!\n1234567890");
        gpuEndFrame();
        gpuVSync();
    }
}
