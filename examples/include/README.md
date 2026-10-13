# Retrolang Standard Library

Retrolang provides a minimal set of low-level functionality that aid with writing PlayStation programs. These files are meant to be directly included to the main source file using `#include` directive.

* `core.ri` - core definitions
* `bios.ri` - BIOS functions
* `gpu.ri` - GPU driver
* `pad.ri` - gamepad driver.

Usage (assuming you've copied the `include` folder to your project's source directory):

```c
#include "include/core.ri"
#include "include/bios.ri"
#include "include/pad.ri"
#include "include/gpu.ri"
```
