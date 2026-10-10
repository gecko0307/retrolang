# Retrolang Language Reference

Retrolang is a minimalistic C-like system language for the MIPS R3000 / PlayStation 1. The compiler, `rlc`, translates a `.r` source file directly into a PS-X EXE. It has no runtime library, no heap and no optimizer: what you write is, nearly statement for statement, what the CPU executes.

This document covers the core language. See the separate documents for macros, GTE intrinsics and external assembly.

## Contents

1. [Toolchain](#1-toolchain)
2. [Hello, World](#2-hello-world)
3. [Lexical structure](#3-lexical-structure)
4. [Types](#4-types)
5. [Declarations and scope](#5-declarations-and-scope)
6. [Functions](#6-functions)
7. [Statements](#7-statements)
8. [Expressions](#8-expressions)
9. [Structs](#9-structs)
10. [BIOS calls](#10-bios-calls)
11. [Hardware access](#11-hardware-access)
12. [Memory layout and calling convention](#12-memory-layout-and-calling-convention)
13. [Code generation notes](#13-code-generation-notes)
14. [Limitations](#14-limitations)
15. [Errors](#15-errors)
16. [Examples](#16-examples)

---

## 1. Toolchain

```
rlc [options] <input_file>
```

| Option | Meaning |
|---|---|
| `-o`, `--output <file>` | Output file name (default `PSX.EXE`) |
| `-v`, `--verbose` | Print code size, data labels, section addresses and the generated instruction listing |
| `-h`, `--help` | Show usage |

The input file extension selects the front end:

- `.r`: Retrolang source, compiled to MIPS code.
- `.s`: assembly source, assembled directly (no compiler involved).

Pipeline: source, then preprocessing and lexing, parsing to an AST, code generation to an intermediate instruction list, linking (encoding and label resolution), and finally the PS-X EXE writer.

A program must define `main()`. It is started from a small stub that sets up the stack pointer. If `main` returns, the CPU spins in an endless loop.

---

## 2. Hello, World

```c
void main()
{
    bios_a(0x3F, "Hello, World!\n"); // BIOS printf
}
```

---

## 3. Lexical structure

### Comments

```c
// line comment
/* block comment (does not nest) */
```

### Identifiers and keywords

Identifiers can contain letters, digits and underscores (`_`), and cannot start with a digit. The following words are reserved:

```
int short char void uint ushort uchar unsigned
struct sizeof macro
if else while do for return break continue
```

The names of the compiler built-ins (`bios_a`, `bios_b`, `bios_c`, `nop` and the `gte_*` intrinsics) are also taken. Do not use them as function names.

### Integer literals

| Form | Example |
|---|---|
| Decimal | `255` |
| Hexadecimal | `0xFF` |
| Binary | `0b1010` |
| Octal | `0o17` |
| Unsigned suffix | `10u` |
| Character | `'A'`, `'\n'`, `'\0'` |

- A leading zero does **not** mean octal: `010` is decimal ten. Use `0o`.
- Integer literals must fit in 32 bits. A number above `0x7FFFFFFF` is automatically lowered to 32-bit integer.
- There are no negative literals; `-5` is unary minus applied to `5`.
- There is no floating point support.

### String literals

Strings (`"text"`) have type `char*` and point to a null-terminated array in the static data section of the executable. Identical literals share one copy. Supported escapes are `\n \r \t \\ \" \0`; for any other escape character `\c` the result is just `c`. A string cannot contain a raw newline, use an escape character `\n`.

### Preprocessor

A preprocessor directive must be the first token on its line and takes the rest of the line.

| Directive | Meaning |
|---|---|
| `#define NAME tokens...` | Object-like token macro (no parameters) |
| `#undef NAME` | Remove a definition |
| `#include "file"` | Insert another source file; the path is relative to the including file |

`#define` bodies are token sequences, expanded where the name is used. A macro never expands recursively into itself. There is no `#if`/`#ifdef` and no include guard, so include each file once. A file that includes itself, directly or indirectly, is an error.

`#define` is purely lexical. For typed, hygienic substitution use `macro` (see Macros.md).

---

## 4. Types

| Type | Size | Notes |
|---|---|---|
| `int` | 4 | signed |
| `uint`, `unsigned`, `unsigned int` | 4 | unsigned |
| `short` | 2 | signed |
| `ushort`, `unsigned short` | 2 | unsigned |
| `char` | 1 | signed |
| `uchar`, `unsigned char` | 1 | unsigned |
| `void` | - | only as a return type or as `void*` |
| `T*` | 4 | pointer to any type; compared as unsigned |
| `struct Name` | see [Structs](#9-structs) | |

There is no `long`, `float`, `bool`, `enum`, `union` or `typedef`.

**Integer arithmetic** is always done on 32-bit values. Like C, `char`, `uchar`, `short` and `ushort` are promoted to (signed) `int` in expressions; only `uint` makes `/`, `%`, `>>` and comparisons unsigned. Pointers compare as unsigned. When a value is stored into a `char` or `short` variable, or cast to one, it is truncated and sign- or zero-extended according to its type.

**Alignment**: the CPU raises an exception on unaligned `short`/`int` access, and the compiler adds no checks. Be careful when casting a `char*` to an `int*`. Required alignment for `short` is 2 bytes, for `int` - 4 bytes.

**Type system is weak.** Integers and pointers convert freely, and pointer types are not checked against each other. The compiler checks things it cannot compile: dereferencing a non-pointer, bad member access, wrong argument counts, and so on.

---

## 5. Declarations and scope

### Global variables

```c
int counter;                        // zero-initialized
int limit = 100;
int table[4] = {1, 2, 3, 4};        // missing elements are zero, extra ones are an error
short samples[] = {10, 20, 30};     // size taken from the initializer
char title[] = "Game";              // char arrays can be initialized from a string
char buffer[256];
int a, b = 2, *p;                   // several declarators
uint* GP0 = 0x1F801810;             // pointer initialized with a constant address
```

- Initializers must be constant expressions (see [Constant expressions](#constant-expressions)). Addresses of other objects cannot be used as initializers.
- Global data lives in the executable image, so it is writable and zero-filled unless initialized.
- A string initializer is only allowed for `char` arrays. A global `char*` cannot be initialized with a string literal, only with external data file (see below).
- Globals and functions can be used before their definition in the file. Structs and macros cannot; they must be defined first.

Embedding a binary file into a global array:

```c
uchar* texture @("texture.bin");
```

Or:

```c
uchar texture[] @("texture.bin");   // array length is the file size in bytes
```

**The path is resolved relative to the working directory of the compiler**, not the `*.r` source file.

### Local variables

```c
void f()
{
    int x = 5;            // scalar with initializer
    int i, *p, buf[16];   // several declarators; arrays are uninitialized
    struct Vec v;         // struct on the stack
}
```

- Declarations may appear anywhere in a block, and in the first clause of a `for`.
- Local arrays and structs cannot have initializers, and local variables without one hold garbage.
- Scalars live in registers (`$s0`-`$s7`). A variable whose address is taken with `&`, or any variable beyond the eighth, lives in the stack frame instead.

### Arrays

`T name[N]` declares `N` elements; `N` must be a constant expression. Multi-dimensional arrays are not supported. An array name in an expression decays to a pointer to its first element (`&arr` means the same). Arrays cannot be assigned, passed or returned (use pointers).

### Scope

Names are block-scoped. An inner declaration may shadow an outer one, but a name cannot be declared twice in the same block. Global names are visible everywhere.

---

## 6. Functions

```c
int add(int a, int b)
{
    return a + b;
}

void log_value(char* label, int v);   // prototype
```

- Up to **4 parameters** and **4 call arguments** (passed in `$a0`-`$a3`).
- Parameters and return values must be scalars or pointers. Struct cannot be passed or returned by value, only by pointer.
- `f()` and `f(void)` both mean "no parameters".
- Recursion is supported.
- Argument count is checked at each call; argument types are not.
- Only named global functions can be called. There are no function pointers.
- A `void` function cannot `return` a value. Flowing off the end of a non-`void` function returns whatever is in `$v0`.
- `main` may be declared `void` or `int`.
- A function body can be implemented in assembly with `@("file.s")` attribute (see ASM.md).

---

## 7. Statements

```c
{ ... }                          // block
expr;                            // expression statement
;                                // empty statement

if (cond) stmt else stmt
while (cond) stmt
do stmt while (cond);
for (init; cond; step) stmt      // init: declaration or expression; all parts optional
return;   return expr;
break;    continue;
```

- A condition is any integer or pointer expression; non-zero is true.
- `break` and `continue` apply to the innermost loop. `continue` in a `for` runs the step expression.
- A variable declared in a `for` header is scoped to the loop.
- There is no `switch` and no `goto`.

---

## 8. Expressions

### Precedence

From highest to lowest. All binary operators are left-associative except assignment.

| Level | Operators |
|---|---|
| 1 | `f()`  `a[i]`  `.`  `->`  postfix `++` `--` |
| 2 | prefix `++` `--`, unary `-` `+` `!` `~` `*` `&`, `(type)` cast, `sizeof(type)` |
| 3 | `*`  `/`  `%` |
| 4 | `+`  `-` |
| 5 | `<<`  `>>` |
| 6 | `<`  `<=`  `>`  `>=` |
| 7 | `==`  `!=` |
| 8 | `&` |
| 9 | `^` |
| 10 | `\|` |
| 11 | `&&` |
| 12 | `\|\|` |
| 13 | `=`  `+=`  `-=`  `*=`  `/=`  `%=`  `&=`  `\|=`  `^=`  `<<=`  `>>=` (right-associative) |

There is no ternary operator (`?`) and no comma operator.

`&&` and `||` short-circuit and produce 0 or 1; so do comparisons and `!`. `>>` is arithmetic for signed operands and logical for `uint`. Operands are evaluated left to right, and call arguments are evaluated left to right.

### Pointers

```c
int a[8];
int* p = a;        // or &a[0]
p[2] = 5;          // same as *(p + 2)
p++;               // advances by sizeof(int) bytes
int n = q - p;     // difference in elements
```

- Arithmetic is scaled by the element size. `void*` is scaled by 1 and cannot be dereferenced or indexed.
- `&` works on variables, array elements and struct members.
- Memory accesses are never reordered or elided, so pointers to hardware registers behave as you would expect. There's no need for `volatile`.

### Casts

`(type)expr` converts to any type, including pointers (`(uint*)0x1F801810`,
`(struct Packet*)buf`). Casts to `char`/`short` types truncate and extend; other casts change nothing at run time.

### sizeof

`sizeof(type)` gives the size in bytes as a compile-time constant, e.g.
`sizeof(int)`, `sizeof(struct Vec)`, `sizeof(char*)`. It applies to types only, not to expressions.

### Constant expressions

Expressions built from literals, `sizeof`, and the operators `+ - * / % & | ^ << >> ~ ! && ||` and comparisons are folded at compile time with 32-bit wrapping arithmetic. A constant is required for array sizes, global initializers and constant list indices. Anywhere else, a constant sub-expression is simply folded as an optimization.

---

## 9. Structs

Structs are defined at top level, before use:

```c
struct Vec
{
    int x;
    int y;
};

struct Node
{
    int value;
    uchar tag[3];            // array member
    struct Vec pos;          // nested struct, must already be defined
    struct Node* next;       // self-reference only by pointer
};
```

Members can be scalars, pointers, arrays or previously defined structs, and several can share a declaration (`int a, b;`). Layout follows C rules: every member is aligned to its own size and the struct size is rounded up to its largest alignment.

```c
struct Vec v;
struct Vec* p = &v;
v.x = 1;
p->y = 2;
struct Vec points[4];        // array of structs
points[i].x = i;
struct Vec copy;
copy = v;                    // whole-struct copy, as a statement only
int size = sizeof(struct Vec);
```

Struct copy is expanded inline and is limited to 32 word-sized pieces.

Not supported: struct initializers, passing or returning structs by value, using a struct as an expression value (use members, `&` or `=`), unions, bit-fields, `typedef`, and nested struct definitions.

---

## 10. BIOS calls

```c
bios_a(function_number, arg0, arg1, ...);   // table at 0xA0
bios_b(function_number, ...);               // table at 0xB0
bios_c(function_number, ...);               // table at 0xC0
```

The function number must be a constant. Up to four further arguments are passed in `$a0`-`$a3`. The result is an `int`.

```c
bios_a(0x3F, "x = %d, name = %s\n", x, name);   // printf
```

---

## 11. Hardware access

There are no `volatile` or `extern` keywords. Because the compiler performs every load and store you write, memory-mapped registers can be accessed with plain pointers:

```c
uint* GP1 = 0x1F801814;                // global pointer to a constant address

void main()
{
    *GP1 = 0x03000000;                 // GP1: display enable (via a global pointer)
    *(uint*)0x1F801810 = 0xE1000000;   // or a cast of a literal address
}
```

For the COP0 and COP2 (GTE) operations, use the dedicated intrinsics (see GTE Intrinsics.md).

---

## 12. Memory layout and calling convention

PSX-EXE file layout is the following:

| Item | Value |
|---|---|
| Load address and entry point | `0x80010000` (the startup stub comes first) |
| Order in the image | code, then data (globals and string literals, 4-byte aligned) |
| Stack pointer at start | `0x801FFF00`, growing down |
| Heap | none |
| EXE header | 2 KiB, file size padded to a multiple of 2048 |

Calling convention:

| Registers | Role |
|---|---|
| `$a0`-`$a3` | arguments |
| `$v0` | return value |
| `$s0`-`$s7` | local variables; callee-saved (saved in the prologue only if used) |
| `$t0`-`$t9` | expression temporaries; live ones are saved by the caller around each call |
| `$ra` | saved by any function that makes a call |
| `$sp` | stack pointer; frames are 8-byte aligned |

Symbols in the generated code are `f_<name>` for functions, `g_<name>` for globals and `str_<n>` for string literals.

---

## 13. Code generation notes

The compiler is a single-pass, non-optimizing code generator. Knowing its habits helps with performance-critical code:

- Locals in registers are cheap; the first eight scalars whose address is never taken get one. Taking `&x` puts `x` in memory.
- Expressions use ten temporaries. A very deeply nested expression fails with "expression too complex".
- Every branch, jump and load is followed by a `nop` (delay slot). Slots are not filled.
- Folded constants, short immediate forms, shifts for `* 2^n` (and for `/ 2^n` and `% 2^n` on unsigned values) and compare-with-zero branches are the only optimizations.
- `*`, `/` and `%` use the CPU's multiply/divide unit and are slow, and there is no trap on division by zero.
- There is no automatic inlining. Function calls are always expanded to jumps. Use `macro` to inline code manually.

---

## 14. Limitations

Not available: floating point types, 64-bit integers, `typedef`, `enum`, `union`, bit-fields, `const`/`static`/`extern`/`volatile`, `switch`, `goto`, the `?:` and comma operators, function pointers, multi-dimensional arrays, array parameters, `sizeof(expression)`, struct initializers, local array initializers, struct values as arguments, results or expressions, user-defined variadic functions, `#if`/`#ifdef` and function-like `#define` (use `macro`).

Limits: 4 parameters and 4 call arguments; 8 register locals (the rest go to the stack); a stack frame under 32000 bytes; global arrays up to 4000000 elements.

---

## 15. Errors

Diagnostics use the form

```
file(line): error: message
```

and always name the file and line of the offending source, including inside included files. The compiler stops at the first error.
---

## 16. Examples

### Recursion

```c
int fib(int n)
{
    if (n < 2)
        return n;
    return fib(n - 1) + fib(n - 2);
}

void main()
{
    bios_a(0x3F, "fib(10) = %d\n", fib(10));   // 55
}
```

### Pointers and strings

```c
int length(char* s)
{
    int n = 0;
    while (s[n] != 0)
        n++;
    return n;
}

void main()
{
    bios_a(0x3F, "%d\n", length("Retrolang"));   // 9
}
```

### Structs

```c
struct Vec
{
    int x;
    int y;
};

struct Vec points[4];

int dot(struct Vec* a, struct Vec* b)
{
    return a->x * b->x + a->y * b->y;
}

void main()
{
    for (int i = 0; i < 4; i++)
    {
        points[i].x = i;
        points[i].y = i * 2;
    }
    bios_a(0x3F, "dot = %d\n", dot(&points[1], &points[2]));   // 10
}
```
