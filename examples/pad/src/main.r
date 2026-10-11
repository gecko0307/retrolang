/**
 * Gamepad test.
 * Prints pressed buttons to TTY
 */

#include "bios.ri"
#include "pad.ri"

void main()
{
    padInit();

    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();

             if (pad1 & PAD_UP)       printf("UP\n");
        else if (pad1 & PAD_DOWN)     printf("DOWN\n");
        else if (pad1 & PAD_LEFT)     printf("LEFT\n");
        else if (pad1 & PAD_RIGHT)    printf("RIGHT\n");
        else if (pad1 & PAD_CIRCLE)   printf("CIRCLE\n");
        else if (pad1 & PAD_CROSS)    printf("CROSS\n");
        else if (pad1 & PAD_SQUARE)   printf("SQUARE\n");
        else if (pad1 & PAD_TRIANGLE) printf("TRIANGLE\n");
        else if (pad1 & PAD_L1)       printf("L1\n");
        else if (pad1 & PAD_L2)       printf("L2\n");
        else if (pad1 & PAD_R1)       printf("R1\n");
        else if (pad1 & PAD_R2)       printf("R2\n");
        else if (pad1 & PAD_SELECT)   printf("SELECT\n");
        else if (pad1 & PAD_START)    printf("START\n");
    }
}
