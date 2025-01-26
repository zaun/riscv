`default_nettype none
`timescale 1ns / 1ps

// `define LOG_REG

`include "cpu_regfile.sv"

`ifndef XLEN
`define XLEN 32
`endif

module cpu_regfile_tb;
`include "test/test_macros.sv"

// Parameters for XLEN
localparam XLEN = `XLEN;

// -----------------------------
// Register File Signals
// -----------------------------
// Inputs
logic            clk;
logic            reset;
logic [4:0]      rs1_addr;
logic [4:0]      rs2_addr;
logic [4:0]      rd_addr;
logic [XLEN-1:0] rd_data;
logic            rd_write_en;

// Outputs
logic [XLEN-1:0] rs1_data;
logic [XLEN-1:0] rs2_data;


// Instantiate the Register File
cpu_regfile #(
    .XLEN(XLEN)
) uut32 (
    .clk         (clk),
    .reset       (reset),
    .rs1_addr    (rs1_addr),
    .rs2_addr    (rs2_addr),
    .rd_addr     (rd_addr),
    .rd_data     (rd_data),
    .rd_write_en (rd_write_en),
    .rs1_data    (rs1_data),
    .rs2_data    (rs2_data)
);

// Task to perform a write test
task Test(
    input string     desc,
    input [4:0]      in_rd_addr,
    input [XLEN-1:0] in_rd_data,
    input            in_rd_write_en,
    input [4:0]      in_rs1_addr,
    input [4:0]      in_rs2_addr,
    input [XLEN-1:0] expected_rs1_data,
    input [XLEN-1:0] expected_rs2_data
);
    begin
        `TEST("cpu_regfile", desc);
        rd_addr     = in_rd_addr;
        rd_data     = in_rd_data;
        rd_write_en = in_rd_write_en;
        rs1_addr    = in_rs1_addr;
        rs2_addr    = in_rs2_addr;

        @(posedge clk);

        `EXPECT("rs1_data value", rs1_data, expected_rs1_data);
        `EXPECT("rs2_data value", rs2_data, expected_rs2_data);

        rd_write_en = 0;
    end
endtask

// Clock generation for 32-bit Register File
initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz clock
end

initial begin
    $dumpfile("cpu_regfile_tb.vcd");
    $dumpvars(0, cpu_regfile_tb);

    // Initialize Inputs for 32-bit Register File
    reset       = 1;
    rd_addr     = 5'd0;
    rd_data     = {XLEN{1'b0}};
    rd_write_en = 1'b0;
    rs1_addr    = 5'd0;
    rs2_addr    = 5'd0;

    // ====================================
    // Apply Reset
    // ====================================
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);
    reset = 0;
    @(posedge clk);

    Test("Write x1=0x12345678 and read x1, x2",
            5'd1, 32'h12345678, 1'b1,    // Write to x1
            5'd1, 5'd2,                  // Read from x1 and x2
            32'h12345678, 32'h00000000); // Expected x1=0x12345678, x2=0

    Test("Attempt to write x0=0xDEADBEEF (should remain 0) and read x0, x1",
                    5'd0, 32'hDEADBEEF, 1'b1,    // Write to x0
                    5'd0, 5'd1,                  // Read from x0 and x1
                    32'h00000000, 32'h12345678); // Expected x0=0, x1=0x12345678

    Test("Write x2=0xFFFFFFFF and read x1, x2",
                    5'd2, 32'hFFFFFFFF, 1'b1, // Write to x2
                    5'd1, 5'd2,               // Read from x1 and x2
                    32'h12345678, 32'hFFFFFFFF); // Expected x1=0x12345678, x2=0xFFFFFFFF

    Test("Write x3=0x00000000 and read x3, x4",
                    5'd3, 32'h00000000, 1'b1, // Write to x3
                    5'd3, 5'd4,               // Read from x3 and x4
                    32'h00000000, 32'h00000000); // Expected x3=0, x4=0

    Test("Write x4=0xAAAAAAAA and read x1, x4",
                    5'd4, 32'hAAAAAAAA, 1'b1, // Write to x4
                    5'd1, 5'd4,               // Read from x1 and x4
                    32'h12345678, 32'hAAAAAAAA); // Expected x1=..., x4=0xAAAAAAAA

    // ====================================
    // Apply Reset
    // ====================================
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);
    reset = 0;
    @(posedge clk);

    Test("After reset: read x0, x1, x2",
                    5'd0, 32'h00000000, 1'b0, // No write
                    5'd0, 5'd1,               // Read from x0 and x1
                    32'h00000000, 32'h00000000); // Expected x0=0, x1=0

    Test("After reset: read x2, x3",
                    5'd0, 32'h00000000, 1'b0, // No write
                    5'd2, 5'd3,               // Read from x2 and x3
                    32'h00000000, 32'h00000000); // Expected x2=0, x3=0

    Test("After reset: read x4",
                    5'd0, 32'h00000000, 1'b0, // No write
                    5'd4, 5'd0,               // Read from x4 and x0
                    32'h00000000, 32'h00000000); // Expected x4=0, x0=0

    Test("Write x5=0x55555555 and x6=0xAAAAAAAA and read x5, x6",
                    5'd5, 32'h55555555, 1'b1, // Write to x5
                    5'd5, 5'd6,               // Read from x5 and x6
                    32'h55555555, 32'h00000000); // Expected x5=0x55555555, x6=0

    Test("Write x6=0xAAAAAAAA and read x5, x6",
                    5'd6, 32'hAAAAAAAA, 1'b1, // Write to x6
                    5'd5, 5'd6,               // Read from x5 and x6
                    32'h55555555, 32'hAAAAAAAA); // Expected x5=0x55555555, x6=0xAAAAAAAA

    Test("Write x7=0x0 and read x7, x8",
                    5'd7, 32'h00000000, 1'b1, // Write to x7
                    5'd7, 5'd8,               // Read from x7 and x8
                    32'h00000000, 32'h00000000); // Expected x7=0, x8=0


    Test("Write x8=0xFFFFFFFF and read x7, x8",
                    5'd8, 32'hFFFFFFFF, 1'b1, // Write to x8
                    5'd7, 5'd8,               // Read from x7 and x8
                    32'h00000000, 32'hFFFFFFFF); // Expected x7=0, x8=0xFFFFFFFF

    if (XLEN >=64) begin
    Test("Write x1=0x123456789ABCDEF0 and read x1, x2",
                    5'd1, 64'h123456789ABCDEF0, 1'b1, // Write to x1
                    5'd1, 5'd2,                     // Read from x1 and x2
                    64'h123456789ABCDEF0, 64'h0000000000000000); // Expected x1=..., x2=0

    Test("Attempt to write x0=0xDEADBEEFDEADBEEF (should remain 0) and read x0, x1",
                    5'd0, 64'hDEADBEEFDEADBEEF, 1'b1, // Write to x0
                    5'd0, 5'd1,                     // Read from x0 and x1
                    64'h0000000000000000, 64'h123456789ABCDEF0); // Expected x0=0, x1=...

    Test("Write x2=0xFFFFFFFFFFFFFFFF and read x1, x2",
                    5'd2, 64'hFFFFFFFFFFFFFFFF, 1'b1, // Write to x2
                    5'd1, 5'd2,                     // Read from x1 and x2
                    64'h123456789ABCDEF0, 64'hFFFFFFFFFFFFFFFF); // Expected x1=..., x2=...

    Test("Write x3=0x0000000000000000 and read x3, x4",
                    5'd3, 64'h0000000000000000, 1'b1, // Write to x3
                    5'd3, 5'd4,                     // Read from x3 and x4
                    64'h0000000000000000, 64'h0000000000000000); // Expected x3=0, x4=0

    Test("Write x4=0xAAAAAAAAAAAAAAAA and read x1, x4",
                    5'd4, 64'hAAAAAAAAAAAAAAAA, 1'b1, // Write to x4
                    5'd1, 5'd4,                     // Read from x1 and x4
                    64'h123456789ABCDEF0, 64'hAAAAAAAAAAAAAAAA); // Expected x1=..., x4=...

    // ====================================
    // Apply Reset
    // ====================================
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);
    reset = 0;
    @(posedge clk);

    Test("After reset: read x0, x1, x2",
                    5'd0, 64'h0000000000000000, 1'b0, // No write
                    5'd0, 5'd1,                     // Read from x0 and x1
                    64'h0000000000000000, 64'h0000000000000000); // Expected x0=0, x1=0

    Test("After reset: read x2, x3",
                    5'd0, 64'h0000000000000000, 1'b0, // No write
                    5'd2, 5'd3,                     // Read from x2 and x3
                    64'h0000000000000000, 64'h0000000000000000); // Expected x2=0, x3=0

    Test("After reset: read x4",
                    5'd0, 64'h0000000000000000, 1'b0, // No write
                    5'd4, 5'd0,                     // Read from x4 and x0
                    64'h0000000000000000, 64'h0000000000000000); // Expected x4=0, x0=0

    Test("Write x5=0x5555555555555555 and x6=0xAAAAAAAAAAAAAAAA and read x5, x6",
                    5'd5, 64'h5555555555555555, 1'b1, // Write to x5
                    5'd5, 5'd6,                     // Read from x5 and x6
                    64'h5555555555555555, 64'h0000000000000000); // Expected x5=..., x6=0

    Test("Write x6=0xAAAAAAAAAAAAAAAA and read x5, x6",
                    5'd6, 64'hAAAAAAAAAAAAAAAA, 1'b1, // Write to x6
                    5'd5, 5'd6,                     // Read from x5 and x6
                    64'h5555555555555555, 64'hAAAAAAAAAAAAAAAA); // Expected x5=..., x6=...

    Test("Write x7=0x0000000000000000 and read x7, x8",
                    5'd7, 64'h0000000000000000, 1'b1, // Write to x7
                    5'd7, 5'd8,                     // Read from x7 and x8
                    64'h0000000000000000, 64'h0000000000000000); // Expected x7=0, x8=0

    Test("Write x8=0xFFFFFFFFFFFFFFFF and read x7, x8",
                    5'd8, 64'hFFFFFFFFFFFFFFFF, 1'b1, // Write to x8
                    5'd7, 5'd8,                     // Read from x7 and x8
                    64'h0000000000000000, 64'hFFFFFFFFFFFFFFFF); // Expected x7=0, x8=0xFFFFFFFFFFFFFFFF
    end
    
    // -------------------
    // Finish the simulation
    // -------------------
    `FINISH;
end

endmodule
