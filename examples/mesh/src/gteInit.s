; void gteInit()

.text
    ; Enable GTE
    mfc0    $t0, $12
    nop
    lui     $t1, 0x4000
    or      $t0, $t0, $t1
    mtc0    $t0, $12
    nop
    
    ; For AVSZ3
    addiu   $t0, $0, 0x555
    ctc2    $t0, $ZSF3
    nop
    nop
