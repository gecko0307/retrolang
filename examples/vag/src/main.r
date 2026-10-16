#include "bios.ri"
#include "pad.ri"
#include "spu.ri"

uchar vagFile[] @("assets/camera.vag");

void main()
{
    padInit();
    spuInit();
    
    int sound = spuLoadVag(vagFile);
    int voice = spuPlay(sound, 0x3FFF);
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
        
        int playing = spuSoundPlaying(sound);

        if ((pad1 & PAD_CROSS) && !playing)
        {
            voice = spuPlay(sound, 0x3FFF);
        }
    }
}
