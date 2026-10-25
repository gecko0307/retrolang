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

/*
 * STR video playback example.
 */

#import "retrolib.r"

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
    
    strTrace = 0;
    mdecTrace = 0;
    
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
