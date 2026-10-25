# Retrolib Standard Library

Retrolang provides a minimal set of low-level functionality that aid with writing PlayStation programs.

Core modules:

* `retrolib.r` - imports entire library at once
* `core.r` - core definitions
* `bios.r` - macros for some common BIOS calls
* `dma.r` - DMA API
* `pad.r` - gamepad driver
* `gpu.r` - GPU driver / graphics API
* `spu.r` - SPU driver / sound API
* `cd.r` - CD audio API
* `xa.r` - XA playback API
* `save.r` - memory card save/load API
* `mdec.r` - MDEC module
* `vlc.r` - VLC decoder
* `str.r` - STR video streaming
* `iso.r` - ISO 9660 file lookup.

Additional experimental modules (not included to `retrolib.r`):

* `pcsx.r` - PCSX-Redux API.

Usage (assuming you've pointed RLC to `retrolib` as an include/import directory):

```c
#import "retrolib.r"
```
