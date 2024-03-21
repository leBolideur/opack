.global main
.align 4

.text
main:
    mov x0, #1
    adrp x1, msg@page
    # add x1, x1, #14
    mov x2, #14
    mov x16, #4
    svc 0

    mov x0, #0
    mov x16, #1
    svc 0

.data
    msg: .ascii "Hello, you"
