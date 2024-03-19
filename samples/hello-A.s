.global main
.align 4

.text
main:
    // Préparer le pointeur vers la lettre 'A'
    adr x1, msg       // x1 obtient l'adresse du message
    mov x2, #1        // Taille du message (1 octet)
    mov x0, #1        // Descripteur de fichier stdout
    mov x16, #4      // Numéro syscall pour write
    svc 0             // Appel système write

    // Appel système pour terminer le programme
    mov x0, #0        // Code de sortie
    mov x16, #93    // Numéro syscall pour exit
    svc 0             // Appel système exit

    // Stocker 'A' directement dans le texte (inline)
msg:
    .byte 65          // Code ASCII pour 'A'
