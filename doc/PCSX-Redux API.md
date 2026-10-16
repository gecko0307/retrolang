# PCSX-Redux MIPS API

Retrolang includes full support for [PCSX-Redux](https://github.com/grumpycoders/pcsx-redux) binary API that is described [here](https://pcsx-redux.consoledev.net/mips_api/). It allows PlayStation programs to communicate with the emulator for debugging purposes: show popup messages, add breakpoints, use memory sanitizer, and even execute Lua scripts!

## Functions

The following functions are available:

- `pcsx_putc(int c)` - Print ASCII character with code c to console/stdout.
- `pcsx_debugbreak()` - Break execution (Pause emulation).
- `pcsx_execSlot(uint8_t slot)` - Executes Lua function at PCSX.execSlots[slot]. The slot value can be between 1 and 255, as a slot value of 0 is pcsx_debugbreak(). If no Lua function exists within a slot, nothing happens.
- `pcsx_exit(int code)` - When the emulator was started with -testmode, exit the emulator and forward code as exit code. Otherwise, log the exit code and pause emulation.
- `pcsx_message(const char* msg)` - Create a UI dialog displaying msg
- `pcsx_checkKernel(int enable)` - Enable or disable kernel checking.
- `pcsx_isCheckingKernel()` - Returns truthy if kernel checking is enabled.
- `pcsx_present()` - Returns 1 if code is running in PCSX-Redux
- `pcsx_initMsan()` - Initialize memory sanitizer system.
- `pcsx_resetMsan()` - Reset memory sanitizer system.
- `pcsx_msanAlloc(uint32_t size)` - Allocate memory with memory sanitizer.
- `pcsx_msanFree(void* ptr)` - Free memory with memory sanitizer.
- `pcsx_msanRealloc(void* ptr, uint32_t size)` - Reallocate memory with memory sanitizer.
- `pcsx_registerHeapMetadata(const void* metadata)` - Register the address of the psyqo heap metadata, which is used by the PSYQo heap viewer.
