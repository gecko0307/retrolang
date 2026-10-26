/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the software
to the public domain. We make this dedication for the benefit of the
public at large and to the detriment of our heirs and successors.
We intend this dedication to be an overt act of relinquishment in 
perpetuity of all present and future rights to this software under
copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
*/

#import "retrolib_mini.r"

uchar levelTiles[20 * 16] @("assets/level.bin");
uchar tiles[] @("assets/tiles.tim");
uchar character[] @("assets/character.tim");
uchar fontImage[] @("assets/font.tim");
uchar vagJump[] @("assets/jump.vag");
uchar vagPickup[] @("assets/pickup.vag");

struct GpuSettings gpu;

#define TILE_WIDTH 16
#define TILE_HEIGHT 16

struct Tile
{
    ushort x;
    ushort y;
    uchar u;
    uchar v;
    ushort __padding;
};

struct GpuTexture tilesTexture;

void drawTile(struct Tile* tile, int z)
{
    int* p = gpuAllocZ(5, z);
    if (p == 0) return;
    uint u = tilesTexture.px + tile->u;
    uint v = tilesTexture.py + tile->v;
    p[0] = GP0_SPRITE2 | tilesTexture.tpage;
    p[1] = GP0_SPRITE_TEX_RAW | COLOR_NEUTRAL;
    p[2] = GP0_PACK_COORDS(tile->x, tile->y);
    p[3] = GP0_PACK_UV_DATA(u, v, (uint)tilesTexture.clutId);
    p[4] = GP0_PACK_COORDS(TILE_WIDTH, TILE_HEIGHT);
}

macro TILE(u, v) = (u << 4) | (v & 0xf);
macro TILE_EMPTY = TILE(10, 15);
macro TILE_GRND1 = TILE(0, 0);
macro TILE_GRND2 = TILE(0, 1);

#define LEVEL_WIDTH 20
#define LEVEL_HEIGHT 16

struct Pickup
{
    uint value;
    ushort x;
    ushort y;
    uchar u;
    uchar v;
    ushort active;
};

void drawPickup(struct Pickup* pickup, int z)
{
    int* p = gpuAllocZ(5, z);
    if (p == 0) return;
    uint u = tilesTexture.px + pickup->u;
    uint v = tilesTexture.py + pickup->v;
    p[0] = GP0_SPRITE2 | tilesTexture.tpage;
    p[1] = GP0_SPRITE_TEX_RAW | COLOR_NEUTRAL;
    p[2] = GP0_PACK_COORDS(pickup->x, pickup->y);
    p[3] = GP0_PACK_UV_DATA(u, v, (uint)tilesTexture.clutId);
    p[4] = GP0_PACK_COORDS(TILE_WIDTH, TILE_HEIGHT);
}

struct Pickup pickups[3];
int numPickups = 3;

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
        p[1] = GP0_SPRITE_TEX_RAW;
        p[2] = GP0_PACK_COORDS(x, y);
        p[3] = GP0_PACK_UV_DATA(u, v, (uint)fontAtlas->clutId);
        p[4] = (CH_HEIGHT << 16) | CH_WIDTH;
        
        x += CH_WIDTH + CH_KERNING;
    }
}

void intToStr(char* buf, int len, int value)
{
    int pos = len;
    int a = value;
    while(pos > 0)
    {
        pos--;
        buf[pos] = '0' + (a % 10);
        a /= 10;
    }
}

void main()
{
    padInit();
    
    int timeStep;
    int frameTime = 3333; //1/30 * 100000
    if (*(char*)0xbfc7ff52 == 'E')
    {
        gpu.videoMode = VMODE_PAL;
        timeStep = 2000; //1/50 * 100000
        printf("Video mode: PAL\n");
    }
    else
    {
        gpu.videoMode = VMODE_NTSC;
        timeStep = 1666; //1/60 * 100000
        printf("Video mode: NTSC\n");
    }
    
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
    
    spuInit();
    
    gpuTextureInit((struct TimHeader*)tiles, &tilesTexture);
    gpuTextureUpload(&tilesTexture);
    
    struct Tile tile;
    tile.x = 0;
    tile.y = 0;
    tile.u = 0;
    tile.v = 0;
    
    pickups[0].value = 10;
    pickups[0].x = 4 * 16;
    pickups[0].y = 13 * 16;
    pickups[0].u = 96;
    pickups[0].v = 192;
    pickups[0].active = true;
    
    pickups[1].value = 10;
    pickups[1].x = 17 * 16;
    pickups[1].y = 8 * 16;
    pickups[1].u = 96;
    pickups[1].v = 192;
    pickups[1].active = true;
    
    pickups[2].value = 10;
    pickups[2].x = 11 * 16;
    pickups[2].y = 7 * 16;
    pickups[2].u = 96;
    pickups[2].v = 192;
    pickups[2].active = true;
    
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
    
    struct GpuTexture font;
    gpuTextureInit((struct TimHeader*)fontImage, &font);
    gpuTextureUpload(&font);
    
    int sndJump = spuLoadVag(vagJump);
    int sndPickup = spuLoadVag(vagPickup);
    int jumpVoice = -1;
    int pickupVoice = -1;
    
    int chx = 16;
    int chy = 16;
    int chDir = 1;
    int chu = 0;
    int chv = 0;
    int canJump = 1;
    int jumpAccel = 0;
    int fallAccel = 0;
    int onGround = 0;
    int speed = 3;
    int jumpForce = 4;
    int maxJumpForce = 5;
    int maxFallAccel = 5;
    int jumpTimer = 0;
    int maxJumpTimer = 8;
    
    int animCounter = 0;
    
    char* scoreStr = "00000000";
    int score = 0;
    
    int timer = 0;
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
        
        timer += timeStep;
        if (timer >= frameTime)
        {
            timer -= frameTime;

            int dx = 0;
            int dy = 0;
            
            if (pad1 & PAD_LEFT)  { dx = -speed; chDir = -1; }
            if (pad1 & PAD_RIGHT) { dx = speed;  chDir = 1; }

            int jumpPressed = (pad1 & PAD_CROSS) > 0;
            if (jumpPressed)
            {
                if (onGround && canJump)
                {
                    jumpAccel = jumpForce;
                    canJump = 0;
                    if (jumpVoice = -1)
                        spuStop(jumpVoice);
                    jumpVoice = spuPlay(sndJump, 0x3FFF);
                    jumpTimer = 0;
                }
            }
            else
            {
                canJump = 1;
            }
            
            if (jumpAccel > 0 && jumpPressed)
            {
                if (jumpTimer < maxJumpTimer)
                {
                    jumpAccel++;
                    jumpTimer++;
                }
            }

            if (jumpAccel > 0)
            {
                dy = -jumpAccel;
                jumpAccel--;
            }
            else if (!onGround)
            {
                jumpAccel = 0;
                if (fallAccel < maxFallAccel)
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
            
            // Animation
            int animStep = 0;
            animCounter++;
            if (animCounter >= 2)
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
            
            // Pickups
            int chCenterX = chx + 8;
            int chCenterY = chy + 8;
            for (int i = 0; i < numPickups; i++)
            {
                struct Pickup* pickup = &pickups[i];
                if (!pickup->active)
                    continue;
                if (chCenterX >= (pickup->x + 4) && chCenterX <= (pickup->x + 12) &&
                    chCenterY >= (pickup->y + 4) && chCenterY <= (pickup->y + 12))
                {
                    pickup->active = 0;
                    score += pickup->value;
                    if (pickupVoice = -1)
                        spuStop(pickupVoice);
                    pickupVoice = spuPlay(sndPickup, 0x3FFF);
                }
            }
            
            charSprite.x = chx - 3;
            charSprite.y = chy - 2;
            charSprite.u = chu;
            charSprite.v = chv;
        }
        
        // Render
        gpuSortClear(0x9d38ae);
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
                drawTile(&tile, 2);
            }
        }
        for (int i = 0; i < numPickups; i++)
        {
            struct Pickup* pickup = &pickups[i];
            if (pickup->active)
                drawPickup(pickup, 1);
        }
        
        gpuSortSprite2(&charSprite, 0);
        intToStr(scoreStr, 8, score);
        drawText(&font, 5, 5, scoreStr);
        gpuEndFrame();
    }
}
