///////////////////////////////////////////////////////////////////////////////////////////////////
// ALU Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module cpu_alu
 * @brief Performs arithmetic and logical operations.
 *
 * The ALU (Arithmetic Logic Unit) is a fundamental component of the CPU responsible for 
 * performing arithmetic and logical operations based on the provided control signal. 
 * It supports a range of RISC-V base integer instructions, including addition, subtraction, 
 * bitwise logic operations, shifts, and comparisons. The operations are all combinational logic.
 *
 * ## Features
 * - **Arithmetic Operations**: Addition and subtraction of two operands.
 * - **Logical Operations**: Bitwise AND, OR, XOR.
 * - **Shift Operations**: Logical and arithmetic left/right shifts.
 * - **Comparison Operations**: Signed and unsigned less-than checks.
 * - **Flags**:
 *   - Zero (`zero`): Asserted when the result is zero.
 *   - Less Than (`less_than`): Asserted for signed less-than comparisons of operands.
 *   - Unsigned Less Than (`unsigned_less_than`): Asserted for unsigned less-than comparisons of
 *                                                operands.
 *
 * ## Parameters
 * - `XLEN`: Configurable data width of the operands (default is 32 bits).
 *
 * ## Interface
 * - Inputs:
 *   - `operand_a`: First operand (XLEN bits).
 *   - `operand_b`: Second operand (XLEN bits).
 *   - `control`: Operation selector (4 bits).
 * - Outputs:
 *   - `result`: Result of the selected operation (XLEN bits).
 *   - `zero`: Flag indicating if the result is zero (1 bit).
 *   - `less_than`: Flag for signed less-than comparison (1 bit).
 *   - `unsigned_less_than`: Flag for unsigned less-than comparison (1 bit).
 *
 * ## Operation Encoding
 * ```
 * Control Signal | Operation
 * -------------- | --------------------------------------------------------
 * `0000`         | Add two operands
 * `0001`         | Subtract operand_b from operand_a
 * `0010`         | Bitwise AND of two operands
 * `0011`         | Bitwise OR of two operands
 * `0100`         | Bitwise XOR of two operands
 * `0101`         | Logical left shift of operand_b by operand_a[4:0]
 * `0110`         | Logical right shift of operand_b by operand_a[4:0]
 * `0111`         | Arithmetic right shift of operand_b by operand_a[4:0]
 * `1000`         | Signed less-than comparison
 * `1001`         | Unsigned less-than comparison
 * ```
 *
 * ## Block Diagram
 * ```
 * ┌────────────────────────────────────────────────────────────────────────────────────┐
 * │ Inputs:                                                                            │
 * │  operand_b  ───────────────────────────────────────────────┐                       │
 * │                                                            │                       │
 * │  operand_a  ─────────────────┐                             │                       │
 * │                              │                             │                       │
 * │  control  ─────┐             │                             │                       │
 * │                │             │                             │                       │
 * │           ┌────▼────┐  ┌─────▼─────┐  ┌───────────┐  ┌─────▼─────┐  ┌───────────┐  │
 * │           │ Decoder │  │  Unsigned ▶──▶   Signed  │  │  Unsigned ▶──▶   Signed  │  │
 * │           └────▼────┘  │ RegisterA │  │ RegisterA │  │ RegisterB │  │ RegisterB │  │
 * │                │       └─────▼─────┘  └─────▼─────┘  └─────▼─────┘  └─────▼─────┘  │
 * │                │             │              │              │              │        │
 * │                │             │              │              │              │        │
 * │    ┌─────────--▼─────────┐   │              │              │              │        │
 * │    │ Unsigned Operations ◀───█─────────────┤│├─────────────█              │        │
 * │    └─────────--▼─────────┘   │              │              │              │        │
 * │                │             │              │              │              │        │
 * │    ┌─────────--▼─────────┐   │              │              │              │        │
 * │    │ Signed Operations   ◀──┤│├─────────────█─────────────┤│├─────────────█        │
 * │    └─────────--▼─────────┘   │              │              │              │        │
 * │                │             │              │              │              │        │
 * │    ┌─────────--▼─────────┐   │              │              │              │        │
 * │    │ Arithmetic Shift    ◀──┤│├─────────────█──────────────█              │        │
 * │    └─────────--▼─────────┘   │              │              │              │        │
 * │                │             │              │              │              │        │
 * │    ┌─────────--▼─────────┐   │              │              │              │        │
 * │    │ Result              │   │              │              │              │        │
 * │    └─────────--▼─────────┘   │              │              │              │        │
 * │                │             │              │              │              │        │
 * │                │             │              │              │              │        │
 * │ Outputs:       │             │              │              │              │        │
 * │  result  ──────┤             │              │              │              │        │
 * │                │             │              │              │              │        │
 * │  zero  ────────┘             │              │              │              │        │
 * │                              │              │              │              │        │
 * │  less_than  ────────────────┤│├─────────────█─────────────┤│├─────────────█        │
 * │                              │                             │                       │
 * │  unsigned_less_than  ────────█─────────────────────────────█                       │
 * └────────────────────────────────────────────────────────────────────────────────────┘
 * ```
 **/


  Providing alternative blocks


`timescale 1ns / 1ps
`default_nettype none

// ────────────────────────--
// ALU Operation Encoding
// ────────────────────────--
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

// ────────────────────────--
// Shift Bits Calculation
// ────────────────────────--
localparam SHIFT_BITS = $clog2(XLEN); // 5 for XLEN=32, 6 for XLEN=64

// ────────────────────────--
// Internal Signals for Signed Comparisons
// ────────────────────────--
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

// ────────────────────────--
// Flag Assignments
// ────────────────────────--

// Zero Flag: High if result is zero
assign zero                = (result == {XLEN{1'b0}});

// Less Than Flags
assign less_than           = (operand_a_signed < operand_b_signed); // Signed Comparison
assign unsigned_less_than  = (operand_a < operand_b);               // Unsigned Comparison

endmodule
