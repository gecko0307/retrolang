/**
 * Mesh rendering test
 */

#include "../../include/core.ri"
#include "../../include/pad.ri"
#include "../../include/gpu.ri"

#define F_ONE 0x1000

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

// Rotate/translate/perspective transform
struct RTPSTransform
{
    // Translation
    int tx;
    int ty;
    int tz;
    
    // 3x3 rotation matrix of Q3.12 elements
    short r[9];
    
    // Projection
    short h;
    int ofx;
    int ofy;
    short dqa;
    short dqb;
};

void gteInit() @("gteInit.s");
void gteRTPS(struct RTPSTransform* rtpsTransform, struct Vertex* inVertex, struct SVertex* outVertex) @("gteRTPS.s");

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

#define CUBE_NUM_VERTS 8
#define CUBE_NUM_TRIS 4

// Global GPU config
struct GpuSettings gpu;

char* textures @("assets/character.tim");
char* mesh @("assets/character.psm");

#define SCREEN_WIDTH 320
#define SCREEN_HEIGHT 240
#define HALF_SCR_WIDTH 160
#define HALF_SCR_HEIGHT 120

#define SCALE 0x2000

#define Z_NEAR 100
#define Z_SHIFT 0

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
    gteInit();
    
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
    tr.ty = 256;
    tr.tz = 700;
    tr.r[0] = SCALE;  tr.r[1] = 0x0000; tr.r[2] = 0x0000;
    tr.r[3] = 0x0000; tr.r[4] = SCALE;  tr.r[5] = 0x0000;
    tr.r[6] = 0x0000; tr.r[7] = 0x0000; tr.r[8] = SCALE;
    tr.h = 0x100;
    tr.ofx = 0x10000 * HALF_SCR_WIDTH;
    tr.ofy = 0x10000 * HALF_SCR_HEIGHT;
    tr.dqa = F_ONE;
    tr.dqb = 0x000;
    
    //
    char* p = mesh;
    
    struct PSMHeader* psm = (struct PSMHeader*)mesh;
    char* verts = p + 16;
    char* uvs = p + psm->uvOffset;
    char* indices = p + psm->idxOffset;
    
    uint uvOffset = ((16 + psm->numVerts * 8) + 3) & ~3;
    uint idxOffset = ((uvOffset + psm->numVerts * 2) + 3) & ~3;
    
    bios_a(0x3f, "psm->numVerts = %d\n", psm->numVerts);
    bios_a(0x3f, "psm->numTris = %d\n", psm->numTris);
    bios_a(0x3f, "psm->texWidth = %d\n", psm->texWidth);
    bios_a(0x3f, "psm->texHeight = %d\n", psm->texHeight);
    bios_a(0x3f, "psm->uvOffset = %d\n", psm->uvOffset);
    bios_a(0x3f, "uvOffset calculated = %d\n", uvOffset);
    bios_a(0x3f, "psm->idxOffset = %d\n", psm->idxOffset);
    bios_a(0x3f, "idxOffset calculated = %d\n", idxOffset);
    
    ushort vi1, vi2, vi3;
    
    struct Vertex* vertices = (struct Vertex*)verts;
    uchar* uvCoords = (uchar*)uvs;
    ushort* vIndices = (ushort*)indices;

    // A textured triangle
    struct GpuTriangle3 tri;
    tri.texture = &tex;
    tri.x1 = 0;
    tri.y1 = 0;
    tri.u1 = 0;
    tri.v1 = 0;
    tri.x2 = 0;
    tri.y2 = 0;
    tri.u2 = 0;
    tri.v2 = 0;
    tri.x3 = 0;
    tri.y3 = 0;
    tri.u3 = 0;
    tri.v3 = 0;
    tri.color = 0x808080;
    
    struct SVertex vout1;
    struct SVertex vout2;
    struct SVertex vout3;
    
    int speed = 10;
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
             if (pad1 & PAD_UP)    tr.tz -= speed;
        else if (pad1 & PAD_DOWN)  tr.tz += speed;
             if (pad1 & PAD_LEFT)  tr.tx += speed;
        else if (pad1 & PAD_RIGHT) tr.tx -= speed;
        
        gpuQueueClear(0x808080);
        
        for(int i = 0; i < psm->numTris; i++)
        {
            vi1 = vIndices[i * 3];
            vi2 = vIndices[i * 3 + 1];
            vi3 = vIndices[i * 3 + 2];
            
            struct Vertex* v1 = &vertices[vi1];
            struct Vertex* v2 = &vertices[vi2];
            struct Vertex* v3 = &vertices[vi3];
            gteRTPS(&tr, v1, &vout1);
            gteRTPS(&tr, v2, &vout2);
            gteRTPS(&tr, v3, &vout3);
            
            tri.x1 = vout1.x;
            tri.y1 = vout1.y;
            tri.u1 = uvCoords[vi1 * 2];
            tri.v1 = uvCoords[vi1 * 2 + 1];
            tri.x2 = vout2.x;
            tri.y2 = vout2.y;
            tri.u2 = uvCoords[vi2 * 2];
            tri.v2 = uvCoords[vi2 * 2 + 1];
            tri.x3 = vout3.x;
            tri.y3 = vout3.y;
            tri.u3 = uvCoords[vi3 * 2];
            tri.v3 = uvCoords[vi3 * 2 + 1];
            
            int z1 = vout1.z;
            int z2 = vout2.z;
            int z3 = vout3.z;
            // Near-plane rejection
            if (z1 < Z_NEAR || z2 < Z_NEAR || z3 < Z_NEAR)
                continue;
            int otz = (z1 + z2 + z3) / 3 >> Z_SHIFT;
            if (otz >= OT_SIZE - 1)
                continue; // Beyond far range, drop it
            gpuQueueDrawTriangle3(&tri, otz);
        }
        
        gpuEndFrame();
    }
}
