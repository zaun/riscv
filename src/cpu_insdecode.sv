`ifndef __CPU_INSDECODE__
`define __CPU_INSDECODE__
///////////////////////////////////////////////////////////////////////////////////////////////////
// Instruction Decoder Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module cpu_insdecode
 * @brief Decodes a 32-bit RISC-V instruction into its constituent fields and
 * control signals.
 *
 * The `cpu_insdecode` module takes a 32-bit instruction as input and extracts
 * the opcode, rd, funct3, rs1, rs2, funct7, and immediate fields. It also
 * generates control signals indicating the type of instruction, such as
 * whether it's a load, store, ALU operation, branch, etc.
 *
 * Features:
 * - Supports immediate generation for different instruction formats.
 * - Generates control signals for instruction types.
 * - Conditionally includes support for Zicsr and Zifencei extensions.
 *
 * Developers should be aware that:
 * - The module uses `ifdef` directives to conditionally include outputs for
 *   optional extensions.
 * - Immediate values are sign-extended as per RISC-V specification.
 */

`timescale 1ns / 1ps
`default_nettype none

module cpu_insdecode #(
    parameter XLEN = 32  // Data width: 32 or 64 bits
) (
    input  wire [31:0]     instr,
    output reg  [6:0]      opcode,
    output reg  [4:0]      rd,
    output reg  [2:0]      funct3,
    output reg  [4:0]      rs1,
    output reg  [4:0]      rs2,
    output reg  [6:0]      funct7,
    output reg  [11:0]     funct12,
    output reg  [XLEN-1:0] imm,

    // Control Signals
    output reg             is_mem,
    output reg             is_op_imm,
    output reg             is_op,
    output reg             is_lui,
    output reg             is_auipc,
    output reg             is_branch,
    output reg             is_jal,
    output reg             is_jalr,
    output reg             is_system
    `ifdef SUPPORT_ZIFENCEI
    ,output reg             is_fence
    `endif
    `ifdef SUPPORT_M
    ,output reg             is_mul_div
    `endif
    `ifdef SUPPORT_F
    ,output reg             is_fpu
    `endif
);

// ──────────────────────────
// Extract Fields
// ──────────────────────────
assign opcode = instr[6:0];
assign rd     = instr[11:7];
assign funct3 = instr[14:12];
assign rs1    = instr[19:15];
assign rs2    = instr[24:20];
assign funct7 = instr[31:25];
assign funct12 = instr[31:20];

// ──────────────────────────
// Immediate Generation
// ──────────────────────────
always_comb begin
    case (opcode)
        7'b0010011, // OP-IMM
        7'b0011011: // OP-IMM-64
            if (funct3 == 3'b001 || funct3 == 3'b101) // Shift operations
                imm = {27'b0, instr[24:20]}; // Extract shift amount as unsigned
            else
                imm = {{(XLEN-12){instr[31]}}, instr[31:20]}; // Sign-extend immediate
        7'b0000011, // LOAD
        7'b1110011, // SYSTEM
        7'b1100111, // JALR
        7'b0001111: // FENCE and FENCE.I
            imm = {{(XLEN-12){instr[31]}}, instr[31:20]};
        7'b0100011: // STORE
            imm = {{(XLEN-12){instr[31]}}, instr[31], instr[30:25], instr[11:7]};
        7'b1100011: // BRANCH
            imm = {{(XLEN-13){instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
        7'b0110111, // LUI
        7'b0010111: // AUIPC
            imm = {{(XLEN-32){instr[31]}}, instr[31:12], {12{1'b0}}};
        7'b1101111: // JAL
            imm = {{(XLEN-21){instr[31]}}, instr[31], instr[19:12],
                    instr[20], instr[30:21], 1'b0};
        default:
            imm = {XLEN{1'b0}};
    endcase
end

// ──────────────────────────
// Control Signals
// ──────────────────────────
assign is_mem     = (opcode == 7'b0000011) || (opcode == 7'b0100011);
assign is_op_imm  = (opcode == 7'b0010011) || (opcode == 7'b0011011);
assign is_op      = (opcode == 7'b0110011) || (opcode == 7'b0111011);
assign is_lui     = (opcode == 7'b0110111);
assign is_auipc   = (opcode == 7'b0010111);
assign is_branch  = (opcode == 7'b1100011);
assign is_jal     = (opcode == 7'b1101111);
assign is_jalr    = (opcode == 7'b1100111);
assign is_system  = (opcode == 7'b1110011);


`ifdef SUPPORT_ZIFENCEI
assign is_fence   = (opcode == 7'b0001111);
`endif

`ifdef SUPPORT_M
assign is_mul_div = ((opcode == 7'b0110011) && (funct7 == 7'b0000001) ||
                        (opcode == 7'b0111011) && (funct7 == 7'b0000001));
`endif

`ifdef SUPPORT_F
assign is_fpu     = (opcode == 7'b1010011);
`endif

endmodule

`endif // __CPU_INSDECODE__
