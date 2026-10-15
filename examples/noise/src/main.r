/**
 * Minimal SPU noise test.
 */

#include "retrolib.ri"

ushort* SPU_V0_VOL_L = 0x1F801C00;
ushort* SPU_V0_VOL_R = 0x1F801C02;
ushort* SPU_V0_START = 0x1F801C06;
ushort* SPU_V0_ADSR1 = 0x1F801C08;
ushort* SPU_V0_ADSR2 = 0x1F801C0A;

ushort* SPU_MVOL_L   = 0x1F801D80;
ushort* SPU_MVOL_R   = 0x1F801D82;

ushort* SPU_KON0     = 0x1F801D88;
ushort* SPU_NON0     = 0x1F801D94;
ushort* SPU_CTRL     = 0x1F801DAA;

void main()
{
    padInit();

    // Enable SPU, unmute, configure noise clock
    *SPU_CTRL = 0xEA30;

    // Master volume
    *SPU_MVOL_L = 0x3FFF;
    *SPU_MVOL_R = 0x3FFF;

    /*
     * Voice 0 start address.
     * Not actually used for noise output,
     * but this is part of the known working test
     */
    *SPU_V0_START = 0x1010;

    // Voice 0 volume
    *SPU_V0_VOL_L = 0x3FFF;
    *SPU_V0_VOL_R = 0x3FFF;

    // ADSR
    *SPU_V0_ADSR1 = 0xBF3F;
    *SPU_V0_ADSR2 = 0xCFFF;

    // Voice 0 uses noise generator
    *SPU_NON0 = 0x0001;

    // Start voice 0
    *SPU_KON0 = 0x0001;

    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
    }
}
