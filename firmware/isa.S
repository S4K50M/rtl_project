.section .text.start
.globl _start
.macro check reg, val
    li t5, \val
    bne \reg, t5, fail
    addi t3, t3, 1
.endm
_start:
    li t3, 0
    li t1, 0x80000001
    li t2, 31
    sra t0, t1, t2
    check t0, -1
    srl t0, t1, t2
    check t0, 1
    sll t0, t1, t2
    check t0, 0x80000000
    srai t0, t1, 31
    check t0, -1
    srli t0, t1, 31
    check t0, 1
    slli t0, t2, 4
    check t0, 496
    slt t0, t1, t2
    check t0, 1
    sltu t0, t1, t2
    check t0, 0
    slti t0, t1, -1
    check t0, 1
    sltiu t0, t1, -1
    check t0, 1
    add t0, t1, t2
    check t0, 0x80000020
    sub t0, t1, t2
    check t0, 0x7fffffe2
    xor t0, t1, t2
    check t0, 0x8000001e
    or t0, t1, t2
    check t0, 0x8000001f
    and t0, t1, t2
    check t0, 1
    xori t0, t2, -1
    check t0, -32
    ori t0, t2, 64
    check t0, 95
    andi t0, t2, 15
    check t0, 15
    blt t2, t1, fail
    bge t1, t2, fail
    bltu t1, t2, fail
    bgeu t2, t1, fail
    beq t1, t2, fail
    bne t1, t1, fail
    blt t1, t2, 1f
    j fail
1:  bgeu t1, t2, 2f
    j fail
2:  jal t0, 3f
    j fail
3:  la t1, 3b
    addi t1, t1, -4
    bne t0, t1, fail
    la t0, 4f
    jalr zero, 0(t0)
    j fail
4:  li t4, 0x1800
    li t0, 0x89abcdef
    sw t0, 0(t4)
    lw t0, 0(t4)
    check t0, 0x89abcdef
    lb t0, 0(t4)
    check t0, -17
    lbu t0, 0(t4)
    check t0, 239
    lh t0, 2(t4)
    check t0, -30293
    lhu t0, 2(t4)
    check t0, 35243
    li t0, 0x80
    sb t0, 1(t4)
    li t0, 0x1234
    sh t0, 2(t4)
    lw t0, 0(t4)
    check t0, 0x123480ef
    addi zero, zero, 42
    check zero, 0
    fence rw, rw
    li t0, 0x600dcafe
    li t1, 0x1000
    sw t0, 0(t1)
    ebreak
fail:
    li t1, 0x1000
    sw t3, 0(t1)
    .word 0
