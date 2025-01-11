`default_nettype none
`timescale 1ns / 1ps

`include "src/cpu_alu.sv"

module cpu_alu_tb;
        
    // Parameters for XLEN
    localparam XLEN_32 = 32;
    localparam XLEN_64 = 64;
    
    // -----------------------------
    // 32-bit ALU Signals
    // -----------------------------
    // Inputs
    logic signed [XLEN_32-1:0]  operand_a32;
    logic [XLEN_32-1:0]         operand_b32;
    logic [3:0]                 control32;
    logic [XLEN_32-1:0]         result32;
    logic                       zero32;
    logic                       less_than32;
    logic                       unsigned_less_than32;
    
    // -----------------------------
    // 64-bit ALU Signals
    // -----------------------------
    logic signed [XLEN_64-1:0]  operand_a64;
    logic [XLEN_64-1:0]         operand_b64;
    logic [3:0]                 control64;
    logic [XLEN_64-1:0]         result64;
    logic                       zero64;
    logic                       less_than64;
    logic                       unsigned_less_than64;
    
    // Instantiate the 32-bit ALU
    cpu_alu #(
        .XLEN(XLEN_32)
    ) uut32 (
        .operand_a           (operand_a32),
        .operand_b           (operand_b32),
        .control             (control32),
        .result              (result32),
        .zero                (zero32),
        .less_than           (less_than32),
        .unsigned_less_than  (unsigned_less_than32)
    );
    
    // Instantiate the 64-bit ALU
    cpu_alu #(
        .XLEN(XLEN_64)
    ) uut64 (
        .operand_a           (operand_a64),
        .operand_b           (operand_b64),
        .control             (control64),
        .result              (result64),
        .zero                (zero64),
        .less_than           (less_than64),
        .unsigned_less_than  (unsigned_less_than64)
    );
    
    integer testCount = 0;
    integer testCountPass = 0;
    integer testCountFail = 0;
    
    // Expectation Macro
    `define EXPECT(desc, actual, expected) \
        if ((actual) === (expected)) begin \
            $display("  == PASS == %s (Value: 0x%h)", desc, actual); \
            testCountPass = testCountPass + 1; \
        end else begin \
            $display("  == FAIL == %s (Expected: 0x%h, Got: 0x%h)", desc, expected, actual); \
            testCountFail = testCountFail + 1; \
        end
    
    // Base Test Macros
    `define TEST32(desc, ctrl, a, c, expected_result, expected_zero, expected_less, expected_unsigned_less) \
        begin \
            testCount = testCount + 1; \
            $display("\n[32bit ALU] Test %0d: %s", testCount, desc); \
            operand_a32 = a; \
            operand_b32 = c; \
            control32 = ctrl; \
            $display("  Operands for 32-bit ALU: a32=0x%h, b32=0x%h", operand_a32, operand_b32); \
            #10; /* Wait for ALU operation */ \
            `EXPECT("Result", result32, expected_result); \
            `EXPECT("Zero Flag", zero32, expected_zero); \
            `EXPECT("Less Than Flag", less_than32, expected_less); \
            `EXPECT("Unsigned Less Than Flag", unsigned_less_than32, expected_unsigned_less); \
        end

    `define TEST64(desc, ctrl, a, c, expected_result, expected_zero, expected_less, expected_unsigned_less) \
        begin \
            testCount = testCount + 1; \
            $display("\n[64bit ALU] Test %0d: %s", testCount, desc); \
            operand_a64 = a; \
            operand_b64 = c; \
            control64 = ctrl; \
            $display("  Operands for 64-bit ALU: a64=0x%h, b64=0x%h", operand_a64, operand_b64); \
            #10; /* Wait for ALU operation */ \
            `EXPECT("Result", result64, expected_result); \
            `EXPECT("Zero Flag", zero64, expected_zero); \
            `EXPECT("Less Than Flag", less_than64, expected_less); \
            `EXPECT("Unsigned Less Than Flag", unsigned_less_than64, expected_unsigned_less); \
        end    
    
    // Finalization Macro
    `define FINISH \
    begin \
        $display("\n===================================="); \
        $display("Total Tests Run:    %0d", testCount); \
        $display("Tests Passed:       %0d", testCountPass); \
        $display("Tests Failed:       %0d", testCountFail); \
        if (testCountFail > 0) begin \
            $display("== Some tests FAILED. ==============\n"); \
            $stop; \
        end else begin \
            $display("== All tests PASSED successfully. ==\n"); \
            $finish; \
        end \
    end
        
    initial begin
        $dumpfile("cpu_alu_tb.vcd");
        $dumpvars(0, cpu_alu_tb);
    
        // Initialize Inputs for 32-bit ALU
        operand_a32 = 0;
        operand_b32 = 0;
        control32 = 0;
    
        // Initialize Inputs for 64-bit ALU
        operand_a64 = 0;
        operand_b64 = 0;
        control64 = 0;
        
        //////////////////////////////////////////////////////////////
        // Arithmetic Operations (I Extension)
        //////////////////////////////////////////////////////////////
                
        // Test ALU_ADD: 0x00000020 + 0x0000000A = 0x0000002A
        `TEST32("ADD: 0x00000020 + 0x0000000A = 0x0000002A",
            `ALU_ADD, 32'h00000020, 32'h0000000A, 32'h0000002A,
            0,  // expected_zero = (0x0000002A != 0)
            0,  // expected_less = (0x00000020 < 0x0000000A) signed = 0
            0   // expected_unsigned_less = (0x00000020 < 0x0000000A) unsigned = 0
        );
        
        // Test ALU_ADD: 0xFFFFFFFFFFFFFFFF + 0x0000000000000001 = 0x0000000000000000 (Overflow)
        `TEST64("ADD: 0xFFFFFFFFFFFFFFFF + 0x0000000000000001 = 0x0000000000000000",
            `ALU_ADD, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000001, 64'h0000000000000000,
            1,  // expected_zero = (0x0000000000000000 == 0)
            1,  // expected_less = (0xFFFFFFFFFFFFFFFF < 0x0000000000000001) signed = 1
            0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFFF < 0x0000000000000001) unsigned = 0
        );
        
        // Test ALU_SUB: 0x00000032 - 0x00000014 = 0x0000001E
        `TEST32("SUB: 0x00000032 - 0x00000014 = 0x0000001E",
            `ALU_SUB, 32'h00000032, 32'h00000014, 32'h0000001E,
            0,  // expected_zero = (0x0000001E != 0)
            0,  // expected_less = (0x00000032 < 0x00000014) signed = 0
            0   // expected_unsigned_less = (0x00000032 < 0x00000014) unsigned = 0
        );
        
        // Test ALU_SUB: 0x00000064 - 0x00000032 = 0x00000032
        `TEST64("SUB: 0x00000064 - 0x00000032 = 0x00000032",
            `ALU_SUB, 64'h0000000000000064, 64'h0000000000000032, 64'h0000000000000032,
            0,  // expected_zero = (0x00000032 != 0)
            0,  // expected_less = (0x00000064 < 0x00000032) signed = 0
            0   // expected_unsigned_less = (0x00000064 < 0x00000032) unsigned = 0
        );
                
        // Test ALU_AND: 0xFF0FF0F0 & 0x0F0F0F0F = 0x0F0F0000
        `TEST32("AND: 0xFF0FF0F0 & 0x0F0F0F0F = 0x0F0F0000",
            `ALU_AND, 32'hFF0FF0F0, 32'h0F0F0F0F, 32'h0F0F0000,
            0,  // expected_zero = (0x0F0F0000 != 0)
            1,  // expected_less = (0xFF0FF0F0 < 0x0F0F0F0F) signed = 1
            0   // expected_unsigned_less = (0xFF0FF0F0 < 0x0F0F0F0F) unsigned = 0
        );
        
        // Test ALU_AND: 0xFF0FF0F0F0F0F0F0 & 0x0F0F0F0F0F0F0F0F = 0x0F0F000000000000
        `TEST64("AND: 0xFF0FF0F0F0F0F0F0 & 0x0F0F0F0F0F0F0F0F = 0x0F0F000000000000",
            `ALU_AND, 64'hFF0FF0F0F0F0F0F0, 64'h0F0F0F0F0F0F0F0F, 64'h0F0F000000000000,
            0,  // expected_zero = (0x0F0F000000000000 != 0)
            1,  // expected_less = (0xFF0FF0F0F0F0F0F0 < 0x0F0F0F0F0F0F0F0F) signed = 1
            0   // expected_unsigned_less = (0xFF0FF0F0F0F0F0F0 < 0x0F0F0F0F0F0F0F0F) unsigned = 0
        );
        
        // Test ALU_OR: 0xFF00FF00 | 0x00FF00FF = 0xFFFFFFFF
        `TEST32("OR: 0xFF00FF00 | 0x00FF00FF = 0xFFFFFFFF",
            `ALU_OR, 32'hFF00FF00, 32'h00FF00FF, 32'hFFFFFFFF,
            0,  // expected_zero = (0xFFFFFFFF != 0)
            1,  // expected_less = (0xFF00FF00 < 0x00FF00FF) signed = 1
            0   // expected_unsigned_less = (0xFF00FF00 < 0x00FF00FF) unsigned = 0
        );
        
        // Test ALU_OR: 0xFF00FF00FF00FF00 | 0x00FF00FF00FF00FF = 0xFFFFFFFFFFFFFFFF
        `TEST64("OR: 0xFF00FF00FF00FF00 | 0x00FF00FF00FF00FF = 0xFFFFFFFFFFFFFFFF",
            `ALU_OR, 64'hFF00FF00FF00FF00, 64'h00FF00FF00FF00FF, 64'hFFFFFFFFFFFFFFFF,
            0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
            1,  // expected_less = (0xFF00FF00FF00FF00 < 0x00FF00FF00FF00FF) signed = 1
            0   // expected_unsigned_less = (0xFF00FF00FF00FF00 < 0x00FF00FF00FF00FF) unsigned = 0
        );
                
        // Test ALU_XOR: 0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF
        `TEST32("XOR: 0xAAAAAAAA ^ 0x55555555 = 0xFFFFFFFF",
            `ALU_XOR, 32'hAAAAAAAA, 32'h55555555, 32'hFFFFFFFF,
            0,  // expected_zero = (0xFFFFFFFF != 0)
            1,  // expected_less = (0xAAAAAAAA < 0x55555555) signed = 1
            0   // expected_unsigned_less = (0xAAAAAAAA < 0x55555555) unsigned = 0
        );
        
        // Test ALU_XOR: 0xAAAAAAAAAAAAAAAA ^ 0x5555555555555555 = 0xFFFFFFFFFFFFFFFF
        `TEST64("XOR: 0xAAAAAAAAAAAAAAAA ^ 0x5555555555555555 = 0xFFFFFFFFFFFFFFFF",
            `ALU_XOR, 64'hAAAAAAAAAAAAAAAA, 64'h5555555555555555, 64'hFFFFFFFFFFFFFFFF,
            0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
            1,  // expected_less = (0xAAAAAAAAAAAAAAAA < 0x5555555555555555) signed = 1
            0   // expected_unsigned_less = (0xAAAAAAAAAAAAAAAA < 0x5555555555555555) unsigned = 0
        );
        
        // Test ALU_SLL: 0x00000001 << 0x00000004 = 0x00000010
        `TEST32("SLL: 0x00000001 << 0x00000004 = 0x00000010",
            `ALU_SLL, 32'h00000001, 32'h00000004, 32'h00000010,
            0,  // expected_zero = (0x00000010 != 0)
            1,  // expected_less = (0x00000001 < 0x00000004) signed = 1
            1   // expected_unsigned_less = (0x00000001 < 0x00000004) unsigned = 1
        );
        
        // Test ALU_SLL: 0x0000000000000001 << 0x0000000000000004 = 0x0000000000000010
        `TEST64("SLL: 0x0000000000000001 << 0x0000000000000004 = 0x0000000000000010",
            `ALU_SLL, 64'h0000000000000001, 64'h0000000000000004, 64'h0000000000000010,
            0,  // expected_zero = (0x0000000000000010 != 0)
            1,  // expected_less = (0x0000000000000001 < 0x0000000000000004) signed = 1
            1   // expected_unsigned_less = (0x0000000000000001 < 0x0000000000000004) unsigned = 1
        );
        
        // Test ALU_SRL: 0x00000010 >> 0x00000004 = 0x00000001
        `TEST32("SRL: 0x00000010 >> 0x00000004 = 0x00000001",
            `ALU_SRL, 32'h00000010, 32'h00000004, 32'h00000001,
            0,  // expected_zero = (0x00000001 != 0)
            0,  // expected_less = (0x00000010 < 0x00000004) signed = 0
            0   // expected_unsigned_less = (0x00000010 < 0x00000004) unsigned = 0
        );
        
        // Test ALU_SRL: 0x0000000000000010 >> 0x0000000000000004 = 0x0000000000000001
        `TEST64("SRL: 0x0000000000000010 >> 0x0000000000000004 = 0x0000000000000001",
            `ALU_SRL, 64'h0000000000000010, 64'h0000000000000004, 64'h0000000000000001,
            0,  // expected_zero = (0x0000000000000001 != 0)
            0,  // expected_less = (0x0000000000000010 < 0x0000000000000004) signed = 0
            0   // expected_unsigned_less = (0x0000000000000010 < 0x0000000000000004) unsigned = 0
        );
        
        // Test ALU_SRA: 0xFFFFFFE0 >> 0x00000004 = 0xFFFFFFFE
        `TEST32("SRA: 0xFFFFFFE0 >> 0x00000004 = 0xFFFFFFFE",
            `ALU_SRA, 32'hFFFFFFE0, 32'h00000004, 32'hFFFFFFFE,
            0,  // expected_zero = (0xFFFFFFFE != 0)
            1,  // expected_less = (0xFFFFFFE0 < 0x00000004) signed = 1
            0   // expected_unsigned_less = (0xFFFFFFE0 < 0x00000004) unsigned = 0
        );
        
        // Test ALU_SRA: 0xFFFFFFFFFFFFFFE0 >> 0x0000000000000004 = 0xFFFFFFFFFFFFFFFE
        `TEST64("SRA: 0xFFFFFFFFFFFFFFE0 >> 0x0000000000000004 = 0xFFFFFFFFFFFFFFFE",
            `ALU_SRA, 64'hFFFFFFFFFFFFFFE0, 64'h0000000000000004, 64'hFFFFFFFFFFFFFFFE,
            0,  // expected_zero = (0xFFFFFFFFFFFFFFFE != 0)
            1,  // expected_less = (0xFFFFFFFFFFFFFFE0 < 0x0000000000000004) signed = 1
            0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFE0 < 0x0000000000000004) unsigned = 0
        );
                
        // Test ALU_SLT: 0x00000005 < 0x0000000A = 0x00000001
        `TEST32("SLT: 0x00000005 < 0x0000000A = 0x00000001",
            `ALU_SLT, 32'h00000005, 32'h0000000A, 32'h00000001,
            0,  // expected_zero = (0x00000001 != 0)
            1,  // expected_less = (0x00000005 < 0x0000000A) signed = 1
            1   // expected_unsigned_less = (0x00000005 < 0x0000000A) unsigned = 1
        );
        
        // Test ALU_SLT: 0x0000000000000005 < 0x000000000000000A = 0x0000000000000001
        `TEST64("SLT: 0x0000000000000005 < 0x000000000000000A = 0x0000000000000001",
            `ALU_SLT, 64'h0000000000000005, 64'h000000000000000A, 64'h0000000000000001,
            0,  // expected_zero = (0x0000000000000001 != 0)
            1,  // expected_less = (0x0000000000000005 < 0x000000000000000A) signed = 1
            1   // expected_unsigned_less = (0x0000000000000005 < 0x000000000000000A) unsigned = 1
        );
        
        // Test ALU_SLTU: 0x00000005 < 0x0000000A = 0x00000001
        `TEST32("SLTU: 0x00000005 < 0x0000000A = 0x00000001",
            `ALU_SLTU, 32'h00000005, 32'h0000000A, 32'h00000001,
            0,  // expected_zero = (0x00000001 != 0)
            1,  // expected_less = (0x00000005 < 0x0000000A) signed = 1
            1   // expected_unsigned_less = (0x00000005 < 0x0000000A) unsigned = 1
        );
        
        // Test ALU_SLTU: 0x0000000000000005 < 0x000000000000000A = 0x0000000000000001
        `TEST64("SLTU: 0x0000000000000005 < 0x000000000000000A = 0x0000000000000001",
            `ALU_SLTU, 64'h0000000000000005, 64'h000000000000000A, 64'h0000000000000001,
            0,  // expected_zero = (0x0000000000000001 != 0)
            1,  // expected_less = (0x0000000000000005 < 0x000000000000000A) signed = 1
            1   // expected_unsigned_less = (0x0000000000000005 < 0x000000000000000A) unsigned = 1
        );

        // 32-bit ADD Overflow
        `TEST32("ADD Overflow: 0x7FFFFFFF + 0x00000001 = 0x80000000",
            `ALU_ADD, 32'h7FFFFFFF, 32'h00000001, 32'h80000000,
            0,  // expected_zero = (0x80000000 != 0)
            0,  // expected_less = (0x7FFFFFFF < 0x00000001) signed = 0
            0   // expected_unsigned_less = (0x7FFFFFFF < 0x80000000) unsigned = 0 
        );

        // 64-bit ADD Overflow
        `TEST64("ADD Overflow: 0x7FFFFFFFFFFFFFFF + 0x0000000000000001 = 0x8000000000000000",
            `ALU_ADD, 64'h7FFFFFFFFFFFFFFF, 64'h0000000000000001, 64'h8000000000000000,
            0,  // expected_zero = (0x8000000000000000 != 0)
            0,  // expected_less = (0x7FFFFFFFFFFFFFFF < 0x0000000000000001) signed = 0
            0   // expected_unsigned_less = (0x7FFFFFFFFFFFFFFF < 0x0000000000000001) unsigned = 0
        );

        // 32-bit SUB Underflow
        `TEST32("SUB Underflow: 0x00000000 - 0x00000001 = 0xFFFFFFFF",
            `ALU_SUB, 32'h00000000, 32'h00000001, 32'hFFFFFFFF,
            0,  // expected_zero = (0xFFFFFFFF != 0)
            1,  // expected_less = (0x00000000 < 0x00000001) signed = 1
            1   // expected_unsigned_less = (0x00000000 < 0x00000001) unsigned = 1
        );

        // 64-bit SUB Underflow
        `TEST64("SUB Underflow: 0x0000000000000000 - 0x0000000000000001 = 0xFFFFFFFFFFFFFFFF",
            `ALU_SUB, 64'h0000000000000000, 64'h0000000000000001, 64'hFFFFFFFFFFFFFFFF,
            0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
            1,  // expected_less = (0x0000000000000000 < 0x0000000000000001) signed = 1
            1   // expected_unsigned_less = (0x0000000000000000 < 0x0000000000000001) unsigned = 1
        );

        // 32-bit SLL Shift Amount Zero
        `TEST32("SLL Shift Zero: 0x00000010 << 0x00000000 = 0x00000010",
            `ALU_SLL, 32'h00000010, 32'h00000000, 32'h00000010,
            0,  // expected_zero = (0x00000010 != 0)
            0,  // expected_less = (0x00000010 < 0x00000000) signed = 0
            0   // expected_unsigned_less = (0x00000010 < 0x00000000) unsigned = 0
        );

        // 64-bit SLL Shift Amount Zero
        `TEST64("SLL Shift Zero: 0x0000000000000010 << 0x0000000000000000 = 0x0000000000000010",
            `ALU_SLL, 64'h0000000000000010, 64'h0000000000000000, 64'h0000000000000010,
            0,  // expected_zero = (0x0000000000000010 != 0)
            0,  // expected_less = (0x0000000000000010 < 0x0000000000000000) signed = 0
            0   // expected_unsigned_less = (0x0000000000000010 < 0x0000000000000000) unsigned = 0
        );

        // 32-bit SLL Shift Amount XLEN
        `TEST32("SLL Shift XLEN: 0x00000001 << 32 = 0x00000001",
            `ALU_SLL, 32'h00000001, 32'h00000020, // Assuming XLEN=32, shift amount = 32 masked to 0
            32'h00000001,
            0,  // expected_zero = (0x00000001 != 0)
            1,  // expected_less = (0x00000001 < 0x00000020) signed = 1
            1   // expected_unsigned_less = (0x00000001 < 0x00000020) unsigned = 1
        );

        // 64-bit SLL Shift Amount XLEN
        `TEST64("SLL Shift XLEN: 0x0000000000000001 << 64 = 0x0000000000000001",
            `ALU_SLL, 64'h0000000000000001, 64'h0000000000000040, // Assuming XLEN=64, shift amount = 64 masked to 0
            64'h0000000000000001,
            0,  // expected_zero = (0x0000000000000001 != 0)
            1,  // expected_less = (0x0000000000000001 < 0x0000000000000040) signed = 1
            1   // expected_unsigned_less = (0x0000000000000001 < 0x0000000000000040) unsigned = 1
        );

        // 32-bit SLT with Equal Operands
        `TEST32("SLT Equal Operands: 0x00000005 < 0x00000005 = 0x00000000",
            `ALU_SLT, 32'h00000005, 32'h00000005, 32'h00000000,
            1,  // expected_zero = (0x00000000 == 0)
            0,  // expected_less = (0x00000005 < 0x00000005) signed = 0
            0   // expected_unsigned_less = (0x00000005 < 0x00000005) unsigned = 0
        );

        // 64-bit SLT with Equal Operands
        `TEST64("SLT Equal Operands: 0x0000000000000005 < 0x0000000000000005 = 0x0000000000000000",
            `ALU_SLT, 64'h0000000000000005, 64'h0000000000000005, 64'h0000000000000000,
            1,  // expected_zero = (0x0000000000000000 == 0)
            0,  // expected_less = (0x0000000000000005 < 0x0000000000000005) signed = 0
            0   // expected_unsigned_less = (0x0000000000000005 < 0x0000000000000005) unsigned = 0
        );

        // 32-bit SLTU with Equal Operands
        `TEST32("SLTU Equal Operands: 0x00000005 < 0x00000005 = 0x00000000",
            `ALU_SLTU, 32'h00000005, 32'h00000005, 32'h00000000,
            1,  // expected_zero = (0x00000000 == 0)
            0,  // expected_less = (0x00000005 < 0x00000005) signed = 0
            0   // expected_unsigned_less = (0x00000005 < 0x00000005) unsigned = 0
        );

        // 64-bit SLTU with Equal Operands
        `TEST64("SLTU Equal Operands: 0x0000000000000005 < 0x0000000000000005 = 0x0000000000000000",
            `ALU_SLTU, 64'h0000000000000005, 64'h0000000000000005, 64'h0000000000000000,
            1,  // expected_zero = (0x0000000000000000 == 0)
            0,  // expected_less = (0x0000000000000005 < 0x0000000000000005) signed = 0
            0   // expected_unsigned_less = (0x0000000000000005 < 0x0000000000000005) unsigned = 0
        );

        // 32-bit AND with All Bits Set
        `TEST32("AND All Bits Set: 0xFFFFFFFF & 0xFFFFFFFF = 0xFFFFFFFF",
            `ALU_AND, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF,
            0,  // expected_zero = (0xFFFFFFFF != 0)
            0,  // expected_less = (0xFFFFFFFF < 0xFFFFFFFF) signed = 0
            0   // expected_unsigned_less = (0xFFFFFFFF < 0xFFFFFFFF) unsigned = 0
        );

        // 64-bit AND with All Bits Set
        `TEST64("AND All Bits Set: 0xFFFFFFFFFFFFFFFF & 0xFFFFFFFFFFFFFFFF = 0xFFFFFFFFFFFFFFFF",
            `ALU_AND, 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF, 64'hFFFFFFFFFFFFFFFF,
            0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
            0,  // expected_less = (0xFFFFFFFFFFFFFFFF < 0xFFFFFFFFFFFFFFFF) signed = 0
            0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFFF < 0xFFFFFFFFFFFFFFFF) unsigned = 0
        );

        // 32-bit OR with Zero Operands
        `TEST32("OR with Zero Operands: 0x00000000 | 0x00000000 = 0x00000000",
            `ALU_OR, 32'h00000000, 32'h00000000, 32'h00000000,
            1,  // expected_zero = (0x00000000 == 0)
            0,  // expected_less = (0x00000000 < 0x00000000) signed = 0
            0   // expected_unsigned_less = (0x00000000 < 0x00000000) unsigned = 0
        );

        // 64-bit OR with Zero Operands
        `TEST64("OR with Zero Operands: 0x0000000000000000 | 0x0000000000000000 = 0x0000000000000000",
            `ALU_OR, 64'h0000000000000000, 64'h0000000000000000, 64'h0000000000000000,
            1,  // expected_zero = (0x0000000000000000 == 0)
            0,  // expected_less = (0x0000000000000000 < 0x0000000000000000) signed = 0
            0   // expected_unsigned_less = (0x0000000000000000 < 0x0000000000000000) unsigned = 0
        );

        // 32-bit SRA with Negative Number
        `TEST32("SRA Negative Number: 0xFFFFFFF0 >>> 4 = 0xFFFFFFFF",
            `ALU_SRA, 32'hFFFFFFF0, // Operand: -16
            32'h00000004, // Shift Amount: 4
            32'hFFFFFFFF, // Expected Result: -1
            0,  // expected_zero = (0xFFFFFFFF != 0)
            1,  // expected_less = (-16 < 4) signed = 1
            0   // expected_unsigned_less = (0xFFFFFFF0 < 0x00000004) unsigned = 0
        );

        // 64-bit SRA with Negative Number
        `TEST64("SRA Negative Number: 0xFFFFFFFFFFFFFFF0 >>> 4 = 64'hFFFFFFFFFFFFFFFF",
            `ALU_SRA, 64'hFFFFFFFFFFFFFFF0, 64'h0000000000000004, 64'hFFFFFFFFFFFFFFFF,
            0,  // expected_zero = (0xFFFFFFFFFFFFFFFF != 0)
            1,  // expected_less = (0xFFFFFFFFFFFFFFF0 < 0x0000000000000004) signed = 1
            0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFF0 < 0x0000000000000004) unsigned = 0
        );

        // 32-bit SLT with Negative and Positive Operands
        `TEST32("SLT Negative vs Positive: 0xFFFFFFFE < 0x00000001 = 0x00000001",
            `ALU_SLT, 32'hFFFFFFFE, // -2 in signed
            32'h00000001, // 1 in signed
            32'h00000001,
            0,  // expected_zero = (0x00000001 != 0)
            1,  // expected_less = (-2 < 1) signed = 1
            0   // expected_unsigned_less = (0xFFFFFFFE < 0x00000001) unsigned = 0
        );

        // 64-bit SLT with Negative and Positive Operands
        `TEST64("SLT Negative vs Positive: 0xFFFFFFFFFFFFFFFE < 0x0000000000000001 = 0x0000000000000001",
            `ALU_SLT, 64'hFFFFFFFFFFFFFFFE, // -2 in signed
            64'h0000000000000001, // 1 in signed
            64'h0000000000000001,
            0,  // expected_zero = (0x0000000000000001 != 0)
            1,  // expected_less = (-2 < 1) signed = 1
            0   // expected_unsigned_less = (0xFFFFFFFFFFFFFFFE < 0x0000000000000001) unsigned = 0
        );
    
        `FINISH;
    end
    
endmodule
