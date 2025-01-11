`default_nettype none
`timescale 1ns / 1ps

`include "src/cpu_mdu.sv"

module cpu_mdu_tb;
        
    // Parameters for XLEN
    localparam XLEN_32 = 32;
    localparam XLEN_64 = 64;
    
    // -----------------------------
    // 32-bit MDU Signals
    // -----------------------------
    // Inputs
    logic clk_32;
    logic reset_32;
    logic signed [XLEN_32-1:0]  operand_a32;
    logic [XLEN_32-1:0]         operand_b32;
    logic [2:0]                 control32;
    logic                       start32;
    logic [XLEN_32-1:0]         result32;
    logic                       ready32;
    
    // -----------------------------
    // 64-bit MDU Signals
    // -----------------------------
    // Inputs
    logic clk_64;
    logic reset_64;
    logic signed [XLEN_64-1:0]  operand_a64;
    logic [XLEN_64-1:0]         operand_b64;
    logic [2:0]                 control64;
    logic                       start64;
    logic [XLEN_64-1:0]         result64;
    logic                       ready64;
    
    // Instantiate the 32-bit MDU
    cpu_mdu #(
        .XLEN(XLEN_32)
    ) uut32 (
        .clk                 (clk_32),
        .reset               (reset_32),
        .operand_a           (operand_a32),
        .operand_b           (operand_b32),
        .control             (control32),
        .result              (result32),
        .start               (start32),
        .ready               (ready32)
    );
    
    // Instantiate the 64-bit MDU
    cpu_mdu #(
        .XLEN(XLEN_64)
    ) uut64 (
        .clk                 (clk_64),
        .reset               (reset_64),
        .operand_a           (operand_a64),
        .operand_b           (operand_b64),
        .control             (control64),
        .result              (result64),
        .start               (start64),
        .ready               (ready64)
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
    
    // Test Macro for Operations with MUL/DIV
    `define TEST32(desc, ctrl, a, b, expected_result) \
        begin \
            testCount = testCount + 1; \
            $display("\n[32bit MDU] Test %0d: %s", testCount, desc); \
            operand_a32 = a; \
            operand_b32 = b; \
            control32 = ctrl; \
            start32 = 1; \
            $display("  Operands for 32-bit MDU: a32=0x%h, b32=0x%h", operand_a32, operand_b32); \
            #10; \
            start32 = 0; \
            fork \
                begin \
                    wait (ready32); \
                    disable timeout32_`__LINE__; \
                end \
                begin: timeout32_`__LINE__ \
                    #1000; // Timeout after 1000 time units \
                    $display("  == FAIL == Timeout waiting for ready32."); \
                    testCountFail = testCountFail + 1; \
                    $stop; \
                end \
            join \
            #10; /* Wait for MDU operation */ \
            `EXPECT("Result", result32, expected_result); \
        end
    `define TEST64(desc, ctrl, a, b, expected_result) \
        begin \
            testCount = testCount + 1; \
            $display("\n[64bit MDU] Test %0d: %s", testCount, desc); \
            operand_a64 = a; \
            operand_b64 = b; \
            control64 = ctrl; \
            start64 = 1; \
            $display("  Operands for 64-bit MDU: a64=0x%h, b64=0x%h", operand_a64, operand_b64); \
            #10; \
            start64 = 0; \
            fork \
                begin \
                    wait (ready64); \
                    disable timeout34_`__LINE__; \
                end \
                begin: timeout34_`__LINE__ \
                    #5000; // Timeout after 1000 time units \
                    $display("  == FAIL == Timeout waiting for ready64."); \
                    testCountFail = testCountFail + 1; \
                    $stop; \
                end \
            join \
            #10; /* Wait for MDU operation */ \
            `EXPECT("Result", result64, expected_result); \
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
    
    // Clock generation
    initial begin
        clk_32 = 0;
        forever #5 clk_32 = ~clk_32; // 100MHz clock
    end
    initial begin
        clk_64 = 0;
        forever #5 clk_64 = ~clk_64; // 100MHz clock
    end
    
    initial begin
        $dumpfile("cpu_mdu_tb.vcd");
        $dumpvars(0, cpu_mdu_tb);
    
        // Initialize Inputs for 32-bit MDU
        reset_32 = 1;
        operand_a32 = 0;
        operand_b32 = 0;
        control32 = 0;
        start32 = 0;
    
        // Initialize Inputs for 64-bit MDU
        reset_64 = 1;
        operand_a64 = 0;
        operand_b64 = 0;
        control64 = 0;
        start64 = 0;
    
        #10;
        reset_32 = 0;
        reset_64 = 0;

        //////////////////////////////////////////////////////////////
        // M Extension Tests
        //////////////////////////////////////////////////////////////
        
        // Test MUL: 0x00000002 * 0x00000003 = 0x00000006
        `TEST32("MUL: 0x00000002 * 0x00000003 = 0x00000006",
            `MDU_MUL, 32'h00000002, 32'h00000003, 32'h00000006
        );
    
        // Test MUL: 0x0000000000000002 * 0x0000000000000003 = 0x0000000000000006
        `TEST64("MUL: 0x0000000000000002 * 0x0000000000000003 = 0x0000000000000006",
            `MDU_MUL, 64'h0000000000000002, 64'h0000000000000003, 64'h0000000000000006
        );
    
        // Test MULH: 0xFFFFFFFF * 0x00000002 = 0xFFFFFFFF (upper 32 bits of product)
        `TEST32("MULH: 0xFFFFFFFF * 0x00000002 = 0xFFFFFFFF",
            `MDU_MULH, 32'hFFFFFFFF, 32'h00000002, 32'hFFFFFFFF
        );
        
        // Test MULH: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFF (upper 64 bits)
        `TEST64("MULH: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFF",
            `MDU_MULH, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000002, 64'hFFFFFFFFFFFFFFFF
        );
        
        // Test MULHSU: 0xFFFFFFFF * 0x00000002 (signed * unsigned) = 0xFFFFFFFF
        `TEST32("MULHSU: 0xFFFFFFFF * 0x00000002 = 0xFFFFFFFF",
            `MDU_MULHSU, 32'hFFFFFFFF, 32'h00000002, 32'hFFFFFFFF
        );
        
        // Test MULHSU: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 (signed * unsigned) = 0xFFFFFFFFFFFFFFFF
        `TEST64("MULHSU: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFF",
            `MDU_MULHSU, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000002, 64'hFFFFFFFFFFFFFFFF
        );
        
        // Test MULHU: 0xFFFFFFFF * 0x00000002 (unsigned * unsigned) = 0x00000001 (upper 32 bits)
        `TEST32("MULHU: 0xFFFFFFFF * 0x00000002 = 0x00000001",
            `MDU_MULHU, 32'hFFFFFFFF, 32'h00000002, 32'h00000001
        );
        
        // Test MULHU: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 (unsigned * unsigned) = 0x0000000000000001 (upper 64 bits)
        `TEST64("MULHU: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 = 0x0000000000000001",
            `MDU_MULHU, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000002, 64'h0000000000000001
        );
        
        // Test DIV: 0x00000006 / 0x00000003 = 0x00000002
        `TEST32("DIV: 0x00000006 / 0x00000003 = 0x00000002",
            `MDU_DIV, 32'h00000006, 32'h00000003, 32'h00000002
        );
        
        // Test DIV: 0x0000000000000006 / 0x0000000000000003 = 0x0000000000000002
        `TEST64("DIV: 0x0000000000000006 / 0x0000000000000003 = 0x0000000000000002",
            `MDU_DIV, 64'h0000000000000006, 64'h0000000000000003, 64'h0000000000000002
        );
        
        // Test REM: 0x00000007 % 0x00000003 = 0x00000001
        `TEST32("REM: 0x00000007 % 0x00000003 = 0x00000001",
            `MDU_REM, 32'h00000007, 32'h00000003, 32'h00000001
        );
        
        // Test REMU: 0x0000000000000007 % 0x0000000000000003 = 0x0000000000000001
        `TEST64("REMU: 0x0000000000000007 % 0x0000000000000003 = 0x0000000000000001",
            `MDU_REMU, 64'h0000000000000007, 64'h0000000000000003, 64'h0000000000000001
        );
        
        // Test MUL by Zero: 0x00000000 * 0x12345678 = 0x00000000
        `TEST32("MUL by Zero: 0x00000000 * 0x12345678 = 0x00000000",
            `MDU_MUL, 32'h00000000, 32'h12345678, 32'h00000000
        );
        
        // Test MUL by Zero: 0x0000000000000000 * 0x123456789ABCDEF0 = 0x0000000000000000
        `TEST64("MUL by Zero: 0x0000000000000000 * 0x123456789ABCDEF0 = 0x0000000000000000",
            `MDU_MUL, 64'h0000000000000000, 64'h123456789ABCDEF0, 64'h0000000000000000
        );
        
        // Test DIV by Zero: 0x00000001 / 0x00000000 = -1 (0x7FFFFFFF)
        `TEST32("DIV by Zero: 0x00000001 / 0x00000000 = 0x7FFFFFFF",
            `MDU_DIV, 32'h00000001, 32'h00000000, 32'h7FFFFFFF
        );
        
        // Test DIV by Zero: 0x0000000000000001 / 0x0000000000000000 = -1 (0x7FFFFFFFFFFFFFFF)
        `TEST64("DIV by Zero: 0x0000000000000001 / 0x0000000000000000 = 0x7FFFFFFFFFFFFFFF",
            `MDU_DIV, 64'h0000000000000001, 64'h0000000000000000, 64'h7FFFFFFFFFFFFFFF
        );
        
        // Test MUL with Negative Operand: 0xFFFFFFFE * 0x00000002 = 0xFFFFFFFC
        `TEST32("MUL with Negative Operand: 0xFFFFFFFE * 0x00000002 = 0xFFFFFFFC",
            `MDU_MUL, 32'hFFFFFFFE, // -2 in signed
            32'h00000002, 32'hFFFFFFFC
        );
        
        // Test MUL with Negative Operand: 0xFFFFFFFFFFFFFFFE * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFC
        `TEST64("MUL with Negative Operand: 0xFFFFFFFFFFFFFFFE * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFC",
            `MDU_MUL, 64'hFFFFFFFFFFFFFFFE, // -2 in signed
            64'h0000000000000002, 64'hFFFFFFFFFFFFFFFC
        );
        
        // Test MUL by One: 0x00000005 * 0x00000001 = 0x00000005
        `TEST32("MUL by One: 0x00000005 * 0x00000001 = 0x00000005",
            `MDU_MUL, 32'h00000005, 32'h00000001, 32'h00000005
        );
        
        // Test MUL by One: 0x0000000000000005 * 0x0000000000000001 = 0x0000000000000005
        `TEST64("MUL by One: 0x0000000000000005 * 0x0000000000000001 = 0x0000000000000005",
            `MDU_MUL, 64'h0000000000000005, 64'h0000000000000001, 64'h0000000000000005
        );

        // Test MUL with Maximum Values: 0x7FFFFFFF * 0x7FFFFFFF
        `TEST32("MUL with Maximum Values: 0x7FFFFFFF * 0x7FFFFFFF = 0x3FFFFFFF",
            `MDU_MULH, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'h3FFFFFFF
        ); 

        // Test MUL with Maximum Values: 0x7FFFFFFFFFFFFFFF * 0x7FFFFFFFFFFFFFFF
        `TEST64("MUL with Maximum Values: 0x7FFFFFFFFFFFFFFF * 0x7FFFFFFFFFFFFFFF = 0x3FFFFFFFFFFFFFFF",
            `MDU_MULH, 64'h7FFFFFFFFFFFFFFF, 64'h7FFFFFFFFFFFFFFF, 64'h3FFFFFFFFFFFFFFF
        );
    
        `FINISH;
    end
    
endmodule
