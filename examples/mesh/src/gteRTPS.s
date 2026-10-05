; void gteRTPS(struct RTPSTransform* rtpsTransform, short* inVertex, struct SVertex* outVertex)

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

    ; Projection params rtpsTransform->h,ofx,ofy,dqa,fqb
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

    ; inVertex
    lw      $t0,  0($a1)
    lw      $t1,  4($a1)
    nop
    mtc2    $t0,  $VXY0
    mtc2    $t1,  $VZ0
    nop
    nop
    rtps
    nop
    nop

    ; Get results
    mfc2    $t0,  $SXY2
    mfc2    $t1,  $SZ3
    nop
    sh      $t0,  0($a2)
    srl     $t0,  $t0, 16
    sh      $t0,  2($a2)
    sh      $t1,  4($a2)
