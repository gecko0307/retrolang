# Macros

Retrtolang lacks C's powerful preprocessor, but supports AST macros instead. Macros are parts of the program reusable at compile time. Retrolang supports expresson macros, parametrized expresson macros, list macros, and statement macros. They are useful for defining constants, inlining performance-critical functions and GTE command blocks.

Statement macro is a special parametrized function-like statement block that expands into inline code rather than a function call:

```c
macro printStr(str)
{
    bios_a(0x3F, str);
}

void main()
{
    printStr("Hello, World!\n"); // this will be directly replaced with `bios_a` call
}
```

Unlike function templates in languages like C++ or D, the statement macro is untyped, returns no value, and possesses no runtime semantics; it serves purely as an abstract syntactic template for generating repetitive code. Its parameters are not final values ​​but expressions (AST nodes); expanding a macro deep-copies its body, replacing every reference to a parameter with a copy of the
argument expression. An argument is re-evaluated at every place where it is used.

```c
macro repeat(f, n)
{
    for(int i = 0; i < n; i++)
    {
        f;
    }
}

void main()
{
    int x = 0;
    repeat(x++; 10);
}
```

This expands to the following:

```c
x = 0;
for(int i = 0; i < 10; i++)
{
    x++;
}
```

Variables declared inside a macro body get a unique name per expansion, so they can never capture or shadow variables used by the arguments.

When inlining performance-critical code, pass plain variables or constants into macros, never expressions like `*p` or `a[i++]` (unless repeating an expression is what you intend).

You can also define expression macros for constants and compile-time evaluation:

```c
macro A = 5;
macro B = A * 10;
```

List macros can be used to store compile-time expression lists (tuples):

```c
macro MemRegion = (0x80050000, 2048);
 
void show(uint addr, int size)
{
    bios_a(0x3F, "region 0x%08x size %d\n", addr, size);
}

void main()
{
    show(MemRegion);
    show(MemRegion[0], MemRegion[1]);
}
```
