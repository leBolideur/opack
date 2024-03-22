.global main
.align 4

.text
main:
    mov x0, #1
    adrp x1, msg@page
    add x1, x1, msg@pageoff

    mov x2, len
    # mov x2, #11
    mov x16, #4
    svc 0

    mov x0, #1
    adrp x1, msg2@page
    add x1, x1, msg2@pageoff
    mov x2, len2
    mov x16, #4
    svc 0

    mov x0, #0
    mov x16, #1
    svc 0

.data
    msg: .asciz "Hello, you\n"
    len = . - msg
    msg2: .asciz "Hello, world!"
    len2 = . - msg2
