# Retrolang

The goal of this project is creating a developer's toolset targeting PlayStation 1 completely from scratch (without using GCC, LLVM and other frameworks). It features a low-level C-like language, Retrolang, that compiles to MIPS R3000 machine code.

## RLC

The main tool is RLC, the Retrolang Compiler. It combines an assembler, compiler, and a linker in a single program and directly outputs `PSX.EXE`.
