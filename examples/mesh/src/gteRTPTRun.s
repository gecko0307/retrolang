; void gteRTPTRun(struct Vertex* inVertices, struct SVertex* outVertices)

.text
    ; Load three packed vertices
    lw      $t0,  0($a0)
    lw      $t1,  4($a0)
    lw      $t2,  8($a0)
    lw      $t3, 12($a0)
    lw      $t4, 16($a0)
    lw      $t5, 20($a0)
    mtc2    $t0,  $VXY0
    mtc2    $t1,  $VZ0
    mtc2    $t2,  $VXY1
    mtc2    $t3,  $VZ1
    mtc2    $t4,  $VXY2
    mtc2    $t5,  $VZ2
    nop
    nop
    rtpt
    nop
    nop

    ; Store SXY0/SZ1
    mfc2    $t0,  $SXY0
    mfc2    $t1,  $SZ1
    nop
    sh      $t0,  0($a1)
    srl     $t0,  $t0, 16
    sh      $t0,  2($a1)
    sh      $t1,  4($a1)

    ; Store SXY1/SZ2
    mfc2    $t0,  $SXY1
    mfc2    $t1,  $SZ2
    nop
    sh      $t0,  8($a1)
    srl     $t0,  $t0, 16
    sh      $t0, 10($a1)
    sh      $t1, 12($a1)

    ; Store SXY2/SZ3
    mfc2    $t0,  $SXY2
    mfc2    $t1,  $SZ3
    nop
    sh      $t0, 16($a1)
    srl     $t0,  $t0, 16
    sh      $t0, 18($a1)
    sh      $t1, 20($a1)
