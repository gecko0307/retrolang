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
 * Interrupts API.
 */

// Interrupt status bits (in I_STAT/I_MASK)
macro IRQ_VBLANK = (1 << 0);  // PAL = 50 Hz, NTSC = 60 Hz
macro IRQ_GPU    = (1 << 1);  // Can be requested via GP0(1Fh) command
macro IRQ_CDROM  = (1 << 2);  // 
macro IRQ_DMA    = (1 << 3);  // 
macro IRQ_TMR0   = (1 << 4);  // Timer 0
macro IRQ_TMR1   = (1 << 5);  // Timer 1
macro IRQ_TMR2   = (1 << 6);  // Timer 2
macro IRQ_ACK    = (1 << 7);  // Pad/memcard acknowledgement
macro IRQ_SIO    = (1 << 8);  // 
macro IRQ_SPU    = (1 << 9);  // 
macro IRQ_GUN    = (1 << 10); // Lightgun input

#if import

#import "core.r"

// Interrupt handler (used by sysEnqIntRP/sysDeqIntRP)
struct IntRP
{
    struct IntRP* next; // next IntRP in the linked list
    void* func2; // executed if func1 returns != 0
    void* func1; // executed first
    int flag; // should be zero
};

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
