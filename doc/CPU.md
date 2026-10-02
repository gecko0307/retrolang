# CPU

The PlayStation's CPU is the MIPS R3000, a 32-bit RISC microprocessor implementing the MIPS-I ISA. The CPU operates at a frequency of 33.87 MHz, features 4 KiB of instruction cache, and lacks a data cache (using instead 1 KiB of "fast memory" known as Scratchpad).

## Registers

The R3000 has 32 general-purpose registers:

- $0 - r0 - always zero
- $1 - at - temporary data for certain assembler pseudo-instructions
- $2..$3 - v0..v1 - procedure return values
- $4..$7 - a0..a3 - procedure arguments
- $8..$15 - t0..t7 - variables
- $16..$23 - s0..s7 - static procedure variables
- $24..$25 - t8..t9 - variables
- $26..$27 - k0..k1 - reserved for BIOS
- $28 - gp - global pointer
- $29 - sp - stack pointer; holds the first free address on the stack
- $30 - fp/s8 - frame pointer
- $31 - ra - return address; jumping to this address returns from the procedure.

Special registers:

- hi, lo – result of integer multiplication/division (upper and lower parts)
- pc – program counter.

O32 ABI:

- $2..$3 (v0..v1) – return values
- $4..$7 (a0..a3) – arguments
- $29 – stack pointer
- $31 – return address.

If a function uses more than four 32-bit arguments, the 5th argument and subsequent ones are placed on the stack.
