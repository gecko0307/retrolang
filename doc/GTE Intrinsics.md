# GTE Intrinsics

GTE (Geometry Transformation Engine) is a second coprocessor (COP2) that implements common vector-matrix math in silicon. It is necessary for fast vertex transformations in 3D games.

GTE is a very complex device for beginners to grasp. Not only does it employ mind-bending fixed-point arithmetic, but working with it in C requires assembly because the compiler itself does not natively support it. In Retrolang, we decided to add GTE support directly into the compiler so that programmer wouldn't have to resort to assembly for routine tasks.

GTE operations rely on special instructions that transfer data to its registers, issue commands to perform calculations, and then retrieve the results into the CPU registers. To incorporate these instructions into the Retrolang code, RLC recognizes special functions known as intrinsics. While they resemble standard functions, they do not actually trigger a function call; instead, they expand into inline code.

Certain common GTE operations are implemented as built-in macros, predefined sequences of instructions that can be expanded with different data inputs.

Basic commands:

- `ctc2(ubyte rd, T expr)` - evaluates an expression, copying the value to the GTE control register. This is most efficient if `expr` is a local variable
- `cfc2(ubyte rd)` - copies the value from the GTE control register to a local variable
- `mtc2(ubyte rd, T expr)` - evaluates an expression, copying the value to the GTE data register. This is most efficient if `expr` is a local variable
- `mfc2(ubyte rd)` - copies the value from the GTE data register to a local variable
- `swc2(ubyte rd, T* ptr)` - stores the value from memory pointed by `ptr` to the GTE data register. This is most efficient if `ptr` is **not** a local variable (i.e., an array element or a struct field)
- `lwc2(ubyte rd, T* ptr)` - loads the from the GTE data register to memory pointed by `ptr`. This is most efficient if `ptr` is **not** a local variable (i.e., an array element or a struct field)
- `gte_rtps()` - rotate-translate-perspective for a single vertex
- `gte_rtpt()` - rotate-translate-perspective for a triangle
- `gte_mvmva()` - 
- `gte_dcpl()` -
- `gte_dpcs()` -
- `gte_dpct()` -
- `gte_intpl()` -
- `gte_sqr()` -
- `gte_ncs()` -
- `gte_nct()` -
- `gte_ncds()` -
- `gte_ncdt()` -
- `gte_nccs()` -
- `gte_ncct()` -
- `gte_cdp()` -
- `gte_cc()` -
- `gte_nclip()` -
- `gte_avsz3()` -
- `gte_avsz4()` -
- `gte_op()` -
- `gte_gpf()` -
- `gte_gpl()`- 

Convenient GTE macros for common operations:

- `gte_enable()` - enables the GTE. Call this before other GTE intrinsics
- `gte_set_matrix(short* m)` - copies 3x3 row-major rotation matrix from system memory pointed by `m` to GTE control registers R11R12, R13R21, R22R23, R31R32, R33. `m` should point to a buffer of 9 `short`s
- `gte_set_vertex(short* v)` - copies an XYZ vertex from the system memory pointed by `v` to GTE data registers VXY0, VZ0, VXY1, VZ1, VXY2, VZ2. `v` should point to a buffer of 12 `shorts` (padding is required for correct alignment, so each vertex is 4 `shorts`)
- `gte_get_vertex(short* v)` - copies an XYZ vertex from GTE data registers VXY0, VZ0, VXY1, VZ1, VXY2, VZ2 to the system memory pointed by `v`. `v` should point to a buffer of 12 `shorts` (padding is required for correct alignment, so each vertex is 4 `shorts`).

Misc:

- `nop()` - inserts a no-op instruction, an instruction that does nothing and acts as a 1-instruction delay for the CPU. GTE operations like `RTPS` and others don't stall the CPU and require two delay slots before the result is available to read. If CPU can't do something useful while GTE is busy, it can just wait for the result.
