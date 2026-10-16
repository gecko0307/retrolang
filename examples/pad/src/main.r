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

/**
 * Gamepad test.
 * Prints pressed buttons to TTY
 */

#include "retrolib.ri"

void main()
{
    padInit();

    while(1)
    {
        padWaitSync();
        int pad1 = padRead1();
        int axisX = padAxis(_pad_lx);
        int axisY = padAxis(_pad_ly);

        if (axisX != 0) printf("Left x-axis: %d\n", axisX);
        if (axisY != 0) printf("Left y-axis: %d\n", axisY);

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
