; void gteRTPT(struct RTPSTransform* rtpsTransform, struct Vertex* inVertices, struct SVertex* outVertices)

.text
    ; Translation rtpsTransform->tx,ty,tz
    lw      $t0,  0($a0)
    lw      $t1,  4($a0)
    lw      $t2,  8($a0)
    ctc2    $t0,  $TRX
    ctc2    $t1,  $TRY
    ctc2    $t2,  $TRZ

    ; Rotation matrix rtpsTransform->r
    lw      $t0,  12($a0)
    lw      $t1,  16($a0)
    lw      $t2,  20($a0)
    lw      $t3,  24($a0)
    lw      $t4,  28($a0)
    ctc2    $t0,  $R11R12
    ctc2    $t1,  $R13R21
    ctc2    $t2,  $R22R23
    ctc2    $t3,  $R31R32
    ctc2    $t4,  $R33

    ; Projection params rtpsTransform->h,ofx,ofy,dqa,dqb
    lh      $t0,  30($a0)
    lw      $t1,  32($a0)
    lw      $t2,  36($a0)
    lh      $t3,  40($a0)
    lh      $t4,  42($a0)
    ctc2    $t0,  $H
    ctc2    $t1,  $OFX
    ctc2    $t2,  $OFY
    ctc2    $t3,  $DQA
    ctc2    $t4,  $DQB

    ; Load three packed vertices
    lw      $t0,  0($a1)
    lw      $t1,  4($a1)
    lw      $t2,  8($a1)
    lw      $t3, 12($a1)
    lw      $t4, 16($a1)
    lw      $t5, 20($a1)
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
    sh      $t0,  0($a2)
    srl     $t0,  $t0, 16
    sh      $t0,  2($a2)
    sh      $t1,  4($a2)

    ; Store SXY1/SZ2
    mfc2    $t0,  $SXY1
    mfc2    $t1,  $SZ2
    nop
    sh      $t0,  8($a2)
    srl     $t0,  $t0, 16
    sh      $t0, 10($a2)
    sh      $t1, 12($a2)

    ; Store SXY2/SZ3
    mfc2    $t0,  $SXY2
    mfc2    $t1,  $SZ3
    nop
    sh      $t0, 16($a2)
    srl     $t0,  $t0, 16
    sh      $t0, 18($a2)
    sh      $t1, 20($a2)