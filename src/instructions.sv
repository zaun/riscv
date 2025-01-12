`ifndef __INSTRUCTIONS__
`define __INSTRUCTIONS__

// TODO: Verify the F, D and Q extenstions

/////////////////////////////////////
/// R-Type Register Instructions (operand, funct7, funct3)
/////////////////////////////////////

`define INST_ADD       17'b0110011_0000000_000 // I Integer add *
`define INST_SUB       17'b0110011_0100000_000 // I Subtract *
`define INST_SLL       17'b0110011_0000000_001 // I Shift left logical *
`define INST_SLT       17'b0110011_0000000_010 // I Set on less than *
`define INST_SLTU      17'b0110011_0000000_011 // I Set on less than unsigned *
`define INST_XOR       17'b0110011_0000000_100 // I Exclusive OR *
`define INST_SRL       17'b0110011_0000000_101 // I Shift right logical *
`define INST_SRA       17'b0110011_0100000_101 // I Shift right arithmetic *
`define INST_OR        17'b0110011_0000000_110 // I Or *
`define INST_AND       17'b0110011_0000000_111 // I And *
`define INST_ADDW      17'b0111011_0000000_000 // I Add word *
`define INST_SUBW      17'b0111011_0100000_000 // I Subtract word *
`define INST_SLLW      17'b0111011_0000000_001 // I Shift left logical word *
`define INST_SRLW      17'b0111011_0000000_101 // I Shift right logical word *
`define INST_SRAW      17'b0111011_0100000_101 // I Shift right arithmetic word *

`define INST_DIV       17'b0110011_0000001_100 // M Signed division *
`define INST_DIVU      17'b0110011_0000001_101 // M Unsigned division *
`define INST_MUL       17'b0110011_0000001_000 // M Signed multiply *
`define INST_MULH      17'b0110011_0000001_001 // M Signed multiply high *
`define INST_MULHSU    17'b0110011_0000001_010 // M Signed/unsigned multiply high *
`define INST_MULHU     17'b0110011_0000001_011 // M Unsigned multiply high *
`define INST_REM       17'b0110011_0000001_110 // M Signed remainder *
`define INST_REMU      17'b0110011_0000001_111 // M Unsigned remainder *
`define INST_DIVUW     17'b0111011_0000001_101 // M Unsigned word division *
`define INST_DIVW      17'b0111011_0000001_100 // M Signed word division *
`define INST_MULW      17'b0111011_0000001_000 // M Signed word multiply *
`define INST_REMUW     17'b0111011_0000001_111 // M Unsigned word remainder *
`define INST_REMW      17'b0111011_0000001_110 // M Signed word remainder *

`define INST_ANDN      17'b0110011_0100000_111 // B And with inverted operand
`define INST_BCLR      17'b0110011_0100100_001 // B Single-Bit clear (Register)
`define INST_BEXT      17'b0110011_0100100_101 // B Single-Bit extract (Register)
`define INST_BINV      17'b0110011_0110100_001 // B Single-Bit invert (Register)
`define INST_BSET      17'b0110011_0010100_001 // B Single-Bit set (Register)
`define INST_CLMUL     17'b0110011_0000101_001 // B Carry-less multiply (low-part)
`define INST_CLMULH    17'b0110011_0000101_011 // B Carry-less multiply (high-part)
`define INST_CLMULR    17'b0110011_0000101_010 // B Carry-less multiply (reversed)
`define INST_MAX       17'b0110011_0000101_110 // B Maximum
`define INST_MAXU      17'b0110011_0000101_111 // B Unsigned maximum
`define INST_MIN       17'b0110011_0000101_100 // B Minimum
`define INST_MINU      17'b0110011_0000101_101 // B Unsigned minimum
`define INST_ORN       17'b0110011_0100000_110 // B OR with inverted operand
`define INST_ROL       17'b0110011_0110000_001 // B Rotate left (Register)
`define INST_ROR       17'b0110011_0110000_101 // B Rotate right (Register)
`define INST_RORW      17'b0111011_0110000_101 // B Rotate right word (Register)
`define INST_SH1ADD    17'b0110011_0010000_010 // B Shift left by 1 and add
`define INST_SH2ADD    17'b0110011_0010000_100 // B Shift left by 2 and add
`define INST_SH3ADD    17'b0110011_0010000_110 // B Shift left by 3 and add
`define INST_XNOR      17'b0110011_0100000_100 // B Exclusive NOR
`define INST_XPERM16   17'b0110011_0010100_110 // B Crossbar Permutation Instruction (word)
`define INST_XPERM32   17'b0110011_0010100_000 // B Crossbar Permutation Instruction (half-word)
`define INST_XPERM4    17'b0110011_0010100_010 // B Crossbar Permutation Instruction (nibble)
`define INST_XPERM8    17'b0110011_0010100_100 // B Crossbar Permutation Instruction (byte)
`define INST_ZEXTH32   17'b0110011_0000100_100 // B Zero-extend halfword (XLEN=32)
`define INST_ZEXTH64   17'b0111011_0000100_100 // B Zero-extend halfword (XLEN=64)
`define INST_ADD_UW    17'b0111011_0000100_000 // B Add unsigned word
`define INST_ROLW      17'b0111011_0110000_001 // B Rotate left word (Register)
`define INST_SH1ADD_UW 17'b0111011_0010000_010 // B Shift unsigend word left by 1 and add
`define INST_SH2ADD_UW 17'b0111011_0010000_100 // B Shift unsigend word left by 2 and add
`define INST_SH3ADD_UW 17'b0111011_0010000_110 // B Shift unsigend word left by 3 and add

`define INST_FADD_S    17'b1010011_0000000_000 // F Floating-point add single
`define INST_FSUB_S    17'b1010011_0100000_000 // F Floating-point subtract single
`define INST_FMUL_S    17'b1010011_0000001_000 // F Floating-point multiply single
`define INST_FDIV_S    17'b1010011_0000101_000 // F Floating-point divide single
`define INST_FSGNJ_S   17'b1010011_0000000_001 // F Floating-point sign injection single
`define INST_FSGNJN_S  17'b1010011_0100000_001 // F Floating-point sign injection negated single
`define INST_FSGNJX_S  17'b1010011_0010000_001 // F Floating-point sign injection XOR single
`define INST_FMIN_S    17'b1010011_0000000_010 // F Floating-point minimum single
`define INST_FMAX_S    17'b1010011_0000000_011 // F Floating-point maximum single
`define INST_FMINU_S   17'b1010011_0000000_010 // F Floating-point minimum unordered single
`define INST_FMAXU_S   17'b1010011_0000000_011 // F Floating-point maximum unordered single
`define INST_FEQ_S     17'b1010011_0000000_100 // F Floating-point equal single
`define INST_FLT_S     17'b1010011_0000000_101 // F Floating-point less than single
`define INST_FLE_S     17'b1010011_0000000_110 // F Floating-point less than or equal single
`define INST_FCLASS_S  17'b1010011_0000000_001 // F Floating-point classify single

`define INST_FADD_D    17'b1010011_0000000_000 // D Floating-point add double
`define INST_FSUB_D    17'b1010011_0100000_000 // D Floating-point subtract double
`define INST_FMUL_D    17'b1010011_0000001_000 // D Floating-point multiply double
`define INST_FDIV_D    17'b1010011_0000101_000 // D Floating-point divide double
`define INST_FSGNJ_D   17'b1010011_0000000_001 // D Floating-point sign injection double
`define INST_FSGNJN_D  17'b1010011_0100000_001 // D Floating-point sign injection negated double
`define INST_FSGNJX_D  17'b1010011_0010000_001 // D Floating-point sign injection XOR double
`define INST_FMIN_D    17'b1010011_0000000_010 // D Floating-point minimum double
`define INST_FMAX_D    17'b1010011_0000000_011 // D Floating-point maximum double
`define INST_FMINU_D   17'b1010011_0000000_010 // D Floating-point minimum unordered double
`define INST_FMAXU_D   17'b1010011_0000000_011 // D Floating-point maximum unordered double
`define INST_FEQ_D     17'b1010011_0000000_100 // D Floating-point equal double
`define INST_FLT_D     17'b1010011_0000000_101 // D Floating-point less than double
`define INST_FLE_D     17'b1010011_0000000_110 // D Floating-point less than or equal double
`define INST_FCLASS_D  17'b1010011_0000000_001 // D Floating-point classify double

`define INST_FADD_Q    17'b1010011_0000000_000 // Q Floating-point add quad
`define INST_FSUB_Q    17'b1010011_0100000_000 // Q Floating-point subtract quad
`define INST_FMUL_Q    17'b1010011_0000001_000 // Q Floating-point multiply quad
`define INST_FDIV_Q    17'b1010011_0000101_000 // Q Floating-point divide quad
`define INST_FSGNJ_Q   17'b1010011_0000000_001 // Q Floating-point sign injection quad
`define INST_FSGNJN_Q  17'b1010011_0100000_001 // Q Floating-point sign injection negated quad
`define INST_FSGNJX_Q  17'b1010011_0010000_001 // Q Floating-point sign injection XOR quad
`define INST_FMIN_Q    17'b1010011_0000000_010 // Q Floating-point minimum quad
`define INST_FMAX_Q    17'b1010011_0000000_011 // Q Floating-point maximum quad
`define INST_FMINU_Q   17'b1010011_0000000_010 // Q Floating-point minimum unordered quad
`define INST_FMAXU_Q   17'b1010011_0000000_011 // Q Floating-point maximum unordered quad
`define INST_FEQ_Q     17'b1010011_0000000_100 // Q Floating-point equal quad
`define INST_FLT_Q     17'b1010011_0000000_101 // Q Floating-point less than quad
`define INST_FLE_Q     17'b1010011_0000000_110 // Q Floating-point less than or equal quad
`define INST_FCLASS_Q  17'b1010011_0000000_001 // Q Floating-point classify quad

/////////////////////////////////////
/// I-Type Immediate Instricntions (opcode, funct3, IMM[31:19])
/////////////////////////////////////

`define INST_ADDI    22'b0010011_000_???????????? // I Add immediate *
`define INST_SLLI    22'b0010011_001_000000?????? // I Shift left logical immediate *
`define INST_SLTI    22'b0010011_010_???????????? // I Set on less than immediate *
`define INST_SLTIU   22'b0010011_011_???????????? // I Set on less than immediate unsigned *
`define INST_XORI    22'b0010011_100_???????????? // I Exclusive Or immediate *
`define INST_SRLI    22'b0010011_101_000000?????? // I Shift right logical immediate *
`define INST_SRAI    22'b0010011_101_010000?????? // I Shift right arithmetic *
`define INST_ORI     22'b0010011_110_???????????? // I Or immediate *
`define INST_ANDI    22'b0010011_111_???????????? // I And immediate *
`define INST_ADDIW   22'b0011011_000_???????????? // I Add immediate word *
`define INST_SLLIW   22'b0011011_001_000000?????? // I Shift left logical immediate word *
`define INST_SRLIW   22'b0011011_101_000000?????? // I Shift right logical immediate word *
`define INST_SRAIW   22'b0011011_101_010000?????? // I Shift right arithmetic *

`define INST_BCLRI   22'b0010011_001_010010?????? // B Single-Bit clear (Immediate)           (31-25 = 0100100, 31-26 = 010010)
`define INST_BINVI   22'b0010011_001_011010?????? // B Single-Bit invert (Immediate)          (31-25 = 0110100, 31-26 = 011010)
`define INST_BSETI   22'b0010011_001_001010?????? // B Single-Bit set (Immediate)             (31-25 = 0010100, 31-26 = 001010)
`define INST_CLZ     22'b0010011_001_011000000000 // B Count leading zero bits                (IMM = 011000000000)
`define INST_CPOP    22'b0010011_001_011000000010 // B Count Bits Set                         (IMM = 011000000010)
`define INST_CTZ     22'b0010011_001_011000000001 // B Count trailing zero bits               (IMM = 011000000001)
`define INST_SEXTB   22'b0010011_001_011000000100 // B Sign-extend byte                       (IMM = 011000000100)
`define INST_SEXTH   22'b0010011_001_011000000101 // B Sign-extend halfword                   (IMM = 011000000101)
`define INST_SHFLI   22'b0010011_001_000010?????? // B Generalized Shuffle immediate          (31-25 = 0000100) (ZIP)
`define INST_BEXTI   22'b0010011_101_010010?????? // B Single-Bit extract (Immediate)         (31-25 = 0100100, 31-26 = 010010)
`define INST_GREVI   22'b0010011_101_011010?????? // B Generalised Reverse with Immediate     (31-36 = 011010) (BREV8, REV8)
`define INST_ORCB    22'b0010011_101_001010000111 // B Bitware OR-combine, byte granule       (IMM = 001010000111)
`define INST_RORI    22'b0010011_101_011000?????? // B Rotate right (Immediate)               (31-35 = 0110000)
`define INST_UNSHFLI 22'b0010011_101_000010?????? // B Generalized Unshuffle immediate        (31-25 = 0000100) (UNZIP)
`define INST_CLZW    22'b0011011_001_011000000000 // B Count leading zero bits in word        (IMM = 011000000000)
`define INST_CPOPW   22'b0011011_001_011000000010 // B Count leading zero bits in word        (IMM = 011000000010)
`define INST_CTZW    22'b0011011_001_011000000001 // B Count leading zero bits in word        (IMM = 011000000001)
`define INST_RORIW   22'b0011011_101_011000?????? // B Rotate right word (Immediate)          (31-35 = 0110000)
`define INST_SLLIUW  22'b0011011_001_000010?????? // B Shift left unsigned word (Immediate)   (31-26 = 000010)

`define INST_FLW     22'b0000011_010_???????????? // F Load floating-point word
`define INST_FSW     22'b0100011_010_???????????? // F Store floating-point word

`define INST_FLD     22'b0000011_011_???????????? // D Load floating-point doubleword
`define INST_FSD     22'b0100011_011_???????????? // D Store floating-point doubleword

`define INST_FLQ     22'b0000011_100_???????????? // Q Load floating-point quadword
`define INST_FSQ     22'b0100011_100_???????????? // Q Store floating-point quadword

/////////////////////////////////////
/// I-Type Branch (opcode, funct3)
/////////////////////////////////////

`define INST_BEQ     10'b1100011_000 // I Branch if equal *
`define INST_BGE     10'b1100011_101 // I Branch if greater than or equal *
`define INST_BGEU    10'b1100011_111 // I Branch if greater than or equal unsigned *
`define INST_BLT     10'b1100011_100 // I Branch if less than *
`define INST_BLTU    10'b1100011_110 // I Branch if less than unsigned *
`define INST_BNE     10'b1100011_001 // I Branch if not equal *

/////////////////////////////////////
/// I-Type Load (opcode, funct3)
/////////////////////////////////////

`define INST_LB      10'b0000011_000 // I Load byte *
`define INST_LBU     10'b0000011_100 // I Load byte Unsigned *
`define INST_LD      10'b0000011_011 // I Load doubleword
`define INST_LH      10'b0000011_001 // I Load halfword *
`define INST_LHU     10'b0000011_101 // I Load halfword unsigned *
`define INST_LW      10'b0000011_010 // I Load word *
`define INST_LWU     10'b0000011_110 // I Load word unsigned

/////////////////////////////////////
/// S-Type Store (opcode, funct3)
/////////////////////////////////////

`define INST_SB      10'b0100011_000 // I Store byte *
`define INST_SD      10'b0100011_011 // I Store double word *
`define INST_SH      10'b0100011_001 // I Store halfword *
`define INST_SW      10'b0100011_010 // I Store word *

/////////////////////////////////////
/// I-Type Fence (opcode, funct3)
/////////////////////////////////////

`define INST_FENCE     10'b0001111_000 // I Memory ordering fence
`define INST_FENCEI    10'b0001111_001 // I Instruction fence

`define INST_FENCE_F   10'b0001111_010 // F Floating-point fence

`define INST_FENCE_F_D 10'b0001111_010 // D Floating-point fence

`define INST_FENCE_F_Q 10'b0001111_011 // Q Floating-point fence for quad

/////////////////////////////////////
/// I-Type System (opcode, funct3, funct12)
/////////////////////////////////////

`define INST_EBREAK    22'b1110011_000_000000000001 // I  Breakpoint exception *
`define INST_ECALL     22'b1110011_000_000000000000 // I  Environment call *
`define INST_MRET      22'b1110011_000_001100000010 // Sm Machine Exception Return *
`define INST_SRET      22'b1110011_000_000100000010 // S  Supervisor Exception Return
`define INST_WIFI      22'b1110011_000_000100000101 // Sm Wait for interrupt
`define INST_CSRRC     22'b1110011_011_???????????? // CSR Atomic Read and Clear Bits *
`define INST_CSRRCI    22'b1110011_111_???????????? // CSR Atomic Read and Clear Bits (Immediate) *
`define INST_CSRRS     22'b1110011_010_???????????? // CSR Atomic Read and Set Bits in CSR *
`define INST_CSRRSI    22'b1110011_110_???????????? // CSR Atomic Read and Set Bits in CSR (Immediate) *
`define INST_CSRRW     22'b1110011_001_???????????? // CSR Atomic Read/Write CSR *
`define INST_CSRRWI    22'b1110011_101_???????????? // CSR Atomic Read/Write CSR (Immediate) *

`define INST_FCVT_W_S  22'b1110011_000_000000000001 // F Convert float to int word single
`define INST_FCVT_WU_S 22'b1110011_000_000000000101 // F Convert float to unsigned int word single
`define INST_FCVT_S_W  22'b1110011_000_000000001001 // F Convert int word to float single
`define INST_FCVT_S_WU 22'b1110011_000_000000001101 // F Convert unsigned int word to float single
`define INST_FMV_X_W   22'b1110011_000_000000010001 // F Move float to integer register
`define INST_FMV_W_X   22'b1110011_000_000000010101 // F Move integer to float register
`define INST_FMV_S_X   22'b1110011_000_000000010001 // F Move float to integer register
`define INST_FMV_X_S   22'b1110011_000_000000010101 // F Move integer to float register

`define INST_FCVT_W_D  22'b1110011_000_000000000001 // D Convert float to int word double
`define INST_FCVT_WU_D 22'b1110011_000_000000000101 // D Convert float to unsigned int word double
`define INST_FCVT_D_W  22'b1110011_000_000000001001 // D Convert int word to float double
`define INST_FCVT_D_WU 22'b1110011_000_000000001101 // D Convert unsigned int word to float double
`define INST_FMV_X_D   22'b1110011_000_000000010001 // D Move float to integer register (double)
`define INST_FMV_D_X   22'b1110011_000_000000010101 // D Move integer to float register (double)
`define INST_FMV_D_X   22'b1110011_000_000000010101 // D Move integer to float register (double)
`define INST_FMV_X_D   22'b1110011_000_000000010001 // D Move float to integer register (double)

`define INST_FCVT_W_Q  22'b1110011_000_000000000001 // Q Convert quad to int word
`define INST_FCVT_WU_Q 22'b1110011_000_000000000101 // Q Convert quad to unsigned int word
`define INST_FCVT_Q_W  22'b1110011_000_000000001001 // Q Convert int word to quad
`define INST_FCVT_Q_WU 22'b1110011_000_000000001101 // Q Convert unsigned int word to quad
`define INST_FMV_X_Q   22'b1110011_000_000000010001 // Q Move quad to integer register
`define INST_FMV_Q_X   22'b1110011_000_000000010101 // Q Move integer to quad register

/////////////////////////////////////
/// Other (operand)
/////////////////////////////////////

`define INST_AUIPC  10'b0010111 // S Add upper immediate to pc
`define INST_LUI    10'b0110111 // I Load upper immediate
`define INST_JAL    10'b1101111 // I Jump and link
`define INST_JALR   10'b1100111 // I Jump and link register

`endif // __INSTRUCTIONS__
