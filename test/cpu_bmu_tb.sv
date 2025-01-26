`default_nettype none
`timescale 1ns / 1ps

`include "cpu_bmu.sv"

`ifndef XLEN
`define XLEN 32
`endif

module cpu_bmu_tb;
`include "test/test_macros.sv"
        
// Parameters for XLEN
localparam XLEN = `XLEN;
    
// -----------------------------
// BMU Signals
// -----------------------------
logic signed [XLEN-1:0]  operand_a;
logic [XLEN-1:0]         operand_b;
logic [5:0]              control;
logic [XLEN-1:0]         result;


// Instantiate the BMU
cpu_bmu #(
    .XLEN(XLEN)
) uut (
    .operand_a           (operand_a),
    .operand_b           (operand_b),
    .control             (control),
    .result              (result)
);

task Test(
    input string             desc,
    input [3:0]              in_control,
    input signed [XLEN-1:0]  in_operand_a,
    input [XLEN-1:0]         in_operand_b,
    input [XLEN-1:0]         expected_result
);
    begin
        `TEST("cpu_bmu", desc);
        operand_a = in_operand_a;
        operand_b = in_operand_b;
        control   = in_control;

        #10;

        `EXPECT("Result", result, expected_result);

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
    $dumpfile("cpu_bmu_tb.vcd");
    $dumpvars(0, cpu_bmu_tb);

    // Initialize Inputs for 32-bit BMU
    operand_a = 0;
    operand_b = 0;
    control = 0;

    //////////////////////////////////////////////////////////////
    // B Extension Tests
    //////////////////////////////////////////////////////////////

    // Test CLZ: Count Leading Zeros
    if (XLEN == 32) begin
    Test("CLZ: 0x00000006 = 29 leading zeros",
        `BMU_CLZ, 32'h00000006, 32'h0, 32'h0000001D
    );
    end else begin
    Test("CLZ: 0x00000006 = 61 leading zeros",
        `BMU_CLZ, 32'h00000006, 32'h0, 32'h0000003D
    );
    end

    if (XLEN == 64) begin
    Test("CLZ: 0x000000000000006E = 57 leading zeros",
        `BMU_CLZ, 64'h000000000000006E, 64'h0, 64'h0000000000000039
    );
    end

    // Test CTZ: Count Trailing Zeros
    Test("CTZ: 0x0F000020 = 5 trailing zeros",
        `BMU_CTZ, 32'h0F000020, 32'h0, 32'h00000005
    );

    if (XLEN == 64) begin
    Test("CTZ: 0x00F0000000002000 = 13 trailing zeros",
        `BMU_CTZ, 64'h00F0000000002000, 64'h0, 64'h000000000000000D
    );
    end

    // Test CPOP: Count Population (Set Bits)
    Test("CPOP: 0xF0F0F0F0 = 16 set bits",
        `BMU_CPOP, 32'hF0F0F0F0, 32'h0, 32'h00000010
    );

    if (XLEN == 64) begin
    Test("CPOP: 0xFFFFFFFF00000000 = 32 set bits",
        `BMU_CPOP, 64'hFFFFFFFF00000000, 64'h0, 64'h0000000000000020
    );
    end

    // Test ANDN: 0xFF00FF00 & ~0x00FF00FF = 0xFF00FF00
    Test("ANDN: 0xFF00FF00 & ~0x00FF00FF = 0xFF00FF00",
        `BMU_ANDN, 32'hFF00FF00, 32'h00FF00FF, 32'hFF00FF00
    );

    if (XLEN == 64) begin
    Test("ANDN: 0xFF00FF00FF00FF00 & ~0x00FF00FF00FF00FF = 0xFF00FF00FF00FF00",
        `BMU_ANDN, 64'hFF00FF00FF00FF00, 64'h00FF00FF00FF00FF, 64'hFF00FF00FF00FF00
    );
    end

    // Test ORN: 0xFF00FF00 | ~0x00FF00FF = 0xFF00FF00
    Test("ORN: 0xFF00FF00 | ~0x00FF00FF = 0xFF00FF00",
        `BMU_ORN, 32'hFF00FF00, 32'h00FF00FF, {{(XLEN-32){1'hF}}, 32'hFF00FF00}
    );

    if (XLEN == 64) begin
    Test("ORN: 0xFF00FF00FF00FF00 | ~0x00FF00FF00FF00FF = 0xFF00FF00FF00FF00",
        `BMU_ORN, 64'hFF00FF00FF00FF00, 64'h00FF00FF00FF00FF, 64'hFF00FF00FF00FF00
    );
    end

    // Test ROL: 0x80000000 rotated left by 1 = 0x00000001
    if (XLEN == 32) begin
    Test("ROL: 0x80000000 rotated left by 1 = 0x00000001",
        `BMU_ROL, 32'h80000000, 32'h00000001, 32'h00000001
    );
    end

    if (XLEN == 64) begin
    Test("ROL: 0x8000000000000000 rotated left by 1 = 0x0000000000000001",
        `BMU_ROL, 64'h8000000000000000, 64'h0000000000000001, 64'h0000000000000001
    );
    end

    // Test ROR: 0x00000001 rotated right by 1 = 0x80000000
    Test("ROR: 0x00000001 rotated right by 1 = 0x80000000",
        `BMU_ROR, 32'h00000001, 32'h00000001, {32'h80000000, {(XLEN-32){1'h0}}}
    );

    if (XLEN == 64) begin
    Test("ROR: 0x0000000000000001 rotated right by 1 = 0x8000000000000000",
        `BMU_ROR, 64'h0000000000000001, 64'h0000000000000001, 64'h8000000000000000
    );
    end

    `FINISH;
end
    
endmodule
