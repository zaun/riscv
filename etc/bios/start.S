.section .text
.global _start

_start:
    lui     sp, 0x0          # Load upper 20 bits with 0x0, sp = 0x00000000
    addi    sp, sp, 0x700     # Add immediate 0x700, sp = 0x00000700
    addi    sp, sp, 0x7F8     # Add immediate 0x7F8, sp = 0x00000FF8
    addi    sp, sp, -8        # Subtract 8, sp = 0x00000FF0
    mv      s0, sp            # Initialize frame pointer (s0) to sp

    call main                # Call the main function

hlt:
    jal x0, hlt              # Infinite loop to halt if main returns
