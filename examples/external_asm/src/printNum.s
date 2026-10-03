; printNum.s

.text
    ; printf("%d\n\0", arg0)
    move $t0, $a0
    li   $a0, .msg
    move $a1, $t0
    li   $t1, 0x003f
    li   $t2, 0x00a0
    jalr  $t2
    nop

    ; return 1
    li   $v0, 0x01

.data
    .msg:
        "%d\n\0"
