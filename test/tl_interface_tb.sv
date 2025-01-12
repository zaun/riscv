`timescale 1ns / 1ps
`default_nettype none

`define DEBUG // Turn on debugging ports
// `define LOG_MEM_INTERFACE
// `define LOG_MEMORY

`include "src/tl_interface.sv"
`include "src/tl_memory.sv"

`ifndef XLEN
`define XLEN 32
`endif

module tl_interface_tb;
`include "test/test_macros.sv"

// ====================================
// Parameters
// ====================================
parameter XLEN = `XLEN;
parameter SID_WIDTH = 2;     // Source ID length for TileLink
parameter MEM_SIZE = 4096;   // Memory size (supports addresses up to 0x0FFF)
parameter MAX_RETRIES = 3;   // Maximum number of retry attempts

// ====================================
// Clock and Reset
// ====================================
reg clk;
reg reset;

// Clock Generation: 100MHz Clock (10ns period)
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// ====================================
// Memory Interface Signals (CPU Side)
// ====================================

reg                  cpu_ready;
reg [XLEN-1:0]       cpu_address;
reg [XLEN-1:0]       cpu_wdata;
reg [XLEN/8-1:0]     cpu_wstrb;
reg [2:0]            cpu_size;     // 0:byte, 1:halfword, 2:word, 3:doubleword
reg                  cpu_read;
wire [XLEN-1:0]      cpu_rdata;
wire                 cpu_valid;
wire                 cpu_ack;
wire                 cpu_denied;
wire                 cpu_corrupt;

// ====================================
// TileLink A Channel
// ====================================
wire                 tl_a_valid;
wire                 tl_a_ready;
wire [2:0]           tl_a_opcode;
wire [2:0]           tl_a_param;
wire [2:0]           tl_a_size;
wire [SID_WIDTH-1:0] tl_a_source;
wire [XLEN-1:0]      tl_a_address;
wire [XLEN/8-1:0]    tl_a_mask;
wire [XLEN-1:0]      tl_a_data;

// ====================================
// TileLink D Channel
// ====================================
wire                 tl_d_valid;
wire                 tl_d_ready;
wire [2:0]           tl_d_opcode;
wire [1:0]           tl_d_param;
wire [2:0]           tl_d_size;
wire [SID_WIDTH-1:0] tl_d_source;
wire [XLEN-1:0]      tl_d_data;
wire                 tl_d_corrupt;
wire                 tl_d_denied;

// ====================================
// Mock Memory Debug Signals
// ====================================
reg [XLEN-1:0] dbg_corrupt_read_address;
reg [XLEN-1:0] dbg_denied_read_address;
reg [XLEN-1:0] dbg_corrupt_write_address;
reg [XLEN-1:0] dbg_denied_write_address;

// ====================================
// Instantiate the Memory Interface (DUT)
// ====================================
tl_interface #(
    .XLEN(XLEN),
    .SID_WIDTH(SID_WIDTH),
    .MAX_RETRIES(MAX_RETRIES)
) dut (
    .clk(clk),
    .reset(reset),

    // CPU Interface
    .cpu_ready(cpu_ready),
    .cpu_address(cpu_address),
    .cpu_wdata(cpu_wdata),
    .cpu_wstrb(cpu_wstrb),
    .cpu_size(cpu_size),
    .cpu_read(cpu_read),
    .cpu_rdata(cpu_rdata),
    .cpu_valid(cpu_valid),
    .cpu_ack(cpu_ack),
    .cpu_denied(cpu_denied),
    .cpu_corrupt(cpu_corrupt),

    // TileLink A Channel
    .tl_a_valid(tl_a_valid),
    .tl_a_ready(tl_a_ready),
    .tl_a_opcode(tl_a_opcode),
    .tl_a_param(tl_a_param),
    .tl_a_size(tl_a_size),
    .tl_a_source(tl_a_source),
    .tl_a_address(tl_a_address),
    .tl_a_mask(tl_a_mask),
    .tl_a_data(tl_a_data),

    // TileLink D Channel
    .tl_d_valid(tl_d_valid),
    .tl_d_ready(tl_d_ready),
    .tl_d_opcode(tl_d_opcode),
    .tl_d_param(tl_d_param),
    .tl_d_size(tl_d_size),
    .tl_d_source(tl_d_source),
    .tl_d_data(tl_d_data),
    .tl_d_corrupt(tl_d_corrupt),
    .tl_d_denied(tl_d_denied)
);

// ====================================
// Instantiate Mock Memory
// ====================================
tl_memory #(
    .XLEN(XLEN),
    .SID_WIDTH(SID_WIDTH),
    .SIZE(MEM_SIZE)
) mock_mem (
    .clk        (clk),
    .reset      (reset),

    // TileLink A Channel
    .tl_a_valid (tl_a_valid),
    .tl_a_ready (tl_a_ready),
    .tl_a_opcode(tl_a_opcode),
    .tl_a_param (tl_a_param),
    .tl_a_size  (tl_a_size),
    .tl_a_source(tl_a_source),
    .tl_a_address(tl_a_address),
    .tl_a_mask  (tl_a_mask),
    .tl_a_data  (tl_a_data),

    // TileLink D Channel
    .tl_d_valid (tl_d_valid),
    .tl_d_ready (tl_d_ready),
    .tl_d_opcode(tl_d_opcode),
    .tl_d_param (tl_d_param),
    .tl_d_size  (tl_d_size),
    .tl_d_source(tl_d_source),
    .tl_d_data  (tl_d_data),
    .tl_d_corrupt(tl_d_corrupt),
    .tl_d_denied (tl_d_denied),

    // Debug inputs (for error simulation)
    .dbg_corrupt_read_address(dbg_corrupt_read_address),
    .dbg_denied_read_address(dbg_denied_read_address),
    .dbg_corrupt_write_address(dbg_corrupt_write_address),
    .dbg_denied_write_address(dbg_denied_write_address)
);

// ====================================
// Testbench Tasks
// ====================================
task WriteData(
    input [XLEN-1:0]   address,
    input [2:0]        size,
    input [XLEN/8-1:0] mask,
    input [XLEN-1:0]   value,
    input              expected_denied,
    input              expected_corrupt
);
begin
    @(posedge clk);
    // Drive CPU interface signals for write
    cpu_ready    = 1'b1;    // CPU Request is ready
    cpu_read     = 1'b0;    // Write operation
    cpu_address  = address;
    cpu_wstrb    = mask;
    cpu_size     = size;
    cpu_wdata    = value;

    @(posedge clk);
    wait (cpu_ack == 1'b1);
    cpu_ready    = 1'b0;    // CPU Request is acknowledged

    // Wait for CPU to acknowledge the write
    @(posedge clk);
    wait (cpu_valid == 1'b1);

    `EXPECT("Verify write cpu_denied", cpu_denied, expected_denied);
    `EXPECT("Verify write cpu_corrupt", cpu_corrupt, expected_corrupt);

    @(posedge clk);

    if (cpu_valid != 1'b0 && cpu_rdata != 1'b0 &&
        cpu_denied != 1'b0 && cpu_corrupt != 1'b0) begin
        $display("CPU interface not idle!");
        $stop;
    end

    cpu_ready = 1'b0; // Deassert ready
    wait (cpu_valid == 1'b0);

    // Cleanup
    @(posedge clk);
end
endtask

task ReadData(
    input [XLEN-1:0]   address,
    input [2:0]        size,
    input [XLEN-1:0]   expected_value,
    input              expected_denied,
    input              expected_corrupt
);
begin
    @(posedge clk);
    // Drive CPU interface signals for write
    cpu_ready    = 1'b1;            // CPU Request is ready
    cpu_read     = 1'b1;            // Read operation
    cpu_address  = address;
    cpu_wstrb    = {XLEN/8{1'b1}};  // Should be ignored
    cpu_size     = size;
    cpu_wdata    = 'hDEADBEEF;      // Should be ignored

    @(posedge clk);
    wait (cpu_ack == 1'b1);
    cpu_ready    = 1'b0;    // CPU Request is acknowledged

    // Wait for CPU to acknowledge the write
    @(posedge clk);
    wait (cpu_valid == 1'b1);


    `EXPECT("Verify read value", cpu_rdata, expected_value);
    `EXPECT("Verify read cpu_denied", cpu_denied, expected_denied);
    `EXPECT("Verify read cpu_corrupt", cpu_corrupt, expected_corrupt);

    @(posedge clk);

    if (cpu_valid != 1'b0 && cpu_rdata != 1'b0 &&
        cpu_denied != 1'b0 && cpu_corrupt != 1'b0) begin
        $display("CPU interface not idle!");
        $stop;
    end

    cpu_ready = 1'b0; // Deassert ready
end
endtask

// ====================================
// Test Sequence
// ====================================
initial begin
    $dumpfile("tl_interface_tb.vcd");
    $dumpvars(0, tl_interface_tb);

    test = 0;

    // Initialize CPU Interface Signals
    cpu_ready    = 1'b0;
    cpu_read     = 1'b0;
    cpu_address  = {XLEN{1'b0}};
    cpu_wdata    = {XLEN{1'b0}};
    cpu_wstrb    = {(XLEN/8){1'b0}};

    // Initialize Mock Memory Debug Signals
    dbg_corrupt_read_address   = {XLEN{1'b1}};
    dbg_denied_read_address    = {XLEN{1'b1}};
    dbg_corrupt_write_address  = {XLEN{1'b1}};
    dbg_denied_write_address   = {XLEN{1'b1}};

    // ====================================
    // Apply Reset
    // ====================================
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);
    reset = 0;
    @(posedge clk);

    // ====================================
    // Test: Write Bytes to address 0x00...0x0F
    // ====================================
    `TEST("tl_interface", "Write Byte all alignments");
    WriteData(32'h00, 3'b000, 4'b0001, 8'h11, 0, 0);
    WriteData(32'h01, 3'b000, 4'b0001, 8'h22, 0, 0);
    WriteData(32'h02, 3'b000, 4'b0010, 16'h33, 0, 0);
    WriteData(32'h03, 3'b000, 4'b0010, 16'h44, 0, 0);
    WriteData(32'h04, 3'b000, 4'b0100, 24'h55, 0, 0);
    WriteData(32'h05, 3'b000, 4'b0100, 24'h66, 0, 0);
    WriteData(32'h06, 3'b000, 4'b1000, 32'h77, 0, 0);
    WriteData(32'h07, 3'b000, 4'b1000, 32'h88, 0, 0);
    `EXPECT("Byte at 0x01 is valid", mock_mem.memory['h00], 'h11);
    `EXPECT("Byte at 0x02 is valid", mock_mem.memory['h01], 'h22);
    `EXPECT("Byte at 0x03 is valid", mock_mem.memory['h02], 'h33);
    `EXPECT("Byte at 0x04 is valid", mock_mem.memory['h03], 'h44);
    `EXPECT("Byte at 0x05 is valid", mock_mem.memory['h04], 'h55);
    `EXPECT("Byte at 0x06 is valid", mock_mem.memory['h05], 'h66);
    `EXPECT("Byte at 0x07 is valid", mock_mem.memory['h06], 'h77);
    `EXPECT("Byte at 0x07 is valid", mock_mem.memory['h07], 'h88);
    if (XLEN >=64) begin
    WriteData(32'h08, 3'b000, 8'b00010000, 40'h99, 0, 0);
    WriteData(32'h09, 3'b000, 8'b00010000, 40'hAA, 0, 0);
    WriteData(32'h0A, 3'b000, 8'b00100000, 48'hBB, 0, 0);
    WriteData(32'h0B, 3'b000, 8'b00100000, 48'hCC, 0, 0);
    WriteData(32'h0C, 3'b000, 8'b01000000, 56'hDD, 0, 0);
    WriteData(32'h0D, 3'b000, 8'b01000000, 56'hEE, 0, 0);
    WriteData(32'h0E, 3'b000, 8'b10000000, 64'hFF, 0, 0);
    WriteData(32'h0F, 3'b000, 8'b10000000, 64'hED, 0, 0);
    `EXPECT("Byte at 0x08 is valid", mock_mem.memory['h08], 'h99);
    `EXPECT("Byte at 0x09 is valid", mock_mem.memory['h09], 'hAA);
    `EXPECT("Byte at 0x0A is valid", mock_mem.memory['h0A], 'hBB);
    `EXPECT("Byte at 0x0B is valid", mock_mem.memory['h0B], 'hCC);
    `EXPECT("Byte at 0x0C is valid", mock_mem.memory['h0C], 'hDD);
    `EXPECT("Byte at 0x0D is valid", mock_mem.memory['h0D], 'hEE);
    `EXPECT("Byte at 0x0E is valid", mock_mem.memory['h0E], 'hFF);
    `EXPECT("Byte at 0x0F is valid", mock_mem.memory['h0F], 'hED);
    end

    // ====================================
    // Test: Write Half-Words to address 0x01...0x1F
    // ====================================
    `TEST("tl_interface", "Write Half-Words all valid alignments");
    WriteData(32'h10, 3'b001, 4'b0011, 16'h1122, 0, 0);
    WriteData(32'h12, 3'b001, 4'b0011, 16'h3344, 0, 0);
    WriteData(32'h14, 3'b001, 4'b1100, 32'h5566, 0, 0);
    WriteData(32'h16, 3'b001, 4'b1100, 32'h7788, 0, 0);
    `EXPECT("Byte at 0x11 is valid", mock_mem.memory['h10], 'h22);
    `EXPECT("Byte at 0x12 is valid", mock_mem.memory['h11], 'h11);
    `EXPECT("Byte at 0x13 is valid", mock_mem.memory['h12], 'h44);
    `EXPECT("Byte at 0x14 is valid", mock_mem.memory['h13], 'h33);
    `EXPECT("Byte at 0x15 is valid", mock_mem.memory['h14], 'h66);
    `EXPECT("Byte at 0x16 is valid", mock_mem.memory['h15], 'h55);
    `EXPECT("Byte at 0x17 is valid", mock_mem.memory['h16], 'h88);
    `EXPECT("Byte at 0x17 is valid", mock_mem.memory['h17], 'h77);
    if (XLEN >=64) begin
    WriteData(32'h18, 3'b001, 8'b00110000, 48'h99AA, 0, 0);
    WriteData(32'h1A, 3'b001, 8'b00110000, 48'hBBCC, 0, 0);
    WriteData(32'h1C, 3'b001, 8'b11000000, 64'hDDEE, 0, 0);
    WriteData(32'h1E, 3'b001, 8'b11000000, 64'hFFED, 0, 0);
    `EXPECT("Byte at 0x18 is valid", mock_mem.memory['h18], 'hAA);
    `EXPECT("Byte at 0x19 is valid", mock_mem.memory['h19], 'h99);
    `EXPECT("Byte at 0x1A is valid", mock_mem.memory['h1A], 'hCC);
    `EXPECT("Byte at 0x1B is valid", mock_mem.memory['h1B], 'hBB);
    `EXPECT("Byte at 0x1C is valid", mock_mem.memory['h1C], 'hEE);
    `EXPECT("Byte at 0x1D is valid", mock_mem.memory['h1D], 'hDD);
    `EXPECT("Byte at 0x1E is valid", mock_mem.memory['h1E], 'hED);
    `EXPECT("Byte at 0x1F is valid", mock_mem.memory['h1F], 'hFF);
    end

    `TEST("tl_interface", "Write Half-Words invalid alignments");
    WriteData(32'h16, 3'b001, 4'b1110, 32'h7788, 1, 0);
    WriteData(32'h16, 3'b001, 4'b0111, 32'h7788, 1, 0);
    WriteData(32'h16, 3'b001, 4'b0110, 32'h7788, 1, 0);
    WriteData(32'h16, 3'b001, 4'b0001, 32'h7788, 1, 0);
    WriteData(32'h16, 3'b001, 4'b0010, 32'h7788, 1, 0);
    WriteData(32'h16, 3'b001, 4'b0100, 32'h7788, 1, 0);
    WriteData(32'h16, 3'b001, 4'b1000, 32'h7788, 1, 0);
    WriteData(32'h16, 3'b001, 4'b1010, 32'h7788, 1, 0);
    if (XLEN >=64) begin
    WriteData(32'h18, 3'b001, 8'b00011000, 48'h99AA, 1, 0);
    WriteData(32'h18, 3'b001, 8'b01100000, 48'h99AA, 1, 0);
    WriteData(32'h18, 3'b001, 8'b00111000, 48'h99AA, 1, 0);
    WriteData(32'h18, 3'b001, 8'b10001000, 48'h99AA, 1, 0);
    end

    // ====================================
    // Test: Write Words to address 0x01...0x1F
    // ====================================
    `TEST("tl_interface", "Write Words all alignments");
    WriteData(32'h20, 3'b010, 4'b1111, 32'h11223344, 0, 0);
    WriteData(32'h24, 3'b010, 4'b1111, 32'h55667788, 0, 0);
    `EXPECT("Byte at 0x21 is valid", mock_mem.memory['h20], 'h44);
    `EXPECT("Byte at 0x22 is valid", mock_mem.memory['h21], 'h33);
    `EXPECT("Byte at 0x23 is valid", mock_mem.memory['h22], 'h22);
    `EXPECT("Byte at 0x24 is valid", mock_mem.memory['h23], 'h11);
    `EXPECT("Byte at 0x25 is valid", mock_mem.memory['h24], 'h88);
    `EXPECT("Byte at 0x26 is valid", mock_mem.memory['h25], 'h77);
    `EXPECT("Byte at 0x27 is valid", mock_mem.memory['h26], 'h66);
    `EXPECT("Byte at 0x27 is valid", mock_mem.memory['h27], 'h55);
    if (XLEN >=64) begin
    WriteData(32'h28, 3'b010, 8'b11110000, 64'h99AABBCC, 0, 0);
    WriteData(32'h2C, 3'b010, 8'b11110000, 64'hDDEEFFED, 0, 0);
    `EXPECT("Byte at 0x28 is valid", mock_mem.memory['h28], 'hCC);
    `EXPECT("Byte at 0x29 is valid", mock_mem.memory['h29], 'hBB);
    `EXPECT("Byte at 0x2A is valid", mock_mem.memory['h2A], 'hAA);
    `EXPECT("Byte at 0x2B is valid", mock_mem.memory['h2B], 'h99);
    `EXPECT("Byte at 0x2C is valid", mock_mem.memory['h2C], 'hED);
    `EXPECT("Byte at 0x2D is valid", mock_mem.memory['h2D], 'hFF);
    `EXPECT("Byte at 0x2E is valid", mock_mem.memory['h2E], 'hEE);
    `EXPECT("Byte at 0x2F is valid", mock_mem.memory['h2F], 'hDD);
    end

    // ====================================
    // Test: Write Double-Words to address 0x01...0x1F
    // ====================================
    if (XLEN >=64) begin
    `TEST("tl_interface", "Write Double-Words all alignments");
    WriteData(32'h30, 3'b011, 8'b11111111, 64'h1122334455667788, 0, 0);
    WriteData(32'h38, 3'b011, 8'b11111111, 64'h99AABBCCDDEEFFED, 0, 0);
    `EXPECT("Byte at 0x31 is valid", mock_mem.memory['h30], 'h88);
    `EXPECT("Byte at 0x32 is valid", mock_mem.memory['h31], 'h77);
    `EXPECT("Byte at 0x33 is valid", mock_mem.memory['h32], 'h66);
    `EXPECT("Byte at 0x34 is valid", mock_mem.memory['h33], 'h55);
    `EXPECT("Byte at 0x35 is valid", mock_mem.memory['h34], 'h44);
    `EXPECT("Byte at 0x36 is valid", mock_mem.memory['h35], 'h33);
    `EXPECT("Byte at 0x37 is valid", mock_mem.memory['h36], 'h22);
    `EXPECT("Byte at 0x37 is valid", mock_mem.memory['h37], 'h11);
    `EXPECT("Byte at 0x38 is valid", mock_mem.memory['h38], 'hED);
    `EXPECT("Byte at 0x39 is valid", mock_mem.memory['h39], 'hFF);
    `EXPECT("Byte at 0x3A is valid", mock_mem.memory['h3A], 'hEE);
    `EXPECT("Byte at 0x3B is valid", mock_mem.memory['h3B], 'hDD);
    `EXPECT("Byte at 0x3C is valid", mock_mem.memory['h3C], 'hCC);
    `EXPECT("Byte at 0x3D is valid", mock_mem.memory['h3D], 'hBB);
    `EXPECT("Byte at 0x3E is valid", mock_mem.memory['h3E], 'hAA);
    `EXPECT("Byte at 0x3F is valid", mock_mem.memory['h3F], 'h99);
    end

    // ====================================
    // Test: Read Bytes to address 0x00...0x0F
    // ====================================
    `TEST("tl_interface", "Read Byte all alignments");
    ReadData(32'h00, 3'b000, 'h11, 0, 0);
    ReadData(32'h01, 3'b000, 'h22, 0, 0);
    ReadData(32'h02, 3'b000, 'h33, 0, 0);
    ReadData(32'h03, 3'b000, 'h44, 0, 0);
    ReadData(32'h04, 3'b000, 'h55, 0, 0);
    ReadData(32'h05, 3'b000, 'h66, 0, 0);
    ReadData(32'h06, 3'b000, 'h77, 0, 0);
    ReadData(32'h07, 3'b000, 'h88, 0, 0);
    if (XLEN >=64) begin
    ReadData(32'h08, 3'b000, 'h99, 0, 0);
    ReadData(32'h09, 3'b000, 'hAA, 0, 0);
    ReadData(32'h0A, 3'b000, 'hBB, 0, 0);
    ReadData(32'h0B, 3'b000, 'hCC, 0, 0);
    ReadData(32'h0C, 3'b000, 'hDD, 0, 0);
    ReadData(32'h0D, 3'b000, 'hEE, 0, 0);
    ReadData(32'h0E, 3'b000, 'hFF, 0, 0);
    ReadData(32'h0F, 3'b000, 'hED, 0, 0);
    end

    // ====================================
    // Test: Read Half-Word to address 0x10...0x1F
    // ====================================
    `TEST("tl_interface", "Read Half-Word all alignments");
    ReadData(32'h10, 3'b001, 'h1122, 0, 0);
    ReadData(32'h12, 3'b001, 'h3344, 0, 0);
    ReadData(32'h14, 3'b001, 'h5566, 0, 0);
    ReadData(32'h16, 3'b001, 'h7788, 0, 0);
    if (XLEN >=64) begin
    ReadData(32'h18, 3'b001, 'h99AA, 0, 0);
    ReadData(32'h1A, 3'b001, 'hBBCC, 0, 0);
    ReadData(32'h1C, 3'b001, 'hDDEE, 0, 0);
    ReadData(32'h1E, 3'b001, 'hFFED, 0, 0);
    end

    // ====================================
    // Test: Read Word to address 0x10...0x1F
    // ====================================
    `TEST("tl_interface", "Read Word all alignments");
    ReadData(32'h20, 3'b010, 'h11223344, 0, 0);
    ReadData(32'h24, 3'b010, 'h55667788, 0, 0);
    if (XLEN >=64) begin
    ReadData(32'h28, 3'b010, 'h99AABBCC, 0, 0);
    ReadData(32'h2C, 3'b010, 'hDDEEFFED, 0, 0);
    end

    // ====================================
    // Test: Read Double-Word to address 0x10...0x1F
    // ====================================
    if (XLEN >=64) begin
    `TEST("tl_interface", "Read Word all alignments");
    ReadData(32'h30, 3'b011, 'h1122334455667788, 0, 0);
    ReadData(32'h38, 3'b011, 'h99AABBCCDDEEFFED, 0, 0);
    end

    // ====================================
    // Test: Denied and Corrupt Reads
    // ====================================
    `TEST("tl_interface", "Denied Reads using dbg_denied_read_address");
    dbg_denied_read_address = 32'h10; // Mark address 0x10 as denied
    ReadData(32'h10, 3'b001, 'h0000, 1, 0); // Expect denied
    dbg_denied_read_address = {XLEN{1'b1}}; // Clear denied condition

    `TEST("tl_interface", "Corrupt Reads using dbg_corrupt_read_address");
    dbg_corrupt_read_address = 32'h12; // Mark address 0x12 as corrupt
    ReadData(32'h12, 3'b001, 'h0000, 0, 1); // Expect corrupt
    dbg_corrupt_read_address = {XLEN{1'b1}}; // Clear corrupt condition

    // ====================================
    // Test: Denied and Corrupt Writes
    // ====================================
    `TEST("tl_interface", "Denied Writes using dbg_denied_write_address");
    dbg_denied_write_address = 32'h20; // Mark address 0x20 as denied
    WriteData(32'h20, 3'b010, 4'b1111, 32'hDEADBEEF, 1, 0); // Expect denied
    dbg_denied_write_address = {XLEN{1'b1}}; // Clear denied condition

    `TEST("tl_interface", "Corrupt Writes using dbg_corrupt_write_address");
    dbg_corrupt_write_address = 32'h24; // Mark address 0x24 as corrupt
    WriteData(32'h24, 3'b010, 4'b1111, 32'hBADF00D, 0, 1); // Expect corrupt
    dbg_corrupt_write_address = {XLEN{1'b1}}; // Clear corrupt condition

    // ====================================
    // Finish Testbench
    // ====================================
    $display("\nTest memory dump:");
    `DISPLAY_MEM_RANGE_ARRAY(mock_mem, 'h00, 'h3f);
    `FINISH;
end

endmodule
