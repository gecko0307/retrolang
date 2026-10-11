# Static Allocator

Because PlayStation 1 has very limited fixed-size RAM, we recommend to avoid non-deterministic dynamic allocations and use a statically defined memory layout. Retrolang provides a language-level semantic that makes this a easier: memory regions. You can split available memory into large fixed-size chunks and statically allocate your buffers/arrays there. The compiler will calculate offsets and check collisions between regions and reserved areas.

```c
macro REGION1 = (0x80180000, 160);

int buffer1[20] @REGION1;
int buffer2[20] @REGION1;
```

You can achieve the same with ordinary static variables that are embedded to the data section, but that will bloat the executable, which is undesirable in some scenarios (like booting via FreePSXBoot exploit). Also region allocator supports the Scratchpad:

```c
int buffer1[20] @SCRATCHPAD;
```

## Available RAM

You can use any regions of the main RAM (2 MiB) unoccupied with

- BIOS workspace: base `0x80000000`, 64 KiB
- Executable: base `0x80010000`, X KiB
- Stack: base `0x801FFF00`, 64 KiB.

Retrolang examples that use the GPU also reserve the following regions for internal buffers:

- Command buffer 0: base `0x80180000`, 32 KiB
- Command buffer 1: base `0x80188000`, 32 KiB
- Ordering table 0: base `0x80190000`, 8 KiB
- Ordering table 1: base `0x80192000`, 8 KiB.

Static allocator requires all addresses in KSEG0 (base 0x80000000). To convert an address given in other segment, use `TO_KSEG0` macro from `core.ri`:

```c
#include "core.ri"

macro REGION1 = (TO_KSEG0(0x1F180000), 160);
```

Region (both its base address and size) should be aligned to 4 bytes. All allocations inside of a region are also aligned to 4 bytes.
