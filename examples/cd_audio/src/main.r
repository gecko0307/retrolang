#import "retrolib.r"

void main()
{
    padInit();
    spuInit();
    cdInit();
    
    cdPlayLoop(2);
    
    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
        cdUpdate();
    }
}
