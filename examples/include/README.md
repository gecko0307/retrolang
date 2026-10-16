# Retrolib Standard Library

Retrolang provides a minimal set of low-level functionality that aid with writing PlayStation programs. These files are meant to be directly included to the main source file using `#include` directive.

* `retrolib.ri` - includes entire library at once (recommended)
* `core.ri` - core definitions
* `bios.ri` - macros for some common BIOS calls
* `pad.ri` - gamepad driver
* `gpu.ri` - GPU driver / graphics API
* `spu.ri` - SPU driver / sound API
* `cd.ri` - CD audio API
* `pcsx.ri` - PCSX-Redux API.

Usage (assuming you've copied the `include` folder to your project's source directory):

```c
#include "include/retrolib.ri"
```
