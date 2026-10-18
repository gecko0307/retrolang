# Retrolang SDK

<img align="left" alt="controller" src="https://raw.githubusercontent.com/gecko0307/retrolang/main/media/controller.png" height="127px" style="image-rendering:pixelated" />

The goal of this project is to build a PlayStation 1 development toolchain completely from scratch, without relying on GCC, LLVM, or other similar compiler frameworks. It features a low-level C-like language, Retrolang, that compiles to MIPS R3000 machine code.

Retrolang tools are written entirely in [D language](https://dlang.org/).

What can you do with Retrolang (in more or less convenient ways):

- Render 2D and 3D graphics via command buffers and the DMA
- Upload TIM files to VRAM
- Work with the GTE
- Query the gamepad buttons and analog sticks
- Load files from the CD-ROM
- Play VAG sounds
- Play CDDA tracks
- Access memory cards
- Work with the BIOS.

All provided software is experimental and is in alpha stage.

## Screenshots

Platformer game example:

![Platformer](media/platformer.png)

3D rendering example:

![3D scene](media/3d_scene.png)

## Rationale

Retrolang is a result of 10+ years of tinkering with the console, different SDKs, custom GPU libraries and related tools. It was initially created as an assembler, but eventually got many improvements. I always wanted to write my own programs for PSX, but the tooling was frustratingly clunky, so I eventually decided to make my own everything, right down to the machine code.

Main philosophy of the project: PSX programming doesn't require a full-fledged C with all of its baggage. A subset is sufficient. What's really needed are platform-specific language capabilities, as well as a simple, readable and easily hackable standard library. Popular C toolchains also tend to be bulky; Retrolang produces tiny executables that can run via [FreePSXBoot](https://github.com/brad-lin/FreePSXBoot).

Unlike C, Retrolang is a language with **predictable semantics**. The compiler translates your program verbatim, without optimizations and unexpected changes behind your back, which is important for bare-metal programming. For example, it doesn't implicitly inline functions and optimize memory access. You are solely responsible for writing good-quality code and using the console's limited resources wisely.

Project goals:
- Provide a convenient domain-specific language as a trade-off between C and assembly for hobby R3000 programming with straightforward, unhindered hardware access;
- Provide modern, open, self-contained x86_64 replacements for legacy tools;
- Provide a clean-room SDK that doesn't depend on a single byte of proprietary software.

## RLC

The main tool is RLC, the Retrolang Compiler. It combines an assembler, compiler, and a linker in a single program and directly outputs `PSX.EXE`.

Usage:

```
rlc -o PSX.EXE src/main.r
```

RLC builds all source modules together in one pass; it does not produce object files or support incremental builds. Use top-level `import "file.r";` declarations to organize a program across source files. Modules compile once, dependency-first, into the same program and global namespace. Use C-like `#include`s for textual inclusion, especially shared headers and macros; `.ri` is the recommended extension for included files.

Assembling command is similar (RLC treats *.s file as an assembly source):

```
rlc -o PSX.EXE src/main.s
```

## PSXDISASM

Work-in-progress dumper and disassembler for PsyQ LNK *.obj files and PSX-EXE files. Based on [LNK disassembler](https://github.com/gecko0307/psxlib/tree/main/tools/psxdisasm) from PSXLib.

## png2tim

A simple PNG to TIM converter.

## Retrobuild

Build automation system. With Retrobuild, you don't have to call the compiler directly or write platform-specific scripts. It compiles a project, packs it into a CD-ROM image (CUE+BIN) using [mkpsxiso](https://github.com/lameguy64/mkpsxiso), and generates a CU2 sector index for [PSIO](https://psio.cybdyn-systems.com.au/). Uses TOML manifest files (`retrobuild.toml`) to describe projects.

## The Language

Retrolang can be called "C from an alternate universe". It is a simple curly-bracket procedural language largely inspired by C, but based on a different architectural decisions and designed to run in extremely memory-constrained environments.

**Primitive types**: `int`, `short`, `char`, `uint`, `ushort`, `uchar`, `void`, and pointers to them. Pointers compare as unsigned. Literals above `0x7FFFFFFF`, or with a 'u' suffix, are unsigned. Like C, `uchar`/`ushort` promote to (signed) `int` in arithmetic; only `uint` makes `/`, `%`, `>>` and comparisons unsigned. C-style type casts are supported.

**Arrays**: C-like static arrays and strings:

```c
int t[4] = {1, 2, 3, 4};
char hello[] = "Hello!";
```

Constant initialization is supported only for global arrays.

**Structs**: top-level definitions `struct Name { int a; uchar c[3]; };`. Used as `struct Name x;`. Fields may be scalars, pointers, arrays or nested structs. Structs can be copied with `=` (inline, up to 32 words), have their address taken, and be measured with `sizeof(struct Name)`. Not supported: struct initializers, passing/returning structs by value, unions, bit-fields, `typedef`, `sizeof(expression)`.

**Operators**: all basic arithmetic, logical and bitwise operators are supported. Retrolang uses C precedence.

**Statements**: `if`/`else`, `while`, `do`-`while`, `for`, `break`, `continue`, `return`.

**Function calls**: follows O32 ABI. Supports up to 4 arguments (passed in `$a0`-`$a3`), result in `$v0`.

**Program entry point**: `main()`, started from a small stub that sets `$sp`.

**Modules**: RLC implements a [unity-build](https://en.wikipedia.org/wiki/Unity_build) compilation method which is a trade-off between C-style `#include` and a full-featured module system. There are no symbol tables or module-local scopes; the program is a single bundle with one global scope. The `import "file.r"` directive adds a module into the bundle, ensuring each module is parsed only once. AST macros and `#define` directives are not exported between modules; use `#include "file.ri"` for shared definitions.

**BIOS intrinsics**: `bios_a(n, ...)`, `bios_b(n, ...)`, `bios_c(n, ...)` through the `A0h`/`B0h`/`C0h` vectors with up to 3 further arguments. `n` is a function number which is passed in `$t1` register.

**GTE intrinsics**: `gte_enable`, `gte_ctc2`, `gte_mtc2`, `gte_rtpt` and others.

**Embedded files**: a global array can have an attribute `@("file.bin")` to embed a file to the executable.

**Inline assembly**: functions can contain `asm` blocks with Retrolang assembly language code.

**AST macros**: abstract, reusable expressions and statements. Retrolang supports expresson macros, parametrized expresson macros, list macros (tuples), and statement macros. They are useful for defining constants, inlining performance-critical functions and GTE command blocks.

**Static allocator**: a global array can be placed in an arbitrary region of available RAM using the region attribute: `@(0x80180000, 1024)`. Regions work like static arenas: the compiler automatically bumps offset for a new allocation that shares the region base address with existing allocation. List macros can be used to identify regions. Base addresses must be given in KSEG0.

**Code generation notes:**

- Local variables live in `$s0`-`$s7` (callee-saved) unless their address is taken, in which case (or when registers run out) they live in the stack frame.
- Expression temporaries use `$t0`-`$t9` as a register stack. Live temporaries are saved around calls.

**Example program:**

```c
#include "retrolib.ri"

void main()
{
    printf("Hello, World!\n");
}
```

The same in Retrolang assembly language:

```asm
.text
    li $a0, .msg
    li $t1, 0x003f
    li $t2, 0x00a0
    jr $t2
    nop
    
    jr $ra
    nop

.data
  .msg:
    "Hello, World!\n\0"
```

See [doc folder](/doc) for more details on the language.

## Retrolib Standard Library

Retrolang provides a minimal set of optional low-level functionality that aid with writing PlayStation programs. Retrolib is a successor of [PSXLib project](https://github.com/gecko0307/psxlib).

* `retrolib.ri` - imports entire library at once (recommended)
* `core.ri` - core definitions
* `bios.ri` - macros for some common BIOS calls
* `dma.r` - DMA API
* `pad.r` + `pad.ri` - gamepad driver
* `gpu.r` + `gpu.ri` - GPU driver / graphics API
* `spu.r` + `spu.ri` - SPU driver / sound API
* `cd.r` - CD audio API
* `save.r` + `save.ri` - memry card save/load API
* `pcsx.r` + `pcsx.ri` - PCSX-Redux API.

Usage (assuming you've pointed RLC to `retrolib` as an include directory):

```c
#include "retrolib.ri"
```

## Examples Collection

`examples` directory contains a number of basic demos showcasing possibilities of RLC.

- [asm](/examples/asm) - "Hello, World" program implemented in assembly language
- [external_asm](/examples/external_asm) - external assembly function example (printing an argument to TTY and returning a value)
- [pad](/examples/pad) - gamepad test, logs pressed buttons to TTY
- [triangle](/examples/triangle) - classic colored triangle demo (direct rendering via GP0)
- [dma](/examples/dma) - classic colored triangle demo (queued rendering via command buffer)
- [sprite](/examples/sprite) - TIM texture loading and sprite rendering (direct rendering via GP0)
- [text](/examples/text) - bitmap font loading and text rendering (queued rendering via command buffer)
- [platform_game](/examples/platform_game) - 2D platform game
- [mesh](/examples/mesh) - walkable 3D scene with a first person camera
- [memcard](/examples/memcard) - memory card reading and writing
- [vag](/examples/vag) - VAG sound playback example.

All examples support building with Retrobuild. RLC must be available system-wide or locally as `/rlc/rlc.exe` in the repository. Optionally, to build a CD-ROM image, mkpsxiso must be available system-wide or locally as `/mkpsxiso/mkpsxiso.exe` in the repository.

## Recommended Tools

Provided examples rely on the following third-party tools:

- [mkpsxiso by Lameguy64](https://github.com/lameguy64/mkpsxiso) to build CD-ROM images
- [PSX License Tool](https://github.com/jbreckmckye/psx-license-tool) to patch BIN files with your own license data
- [psxavenc](https://github.com/WonderfulToolchain/psxavenc) to convert WAV files to VAG format
- [Blender](https://blender.org) to export meshes to PSM format.

For running examples on the PC, we recommend [DuckStation](https://www.duckstation.org/), a fast and feature-rich PlayStation emulator for Windows, Linux and Mac. To run an image (or directly `PSX.EXE` if you don't build an image), use the following command:

```
duckstation -fastboot -- %~dp0/game.bin
```

or

```
duckstation -fastboot -- %~dp0/iso/PSX.EXE
```

## PCSX-Redux MIPS API

Retrolang includes work-in-progress support for [PCSX-Redux](https://github.com/grumpycoders/pcsx-redux) binary API that is described [here](https://pcsx-redux.consoledev.net/mips_api/). It allows PlayStation programs to communicate with the emulator for debugging purposes.

## TODO

What is not implemented yet in the language:

- Stack arguments
- Modules

In the library:

- Matrix math
- TMD models support
- XA support
- MDEC support

## License

RLC, PSXDISASM, Retrobuild and png2tim are distributed under the Boost Software License, 1.0.

The standard library and all examples are distributed under Unlicense/Public Domain.

## Special Thanks To

- [Martin Korth aka nocash](https://problemkaputt.de/) for his excellent [PlayStation spec](https://problemkaputt.de/psxspx-contents.htm)
- Joshua Walker for his book [Everything You Have Always Wanted to Know about the Playstation But Were Afraid to Ask](https://www.romhacking.net/documents/127/)
- [Lionel Flandrin aka simias](https://github.com/simias) for his [PlayStation emulation guide](https://github.com/simias/psx-guide)
- [IDT R30xx Family Software Reference Manual](https://cgi.cse.unsw.edu.au/~cs3231/doc/R3000.pdf) by Integrated Device Technology, Inc.
