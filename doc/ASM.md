# Retrolang Assembler

Retrolang implements a minimalistic MIPS R3000 assembler which can be used to write entire programs or separate functions.

## Source format

### Lines and comments

- Blank lines are ignored.
- A line beginning with `;` is treated as a comment.
- Labels and instructions are parsed line by line.

Example:

```asm
; comment
.text
    li $a0, .msg
    nop
```

### Section syntax

The assembler understands section switches written as dot-prefixed names:

```asm
.text
.data
```

A `.text` section is required for executable instructions. Code outside `.text` is rejected with an error.

### Data labels

Data declarations are written in `.data` and use a label followed by a colon:

```asm
.data
    .msg:
        "Hello, World!\n\0"
```

## Immediates

Supported immediate forms include:

- literal numbers, for example `10` or `0x003f`
- label references prefixed with a dot, such as `.msg`

Examples:

```asm
li $a0, .msg
j .loop
bne $t0, $t1, .done
```

## Registers

Register syntax is the conventional `$name` form, but the parser also accepts bare numeric register IDs.

General-purpose registers:

- `$r0` / `$zero` - always zero
- `$at` - assembler temporary
- `$v0`..`$v1` - return values
- `$a0`..`$a3` - arguments
- `$t0`..`$t7` - temporaries/locals
- `$s0`..`$s7` - saved registers
- `$t8`..`$t9` - more temporaries
- `$k0`..`$k1` - reserved for kernel/BIOS
- `$gp` - global pointer
- `$sp` - stack pointer
- `$fp` / `$s8` - frame pointer
- `$ra` - return address

COP0 registers:

TODO

COP2 (GTE) data registers:

- `$VXY0` - Vector0 X and Y, 2 packed signed 16-bit integers
- `$VZ0`  - Vector0 Z, signed 16-bit integer
- `$VXY1` - Vector1 X and Y, 2 packed signed 16-bit integers
- `$VZ1`  - Vector1 Z, signed 16-bit integer
- `$VXY2` - Vector2 X and Y, 2 packed signed 16-bit integers
- `$VZ2`  - Vector2 Z, signed 16-bit integer
- `$RGBC` - Color/code value, 4 packed unsigned bytes
- `$OTZ`  - Average Z value (for Ordering Table), unsigned 16-bit integer
- `$IR0`  - 16-bit Accumulator (Interpolate), signed 16-bit integer
- `$IR1`  - 16-bit Accumulator (Vector X), signed 16-bit integer
- `$IR2`  - 16-bit Accumulator (Vector Y), signed 16-bit integer
- `$IR3`  - 16-bit Accumulator (Vector Z), signed 16-bit integer
- `$SXY0` - Screen XY-coordinate FIFO stage1, 2 packed signed 16-bit integers
- `$SXY1` - Screen XY-coordinate FIFO stage2, 2 packed signed 16-bit integers
- `$SXY2` - Screen XY-coordinate FIFO stage3, 2 packed signed 16-bit integers
- `$SXYP` - Screen XY-coordinate FIFO stage4, 2 packed signed 16-bit integers
- `$SZ0`  - Screen Z-coordinate FIFO stage1, unsigned 16-bit integer
- `$SZ1`  - Screen Z-coordinate FIFO stage2, unsigned 16-bit integer
- `$SZ2`  - Screen Z-coordinate FIFO stage3, unsigned 16-bit integer
- `$SZ3`  - Screen Z-coordinate FIFO stage4, unsigned 16-bit integer
- `$RGB0` - Color CRGB-code/color FIFO stage1, 4 packed unsigned bytes
- `$RGB1` - Color CRGB-code/color FIFO stage2, 4 packed unsigned bytes
- `$RGB2` - Color CRGB-code/color FIFO stage3, 4 packed unsigned bytes
- `$MAC0` - 32bit Maths Accumulators (Value), signed 32-bit integer
- `$MAC1` - 32bit Maths Accumulators (Vector X), signed 32-bit integer
- `$MAC2` - 32bit Maths Accumulators (Vector Y), signed 32-bit integer
- `$MAC3` - 32bit Maths Accumulators (Vector Z), signed 32-bit integer
- `$IRGB` - Convert RGB Color (48bit vs 15bit), unsigned 16-bit integer
- `$ORGB` - 
- `$LZCS` - Count Leading-Zeroes/Ones (sign bits), 2 packed signed 32-bit integers
- `$LZCR` - Count Leading-Zeroes/Ones (sign bits), 2 packed signed 32-bit integers

COP2 (GTE) control registers:

TODO

## Instructions

### Arithmetic and data movement

```asm
nop
add  rd, rs, rt
addu rd, rs, rt
addi rd, rs, imm
addiu rd, rs, imm
sub  rd, rs, rt
subu rd, rs, rt
mult rs, rt
multu rs, rt
div rs, rt
divu rs, rt
mflo rd
mfhi rd
mtlo rs
mthi rs
li rd, imm_or_label
lui rd, imm
move rd, rs
clear rd
neg rd, rs
not rd, rs
```

### Comparisons and logical ops

```asm
slt  rd, rs, rt
slti rd, rs, imm
sltu rd, rs, rt
sltiu rd, rs, imm
and  rd, rs, rt
andi rd, rs, imm
or   rd, rs, rt
ori  rd, rs, imm
xor  rd, rs, rt
xori rd, rs, imm
nor  rd, rs, rt
sll  rd, rt, shamt
sllv rd, rt, rs
srl  rd, rt, shamt
srlv rd, rt, rs
sra  rd, rt, shamt
srav rd, rt, rs
```

### Memory access

```asm
lw  rt, imm(base)
lh  rt, imm(base)
lhu rt, imm(base)
lb  rt, imm(base)
lbu rt, imm(base)
lwl rt, imm(base)
lwr rt, imm(base)
sw  rt, imm(base)
sh  rt, imm(base)
sb  rt, imm(base)
swl rt, imm(base)
swr rt, imm(base)
```

### Control flow

```asm
j target
jr rs
jal target
jalr rs
beq rs, rt, target
bne rs, rt, target
blez rs, target
bgtz rs, target
bgez rs, target
bltz rs, target
bgezal rs, target
bltzal rs, target
b rs, target
bal target
```

### System

```asm
syscall imm
break imm
```

### Coprocessor 0
```
mtc0 rt, rd
mfc0 rt, rd
cop0 imm
rfe
```

### Coprocessor 2 (GTE)
```
mtc2 rt, data_reg
mfc2 rt, data_reg
ctc2 rt, control_reg
cfc2 rt, control_reg
lwc2 rt, imm(base)
swc2 rt, imm(base)
bc2f imm
bc2t imm
cop2 imm
rtps
rtpt
mvmva
dcpl
dpcs
dpct
intpl
sqr
ncs
nct
ncds
ncdt
nccs
ncct
cdp
cc
nclip
avsz3
avsz4
op
gpf
gpl
```
