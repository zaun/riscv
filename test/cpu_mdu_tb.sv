`default_nettype none
`timescale 1ns / 1ps

`include "cpu_mdu.sv"

`ifndef XLEN
`define XLEN 32
`endif

module cpu_mdu_tb;
`include "test/test_macros.sv"
        
// Parameters for XLEN
localparam XLEN = `XLEN;

// -----------------------------
// 32-bit MDU Signals
// -----------------------------
// Inputs
logic                    clk;
logic                    reset;
logic signed [XLEN-1:0]  operand_a;
logic [XLEN-1:0]         operand_b;
logic [2:0]              control;
logic                    start;
logic [XLEN-1:0]         result;
logic                    ready;

// Instantiate the 32-bit MDU
cpu_mdu #(
    .XLEN(XLEN)
) uut (
    .clk                 (clk),
    .reset               (reset),
    .operand_a           (operand_a),
    .operand_b           (operand_b),
    .control             (control),
    .result              (result),
    .start               (start),
    .ready               (ready)
);



task Test(
    input string             desc,
    input [3:0]              in_control,
    input signed [XLEN-1:0]  in_operand_a,
    input [XLEN-1:0]         in_operand_b,
    input [XLEN-1:0]         expected_result
);
    begin
        `TEST("cpu_mdu", desc);
        operand_a = in_operand_a;
        operand_b = in_operand_b;
        control   = in_control;
        start     = 1;

        @(posedge clk);

        fork
            begin
                wait (ready);
                disable timeout;
            end
            begin: timeout
                #1000; // Timeout after 1000 time units
                $display("  == FAIL == Timeout waiting for ready.");
                $stop;
            end
        join

        `EXPECT("Result", result, expected_result);

        start = 0;
        @(posedge clk);

        #10;
    end
endtask

// Clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz clock
end

initial begin
    $dumpfile("cpu_mdu_tb.vcd");
    $dumpvars(0, cpu_mdu_tb);

    // Initialize Inputs for 32-bit MDU
    reset = 1;
    operand_a = 0;
    operand_b = 0;
    control = 0;
    start = 0;

    #10;
    reset = 0;

    //////////////////////////////////////////////////////////////
    // M Extension Tests
    //////////////////////////////////////////////////////////////
    
    // Test MUL: 0x00000002 * 0x00000003 = 0x00000006
    Test("MUL: 0x00000002 * 0x00000003 = 0x00000006",
        `MDU_MUL, 32'h00000002, 32'h00000003, 32'h00000006
    );

    if (XLEN == 64) begin
    // Test MUL: 0x0000000000000002 * 0x0000000000000003 = 0x0000000000000006
    Test("MUL: 0x0000000000000002 * 0x0000000000000003 = 0x0000000000000006",
        `MDU_MUL, 64'h0000000000000002, 64'h0000000000000003, 64'h0000000000000006
    );
    end

    // Test MULH: 0xFFFFFFFF * 0x00000002 = 0xFFFFFFFF (upper 32 bits of product)
    if (XLEN == 32) begin
    Test("MULH: 0xFFFFFFFF * 0x00000002 = 0xFFFFFFFF",
        `MDU_MULH, 32'hFFFFFFFF, 32'h00000002, 32'hFFFFFFFF
    );
    end
    
    if (XLEN == 64) begin
    // Test MULH: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFF (upper 64 bits)
    Test("MULH: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFF",
        `MDU_MULH, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000002, 64'hFFFFFFFFFFFFFFFF
    );
    end
    
    // Test MULHSU: 0xFFFFFFFF * 0x00000002 (signed * unsigned) = 0xFFFFFFFF
    if (XLEN == 32) begin
    Test("MULHSU: 0xFFFFFFFF * 0x00000002 = 0xFFFFFFFF",
        `MDU_MULHSU, 32'hFFFFFFFF, 32'h00000002, 32'hFFFFFFFF
    );
    end
    
    if (XLEN == 64) begin
    // Test MULHSU: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 (signed * unsigned) = 0xFFFFFFFFFFFFFFFF
    Test("MULHSU: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFF",
        `MDU_MULHSU, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000002, 64'hFFFFFFFFFFFFFFFF
    );
    end
    
    // Test MULHU: 0xFFFFFFFF * 0x00000002 (unsigned * unsigned) = 0x00000001 (upper 32 bits)
    if (XLEN == 32) begin
    Test("MULHU: 0xFFFFFFFF * 0x00000002 = 0x00000001",
        `MDU_MULHU, 32'hFFFFFFFF, 32'h00000002, 32'h00000001
    );
    end
    
    if (XLEN == 64) begin
    // Test MULHU: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 (unsigned * unsigned) = 0x0000000000000001 (upper 64 bits)
    Test("MULHU: 0xFFFFFFFFFFFFFFFF * 0x0000000000000002 = 0x0000000000000001",
        `MDU_MULHU, 64'hFFFFFFFFFFFFFFFF, 64'h0000000000000002, 64'h0000000000000001
    );
    end
    
    // Test DIV: 0x00000006 / 0x00000003 = 0x00000002
    Test("DIV: 0x00000006 / 0x00000003 = 0x00000002",
        `MDU_DIV, 32'h00000006, 32'h00000003, 32'h00000002
    );
    
    if (XLEN == 64) begin
    // Test DIV: 0x0000000000000006 / 0x0000000000000003 = 0x0000000000000002
    Test("DIV: 0x0000000000000006 / 0x0000000000000003 = 0x0000000000000002",
        `MDU_DIV, 64'h0000000000000006, 64'h0000000000000003, 64'h0000000000000002
    );
    end
    
    // Test REM: 0x00000007 % 0x00000003 = 0x00000001
    Test("REM: 0x00000007 % 0x00000003 = 0x00000001",
        `MDU_REM, 32'h00000007, 32'h00000003, 32'h00000001
    );
    
    if (XLEN == 64) begin
    // Test REMU: 0x0000000000000007 % 0x0000000000000003 = 0x0000000000000001
    Test("REMU: 0x0000000000000007 % 0x0000000000000003 = 0x0000000000000001",
        `MDU_REMU, 64'h0000000000000007, 64'h0000000000000003, 64'h0000000000000001
    );
    end
    
    // Test MUL by Zero: 0x00000000 * 0x12345678 = 0x00000000
    Test("MUL by Zero: 0x00000000 * 0x12345678 = 0x00000000",
        `MDU_MUL, 32'h00000000, 32'h12345678, 32'h00000000
    );
    
    if (XLEN == 64) begin
    // Test MUL by Zero: 0x0000000000000000 * 0x123456789ABCDEF0 = 0x0000000000000000
    Test("MUL by Zero: 0x0000000000000000 * 0x123456789ABCDEF0 = 0x0000000000000000",
        `MDU_MUL, 64'h0000000000000000, 64'h123456789ABCDEF0, 64'h0000000000000000
    );
    end
    
    // Test DIV by Zero: 0x00000001 / 0x00000000 = -1 (0x7FFFFFFF)
    Test("DIV by Zero: 0x00000001 / 0x00000000 = 0x7FFFFFFF",
        `MDU_DIV, 32'h00000001, 32'h00000000, {32'h7FFFFFFF, {(XLEN-32){1'hF}}}
    );
    
    if (XLEN == 64) begin
    // Test DIV by Zero: 0x0000000000000001 / 0x0000000000000000 = -1 (0x7FFFFFFFFFFFFFFF)
    Test("DIV by Zero: 0x0000000000000001 / 0x0000000000000000 = 0x7FFFFFFFFFFFFFFF",
        `MDU_DIV, 64'h0000000000000001, 64'h0000000000000000, 64'h7FFFFFFFFFFFFFFF
    );
    end
    
    // Test MUL with Negative Operand: 0xFFFFFFFE * 0x00000002 = 0xFFFFFFFC
    if (XLEN == 32) begin
    Test("MUL with Negative Operand: 0xFFFFFFFE * 0x00000002 = 0xFFFFFFFC",
        `MDU_MUL, 32'hFFFFFFFE, // -2 in signed
        32'h00000002, 32'hFFFFFFFC
    );
    end
    
    if (XLEN == 64) begin
    // Test MUL with Negative Operand: 0xFFFFFFFFFFFFFFFE * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFC
    Test("MUL with Negative Operand: 0xFFFFFFFFFFFFFFFE * 0x0000000000000002 = 0xFFFFFFFFFFFFFFFC",
        `MDU_MUL, 64'hFFFFFFFFFFFFFFFE, // -2 in signed
        64'h0000000000000002, 64'hFFFFFFFFFFFFFFFC
    );
    end
    
    // Test MUL by One: 0x00000005 * 0x00000001 = 0x00000005
    Test("MUL by One: 0x00000005 * 0x00000001 = 0x00000005",
        `MDU_MUL, 32'h00000005, 32'h00000001, 32'h00000005
    );
    
    if (XLEN == 64) begin
    // Test MUL by One: 0x0000000000000005 * 0x0000000000000001 = 0x0000000000000005
    Test("MUL by One: 0x0000000000000005 * 0x0000000000000001 = 0x0000000000000005",
        `MDU_MUL, 64'h0000000000000005, 64'h0000000000000001, 64'h0000000000000005
    );
    end

    // Test MUL with Maximum Values: 0x7FFFFFFF * 0x7FFFFFFF
    if (XLEN == 32) begin
    Test("MUL with Maximum Values: 0x7FFFFFFF * 0x7FFFFFFF = 0x3FFFFFFF",
        `MDU_MULH, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'h3FFFFFFF
    ); 
    end

    if (XLEN == 64) begin
    // Test MUL with Maximum Values: 0x7FFFFFFFFFFFFFFF * 0x7FFFFFFFFFFFFFFF
    Test("MUL with Maximum Values: 0x7FFFFFFFFFFFFFFF * 0x7FFFFFFFFFFFFFFF = 0x3FFFFFFFFFFFFFFF",
        `MDU_MULH, 64'h7FFFFFFFFFFFFFFF, 64'h7FFFFFFFFFFFFFFF, 64'h3FFFFFFFFFFFFFFF
    );
    end

    `FINISH;
end
    
endmodule
