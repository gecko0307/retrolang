/**
 * Text rendering test.
 */

#include "core.ri"
#include "bios.ri"
#include "pad.ri"
#include "gpu.ri"

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
        int* p = gpuAllocZ(5, 0);
        p[0] = GP0_SPRITE2 | fontAtlas->tpage;
        p[1] = GP0_SPRITE_TEX2;
        p[2] = GP0_PACK_COORDS(x, y);
        p[3] = GP0_PACK_UV_DATA(u, v, (uint)fontAtlas->clutId);
        p[4] = (CH_HEIGHT << 16) | CH_WIDTH;
        
        x += CH_WIDTH + CH_KERNING;
    }
}

uchar fontImage[] @("assets/font.tim");

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
