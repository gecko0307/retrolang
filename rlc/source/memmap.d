module memmap;

// All addresses in KSEG0

enum uint RAM_BASE = 0x80000000;
enum uint RAM_SIZE = 2 * 1024 * 1024;
enum uint RAM_END  = RAM_BASE + RAM_SIZE;

enum uint BIOS_SIZE = 64 * 1024;
enum uint EXE_HEADER_SIZE = 2 * 1024;
enum uint LOAD_ADDR = RAM_BASE + BIOS_SIZE;
enum uint HEADER_ADDR = LOAD_ADDR - EXE_HEADER_SIZE;
enum uint RAM = LOAD_ADDR;
enum uint RAM_LENGTH  = RAM_SIZE - BIOS_SIZE;
enum uint STACK_ADDR = RAM_BASE + 0x001FFF00;
enum uint STACK_SIZE = 64 * 1024; // TODO: configurable stack size
enum uint SCRATCHPAD_BASE = 0x9F800000;
enum uint SCRATCHPAD_SIZE = 1024;
