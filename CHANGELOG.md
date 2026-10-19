Retrolang 0.7.0 - TBD
---------------------
- **RLC**
  - Modules support based on the [unity-build](https://en.wikipedia.org/wiki/Unity_build) method. `import` and `#import` directives
  - Inline assembly support (`asm` statement blocks)
  - External assembly support was removed because it is redundant now
  - Ternary operator support: `<condition> ? <result_if_true> : <result_if_false>`
  - Embedded-data search paths: `--data` is now passed through to compilation
  - Windows-safe path lists: `--include` and `--data` use `;` as a separator
  - EXE region selection: `--region japan|europe|north-america`. Europe remains the default
  - Linker map: `--map <file>` for sorted code/data symbol addresses and image sizes
- **Retrolib**
  - Retrolib now uses modules. Each module can be imported to the program separately as needed, or the entire library can be imported using `#import "retrolib.ri"`
  - `save.r` - memory card API.
- **Misc**
  - VSCode extension.

Retrolang 0.6.0 - 18 Oct, 2026
------------------------------
- **Retrolib**
  - `cd.ri` - CD audio API
  - Bugfixes in `spu.ri`
- **Examples**
  - Updated platformer example.

Retrolang 0.5.0 - 16 Oct, 2026
------------------------------
- **RLC**
  - Assembler reimplementation, full-featured relocations support
  - `syscall` intrinsic
  - Improved escape characters parsing
- **Retrolib**
  - `spu.ri` - a simple SPU driver / sound API
  - `pcsx.ri` - a binding to [PCSX-Redux API](https://pcsx-redux.consoledev.net/mips_api/)
  - Many new BIOS call macros in `bios.ri`
  - Fix `padInit` when booting via FreePSXBoot
- **Examples**
  - Memory card I/O example
  - Sound playback examples.

Retrolang 0.4.0 - 14 Oct, 2026
------------------------------
- **RLC**
  - Add necessary initialization for the correct full boot
  - Update GTE API. New intrinsics `mfc0`, `mtc0`
- **Retrolib**
  - New pad driver, analog sticks support
  - Functions to read files from the CD-ROM
  - `irq.ri`, `retrolib.ri`
- **Examples**
  - New DAT file for patching CD image system area.

Retrolang 0.3.0 - 12 Oct, 2026
------------------------------
- **RLC**
  - AST macros support
  - Static memory allocator
  - File-initialized arrays now use the normal array syntax: `uchar texture[] @("texture.tim");`
- **Retrolib**
  - `gpu.ri`: data packing macros `GP0_PACK_COORDS`, `GP0_PACK_UV`, `GP0_PACK_UV_DATA`
  - `bios.ri`
  - New constants in `core.ri`
- **Examples**
  - New example - a platform game
  - All examples are now Retrobuild projects.

Retrolang 0.2.0 - 10 Oct, 2026
------------------------------
- **RLC**
  - GTE intrinsics support
  - Optimize array indexing with constant expressions
- **Retrobuild**
  - New tool - Retrobuild, a simple TOML-based build automation system
- **png2tim**
  - New tool - PNG to TIM converter
- **Examples**
  - Optimized mesh example. Rewrite the rendering function using new GTE intrinsic system, add backface culling, transformed vertex caching and other improvements.

Retrolang 0.1.0 - 7 Oct, 2026
-----------------------------
Initial release.

1 Oct, 2026
-----------
Start as a public project.
