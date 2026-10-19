# Retrolib Standard Library

Retrolang provides a minimal set of low-level functionality that aid with writing PlayStation programs.

* `retrolib.r` - imports entire library at once (recommended)
* `core.ri` - core definitions
* `bios.ri` - macros for some common BIOS calls
* `dma.r` - DMA API
* `pad.r` - gamepad driver
* `gpu.r` - GPU driver / graphics API
* `spu.r` - SPU driver / sound API
* `cd.r` - CD audio API
* `save.r` - memry card save/load API
* `pcsx.r` - PCSX-Redux API.

Usage (assuming you've pointed RLC to `retrolib` as an include/import directory):

```c
#import "retrolib.r"
```
