module psx.exception;

// Exception types (as stored in the `CAUSE` register)
enum PsxException
{
    LoadAddressError = 0x4,  // Address error on load
    StoreAddressError = 0x5, // Address error on store
    SysCall = 0x8,           // System call (caused by the SYSCALL opcode)
    Break = 0x9,
    IllegalInstruction = 0xa,
    CoprocessorError = 0xb,
    Overflow = 0xc,          // Arithmetic overflow
}
