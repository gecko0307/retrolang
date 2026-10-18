# Retrolang Support for VS Code

This extension adds syntax highlighting and basic editor bracket/comment support for Retrolang source files and Retrolang assembly.

| File extension | Language mode |
| --- | --- |
| `.r`, `.ri` | Retrolang |
| `.s` | Retrolang Assembly |

Retrolang highlighting includes C-like keywords and types, strings and character literals, numeric literals, `#include`/`#define` directives, macros, attributes, comments, and inline `asm { ... }` blocks. Assembly files and inline assembly blocks highlight MIPS instructions, registers, directives, labels, strings, numbers, and comments.

## Use from this repository

To install locally, run `vsce package` and install the resulting `.vsix` package from the Extensions view's **Install from VSIX...** command.
