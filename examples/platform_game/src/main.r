#include "core.ri"
#include "bios.ri"
#include "pad.ri"
#include "gpu.ri"

uchar tiles[] @("assets/tiles.tim");
uchar character[] @("assets/character.tim");

struct GpuSettings gpu;

#define TILE_WIDTH 16
#define TILE_HEIGHT 16

struct Tile
{
    struct GpuTexture* texture;
    ushort x;
    ushort y;
    uchar u;
    uchar v;
    ushort __padding;
};

void drawTile(struct Tile* tile, int z)
{
    int* p = gpuAllocZ(5, z);
    if (p == 0) return;
    uint u = tile->texture->px + tile->u;
    uint v = tile->texture->py + tile->v;
    p[0] = GP0_SPRITE2 | tile->texture->tpage;
    p[1] = GP0_SPRITE_TEX2 | COLOR_NEUTRAL;
    p[2] = GP0_PACK_COORDS(tile->x, tile->y);
    p[3] = GP0_PACK_UV_DATA(u, v, (uint)tile->texture->clutId);
    p[4] = GP0_PACK_COORDS(TILE_WIDTH, TILE_HEIGHT);
}

macro TILE(u, v) = (u << 4) | (v & 0xf);
macro TILE_EMPTY = TILE(10, 15);
macro TILE_GRND1 = TILE(0, 0);
macro TILE_GRND2 = TILE(0, 1);

uchar levelTiles[20 * 16] = {
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1,
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY,
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY,
    TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_GRND1, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY, TILE_EMPTY,
    TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1, TILE_GRND1,
    TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2, TILE_GRND2,
};

#define LEVEL_WIDTH 20
#define LEVEL_HEIGHT 16

#define CHARACTER_WIDTH 14
#define CHARACTER_HEIGHT 16

int boxHitsSolid(int left, int top)
{
    if (left < 0 || left + CHARACTER_WIDTH > LEVEL_WIDTH * TILE_WIDTH)
        return 1;

    int x0 = left / TILE_WIDTH;
    int x1 = (left + CHARACTER_WIDTH - 1) / TILE_WIDTH;
    int y0 = top / TILE_HEIGHT;
    int y1 = (top + CHARACTER_HEIGHT - 1) / TILE_HEIGHT;
    if (top < 0) y0 = 0;
    if (y1 >= LEVEL_HEIGHT) y1 = LEVEL_HEIGHT - 1;

    for (int y = y0; y <= y1; y++)
    {
        for (int x = x0; x <= x1; x++)
        {
            if (levelTiles[y * LEVEL_WIDTH + x] != TILE_EMPTY)
                return 1;
        }
    }
    return 0;
}

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
    
    struct GpuTexture tilesTex;
    gpuTextureInit((struct TimHeader*)tiles, &tilesTex);
    gpuTextureUpload(&tilesTex);
    
    struct Tile tile;
    tile.x = 0;
    tile.y = 0;
    tile.u = 0;
    tile.v = 0;
    tile.texture = &tilesTex;
    
    struct GpuTexture characterTex;
    gpuTextureInit((struct TimHeader*)character, &characterTex);
    gpuTextureUpload(&characterTex);
    
    struct GpuSprite2 charSprite;
    charSprite.width = 20;
    charSprite.height = 20;
    charSprite.u = 0;
    charSprite.v = 0;
    charSprite.color = COLOR_NEUTRAL;
    charSprite.texture = &characterTex;
    
    int chx = 16;
    int chy = 100;
    int chDir = 1;
    int chu = 0;
    int chv = 0;
    int jumpAccel = 0;
    int fallAccel = 0;
    int jumpAccelTimer = 0;
    int onGround = 0;
    
    int animCounter = 0;
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();

        int dx = 0;
        if (pad1 & PAD_LEFT)  { dx = -2; chDir = -1; }
        if (pad1 & PAD_RIGHT) { dx = 2;  chDir = 1; }

        int jumpPressed = (pad1 & PAD_CROSS) > 0;
        if (onGround && jumpPressed)
        {
            jumpAccel = 3;
            jumpAccelTimer = 0;
        }
        
        if (jumpAccel > 0 && jumpPressed)
        {
            if (jumpAccelTimer < 15)
            {
                jumpAccel++;
                jumpAccelTimer++;
            }
        }

        int dy = 0;
        if (jumpAccel > 0)
        {
            dy = -jumpAccel;
            jumpAccel--;
        }
        else if (!onGround)
        {
            if (fallAccel < 4)
                fallAccel++;
            dy = fallAccel;
        }

        // horizontal: one pixel at a time
        int sx = 1;
        int nx = dx;
        if (dx < 0)
        {
            sx = -1;
            nx = -dx;
        }
        for (int i = 0; i < nx; i++)
        {
            if (boxHitsSolid(chx + sx, chy))
                break;
            chx += sx;
        }

        // vertical: one pixel at a time
        onGround = 0;
        int sy = 1;
        int ny = dy;
        if (dy < 0)
        {
            sy = -1;
            ny = -dy;
        }
        for (int i = 0; i < ny; i++)
        {
            if (boxHitsSolid(chx, chy + sy))
            {
                if (sy > 0)
                {
                    // landed
                    onGround = 1;
                    fallAccel = 0;
                    dy = 0;
                }
                else
                {
                    // hit ceiling
                    jumpAccel = 0;
                }
                break;
            }
            chy += sy;
        }
        
        int animStep = 0;
        animCounter++;
        if (animCounter >= 3)
        {
            animStep = 20;
            animCounter = 0;
        }
        
        if (dy == 0)
        {
            if (dx == 0)
            {
                if (chDir > 0) chv = 0;
                else chv = 20;
                chu = 0;
                animCounter = 0;
                animStep = 0;
            }
            else if (chDir > 0)
            {
                chu += animStep;
                chv = 0;
                if (chu > 60)
                    chu = 0;
            }
            else if (chDir < 0)
            {
                chu -= animStep;
                chv = 20;
                if (chu < 0)
                    chu = 60;
            }
        }
        else
        {
            if (chDir > 0)
                chv = 40;
            else if (chDir < 0)
                chv = 60;
            
            if (dy < 0)
                chu = 0;
            else if (dy > 0)
                chu = 20;
        }
        
        // Render
        gpuSortClear(0xde9f24);
        for (int y = 0; y < LEVEL_HEIGHT; y++)
        {
            for (int x = 0; x < LEVEL_WIDTH; x++)
            {
                uchar t = levelTiles[y * LEVEL_WIDTH + x];
                if (t == TILE_EMPTY) continue;
                tile.x = x * TILE_WIDTH;
                tile.y = y * TILE_HEIGHT;
                tile.u = (t >> 4)  * TILE_WIDTH;
                tile.v = (t & 0xf) * TILE_HEIGHT;
                drawTile(&tile, 1);
            }
        }
        charSprite.x = chx - 3;
        charSprite.y = chy - 2;
        charSprite.u = chu;
        charSprite.v = chv;
        gpuSortSprite2(&charSprite, 0);
        gpuEndFrame();
    }
}
