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

#define DMA_DPCR            0x1f8010f0
#define DMA_DICR            0x1f8010f4

#define DMA_CH2_MADR        0x1f8010a0
#define DMA_CH2_BCR         0x1f8010a4
#define DMA_CH2_CHCR        0x1f8010a8
#define DMA_CH2_ENABLE      0x00000800
#define DMA_CH2_LIST_START  0x01000401 // RAM -> GPU, linked list, start
#define DMA_CH2_BLOCK_START 0x01000201 // RAM -> GPU, block (request) mode, start

#define DMA_CH4_MADR        0x1f8010c0
#define DMA_CH4_BCR         0x1f8010c4
#define DMA_CH4_CHCR        0x1f8010c8

#define DMA_BUSY            0x01000000

// Waits until the DMA channel is idle.
macro dmaWait(channel)
{
    while ((*channel & DMA_BUSY) != 0) {}
}

#if import

#import "core.r"

// DMA control (channel enables / priorities)
int* dmaDpcr = DMA_DPCR;

// DMA ports
int* dma2Madr = DMA_CH2_MADR; // channel 2: base address
int* dma2Bcr  = DMA_CH2_BCR;  // channel 2: block control
int* dma2Chcr = DMA_CH2_CHCR; // channel 2: channel control

int* dma4Madr = DMA_CH4_MADR; // channel 4: base address
int* dma4Bcr  = DMA_CH4_BCR;  // channel 4: block control
int* dma4Chcr = DMA_CH4_CHCR; // channel 4: channel control

#endif
