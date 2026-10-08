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

/**
 * Mesh rendering test
 */

#include "../../include/core.ri"
#include "../../include/pad.ri"
#include "../../include/gpu.ri"

// Model-space vertex
struct Vertex
{
    short x;
    short y;
    short z;
    short _padding;
};

// Screen-space vertex
struct SVertex
{
    short x, y;
    ushort z;
    ushort _padding;
};

/**
 * Parameters for GTE RTPS
 * (rotate/translate/perspective transform for a single vertex)
 */
struct RTPSTransform
{
    // Translation
    int tx;
    int ty;
    int tz;
    
    // 3x3 rotation matrix of Q3.12 elements
    // R11 R12 R13
    // R21 R22 R23
    // R31 R32 R33
    short r[9];
    
    // Projection settings
    short h;
    int ofx;
    int ofy;
    
    // Depth queing settings
    short dqa;
    short dqb;
};

void gteInit() @("gteInit.s");
void gteRTPTSetParams(struct RTPSTransform* rtpsTransform) @("gteRTPTSetParams.s");
void gteRTPTRun(struct Vertex* inVertices, struct SVertex* outVertices) @("gteRTPTRun.s");

// PSM file header
struct PSMHeader
{
    ushort numVerts;
    ushort numTris;
    ushort texWidth;
    ushort texHeight;
    uint uvOffset;
    uint idxOffset;
    // at offset 16: vertices (numVerts * 8 bytes): short x, y, z, pad
    // at uvOffset: UVs (numVerts * 2 bytes): uchar u, v (array padded to 4 bytes)
    // at idxOffset: indices (numTris * 3 * 2 bytes): ushort (array padded to 4 bytes)
};

struct PSMData
{
    struct Vertex* vertices;
    uchar* uvs;
    ushort* indices;
    struct GpuTexture* texture;
    int tilex;
    int tiley;
    int color;
};

#define SCREEN_WIDTH 320
#define SCREEN_HEIGHT 240
#define HALF_SCR_WIDTH 160
#define HALF_SCR_HEIGHT 120

/**
 * Near clip distance.
 */
#define Z_NEAR 100

/**
 * Right-shift for Z values.
 * Used to compress polygon depth to fit the OT.
 * Larger values -> larger clip distance, but less precision.
 * Smaller values -> smaller clip distance, but more precision.
 */
#define Z_SHIFT 2

/// Draws a PSM mesh with a given transformation.
void drawPSM(struct PSMHeader* psm, struct PSMData* data, struct RTPSTransform* tr, int zBias)
{
    // GTE transformation input and output
    struct Vertex triVertices[3];
    struct SVertex projected[3];
    short x1, y1;
    short x2, y2;
    short x3, y3;
    
    // VRAM position of the texture tile
    uint tx = data->texture->px + data->tilex;
    uint ty = data->texture->py + data->tiley;
    
    ushort vi1, vi2, vi3;
    int z1, z2, z3, otz;
    uint u, v;
    ushort* indices = data->indices;
    uchar* uvs = data->uvs;
    struct Vertex* vertices = data->vertices;
    
    uint clutId = (uint)data->texture->clutId << 16;
    uint tpage = (uint)data->texture->tpage << 16;
    int color = data->color;
    
    // Upload transform parameters to GTE
    //gteRTPTSetParams(tr);
    
    // Upload translation to GTE
    gte_ctc2(GTE_TRX, tr->tx);
    gte_ctc2(GTE_TRY, tr->ty);
    gte_ctc2(GTE_TRZ, tr->tz);
    
    // Upload rotation matrix to GTE
    gte_set_matrix(tr->r);
    
    // Upload projection params to GTE
    gte_ctc2(GTE_H,   tr->h);
    gte_ctc2(GTE_OFX, tr->ofx);
    gte_ctc2(GTE_OFY, tr->ofy);
    gte_ctc2(GTE_DQA, tr->dqa);
    gte_ctc2(GTE_DQB, tr->dqb);
    
    int numIndices = psm->numTris * 3;
    for (int i = 0; i < numIndices; i += 3)
    {
        // Read triangle vertices
        vi1 = indices[i];
        vi2 = indices[i + 1];
        vi3 = indices[i + 2];
        
        triVertices[0] = vertices[vi1];
        triVertices[1] = vertices[vi2];
        triVertices[2] = vertices[vi3];
        
        // Rotate-translate-perspective transform
        //gteRTPTRun(triVertices, projected);
        gte_set_vertex(triVertices);
        gte_rtpt();
        nop();
        nop();
        gte_get_vertex(projected);
        
        // Screen-space vertices x, y
        x1 = projected[0].x; y1 = projected[0].y;
        x2 = projected[1].x; y2 = projected[1].y;
        x3 = projected[2].x; y3 = projected[2].y;
        
        // Screen clipping
        if (x1 < 0 && x2 < 0 && x3 < 0)
            continue;
        if (x1 >= SCREEN_WIDTH && 
            x2 >= SCREEN_WIDTH &&
            x3 >= SCREEN_WIDTH)
            continue;
        if (y1 < 0 && y2 < 0 && y3 < 0)
            continue;
        if (y1 >= SCREEN_HEIGHT &&
            y2 >= SCREEN_HEIGHT &&
            y3 >= SCREEN_HEIGHT)
            continue;
        
        // Backface culling
        int area = (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1);
        if (area > 0)
            continue;
        
        // Screen-space depth
        z1 = projected[0].z;
        z2 = projected[1].z;
        z3 = projected[2].z;
        
        // Near-plane rejection
        if (z1 < Z_NEAR || z2 < Z_NEAR || z3 < Z_NEAR)
            continue;
        
        //otz = (((z1 + z2 + z3) / 3) >> Z_SHIFT) + zBias;
        otz = (((z1 + z2 + z3) * (0x555 >> Z_SHIFT)) >> 12) + zBias;
        if (otz >= OT_SIZE - 1 || otz < 0)
            continue; // Beyond the depth range
        
        int* p = gpuAllocZ(7, otz);
        if (p == 0) break;
        
        // Fill the packet
        p[0] = GP0_TRI3 | color;
        p[1] = (y1 << 16) | (x1 & 0xffff);
        u = tx + uvs[vi1 * 2];
        v = ty + uvs[vi1 * 2 + 1];
        p[2] = clutId | (v << 8) | (u & 0xff);
        p[3] = (y2 << 16) | (x2 & 0xffff);
        u = tx + uvs[vi2 * 2];
        v = ty + uvs[vi2 * 2 + 1];
        p[4] = tpage  | (v << 8) | (u & 0xff);
        p[5] = (y3 << 16) | (x3 & 0xffff);
        u = tx + uvs[vi3 * 2];
        v = ty + uvs[vi3 * 2 + 1];
        p[6] = (v << 8) | (u & 0xff);
    }
}

#define CUBE_NUM_VERTS 8
#define CUBE_NUM_TRIS 4

// Global GPU config
struct GpuSettings gpu;

char* textures @("assets/texture.tim");
char* character @("assets/character.psm");
char* floor @("assets/floor.psm");
char* sin4096 @("sin_table/sin4096.bin");

#define QPI 0x200
#define HPI 0x400
#define PI  0x800
#define PI2 0x1000

short sin(uint angle)
{
    short* sinTable = (short*)sin4096;
    return sinTable[angle & 0xfff];
}

short cos(uint angle)
{
    short* sinTable = (short*)sin4096;
    return sinTable[(angle + HPI) & 0xfff];
}

void trSetRotationIdentity(struct RTPSTransform* tr)
{
    tr->r[0] = F_ONE;  tr->r[1] = 0x0000; tr->r[2] = 0x0000;
    tr->r[3] = 0x0000; tr->r[4] = F_ONE;  tr->r[5] = 0x0000;
    tr->r[6] = 0x0000; tr->r[7] = 0x0000; tr->r[8] = F_ONE;
}

void trSetRotationX(struct RTPSTransform* tr, uint a, short scale)
{
    short s = sin(a);
    short c = cos(a);
    short scOne = F_ONE * scale;
    tr->r[0] = scOne; tr->r[1] = 0; tr->r[2] =  0;
    tr->r[3] = 0;     tr->r[4] = c; tr->r[5] = -s;
    tr->r[6] = 0;     tr->r[7] = s; tr->r[8] =  c;
}

void trSetRotationY(struct RTPSTransform* tr, uint a, short scale)
{
    short s = sin(a) * scale;
    short c = cos(a) * scale;
    short scOne = F_ONE * scale;
    tr->r[0] = c;  tr->r[1] = 0;     tr->r[2] = s;
    tr->r[3] = 0;  tr->r[4] = scOne; tr->r[5] = 0;
    tr->r[6] = -s; tr->r[7] = 0;     tr->r[8] = c;
}

void trSetRotationZ(struct RTPSTransform* tr, uint a, short scale)
{
    short s = sin(a);
    short c = cos(a);
    short scOne = F_ONE * scale;
    tr->r[0] = c;  tr->r[1] = -s;  tr->r[2] = 0;
    tr->r[3] = s;  tr->r[4] =  c;  tr->r[5] = 0;
    tr->r[6] = 0;  tr->r[7] =  0;  tr->r[8] = scOne;
}

struct Camera
{
    int x;
    int y;
    int z;
    int rotY;
};

void trSetCameraY(
    struct RTPSTransform* tr,
    struct Camera* cam,
    short scale)
{
    short s = sin(cam->rotY) * scale;
    short c = cos(cam->rotY) * scale;
    short scOne = F_ONE * scale;
    
    int x = cam->x;
    int y = cam->y;
    int z = cam->z;

    // R_view = transpose(R_camera)
    tr->r[0] = c;  tr->r[1] = 0;     tr->r[2] = -s;
    tr->r[3] = 0;  tr->r[4] = scOne; tr->r[5] = 0;
    tr->r[6] = s;  tr->r[7] = 0;     tr->r[8] = c;

    // T_view = -R_view * C
    tr->tx = -((c * x - s * z) >> 12);
    tr->ty = -y;
    tr->tz = -((s * x + c * z) >> 12);
}

#define SCALE 2

void main()
{
    gpu.videoMode = VMODE_PAL;
    gpu.display.width = SCREEN_WIDTH;
    gpu.display.height = SCREEN_HEIGHT;
    gpu.display.x = 0;
    gpu.display.y = 0;
    gpu.clip.width = SCREEN_WIDTH;
    gpu.clip.height = SCREEN_HEIGHT;
    gpu.clip.x = 0;
    gpu.clip.y = 0;
    gpu.interleaving = 0;
    gpu.colorDepth = COLORDEPTH_15BIT;
    
    padInit();
    gpuInit(&gpu);
    
    gte_enable();
    gte_ctc2(GTE_ZSF3, 0x555); // For AVSZ3
    
    // Read TIM data
    struct GpuTexture tex;
    gpuTextureInit((struct TimHeader*)textures, &tex);
    bios_a(0x3f, "tex.px = %d\n", tex.px);
    bios_a(0x3f, "tex.py = %d\n", tex.py);
    bios_a(0x3f, "tex.width = %d\n", tex.width);
    bios_a(0x3f, "tex.height = %d\n", tex.height);
    
    // Upload to VRAM
    gpuTextureUpload(&tex);
    
    struct RTPSTransform tr;
    tr.tx = 0;
    tr.ty = 0;
    tr.tz = 0;
    trSetRotationIdentity(&tr);
    tr.h = 0x100;
    tr.ofx = 0x10000 * HALF_SCR_WIDTH;
    tr.ofy = 0x10000 * HALF_SCR_HEIGHT;
    tr.dqa = F_ONE;
    tr.dqb = 0x000;
    
    char* meshStart;
    
    // Floor mesh data
    struct PSMHeader* psmFloor = (struct PSMHeader*)floor;
    struct PSMData dataFloor;
    meshStart = floor;
    dataFloor.vertices = (struct Vertex*)(meshStart + 16);
    dataFloor.uvs = (uchar*)(meshStart + psmFloor->uvOffset);
    dataFloor.indices = (ushort*)(meshStart + psmFloor->idxOffset);
    dataFloor.texture = &tex;
    dataFloor.tilex = 64;
    dataFloor.tiley = 0;
    dataFloor.color = COLOR_NEUTRAL;
    
    // Character mesh data
    struct PSMHeader* psmCharacter = (struct PSMHeader*)character;
    struct PSMData dataCharacter;
    meshStart = character;
    dataCharacter.vertices = (struct Vertex*)(meshStart + 16);
    dataCharacter.uvs = (uchar*)(meshStart + psmCharacter->uvOffset);
    dataCharacter.indices = (ushort*)(meshStart + psmCharacter->idxOffset);
    dataCharacter.texture = &tex;
    dataCharacter.tilex = 0;
    dataCharacter.tiley = 0;
    dataCharacter.color = COLOR_NEUTRAL;
    
    // Camera
    struct Camera cam;
    cam.x = 0;
    cam.y = -290;
    cam.z = -700;
    cam.rotY = 0;
    
    int pitch = 0;
    
    int speed = 10;
    int yawSpeed = 25;
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
        
        if (pad1 & PAD_LEFT)
        {
            cam.rotY -= yawSpeed;
        }
        else if (pad1 & PAD_RIGHT)
        {
            cam.rotY += yawSpeed;
        }
        
        short sy = sin(cam.rotY);
        short cy = cos(cam.rotY);
        short sp = sin(pitch);
        short cp = cos(pitch);

        int fx = (sy * cp) >> 12;
        int fz = (cy * cp) >> 12;
        
        if (pad1 & PAD_UP)
        {
            cam.x += (fx * speed) >> 12;
            cam.z += (fz * speed) >> 12;
        }
        else if (pad1 & PAD_DOWN)
        {
            cam.x -= (fx * speed) >> 12;
            cam.z -= (fz * speed) >> 12;
        }
        if (pad1 & PAD_L1)
        {
            cam.x -= (cy * speed) >> 12;
            cam.z += (sy * speed) >> 12;
        }
        else if (pad1 & PAD_R1)
        {
            cam.x += (cy * speed) >> 12;
            cam.z -= (sy * speed) >> 12;
        }
        
        trSetCameraY(&tr, &cam, SCALE);
        
        gpuSortClear(0x808080);
        drawPSM(psmCharacter, &dataCharacter, &tr, 0);
        drawPSM(psmFloor, &dataFloor, &tr, 50);
        gpuEndFrame();
    }
}
