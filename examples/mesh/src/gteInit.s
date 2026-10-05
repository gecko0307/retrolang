; void gteInit() - enable GTE

.text
    mfc0    $t0, $12
    nop
    ori     $t0, $t0, 0x40000000
    mtc0    $t0, $12
    nop
    addiu   $t0, $0, 0x555
    ctc2    $t0, $ZSF3
    nop
    nop
