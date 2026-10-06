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
void gteRTPT(struct RTPSTransform* rtpsTransform, struct Vertex* inVertices, struct SVertex* outVertices) @("gteRTPT.s");

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

void drawPSM(struct PSMHeader* psm, struct PSMData* data, struct RTPSTransform* tr)
{
    // GTE transformation input and output
    struct Vertex triVertices[3];
    struct SVertex projected[3];
    
    uint px = data->texture->px + data->tilex;
    uint py = data->texture->py + data->tiley;
    
    ushort vi1, vi2, vi3;
    int z1, z2, z3, otz;
    uint u, v;
    ushort* indices = data->indices;
    uchar* uvs = data->uvs;
    struct Vertex* vertices = data->vertices;
    
    uint clutId = (uint)data->texture->clutId << 16;
    uint tpage = (uint)data->texture->tpage << 16;
    
    for (int i = 0; i < psm->numTris; i++)
    {
        vi1 = indices[i * 3];
        vi2 = indices[i * 3 + 1];
        vi3 = indices[i * 3 + 2];
        struct Vertex* v1 = &vertices[vi1];
        struct Vertex* v2 = &vertices[vi2];
        struct Vertex* v3 = &vertices[vi3];
        
        triVertices[0] = *v1;
        triVertices[1] = *v2;
        triVertices[2] = *v3;
        gteRTPT(tr, triVertices, projected);
        
        if (projected[0].x < 0 && projected[1].x < 0 && projected[2].x < 0)
            continue;
        if (projected[0].x >= SCREEN_WIDTH && projected[1].x >= SCREEN_WIDTH && projected[2].x >= SCREEN_WIDTH)
            continue;
        if (projected[0].y < 0 && projected[1].y < 0 && projected[2].y < 0)
            continue;
        if (projected[0].y >= SCREEN_HEIGHT && projected[1].y >= SCREEN_HEIGHT && projected[2].y >= SCREEN_HEIGHT)
            continue;
        
        z1 = projected[0].z;
        z2 = projected[1].z;
        z3 = projected[2].z;
        
        // Near-plane rejection
        if (z1 < Z_NEAR || z2 < Z_NEAR || z3 < Z_NEAR)
            continue;
        otz = (z1 + z2 + z3) / 3 >> Z_SHIFT;
        if (otz >= OT_SIZE - 1 || otz < 0)
            continue; // Beyond the depth range
        int* p = gpuAllocZ(7, otz);
        if (p == 0) break;
        
        p[0] = GP0_TRI3 | data->color;
        p[1] = (projected[0].y << 16) | (projected[0].x & 0xffff);
        u = px + uvs[vi1 * 2];
        v = py + uvs[vi1 * 2 + 1];
        p[2] = clutId | (v << 8) | (u & 0xff);
        p[3] = (projected[1].y << 16) | (projected[1].x & 0xffff);
        u = px + uvs[vi2 * 2];
        v = py + uvs[vi2 * 2 + 1];
        p[4] = tpage  | (v << 8) | (u & 0xff);
        p[5] = (projected[2].y << 16) | (projected[2].x & 0xffff);
        u = px + uvs[vi3 * 2];
        v = py + uvs[vi3 * 2 + 1];
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

#define F_ONE 0x1000

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
    tr.ty = 0;
    tr.tz = 0;
    trSetRotationIdentity(&tr);
    tr.h = 0x100;
    tr.ofx = 0x10000 * HALF_SCR_WIDTH;
    tr.ofy = 0x10000 * HALF_SCR_HEIGHT;
    tr.dqa = F_ONE;
    tr.dqb = 0x000;
    
    // Floor mesh data
    struct PSMHeader* psmFloor = (struct PSMHeader*)floor;
    struct PSMData dataFloor;
    char* meshStart = floor;
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
    int yawSpeed = 20;
    
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
        drawPSM(psmCharacter, &dataCharacter, &tr);
        drawPSM(psmFloor, &dataFloor, &tr);
        gpuEndFrame();
    }
}
