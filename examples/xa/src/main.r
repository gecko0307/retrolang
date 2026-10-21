#import "retrolib.r"

void main()
{
    padInit();
    spuInit();
    cdInit();
    
    struct DirEntry xaStream;
    if (cd_firstfile("cdrom:\\MUSIC\\FILE0.XA;1", &xaStream) != 0)
    {
        printf("Playing XA stream...\n");
        cdPlayXA(xaStream.lba, 0, 0); // play file 0, channel 0
    }
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
        cdXaUpdate();
    }
}
