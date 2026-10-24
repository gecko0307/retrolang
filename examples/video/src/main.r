#import "retrolib.r"
#import "mdec.r"
#import "str.r"

// Global GPU config
struct GpuSettings gpu;

void main()
{
    padInit();
    spuInit();
    
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
    
    gpuWaitIdle();

    gpuClear(0x000000);
    
    mdecInit();
    cdInit();
    
    //strTrace = 1;
    //mdecTrace = 1;
    
    struct DirEntry vStream;
    if (cd_firstfile("cdrom:\\STR\\VIDEO.STR;1", &vStream) != 0)
    {
        printf("Playing STR...\n");
        strStart(vStream.lba);
    }
    
    int tick = 0;
    while (1)
    {
        strPoll();
        
        while (strFinished() == 0)
        {
            // Flip only when a new frame has been drawn into the back buffer
            if (strUpdate(0, displayOffset, MDEC_DEPTH_15BIT) == 1)
                gpuEndFrame();
        }
        strStop();
        
        // Normal game rendering here, after the end of the video...
    }
}
