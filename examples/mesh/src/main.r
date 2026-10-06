/**
 * Mesh rendering test
 */

#include "../../include/core.ri"
#include "../../include/pad.ri"
#include "../../include/gpu.ri"

#define F_ONE 0x1000

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

struct PSMData
{
    struct Vertex* vertices;
    uchar* uvs;
    ushort* indices;
    struct GpuTexture* texture;
    int color;
};

/**
 * Near clip distance.
 */
#define Z_NEAR 100

/**
 * Right-shift for Z values.
 * Used to compress depth to fit the OT capability.
 * Larger values -> larger clip distance, but less precision.
 * Smaller values -> smaller clip distance, but more precision.
 */
#define Z_SHIFT 2

void drawPSM(struct PSMHeader* psm, struct PSMData* data, struct RTPSTransform* tr)
{
    // GTE transformation result
    struct SVertex vout1;
    struct SVertex vout2;
    struct SVertex vout3;
    
    uint px = data->texture->px;
    uint py = data->texture->py;
    
    ushort vi1, vi2, vi3;
    int z1, z2, z3, otz;
    uint u, v;
    
    for (int i = 0; i < psm->numTris; i++)
    {
        vi1 = data->indices[i * 3];
        vi2 = data->indices[i * 3 + 1];
        vi3 = data->indices[i * 3 + 2];
        struct Vertex* v1 = &data->vertices[vi1];
        struct Vertex* v2 = &data->vertices[vi2];
        struct Vertex* v3 = &data->vertices[vi3];
        
        // TODO: use RTPT
        gteRTPS(tr, v1, &vout1);
        gteRTPS(tr, v2, &vout2);
        gteRTPS(tr, v3, &vout3);
        
        z1 = vout1.z;
        z2 = vout2.z;
        z3 = vout3.z;
        
        // Near-plane rejection
        if (z1 < Z_NEAR || z2 < Z_NEAR || z3 < Z_NEAR)
            continue;
        otz = (z1 + z2 + z3) / 3 >> Z_SHIFT;
        if (otz >= OT_SIZE - 1)
            continue; // Beyond far range, drop it
        int* p = gpuAllocZ(7, otz);
        if (p == 0) break;
        
        p[0] = GP0_TRI3 | data->color;
        p[1] = (vout1.y << 16) | (vout1.x & 0xffff);
        u = px + data->uvs[vi1 * 2];
        v = py + data->uvs[vi1 * 2 + 1];
        p[2] = ((uint)data->texture->clutId << 16) | (v << 8) | (u & 0xff);
        p[3] = (vout2.y << 16) | (vout2.x & 0xffff);
        u = px + data->uvs[vi2 * 2];
        v = py + data->uvs[vi2 * 2 + 1];
        p[4] = ((uint)data->texture->tpage << 16)  | (v << 8) | (u & 0xff);
        p[5] = (vout3.y << 16) | (vout3.x & 0xffff);
        u = px + data->uvs[vi3 * 2];
        v = py + data->uvs[vi3 * 2 + 1];
        p[6] = (v << 8) | (u & 0xff);
    }
}

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
    
    // Mesh data
    struct PSMHeader* psm = (struct PSMHeader*)mesh;
    struct PSMData data;
    char* meshStart = mesh;
    data.vertices = (struct Vertex*)(meshStart + 16);
    data.uvs = (uchar*)(meshStart + psm->uvOffset);
    data.indices = (ushort*)(meshStart + psm->idxOffset);
    data.texture = &tex;
    data.color = 0x808080;
    
    bios_a(0x3f, "psm->numVerts = %d\n", psm->numVerts);
    bios_a(0x3f, "psm->numTris = %d\n", psm->numTris);
    bios_a(0x3f, "psm->texWidth = %d\n", psm->texWidth);
    bios_a(0x3f, "psm->texHeight = %d\n", psm->texHeight);
    bios_a(0x3f, "psm->uvOffset = %d\n", psm->uvOffset);
    bios_a(0x3f, "psm->idxOffset = %d\n", psm->idxOffset);
    
    int speed = 10;
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
             if (pad1 & PAD_UP)    tr.tz -= speed;
        else if (pad1 & PAD_DOWN)  tr.tz += speed;
             if (pad1 & PAD_LEFT)  tr.tx += speed;
        else if (pad1 & PAD_RIGHT) tr.tx -= speed;
        
        gpuSortClear(0x808080);
        drawPSM(psm, &data, &tr);
        gpuEndFrame();
    }
}
