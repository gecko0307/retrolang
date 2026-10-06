; void gteInit()

.text
    ; Enable GTE
    mfc0    $t0, $12
    nop
    ori     $t0, $t0, 0x40000000
    mtc0    $t0, $12
    nop
    
    ; For AVSZ3
    addiu   $t0, $0, 0x555
    ctc2    $t0, $ZSF3
    nop
    nop
