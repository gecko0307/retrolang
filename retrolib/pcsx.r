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
 * PCSX-Redux debug API.
 * https://pcsx-redux.consoledev.net/mips_api/
 */

/// Prints ASCII character with code c to emulator's stdout.
macro pcsx_putc(c)
{
    *PCSX_IO = c;
}

/// Breaks execution.
macro pcsx_debugbreak()
{
    *PCSX_BREAK = 0;
}

/**
 * Executes Lua function at PCSX.execSlots[slot].
 * The slot value can be between 1 and 255, as a slot value of 0 is pcsx_debugbreak().
 * If no Lua function exists within a slot, nothing happens.
 */
macro pcsx_execSlot(slot)
{
    *PCSX_EXECSLOT = slot;
}

/**
 * When the emulator was started with -testmode, exit the emulator and forward code as exit code.
 * Otherwise, log the exit code and pause emulation.
 */
macro pcsx_exit(code)
{
    *PCSX_EXIT = code;
}

/// Create a UI dialog displaying msg.
macro pcsx_message(msg)
{
    *PCSX_MESSAGE = msg;
}

/// Enable or disable kernel checking.
macro pcsx_checkKernel(enable)
{
    *PCSX_CHECKKERNEL = enable;
}

/// Returns 1 if kernel checking is enabled.
macro pcsx_isCheckingKernel(enable) = (*PCSX_CHECKKERNEL != 0);

/// Returns 1 if code is running in PCSX-Redux.
macro pcsx_present() = (*(uint*)PCSX_IO == 0x58534350);

/*
 * Memory sanitizer
 */

/// Initialize memory sanitizer system.
macro pcsx_initMsan()
{
    *PCSX_MSAN_CTRL = 0;
}

/// Reset memory sanitizer system.
macro pcsx_resetMsan()
{
    *PCSX_MSAN_CTRL = 1;
}

/// Register the address of the PSYQo heap metadata, which is used by the PSYQo heap viewer.
macro pcsx_registerHeapMetadata(metadata)
{
    *(void*)PCSX_MSAN_HEAP_META = metadata;
}

#if import

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

#endif
