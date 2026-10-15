; Prints "Hello, World!" to TTY

.text
  start:
    li $a0, msg
    li $t1, 0x003f
    li $t2, 0x00a0
    jalr $t2
    nop
    
  loop:
    li $t0, loop
    jalr $t0
    nop

.data
    msg: .asciiz "Hello, World!\n"
