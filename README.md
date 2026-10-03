# Retrolang

The goal of this project is to build a PlayStation 1 development toolchain from scratch, without relying on GCC, LLVM, or other similar compiler frameworks. It features a low-level C-like language, Retrolang, that compiles to MIPS R3000 machine code.

Retrolang currently allows you to write simple programs for PlayStation: output data to the TTY, request information from the gamepad, and draw simple 2D graphics (directly or via DMA).

All provided software is experimental and is in alpha stage.

![Triangle](media/hello_triangle.png)
![Cat](media/cat.png)
![Text](media/text.png)

## Core Idea

Main philosophy of the project: PSX programming doesn't require a full-fledged C. A subset is sufficient. What we really need is platform-specific language capabilities and a simple, readable and easily hackable standard library.

## RLC

The main tool is RLC, the Retrolang Compiler. It combines an assembler, compiler, and a linker in a single program and directly outputs `PSX.EXE`.

Usage:

```
rlc -o PSX.EXE src/main.r
```

Because there are no object files and incremental building support at the moment, main source file (`main.r`) should contain the whole program. You can use C-like `#include`s to make a single source file from multiple files. It is recommended to use `.ri` extension for included files.

Assembling command is similar (RLC treats *.s file as an assembly source):

```
rlc -o PSX.EXE src/main.s
```

RLC translates your program verbatim, without optimizations and unexpected changes behind your back. You are solely responsible for writing good-quality code and using the console's limited resources wisely.

## The Language

Retrolang is a very basic curly-bracket procedural language inspired by C, but desifned to run in extremely memory-constrained environments.

**Primitive types**: `int`, `short`, `char`, `uint`, `ushort`, `uchar`, `void`, and pointers to them. Pointers compare as unsigned. Literals above `0x7FFFFFFF`, or with a 'u' suffix, are unsigned. Like C, `uchar`/`ushort` promote to (signed) `int` in arithmetic; only `uint` makes `/`, `%`, `>>` and comparisons unsigned. C-style type casts are supported.

**Arrays**: C-like static arrays and strings:

```c
int t[4] = {1, 2, 3, 4};
char hello[] = "Hello!";
```

**Structs**: top-level definitions `struct Name { int a; uchar c[3]; };`. Used as `struct Name x;`. Fields may be scalars, pointers, arrays or nested structs. Structs can be copied with `=` (inline, up to 32 words), have their address taken, and be measured with `sizeof(struct Name)`. Not supported: struct initializers, passing/returning structs by value, unions, bit-fields, `typedef`, `sizeof(expression)`.

**Operators**: all basic arithmetic, logical and bitwise operators are supported. Retrolang uses C precedence. Ternary operator is not supported.

**Statements**: `if`/`else`, `while`, `do`-`while`, `for`, `break`, `continue`, `return`.

**Function calls**: follows O32 ABI. Supports up to 4 arguments (passed in `$a0`-`$a3`), result in `$v0`.

**Program entry point**: `main()`, started from a small stub that sets `$sp`.

**Intrinsics**: BIOS calls `bios_a(n, ...)`, `bios_b(n, ...)`, `bios_c(n, ...)` through the `A0h`/`B0h`/`C0h` vectors with up to 3 further arguments. `n` is a function number which is passed in `$t1` register.

**Embedded files**: a global array can have an attribute `@("file.bin")` to embed a file to the executable.

**External assembly**: a function with an attribute `@("file.s")` relies on external implementation in Retrolang assembly. The compiler still generates prologue/epilogue for such functions. Local data/jump labels can be used inside the assembly source. Globally visible assembly labels are not supported.

**Code generation notes:**

- Local variables live in `$s0`-`$s7` (callee-saved) unless their address is taken, in which case (or when registers run out) they live in the stack frame.
- Expression temporaries use `$t0`-`$t9` as a register stack. Live temporaries are saved around calls.

## Standard Library

Retrolang provides a minimal set of low-level functionality that aid with writing PlayStation programs. It is partly a port of [psxlib project](https://github.com/gecko0307/psxlib). These files are meant to be directly included to the main source file using `#include` directive.

* `core.ri` - core definitions
* `gpu.ri` - GPU driver
* `pad.ri` - gamepad driver.

Usage (assuming you've copied the [include](/examples/include) folder to your project's source directory):

```c
#include "include/core.ri"
#include "include/pad.ri"
#include "include/gpu.ri"
```

## Examples

"Hello, World" program:

```c
void main()
{
    bios_a(0x3F, "Hello, World!\n");
}
```

The same in Retrolang assembly:

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

## Recommended Tools

Provided examples rely the following third-party tools:

- [mkpsxiso by Lameguy64](https://github.com/lameguy64/mkpsxiso) to build CD-ROM images
- [img2tim by Lameguy64](https://github.com/lameguy64/img2tim) to convert textures to TIM format.

For running examples on the PC, we recommend [DuckStation](https://www.duckstation.org/), a fast and feature-rich PlayStation emulator for Windows, Linux and Mac. To run an image (or directly `PSX.EXE` if you don't build an image), use the following command:

```
duckstation -fastboot -- %~dp0/build/game.bin
```

or

```
duckstation -fastboot -- %~dp0/iso/PSX.EXE
```

## TODO

What is not implemented yet:

- Stack arguments
- Modules
- GTE intrinsics
