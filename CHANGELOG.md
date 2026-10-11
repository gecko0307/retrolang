Retrolang 0.3.0 - TBD
---------------------
- **RLC**
  - AST macros support
  - Static memory allocator
  - File-initialized arrays now use the normal array syntax: `uchar texture[] @("texture.tim");`
- **Examples**
  - `gpu.ri`: data packing macros `GP0_PACK_COORDS`, `GP0_PACK_UV`, `GP0_PACK_UV_DATA`
  - `bios.ri`
  - New constants in `core.ri`
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
  - Optimize mesh example. Rewrite the rendering function using new GTE intrinsic system, add backface culling, transformed vertex caching and other improvements.

Retrolang 0.1.0 - 7 Oct, 2026
-----------------------------
Initial release.

1 Oct, 2026
-----------
Start as a public project.
