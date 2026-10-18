# Retrolib Standard Library

Retrolang provides a minimal set of low-level functionality that aid with writing PlayStation programs.

* `retrolib.ri` - includes entire library at once (recommended)
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
