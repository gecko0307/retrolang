#include "bios.ri"
#include "pad.ri"
#include "spu.ri"

struct VAGHeader
{
    char magic[4];
    int version;
    int reserved1;
    int dataSize;
    int sampleRate;
    char reserved2[12];
    char name[16];
};

uint swapEndian(uint val) 
{
    return ((val >> 24) & 0xff) |
           ((val << 8)  & 0xff0000) |
           ((val >> 8)  & 0xff00) |
           ((val << 24) & 0xff000000);
}

uchar vagFile[] @("assets/camera.vag");

void main()
{
    padInit();
    spuInit();
    
    // Retrieve VAG info from the file header
    struct VAGHeader* vag = (struct VAGHeader*)vagFile;
    
    uint dataSize = swapEndian(vag->dataSize);
    uint sampleRate = swapEndian(vag->sampleRate);
    
    printf("magic = %s\n", vag->magic);
    printf("version = %d\n", swapEndian(vag->version));
    printf("dataSize = %d\n", dataSize);
    printf("sampleRate = %d\n", sampleRate);
    printf("name = %s\n", vag->name);

    // Load VAG to SPU RAM using byte address 0x5000
    // Internal loadVag logic will divide this by 8 to get block 0x0200
    uint spu_byte_addr = 0x5000;
    loadVag(vagFile + sizeof(struct VAGHeader), dataSize, spu_byte_addr);

    // Voice 0 start address (in 8-byte blocks -> 0x0200)
    *SPU_V0_START = spu_byte_addr / 8;

    // Voice 0 volume
    *SPU_V0_VOL_L = 0x3FFF;
    *SPU_V0_VOL_R = 0x3FFF;

    // ADSR settings
    *SPU_V0_ADSR1 = 0x00FF;
    *SPU_V0_ADSR2 = 0x0000;

    // Calculate pitch
    *SPU_V0_PITCH = (sampleRate * 4096) / 44100;

    *SPU_NON0  = 0x0000;
    *SPU_KOFF0 = 0x0001;
    *SPU_KON0  = 0x0001;
    
    int playing = 0;
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
        
        if (playing && (*SPU_ENDX & 0x0001))
            playing = 0;

        if ((pad1 & PAD_CROSS) && !playing)
        {
            *SPU_NON0 = 0x0000;
            *SPU_KON0 = 0x0001;
            playing = 1;
        }
    }
}
