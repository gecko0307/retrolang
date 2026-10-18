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
 * PCSX-Redux debug API (implementation module).
 * https://pcsx-redux.consoledev.net/mips_api/
 */

#include "pcsx.ri"

int* SBUS_DEV0_ADDR  = 0x1F801000;
int* SBUS_DEV8_ADDR  = 0x1F801004;
int* SBUS_DEV0_CTRL  = 0x1F801008;
int* SBUS_DEV1_CTRL  = 0x1F80100C;
int* SBUS_DEV2_CTRL  = 0x1F801010;
int* SBUS_DEV4_CTRL  = 0x1F801014;
int* SBUS_DEV5_CTRL  = 0x1F801018;
int* SBUS_DEV8_CTRL  = 0x1F80101C;
int* SBUS_COM_CTRL   = 0x1F801020;

// PCSX MMIO
char*  PCSX_IO          = 0x1F802080;
char*  PCSX_BREAK       = 0x1F802081;
uchar* PCSX_EXECSLOT    = 0x1F802081;
short* PCSX_EXIT        = 0x1F802082;
char** PCSX_MESSAGE     = 0x1F802084;
char*  PCSX_CHECKKERNEL = 0x1F802088;

/**
 * PCSX-Redux API needs DEV8/EXP2 (1f802000 to 1f80207f),
 * which holds the hardware register for the BIOS POST status,
 * to be expanded to 1f8020ff.
 */
void pcsx_init()
{
    int size = *SBUS_DEV8_CTRL;
    while (size < 0x80000)
        size++;
    *SBUS_DEV8_CTRL = size;
}

/*
 * Memory sanitizer
 */

char* PCSX_MSAN_CTRL      = 0x1F802089;
char* PCSX_MSAN_HEAP_META = 0x1F8020A0;
int*  PCSX_MSAN_ALLOC     = 0x1F80208C; // read = alloc, write = free
int*  PCSX_MSAN_REALLOC   = 0x1F802090;
int*  PCSX_MSAN_CHAIN     = 0x1F802094;

/// Allocates memory with memory sanitizer.
void* pcsx_msanAlloc(uint size)
{
    return *(void**)PCSX_MSAN_ALLOC;
}

/// Frees memory with memory sanitizer.
void pcsx_msanFree(void* ptr)
{
    *(void**)PCSX_MSAN_ALLOC = ptr;
}

/// Reallocates memory with memory sanitizer.
void* pcsx_msanRealloc(void* ptr, uint size)
{
    return *(void**)PCSX_MSAN_REALLOC;
}

///
void pcsx_msanSetChainPtrRaw(void* ptrToNext, uint wordCount, void* headerAddr)
{
    *(void**)PCSX_MSAN_CHAIN = headerAddr;
}

///
void pcsx_msanSetChainPtr(void* headerAddr, void* ptrToNext, uint wordCount)
{
    pcsx_msanSetChainPtrRaw(ptrToNext, wordCount, headerAddr);
}

///
void* pcsx_msanGetChainPtr(void* headerAddr)
{
    return *(void**)PCSX_MSAN_CHAIN;
}
