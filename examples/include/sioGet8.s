.text
    lui     $t0, 0x1F80
    addu    $t0, $t0, $a0
    lbu     $v0, 0($t0)

