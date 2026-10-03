# Retrolang Standard Library

Retrolang provides a minimal set of low-level functionality that aid with writing PlayStation programs. It is partly a port of [psxlib project](https://github.com/gecko0307/psxlib). These files are meant to be directly included to the project using the `#include` preprocessor directive.

* `core.ri` - core definitions
* `gpu.ri` - GPU driver
* `pad.ri` - gamepad driver.

Usage (assuming you've copied the `include` folder to your project's source directory):

```c
#include "include/core.ri"
#include "include/pad.ri"
#include "include/gpu.ri"
```
