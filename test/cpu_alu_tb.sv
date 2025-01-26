`default_nettype none
`timescale 1ns / 1ps

`include "cpu_alu.sv"

`ifndef XLEN
`define XLEN 32
`endif

module cpu_alu_tb;
`include "test/test_macros.sv"
        
// Parameters for XLEN
localparam XLEN = `XLEN;

// -----------------------------
// 32-bit ALU Signals
// -----------------------------
// Inputs
logic signed [XLEN-1:0]  operand_a;
logic [XLEN-1:0]         operand_b;
logic [3:0]              control;
logic [XLEN-1:0]         result;
logic                    zero;
logic                    less_than;
logic                    unsigned_less_than;

// Instantiate the 32-bit ALU
cpu_alu #(
    .XLEN(XLEN)
) uut (
    .operand_a           (operand_a),
    .operand_b           (operand_b),
    .control             (control),
    .result              (result),
    .zero                (zero),
    .less_than           (less_than),
    .unsigned_less_than  (unsigned_less_than)
);

task Test(
    input string             desc,
    input [3:0]              in_control,
    input signed [XLEN-1:0]  in_operand_a,
    input [XLEN-1:0]         in_operand_b,
    input [XLEN-1:0]         expected_result,
    input                    expected_zero,
    input                    expected_less_than,
    input                    expected_unsigned_less_than
);
    begin
        `TEST("cpu_alu", desc);
        operand_a = in_operand_a;
        operand_b = in_operand_b;
        control   = in_control;

        #10;

        `EXPECT("Result", result, expected_result);
        `EXPECT("Zero Flag", zero, expected_zero);
        `EXPECT("Less Than Flag", less_than, expected_less_than);
        `EXPECT("Unsigned Less Than Flag", unsigned_less_than, expected_unsigned_less_than);

        #10;
    end
endtask
    

//-----------------------------------------------------
// Clock Generation
// Needed for `FINISH macro
//-----------------------------------------------------
logic clk;
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

initial begin
    $dumpfile("cpu_alu_tb.vcd");
    $dumpvars(0, cpu_alu_tb);

    // Initialize Inputs for 32-bit ALU
    operand_a = 0;
    operand_b = 0;
    control = 0;
    
    //////////////////////////////////////////////////////////////
    // Arithmetic Operations (I Extension)
    //////////////////////////////////////////////////////////////
            
    // Test ALU_ADD: 0x00000020 + 0x0000000A = 0x0000002A
    Test("ADD: 0x00000020 + 0x0000000A = 0x0000002A",
        `ALU_ADD, 32'h00000020, 32'h0000000A, 32'h0000002A,
        0,  // expected_zero = (0x0000002A != 0)
        0,  // expected_less = (0x00000020 < 0x0000000A) signed = 0
        0   // expected_unsigned_less = (0x00000020 < 0x0000000A) unsigned = 0
    );
    
    if (XLEN >= 64) begin
    // Test ALU_ADD: 0xFFFFFFFFFFFFFFFF + 0x0000000000000001 = 0x0000000000000000 (Overflow)
    Test("ADD: 0xFFFFFFFFFFFFFFFF + 0x0000000000000001 = 0x0000000000000000",
        `ALU_ADD, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001, 64'h0000000000000000,
        1,  // expected_zero = (0x0000000000000000 == 0)
        1,  // expected_less = (0xFFFFFFFFFFFFFFFF < 0x0000000000000001) signed = 1
        0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFFF < 0x0000000000000001) unsigned = 0
    );
    end

    // Test ALU_SUB: 0x00000032 - 0x00000014 = 0x0000001E
    Test("SUB: 0x00000032 - 0x00000014 = 0x0000001E",
        `ALU_SUB, 32'h00000032, 32'h00000014, 32'h0000001E,
        0,  // expected_zero = (0x0000001E != 0)
        0,  // expected_less = (0x00000032 < 0x00000014) signed = 0
        0   // expected_unsigned_less = (0x00000032 < 0x00000014) unsigned = 0
    );
    
    if (XLEN >= 64) begin
    // Test ALU_SUB: 0x00000064 - 0x00000032 = 0x00000032
    Test("SUB: 0x00000064 - 0x00000032 = 0x00000032",
        `ALU_SUB, 64'h0000000000000064, 64'h0000000000000032, 64'h0000000000000032,
        0,  // expected_zero = (0x00000032 != 0)
        0,  // expected_less = (0x00000064 < 0x00000032) signed = 0
        0   // expected_unsigned_less = (0x00000064 < 0x00000032) unsigned = 0
    );
    end
            
    // Test ALU_AND: 0xFF0FF0F0 & 0x0F0F0F0F = 0x0F0F0000
    if (XLEN == 32) begin
    Test("AND: 0xFF0FF0F0 & 0x0F0F0F0F = 0x0F0F0000",
        `ALU_AND, 32'hFF0FF0F0, 32'h0F0F0F0F, 32'h0F0F0000,
        0,  // expected_zero = (0x0F0F0000 != 0)
        1,  // expected_less = (0xFF0FF0F0 < 0x0F0F0F0F) signed = 1
        0   // expected_unsigned_less = (0xFF0FF0F0 < 0x0F0F0F0F) unsigned = 0
    );
    end else begin
    Test("AND: 0xFF0FF0F0 & 0x0F0F0F0F = 0x0F0F0000",
        `ALU_AND, 32'hFF0FF0F0, 32'h0F0F0F0F, 32'h0F0F0000,
        0,  // expected_zero = (0x0F0F0000 != 0)
        0,  // expected_less = (0xFF0FF0F0 < 0x0F0F0F0F) signed = 1
        0   // expected_unsigned_less = (0xFF0FF0F0 < 0x0F0F0F0F) unsigned = 0
    );
    end
    
    if (XLEN >= 64) begin
    // Test ALU_AND: 0xFF0FF0F0F0F0F0F0 & 0x0F0F0F0F0F0F0F0F = 0x0F0F000000000000
    Test("AND: 0xFF0FF0F0F0F0F0F0 & 0x0F0F0F0F0F0F0F0F = 0x0F0F000000000000",
        `ALU_AND, 64'hFF0FF0F0F0F0F0F0, 64'h0F0F0F0F0F0F0F0F, 64'h0F0F000000000000,
        0,  // expected_zero = (0x0F0F000000000000 != 0)
        1,  // expected_less = (0xFF0FF0F0F0F0F0F0 < 0x0F0F0F0F0F0F0F0F) signed = 1
        0   // expected_unsigned_less = (0xFF0FF0F0F0F0F0F0 < 0x0F0F0F0F0F0F0F0F) unsigned = 0
    );
    end
    
    // Test ALU_OR: 0xFF00FF00 | 0x00FF00FF = 0xFFFFFFFF
    if (XLEN == 32) begin
    Test("OR: 0xFF00FF00 | 0x00FF00FF = 0xFFFFFFFF",
        `ALU_OR, 32'hFF00FF00, 32'h00FF00FF, 32'hFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFF != 0)
        1,  // expected_less = (0xFF00FF00 < 0x00FF00FF) signed = 1
        0   // expected_unsigned_less = (0xFF00FF00 < 0x00FF00FF) unsigned = 0
    );
    end else begin
    Test("OR: 0xFF00FF00 | 0x00FF00FF = 0xFFFFFFFF",
        `ALU_OR, 32'hFF00FF00, 32'h00FF00FF, 32'hFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFF != 0)
        0,  // expected_less = (0xFF00FF00 < 0x00FF00FF) signed = 1
        0   // expected_unsigned_less = (0xFF00FF00 < 0x00FF00FF) unsigned = 0
    );
    end
    
    if (XLEN >= 64) begin
    // Test ALU_OR: 0xFF00FF00FF00FF00 | 0x00FF00FF00FF00FF = 0xFFFFFFFFFFFFFFFF
    Test("OR: 0xFF00FF00FF00FF00 | 0x00FF00FF00FF00FF = 0xFFFFFFFFFFFFFFFF",
        `ALU_OR, 64'hFF00FF00FF00FF00, 64'h00FF00FF00FF00FF, 64'hFFFFFFFFFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
        1,  // expected_less = (0xFF00FF00FF00FF00 < 0x00FF00FF00FF00FF) signed = 1
        0   // expected_unsigned_less = (0xFF00FF00FF00FF00 < 0x00FF00FF00FF00FF) unsigned = 0
    );
    end
            
    // Test ALU_XOR: 0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF
    if (XLEN == 32) begin
    Test("XOR: 0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF",
        `ALU_XOR, 32'hAAAAAAAA, 32'h55555555, 32'hFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFF != 0)
        1,  // expected_less = (0xAAAAAAAA < 0x55555555) signed = 1
        0   // expected_unsigned_less = (0xAAAAAAAA < 0x55555555) unsigned = 0
    );
    end else begin
    Test("XOR: 0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF",
        `ALU_XOR, 32'hAAAAAAAA, 32'h55555555, 32'hFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFF != 0)
        0,  // expected_less = (0xAAAAAAAA < 0x55555555) signed = 1
        0   // expected_unsigned_less = (0xAAAAAAAA < 0x55555555) unsigned = 0
    );
    end
    
    if (XLEN >= 64) begin
    // Test ALU_XOR: 0xAAAAAAAAAAAAAAAA ^ 0x5555555555555555 = 0xFFFFFFFFFFFFFFFF
    Test("XOR: 0xAAAAAAAAAAAAAAAA ^ 0x5555555555555555 = 0xFFFFFFFFFFFFFFFF",
        `ALU_XOR, 64'hAAAAAAAAAAAAAAAA, 64'h5555555555555555, 64'hFFFFFFFFFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
        1,  // expected_less = (0xAAAAAAAAAAAAAAAA < 0x5555555555555555) signed = 1
        0   // expected_unsigned_less = (0xAAAAAAAAAAAAAAAA < 0x5555555555555555) unsigned = 0
    );
    end
    
    // Test ALU_SLL: 0x00000001 << 0x00000004 = 0x00000010
    Test("SLL: 0x00000001 << 0x00000004 = 0x00000010",
        `ALU_SLL, 32'h00000001, 32'h00000004, 32'h00000010,
        0,  // expected_zero = (0x00000010 != 0)
        1,  // expected_less = (0x00000001 < 0x00000004) signed = 1
        1   // expected_unsigned_less = (0x00000001 < 0x00000004) unsigned = 1
    );
    
    if (XLEN >= 64) begin
    // Test ALU_SLL: 0x0000000000000001 << 0x0000000000000004 = 0x0000000000000010
    Test("SLL: 0x0000000000000001 << 0x0000000000000004 = 0x0000000000000010",
        `ALU_SLL, 64'h0000000000000001, 64'h0000000000000004, 64'h0000000000000010,
        0,  // expected_zero = (0x0000000000000010 != 0)
        1,  // expected_less = (0x0000000000000001 < 0x0000000000000004) signed = 1
        1   // expected_unsigned_less = (0x0000000000000001 < 0x0000000000000004) unsigned = 1
    );
    end
    
    // Test ALU_SRL: 0x00000010 >> 0x00000004 = 0x00000001
    Test("SRL: 0x00000010 >> 0x00000004 = 0x00000001",
        `ALU_SRL, 32'h00000010, 32'h00000004, 32'h00000001,
        0,  // expected_zero = (0x00000001 != 0)
        0,  // expected_less = (0x00000010 < 0x00000004) signed = 0
        0   // expected_unsigned_less = (0x00000010 < 0x00000004) unsigned = 0
    );
    
    if (XLEN >= 64) begin
    // Test ALU_SRL: 0x0000000000000010 >> 0x0000000000000004 = 0x0000000000000001
    Test("SRL: 0x0000000000000010 >> 0x0000000000000004 = 0x0000000000000001",
        `ALU_SRL, 64'h0000000000000010, 64'h0000000000000004, 64'h0000000000000001,
        0,  // expected_zero = (0x0000000000000001 != 0)
        0,  // expected_less = (0x0000000000000010 < 0x0000000000000004) signed = 0
        0   // expected_unsigned_less = (0x0000000000000010 < 0x0000000000000004) unsigned = 0
    );
    end
    
    // Test ALU_SRA: 0xFFFFFFE0 >> 0x00000004 = 0xFFFFFFFE
    if (XLEN == 32) begin
    Test("SRA: 0xFFFFFFE0 >> 0x00000004 = 0xFFFFFFFE",
        `ALU_SRA, 32'hFFFFFFE0, 32'h00000004, 32'hFFFFFFFE,
        0,  // expected_zero = (0xFFFFFFFE != 0)
        1,  // expected_less = (0xFFFFFFE0 < 0x00000004) signed = 1
        0   // expected_unsigned_less = (0xFFFFFFE0 < 0x00000004) unsigned = 0
    );
    end else begin
    Test("SRA: 0xFFFFFFE0 >> 0x00000004 = 0xFFFFFFFE",
        `ALU_SRA, 32'hFFFFFFE0, 32'h00000004, 32'hFFFFFFE,
        0,  // expected_zero = (0xFFFFFFFE != 0)
        0,  // expected_less = (0xFFFFFFE0 < 0x00000004) signed = 1
        0   // expected_unsigned_less = (0xFFFFFFE0 < 0x00000004) unsigned = 0
    );
    end
    
    if (XLEN == 64) begin
    // Test ALU_SRA: 0xFFFFFFFFFFFFFFE0 >> 0x0000000000000004 = 0xFFFFFFFFFFFFFFFE
    Test("SRA: 0xFFFFFFFFFFFFFFE0 >> 0x0000000000000004 = 0xFFFFFFFFFFFFFFFE",
        `ALU_SRA, 64'hFFFFFFFFFFFFFFE0, 64'h0000000000000004, 64'hFFFFFFFFFFFFFFFE,
        0,  // expected_zero = (0xFFFFFFFFFFFFFFFE != 0)
        1,  // expected_less = (0xFFFFFFFFFFFFFFE0 < 0x0000000000000004) signed = 1
        0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFE0 < 0x0000000000000004) unsigned = 0
    );
    end
            
    // Test ALU_SLT: 0x00000005 < 0x0000000A = 0x00000001
    Test("SLT: 0x00000005 < 0x0000000A = 0x00000001",
        `ALU_SLT, 32'h00000005, 32'h0000000A, 32'h00000001,
        0,  // expected_zero = (0x00000001 != 0)
        1,  // expected_less = (0x00000005 < 0x0000000A) signed = 1
        1   // expected_unsigned_less = (0x00000005 < 0x0000000A) unsigned = 1
    );
    
    if (XLEN >= 64) begin
    // Test ALU_SLT: 0x0000000000000005 < 0x000000000000000A = 0x0000000000000001
    Test("SLT: 0x0000000000000005 < 0x000000000000000A = 0x0000000000000001",
        `ALU_SLT, 64'h0000000000000005, 64'h000000000000000A, 64'h0000000000000001,
        0,  // expected_zero = (0x0000000000000001 != 0)
        1,  // expected_less = (0x0000000000000005 < 0x000000000000000A) signed = 1
        1   // expected_unsigned_less = (0x0000000000000005 < 0x000000000000000A) unsigned = 1
    );
    end
    
    // Test ALU_SLTU: 0x00000005 < 0x0000000A = 0x00000001
    Test("SLTU: 0x00000005 < 0x0000000A = 0x00000001",
        `ALU_SLTU, 32'h00000005, 32'h0000000A, 32'h00000001,
        0,  // expected_zero = (0x00000001 != 0)
        1,  // expected_less = (0x00000005 < 0x0000000A) signed = 1
        1   // expected_unsigned_less = (0x00000005 < 0x0000000A) unsigned = 1
    );
    
    if (XLEN >= 64) begin
    // Test ALU_SLTU: 0x0000000000000005 < 0x000000000000000A = 0x0000000000000001
    Test("SLTU: 0x0000000000000005 < 0x000000000000000A = 0x0000000000000001",
        `ALU_SLTU, 64'h0000000000000005, 64'h000000000000000A, 64'h0000000000000001,
        0,  // expected_zero = (0x0000000000000001 != 0)
        1,  // expected_less = (0x0000000000000005 < 0x000000000000000A) signed = 1
        1   // expected_unsigned_less = (0x0000000000000005 < 0x000000000000000A) unsigned = 1
    );
    end

    // 32-bit ADD Overflow
    Test("ADD Overflow: 0x7FFFFFFF + 0x00000001 = 0x80000000",
        `ALU_ADD, 32'h7FFFFFFF, 32'h00000001, 32'h80000000,
        0,  // expected_zero = (0x80000000 != 0)
        0,  // expected_less = (0x7FFFFFFF < 0x00000001) signed = 0
        0   // expected_unsigned_less = (0x7FFFFFFF < 0x80000000) unsigned = 0 
    );

    if (XLEN >= 64) begin
    // 64-bit ADD Overflow
    Test("ADD Overflow: 0x7FFFFFFFFFFFFFFF + 0x0000000000000001 = 0x8000000000000000",
        `ALU_ADD, 64'h7FFFFFFFFFFFFFFF, 64'h0000000000000001, 64'h8000000000000000,
        0,  // expected_zero = (0x8000000000000000 != 0)
        0,  // expected_less = (0x7FFFFFFFFFFFFFFF < 0x0000000000000001) signed = 0
        0   // expected_unsigned_less = (0x7FFFFFFFFFFFFFFF < 0x0000000000000001) unsigned = 0
    );
    end

    // 32-bit SUB Underflow
    if (XLEN == 32) begin
    Test("SUB Underflow: 0x00000000 - 0x00000001 = 0xFFFFFFFF",
        `ALU_SUB, 32'h00000000, 32'h00000001, 32'hFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFF != 0)
        1,  // expected_less = (0x00000000 < 0x00000001) signed = 1
        1   // expected_unsigned_less = (0x00000000 < 0x00000001) unsigned = 1
    );
    end

    if (XLEN == 64) begin
    // 64-bit SUB Underflow
    Test("SUB Underflow: 0x0000000000000000 - 0x0000000000000001 = 0xFFFFFFFFFFFFFFFF",
        `ALU_SUB, 64'h0000000000000000, 64'h0000000000000001, 64'hFFFFFFFFFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
        1,  // expected_less = (0x0000000000000000 < 0x0000000000000001) signed = 1
        1   // expected_unsigned_less = (0x0000000000000000 < 0x0000000000000001) unsigned = 1
    );
    end

    // 32-bit SLL Shift Amount Zero
    Test("SLL Shift Zero: 0x00000010 << 0x00000000 = 0x00000010",
        `ALU_SLL, 32'h00000010, 32'h00000000, 32'h00000010,
        0,  // expected_zero = (0x00000010 != 0)
        0,  // expected_less = (0x00000010 < 0x00000000) signed = 0
        0   // expected_unsigned_less = (0x00000010 < 0x00000000) unsigned = 0
    );

    if (XLEN >= 64) begin
    // 64-bit SLL Shift Amount Zero
    Test("SLL Shift Zero: 0x0000000000000010 << 0x0000000000000000 = 0x0000000000000010",
        `ALU_SLL, 64'h0000000000000010, 64'h0000000000000000, 64'h0000000000000010,
        0,  // expected_zero = (0x0000000000000010 != 0)
        0,  // expected_less = (0x0000000000000010 < 0x0000000000000000) signed = 0
        0   // expected_unsigned_less = (0x0000000000000010 < 0x0000000000000000) unsigned = 0
    );
    end

    // 32-bit SLL Shift Amount XLEN
    if (XLEN == 32) begin
    Test("SLL Shift XLEN: 0x00000001 << 32 = 0x00000001",
        `ALU_SLL, 32'h00000001, 32'h00000020, // Assuming XLEN=32, shift amount = 32 masked to 0
        32'h00000001,
        0,  // expected_zero = (0x00000001 != 0)
        1,  // expected_less = (0x00000001 < 0x00000020) signed = 1
        1   // expected_unsigned_less = (0x00000001 < 0x00000020) unsigned = 1
    );
    end

    if (XLEN == 64) begin
    // 64-bit SLL Shift Amount XLEN
    Test("SLL Shift XLEN: 0x0000000000000001 << 64 = 0x0000000000000001",
        `ALU_SLL, 64'h0000000000000001, 64'h0000000000000040, // Assuming XLEN=64, shift amount = 64 masked to 0
        64'h0000000000000001,
        0,  // expected_zero = (0x0000000000000001 != 0)
        1,  // expected_less = (0x0000000000000001 < 0x0000000000000040) signed = 1
        1   // expected_unsigned_less = (0x0000000000000001 < 0x0000000000000040) unsigned = 1
    );
    end

    // 32-bit SLT with Equal Operands
    Test("SLT Equal Operands: 0x00000005 < 0x00000005 = 0x00000000",
        `ALU_SLT, 32'h00000005, 32'h00000005, 32'h00000000,
        1,  // expected_zero = (0x00000000 == 0)
        0,  // expected_less = (0x00000005 < 0x00000005) signed = 0
        0   // expected_unsigned_less = (0x00000005 < 0x00000005) unsigned = 0
    );

    if (XLEN >= 64) begin
    // 64-bit SLT with Equal Operands
    Test("SLT Equal Operands: 0x0000000000000005 < 0x0000000000000005 = 0x0000000000000000",
        `ALU_SLT, 64'h0000000000000005, 64'h0000000000000005, 64'h0000000000000000,
        1,  // expected_zero = (0x0000000000000000 == 0)
        0,  // expected_less = (0x0000000000000005 < 0x0000000000000005) signed = 0
        0   // expected_unsigned_less = (0x0000000000000005 < 0x0000000000000005) unsigned = 0
    );
    end

    // 32-bit SLTU with Equal Operands
    Test("SLTU Equal Operands: 0x00000005 < 0x00000005 = 0x00000000",
        `ALU_SLTU, 32'h00000005, 32'h00000005, 32'h00000000,
        1,  // expected_zero = (0x00000000 == 0)
        0,  // expected_less = (0x00000005 < 0x00000005) signed = 0
        0   // expected_unsigned_less = (0x00000005 < 0x00000005) unsigned = 0
    );

    if (XLEN >= 64) begin
    // 64-bit SLTU with Equal Operands
    Test("SLTU Equal Operands: 0x0000000000000005 < 0x0000000000000005 = 0x0000000000000000",
        `ALU_SLTU, 64'h0000000000000005, 64'h0000000000000005, 64'h0000000000000000,
        1,  // expected_zero = (0x0000000000000000 == 0)
        0,  // expected_less = (0x0000000000000005 < 0x0000000000000005) signed = 0
        0   // expected_unsigned_less = (0x0000000000000005 < 0x0000000000000005) unsigned = 0
    );
    end

    // 32-bit AND with All Bits Set
    Test("AND All Bits Set: 0xFFFFFFFF & 0xFFFFFFFF = 0xFFFFFFFF",
        `ALU_AND, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFF != 0)
        0,  // expected_less = (0xFFFFFFFF < 0xFFFFFFFF) signed = 0
        0   // expected_unsigned_less = (0xFFFFFFFF < 0xFFFFFFFF) unsigned = 0
    );

    if (XLEN >= 64) begin
    // 64-bit AND with All Bits Set
    Test("AND All Bits Set: 0xFFFFFFFFFFFFFFFF & 0xFFFFFFFFFFFFFFFF = 0xFFFFFFFFFFFFFFFF",
        `ALU_AND, 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
        0,  // expected_less = (0xFFFFFFFFFFFFFFFF < 0xFFFFFFFFFFFFFFFF) signed = 0
        0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFFF < 0xFFFFFFFFFFFFFFFF) unsigned = 0
    );
    end

    // 32-bit OR with Zero Operands
    Test("OR with Zero Operands: 0x00000000 | 0x00000000 = 0x00000000",
        `ALU_OR, 32'h00000000, 32'h00000000, 32'h00000000,
        1,  // expected_zero = (0x00000000 == 0)
        0,  // expected_less = (0x00000000 < 0x00000000) signed = 0
        0   // expected_unsigned_less = (0x00000000 < 0x00000000) unsigned = 0
    );

    if (XLEN >= 64) begin
    // 64-bit OR with Zero Operands
    Test("OR with Zero Operands: 0x0000000000000000 | 0x0000000000000000 = 0x0000000000000000",
        `ALU_OR, 64'h0000000000000000, 64'h0000000000000000, 64'h0000000000000000,
        1,  // expected_zero = (0x0000000000000000 == 0)
        0,  // expected_less = (0x0000000000000000 < 0x0000000000000000) signed = 0
        0   // expected_unsigned_less = (0x0000000000000000 < 0x0000000000000000) unsigned = 0
    );
    end

    // 32-bit SRA with Negative Number
    if (XLEN == 32) begin
    Test("SRA Negative Number: 0xFFFFFFF0 >>> 4 = 0xFFFFFFFF",
        `ALU_SRA, 32'hFFFFFFF0, // Operand: -16
        32'h00000004, // Shift Amount: 4
        32'hFFFFFFFF, // Expected Result: -1
        0,  // expected_zero = (0xFFFFFFFF != 0)
        1,  // expected_less = (-16 < 4) signed = 1
        0   // expected_unsigned_less = (0xFFFFFFF0 < 0x00000004) unsigned = 0
    );
    end

    if (XLEN == 64) begin
    // 64-bit SRA with Negative Number
    Test("SRA Negative Number: 0xFFFFFFFFFFFFFFF0 >>> 4 = 64'hFFFFFFFFFFFFFFFF",
        `ALU_SRA, 64'hFFFFFFFFFFFFFFF0, 64'h0000000000000004, 64'hFFFFFFFFFFFFFFFF,
        0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
        1,  // expected_less = (0xFFFFFFFFFFFFFFF0 < 0x0000000000000004) signed = 1
        0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFF0 < 0x0000000000000004) unsigned = 0
    );
    end

    // 32-bit SLT with Negative and Positive Operands
    if (XLEN == 32) begin
    Test("SLT Negative vs Positive: 0xFFFFFFFE < 0x00000001 = 0x00000001",
        `ALU_SLT, 32'hFFFFFFFE, // -2 in signed
        32'h00000001, // 1 in signed
        32'h00000001,
        0,  // expected_zero = (0x00000001 != 0)
        1,  // expected_less = (-2 < 1) signed = 1
        0   // expected_unsigned_less = (0xFFFFFFFE < 0x00000001) unsigned = 0
    );
    end

    if (XLEN == 64) begin
    // 64-bit SLT with Negative and Positive Operands
    Test("SLT Negative vs Positive: 0xFFFFFFFFFFFFFFFE < 0x0000000000000001 = 0x0000000000000001",
        `ALU_SLT, 64'hFFFFFFFFFFFFFFFE, // -2 in signed
        64'h0000000000000001, // 1 in signed
        64'h0000000000000001,
        0,  // expected_zero = (0x0000000000000001 != 0)
        1,  // expected_less = (-2 < 1) signed = 1
        0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFFE < 0x0000000000000001) unsigned = 0
    );
    end

    `FINISH;
end
    
endmodule
