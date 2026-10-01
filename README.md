# Retrolang

The goal of this project is creating a developer's toolset targeting PlayStation 1 completely from scratch (without using GCC, LLVM and other frameworks). It features a low-level C-like language, Retrolang, that compiles to MIPS R3000 machine code.

## RLC

The main tool is RLC, the Retrolang Compiler. It combines an assembler, compiler, and a linker in a single program and directly outputs `PSX.EXE`.

Usage:

```
rlc -o PSX.EXE src/main.r
```

Because there are no object files and incremental building support at the moment, main source file (`main.r`) should contain the whole program. You can use C-like `#include`s to make a single source file from multiple files. It is recommended to use `.ri` extension for included files.

## The Language

Retrolang is a very basic curly-bracket imperative language inspired by C.

**Primitive types**: `int`, `short`, `char`, `uint`, `ushort`, `uchar`, `void`, and pointers to them. Pointers compare as unsigned. Literals above `0x7FFFFFFF`, or with a 'u' suffix, are unsigned. Like C, `uchar`/`ushort` promote to (signed) `int` in arithmetic; only `uint` makes `/`, `%`, `>>` and comparisons unsigned. C-style type casts are supported.

**Arrays**: C-like static arrays and strings:

```c
int t[4] = {1, 2, 3, 4};
char hello[] = "Hello!";
```

**Operators**: all basic arithmetic, logical and bitwise operators are supported. Retrolang uses C precedence. Ternary operator is not supported.

**Statements**: `if`/`else`, `while`, `do`-`while`, `for`, `break`, `continue`, `return`.

**Function calls**: up to 4 arguments (passed in `$a0`-`$a3`), result in `$v0`.

**Program entry point**: `main()`, started from a small stub that sets `$sp`.

**Intrinsics**: BIOS calls `bios_a(n, ...)`, `bios_b(n, ...)`, `bios_c(n, ...)` through the `A0h`/`B0h`/`C0h` vectors with up to 3 further arguments. `n` is a function number which is passed in `$t1` register.

**Code generation notes:**

- Local variables live in `$s0`-`$s7` (callee-saved) unless their address is taken, in which case (or when registers run out) they live in the stack frame.
- Expression temporaries use `$t0`-`$t9` as a register stack. Live temporaries are saved around calls.

## Examples

"Hello, World" program:

```c
void main()
{
    bios_a(0x3F, "Hello, World!\n");`
}
```
