# CPU

The PlayStation's CPU is the MIPS R3000, a 32-bit RISC microprocessor implementing the MIPS-I ISA. The CPU operates at a frequency of 33.87 MHz, features 4 KiB of instruction cache, and lacks a data cache (using instead 1 KiB of "fast memory" known as Scratchpad).

## Registers

The R3000 has 32 general-purpose registers:

- `$r0` - always zero
- `$at` - temporary data for certain assembler pseudo-instructions
- `$v0`..`$v1` - procedure return values
- `$a0`..`$a3` - procedure arguments
- `$t0`..`$t7` - variables
- `$s0`..`$s7` - static procedure variables
- `$t8`..`$t9` - temporaries (variables)
- `$k0`..`$k1` - reserved for BIOS
- `$gp` - global pointer
- `$sp` - stack pointer; holds the first free address on the stack
- `$fp` - frame pointer
- `$ra` - return address; jumping to this address returns from the procedure.

## Instructions

TODO
