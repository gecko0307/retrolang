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
 * Interrupts (WIP).
 */

#if import

#import "core.r"

int* I_STAT = 0x1F801070; // Interrupt status register
int* I_MASK = 0x1F801074; // Interrupt mask register

// This is only needed if you don't call padInit, which is unlikely.
void irqEnable()
{
    int sr = mfc0(COP0_SR);
    sr = sr | 0x0401; // Set IEc (bit 0) + IM2 (bit 10)
    mtc0(COP0_SR, sr);
}

//
void irqDisable()
{
    int sr = mfc0(COP0_SR);
    sr = sr & ~0x0001; // Clear IEc bit only
    mtc0(COP0_SR, sr);
}

//
int irqSave()
{
    int sr = mfc0(COP0_SR);
    mtc0(COP0_SR, sr & ~0x0001);
    return sr & 0x0001; // previous IEc
}

//
void irqRestore(int prev)
{
    if (prev)
        irqEnable();
}

#endif
