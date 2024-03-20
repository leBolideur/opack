.global main
.align 4

.text
main:
    mov x0, #0
    adrp x1, msg@PAGE
    add x1, x1, msg@PAGEOFF
    mov x2, #13
    mov x16, #4
    svc 0

    mov x0, #0
    mov x16, #1
    svc 0

.data
msg:
    .asciz "Hello, World !"
