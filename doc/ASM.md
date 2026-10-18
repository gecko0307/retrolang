# Retrolang Assembler

Retrolang implements a minimalistic MIPS R3000 assembler which can be used to write entire programs or separate functions.

## Source format

### Lines and comments

- Blank lines are ignored.
- Comments are `; ...`, `# ...`, `// ...` to the end of the line. Block comments: `/* ... *​/`
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
- label references, with or without a leading dot, such as `msg` or `.msg`
- constant expressions, including arithmetic, shifts, and bitwise operators

Examples:

```asm
li $a0, msg
j loop
bne $t0, $t1, done
```

Label expressions may add or subtract a constant, for example `buffer+4` or `buffer-8`. A label cannot be combined with another label or used in a multiplication or bitwise expression. Names defined with `.equ` are constants and are evaluated during assembly.

## Relocations

A relocation is a symbolic value that cannot be encoded correctly until the linker knows the final address of its label. The assembler keeps the label and any constant addend in the intermediate representation; it does not guess an address or emit a runtime relocation table. During linking, Retrolang lays out the instructions and data, assigns absolute addresses, then patches the affected instruction fields and data bytes before writing the PS-X EXE.

Data follows the assembled code, and each data entry is padded to a four-byte boundary. Consequently, adding or removing instructions can change data addresses. The linker accounts for instruction expansion (including label-based `li`) before resolving references.

### Full-address references

These forms use the absolute address of a label, including its optional addend:

- `li` and `la` load the full 32-bit address. A label-based form expands to two machine instructions for a PS-X EXE address.
- `j` and `jal` encode a label as a jump target. MIPS jump instructions require a four-byte-aligned target in the same 256 MiB region as the instruction following the jump.
- `.word label` stores the full 32-bit address in a word. It is supported in both `.text` and `.data`; data words are written little-endian.

For example, `li $a0, message+4` loads the address four bytes past `message`. The same addend rule applies to jump targets and `.word` references.

### Branch references

A branch label is not an absolute address in the instruction. The linker calculates a signed word displacement relative to the instruction after the branch:

`offset = (target_address - (branch_address + 4)) / 4`

The result must fit in a signed 16-bit immediate, from `-32768` through `32767` words. A numeric branch operand is already a raw word displacement and is not treated as a label relocation. Branch targets and addends should be four-byte aligned.

### `%hi` and `%lo`

An instruction immediate is only 16 bits wide, so a full address used by an instruction such as `lui`, `addiu`, or a load/store offset must be split into two halves. Use `%hi(expression)` and `%lo(expression)` to request those halves:

```asm
lui   $t0, %hi(object+4)
addiu $t0, $t0, %lo(object+4)
```

Both operators apply the addend before splitting the address. `%lo` is interpreted as a signed 16-bit value. `%hi` is adjusted for that sign extension, using the GNU-style rule:

`hi = ((A + 0x8000) >> 16) & 0xffff`

For example, if `object+4` resolves to `0x80018000`, `%hi` produces `0x8002` and `%lo` produces the encoded low bits `0x8000`, interpreted by `addiu` as `-32768`. Adding the halves gives the original address. This adjusted `%hi` convention is intended for a sign-extending low immediate such as `addiu` or a memory offset. `ori` zero-extends its immediate, so do not substitute it for `addiu` in this pair when the low half is at least `0x8000`; use `li` when a straightforward full-address load is preferable.

The same relocation forms are accepted in 16-bit instruction immediate slots, including `lui` and memory offsets. For a memory instruction with a base register, write the low relocation explicitly, for example `lw $t0, %lo(object)($at)`. A label without `%hi` or `%lo` cannot be used directly as an ordinary 16-bit immediate. The convenient absolute-address form `lw $t0, object` is expanded by the assembler into a high-half load followed by a low-half memory access.

### Relocation limits

- `%hi` and `%lo` are not accepted in `j`, `jal`, branch operands, or `.word` values.
- `.byte` and `.half` accept constants, not label relocations. Use `.word` for a stored address.
- Label references must resolve to a code or data label in the linked assembly. Undefined labels are linker errors.
- A branch outside the signed 16-bit word range is rejected by the linker.

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

- `$BPC`      - breakpoint on execute (R/W)
- `$BDA`      - breakpoint on data access (R/W)
- `$JUMPDEST` - randomly memorized jump address (R)
- `$DCIC`     - breakpoint control (R/W)
- `$BADVADDR` - bad virtual address (R)
- `$BDAM`     - data access breakpoint mask (R/W)
- `$BPCM`     - execute breakpoint mask (R/W)
- `$SR`       - system status (R/W)
- `$CAUSE`    - the most recently recognised exception (R)
- `$EPC`      - return address from trap (R)
- `$PRID`     - processor ID (R)

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
