/**
 * GTE triangle transformation test
 */

#include "../../include/core.ri"
#include "../../include/pad.ri"
#include "../../include/gpu.ri"

#define F_ONE 0x1000

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
void gteRTPS(struct RTPSTransform* rtpsTransform, short* inVertex, struct SVertex* outVertex) @("gteRTPS.s");

short v1[4] = { -50, -200,   0, 0 };
short v2[4] = { -50,  200,   0, 0 };
short v3[4] = { -50,  200, 400, 0 };
short v4[4] = { -50, -200, 400, 0 };

// Global GPU config
struct GpuSettings gpu;

#define SCREEN_WIDTH 320
#define SCREEN_HEIGHT 240
#define HALF_SCR_WIDTH 160
#define HALF_SCR_HEIGHT 120

#define SCALE 0x1000
//0x7000
#define HARDWARE_NEAR_PLANE 20

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
    
    struct RTPSTransform tr;
    tr.tx = 0;
    tr.ty = 0;
    tr.tz = 256;
    tr.r[0] = SCALE;  tr.r[1] = 0x0000; tr.r[2] = 0x0000;
    tr.r[3] = 0x0000; tr.r[4] = SCALE;  tr.r[5] = 0x0000;
    tr.r[6] = 0x0000; tr.r[7] = 0x0000; tr.r[8] = SCALE;
    tr.h = 0x100;
    tr.ofx = 0x10000 * HALF_SCR_WIDTH;
    tr.ofy = 0x10000 * HALF_SCR_HEIGHT;
    tr.dqa = F_ONE;
    tr.dqb = 0x000;

    // Draws a shaded triangle
    struct GpuTriangle2 tri;
    tri.x1 = 0;
    tri.y1 = 0;
    tri.color1 = 0x000000ff; // red
    tri.x2 = 0;
    tri.y2 = 0;
    tri.color2 = 0x0000ff00; // green
    tri.x3 = 0;
    tri.y3 = 0;
    tri.color3 = 0x00ff0000; // blue
    
    struct SVertex vout1;
    struct SVertex vout2;
    struct SVertex vout3;
    struct SVertex vout4;
    
    int speed = 10;

    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
             if (pad1 & PAD_UP)    tr.tz -= speed;
        else if (pad1 & PAD_DOWN)  tr.tz += speed;
             if (pad1 & PAD_LEFT)  tr.tx += speed;
        else if (pad1 & PAD_RIGHT) tr.tx -= speed;
        
        gteRTPS(&tr, v1, &vout1);
        gteRTPS(&tr, v2, &vout2);
        gteRTPS(&tr, v3, &vout3);
        gteRTPS(&tr, v4, &vout4);
        
        gpuQueueClear(0x808080);
        
        tri.x1 = vout1.x;
        tri.y1 = vout1.y;
        tri.x2 = vout2.x;
        tri.y2 = vout2.y;
        tri.x3 = vout3.x;
        tri.y3 = vout3.y;
        gpuQueueDrawTriangle2(&tri);
        
        tri.x1 = vout1.x;
        tri.y1 = vout1.y;
        tri.x2 = vout4.x;
        tri.y2 = vout4.y;
        tri.x3 = vout3.x;
        tri.y3 = vout3.y;
        gpuQueueDrawTriangle2(&tri);
        
        gpuEndFrame();
    }
}
