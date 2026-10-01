/**
 * Gamepad test.
 * Prints pressed buttons to TTY
 */

#include "pad.ri"

void main()
{
    padInit();

    while(1)
    {
        padWaitVSync();
        
        int pad1 = padRead1();

             if (pad1 & PAD_UP)       bios_a(0x3f, "UP\n");
        else if (pad1 & PAD_DOWN)     bios_a(0x3f, "DOWN\n");
        else if (pad1 & PAD_LEFT)     bios_a(0x3f, "LEFT\n");
        else if (pad1 & PAD_RIGHT)    bios_a(0x3f, "RIGHT\n");
        else if (pad1 & PAD_CIRCLE)   bios_a(0x3f, "CIRCLE\n");
        else if (pad1 & PAD_CROSS)    bios_a(0x3f, "CROSS\n");
        else if (pad1 & PAD_SQUARE)   bios_a(0x3f, "SQUARE\n");
        else if (pad1 & PAD_TRIANGLE) bios_a(0x3f, "TRIANGLE\n");
        else if (pad1 & PAD_L1)       bios_a(0x3f, "L1\n");
        else if (pad1 & PAD_L2)       bios_a(0x3f, "L2\n");
        else if (pad1 & PAD_R1)       bios_a(0x3f, "R1\n");
        else if (pad1 & PAD_R2)       bios_a(0x3f, "R2\n");
        else if (pad1 & PAD_SELECT)   bios_a(0x3f, "SELECT\n");
        else if (pad1 & PAD_START)    bios_a(0x3f, "START\n");
    }
}
