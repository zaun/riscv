.section .text
.global _start

_start:
    auipc t0, 0              # t0 = PC + (0 << 12) = PC
    mv t1, t0                # Copy PC from t0 to t1
    addi t0, t0, 2047        # Add 2047 to t0 (t0 = PC + 2047)
    addi t0, t0, 1969        # Add 1969 to t0 (t0 = PC + 4016)
    mv sp, t0                # Set sp to t0 (4016)
    
    mv s0, sp                # Initialize frame pointer (s0)

    mv a0, t1                # Move baseAddress from t1 to a0 (first argument register)
    call main                # Call the main function

hlt:
    jal x0, hlt              # Infinite loop to halt if main returns
