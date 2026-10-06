# Retrolang Assembler

Retrolang implements a minimalistic MIPS-I assembler which can be used to write entire programs or separate functions.

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

Examples:

```asm
move $t0, $a0
li $v0, 0x01
jr $ra
```

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

### System and coprocessor ops

```asm
syscall [code]
break [code]
mtc0 rt, rd
mfc0 rt, rd
mtc2 rt, data_reg
mfc2 rt, data_reg
ctc2 rt, control_reg
cfc2 rt, control_reg
cop2 imm
rtps
rtpt
```

GTE support is partial at the moment.
