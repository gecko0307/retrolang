/**
 * 2D sprite rendering + CD-ROM reading test.
 */

#include "core.ri"
#include "bios.ri"
#include "pad.ri"
#include "gpu.ri"

struct GpuSettings gpu;

// 30 KiB region for reading files
#define FILE_BUFFER_SIZE 0x7800
macro FileBuffer = (0x80050000, FILE_BUFFER_SIZE);
uchar fileBuffer[FILE_BUFFER_SIZE] @FileBuffer;
//@("assets/cat.tim");

void main()
{
    padInit();
    
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
    
    // Read TIM file from CD-ROM
    int fd = cd_open("cdrom:\\CAT.TIM;1");
    if (fd < 0)
    {
        printf("Error opening CAT.TIM\n");
        return;
    }
    int bytesRead = cd_read(fd, fileBuffer, FILE_BUFFER_SIZE);
    cd_close(fd);
    if (bytesRead == 0)
    {
        printf("Error reading CAT.TIM\n");
        return;
    }
    printf("Bytes read: %d\n", bytesRead);
    
    // Read TIM data
    struct GpuTexture tex;
    gpuTextureInit((struct TimHeader*)fileBuffer, &tex);
    
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
    sprite.color = COLOR_NEUTRAL;
    gpuDrawSprite2(&sprite);

    while(1)
    {
        padWaitSync();
    }
}
