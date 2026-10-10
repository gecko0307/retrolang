# GTE Intrinsics

GTE (Geometry Transformation Engine) is a second coprocessor (COP2) that implements common vector-matrix math in silicon. It is necessary for fast vertex transformations in 3D games.

GTE is a very complex device for beginners to grasp. Not only does it employ mind-bending fixed-point arithmetic, but working with it in C requires assembly because the compiler itself does not natively support it. In Retrolang, we decided to add GTE support directly into the compiler so that programmer wouldn't have to resort to assembly for routine tasks.

GTE operations rely on special instructions that transfer data to its registers, issue commands to perform calculations, and then retrieve the results into the CPU registers. To incorporate these instructions into the Retrolang code, RLC recognizes special functions known as intrinsics. While they resemble standard functions, they do not actually trigger a function call; instead, they expand into inline code.

Certain common GTE operations are implemented as built-in macros, predefined sequences of instructions that can be expanded with different data inputs.

Basic commands:

- `gte_ctc2(ubyte rd, T expr)` - evaluates an expression, copying the value to the GTE control register
- `gte_cfc2(ubyte rd, T expr)` - 
- `gte_mtc2(ubyte rd, T expr)` - evaluates an expression, copying the value to the GTE data register
- `gte_mfc2(ubyte rd, T expr)` -
- `gte_swc2(ubyte rd, T* ref)` -
- `gte_lwc2(ubyte rd, T* ref)` -
- `gte_rtps()` -
- `gte_rtpt()` -
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

GTE macros:

- `gte_enable()` - 
- `gte_set_matrix()` - 
- `gte_set_vertex()` - 
- `gte_get_vertex()` - 

Misc:

- `nop()` - inserts a no-op instruction, an instruction that does nothing and acts as a 1-instruction delay for the CPU. GTE operations like `RTPS` and others don't stall the CPU and require two delay slots before the result is available to read. If CPU can't do something useful while GTE is busy, it can just wait for the result.
