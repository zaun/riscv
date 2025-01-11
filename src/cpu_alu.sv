`default_nettype none
`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////
// ALU Module
//////////////////////////////////////////////////////////////////////////////
/**
 * @module cpu_alu
 * @brief Performs arithmetic and logical operations.
 *
 * The ALU module executes arithmetic and logical operations based on the
 * `control` signal. It is designed to support base riscv i instructions.
 *
 * Features:
 * - Provides flags for zero result, less than, and unsigned less than
 *   comparisons.
 */

// -----------------------------
// ALU Operation Encoding
// -----------------------------
`define ALU_ADD  4'b0000 // 0  Add two operands
`define ALU_SUB  4'b0001 // 1  Subtract operand_b from operand_a
`define ALU_AND  4'b0010 // 2  Bitwise AND of two operands
`define ALU_OR   4'b0011 // 3  Bitwise OR of two operands
`define ALU_XOR  4'b0100 // 4  Bitwise XOR of two operands
`define ALU_SLL  4'b0101 // 5  Shift operand_b left logical by operand_a[4:0] bits
`define ALU_SRL  4'b0110 // 6  Shift operand_b right logical by operand_a[4:0] bits
`define ALU_SRA  4'b0111 // 7  Shift operand_b right arithmetic by operand_a[4:0] bits
`define ALU_SLT  4'b1000 // 8  Set less than (signed comparison)
`define ALU_SLTU 4'b1001 // 9  Set less than unsigned

module cpu_alu #(
    parameter XLEN = 32
) (
    input  logic [XLEN-1:0] operand_a,
    input  logic [XLEN-1:0] operand_b,
    input  logic [3:0]      control,
    output logic [XLEN-1:0] result,
    output logic            zero,
    output logic            less_than,
    output logic            unsigned_less_than
);

// -----------------------------
// Shift Bits Calculation
// -----------------------------
localparam SHIFT_BITS = $clog2(XLEN); // 5 for XLEN=32, 6 for XLEN=64

// -----------------------------
// Internal Signals for Signed Comparisons
// -----------------------------
logic signed [XLEN-1:0] operand_a_signed;
assign operand_a_signed = operand_a;

logic signed [XLEN-1:0] operand_b_signed;
assign operand_b_signed = operand_b;

always_comb begin
    result = {XLEN{1'b0}};

    case (control)
        `ALU_ADD:  result = operand_a + operand_b;
        `ALU_SUB:  result = operand_a - operand_b;
        `ALU_AND:  result = operand_a & operand_b;
        `ALU_OR:   result = operand_a | operand_b;
        `ALU_XOR:  result = operand_a ^ operand_b;
        `ALU_SLL:  result = operand_a << operand_b[SHIFT_BITS-1:0];
        `ALU_SRL:  result = operand_a >> operand_b[SHIFT_BITS-1:0];
        `ALU_SRA:  result = operand_a_signed >>> operand_b[SHIFT_BITS-1:0];  // Arithmetic Right Shift
        `ALU_SLT:  result = (operand_a_signed < operand_b_signed) ? 1 : 0;   // Signed Comparison
        `ALU_SLTU: result = (operand_a < operand_b) ? 1 : 0;                 // Unsigned Comparison
        default:   result = {XLEN{1'b0}};
    endcase
end

// -----------------------------
// Flag Assignments
// -----------------------------

// Zero Flag: High if result is zero
assign zero                = (result == {XLEN{1'b0}});

// Less Than Flags
assign less_than           = (operand_a_signed < operand_b_signed); // Signed Comparison
assign unsigned_less_than  = (operand_a < operand_b);               // Unsigned Comparison

endmodule
