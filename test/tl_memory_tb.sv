`timescale 1ns / 1ps
`default_nettype none

`define DEBUG // Turn on debugging ports
// `define LOG_MEMORY

`include "tl_memory.sv"

`ifndef XLEN
`define XLEN 32
`endif

module tl_memory_tb;
`include "test/test_macros.sv"

// ====================================
// Parameters
// ====================================
parameter XLEN = `XLEN;
parameter SID_WIDTH = 2;     // Source ID length for TileLink
parameter MEM_SIZE = 4096;   // Memory size (supports addresses up to 0x0FFF)
parameter MEM_WIDTH = 8;

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
// TileLink A Channel
// ====================================
reg                 tl_a_valid;
wire                tl_a_ready;
reg [2:0]           tl_a_opcode;
reg [2:0]           tl_a_param;
reg [2:0]           tl_a_size;
reg [SID_WIDTH-1:0] tl_a_source;
reg [XLEN-1:0]      tl_a_address;
reg [XLEN/8-1:0]    tl_a_mask;
reg [XLEN-1:0]      tl_a_data;

// ====================================
// TileLink D Channel
// ====================================
wire                tl_d_valid;
reg                 tl_d_ready;
wire [2:0]          tl_d_opcode;
wire [1:0]          tl_d_param;
wire [2:0]          tl_d_size;
wire [SID_WIDTH-1:0] tl_d_source;
wire [XLEN-1:0]     tl_d_data;
wire                tl_d_corrupt;
wire                tl_d_denied;

// ====================================
// Mock Memory Debug Signals
// ====================================
reg [XLEN-1:0] dbg_corrupt_read_address;
reg [XLEN-1:0] dbg_denied_read_address;
reg [XLEN-1:0] dbg_corrupt_write_address;
reg [XLEN-1:0] dbg_denied_write_address;

// ====================================
// Instantiate Mock Memory
// ====================================
tl_memory #(
    .XLEN(XLEN),
    .WIDTH(MEM_WIDTH),
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

// Task to perform a write operation directly via TileLink A and D channels
task WriteData(
    input [XLEN-1:0]   address,
    input [2:0]        size,
    input [XLEN/8-1:0] mask,
    input [XLEN-1:0]   value,
    input              expected_denied,
    input              expected_corrupt
);
    reg [SID_WIDTH-1:0] source_id;
    reg [2:0]           opcode;
    reg [2:0]           param;
    integer             wait_cycles;

    begin
        // Initialize request signals
        source_id = 2'b01; // Example Source ID
        opcode = 3'b000;   // PUT_FULL_DATA_OPCODE
        param = 3'b000;    // No additional parameters

        @(posedge clk);
        // Drive TileLink A channel signals
        tl_a_valid = 1'b1;
        tl_a_opcode = opcode;
        tl_a_param  = param;
        tl_a_size   = size;
        tl_a_source = source_id;
        tl_a_address= address;
        tl_a_mask   = mask;
        tl_a_data   = value;

        `ifdef LOG_MEMORY `LOG("test", ("WriteData: Sending WRITE request - Addr: 0x%h, Size: %0d, Mask: 0x%h, Data: 0x%h", address, size, mask, value)); `endif

        // Wait for tl_a_ready
        wait_cycles = 0;
        while (!tl_a_ready && wait_cycles < 100) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (!tl_a_ready) begin
            $display("\033[91mERROR: WriteData timeout waiting for tl_a_ready\033[0m");
            $stop;
        end
        `ifdef LOG_MEMORY `LOG("test", ("Channel A is ready")); `endif

        // Handshake complete, deassert tl_a_valid
        @(posedge clk);
        tl_a_valid = 1'b0;

        // Wait for D channel response
        wait_cycles = 0;
        while (!tl_d_valid && wait_cycles < 100) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end
        `ifdef LOG_MEMORY `LOG("test", ("Channel D is Valid")); `endif

        if (!tl_d_valid) begin
            $display("\033[91mERROR: WriteData timeout waiting for tl_d_valid\033[0m");
            $stop;
        end

        // Verify the response
        if (expected_denied) begin
            `EXPECT("WriteData: tl_d_denied", tl_d_denied, 1'b1);
        end else begin
            `EXPECT("WriteData: tl_d_denied", tl_d_denied, 1'b0);
        end

        if (expected_corrupt) begin
            `EXPECT("WriteData: tl_d_corrupt", tl_d_corrupt, 1'b1);
        end else begin
            `EXPECT("WriteData: tl_d_corrupt", tl_d_corrupt, 1'b0);
        end

        // Verify tl_d_opcode
        if (expected_denied) begin
            `EXPECT("WriteData: tl_d_opcode", tl_d_opcode, 3'b111); // TL_ACCESS_ACK_ERROR
        end else if (expected_corrupt) begin
            `EXPECT("WriteData: tl_d_opcode", tl_d_opcode, 3'b101); // TL_ACCESS_ACK_DATA_CORRUPT
        end else begin
            `EXPECT("WriteData: tl_d_opcode", tl_d_opcode, 3'b000); // TL_ACCESS_ACK
        end

        // Assert tl_d_ready to acknowledge reception
        tl_d_ready = 1'b1;

        @(posedge clk);
        tl_d_ready = 1'b0;

        // Deassert tl_d_ready after response is captured
        @(posedge clk);
    end
endtask

// Task to perform a read operation directly via TileLink A and D channels
task ReadData(
    input [XLEN-1:0]   address,
    input [2:0]        size,
    input [XLEN-1:0]   expected_value,
    input              expected_denied,
    input              expected_corrupt
);
    reg [SID_WIDTH-1:0] source_id;
    reg [2:0]           opcode;
    reg [2:0]           param;
    integer             wait_cycles;

    begin
        // Initialize request signals
        source_id = 2'b10; // Example Source ID
        opcode = 3'b100;   // GET_OPCODE
        param = 3'b000;    // No additional parameters

        @(posedge clk);
        // Drive TileLink A channel signals
        tl_a_valid = 1'b1;
        tl_a_opcode = opcode;
        tl_a_param  = param;
        tl_a_size   = size;
        tl_a_source = source_id;
        tl_a_address= address;
        tl_a_mask   = {(XLEN/8){1'b0}}; // No mask for read
        tl_a_data   = {XLEN{1'b0}};     // No data for read

        `ifdef LOG_MEMORY `LOG("test", ("ReadData: Sending READ request - Addr: 0x%h, Size: %0d", address, size)); `endif

        // Wait for tl_a_ready
        wait_cycles = 0;
        while (!tl_a_ready && wait_cycles < 100) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (!tl_a_ready) begin
            $display("\033[91mERROR: ReadData timeout waiting for tl_a_ready\033[0m");
            $stop;
        end

        // Handshake complete, deassert tl_a_valid
        @(posedge clk);
        tl_a_valid = 1'b0;

        // Wait for D channel response
        wait_cycles = 0;
        while (!tl_d_valid && wait_cycles < 100) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (!tl_d_valid) begin
            $display("\033[91mERROR: ReadData timeout waiting for tl_d_valid\033[0m");
            $stop;
        end

        // Verify the response
        if (expected_denied) begin
            `EXPECT("ReadData: tl_d_denied", tl_d_denied, 1'b1);
        end else begin
            `EXPECT("ReadData: tl_d_denied", tl_d_denied, 1'b0);
        end

        if (expected_corrupt) begin
            `EXPECT("ReadData: tl_d_corrupt", tl_d_corrupt, 1'b1);
        end else begin
            `EXPECT("ReadData: tl_d_corrupt", tl_d_corrupt, 1'b0);
        end

        // Verify tl_d_opcode and data
        if (expected_denied) begin
            `EXPECT("ReadData: tl_d_opcode", tl_d_opcode, 3'b111); // TL_ACCESS_ACK_ERROR
            `EXPECT("ReadData: tl_d_data", tl_d_data, {XLEN{1'b0}});
        end else if (expected_corrupt) begin
            `EXPECT("ReadData: tl_d_opcode", tl_d_opcode, 3'b101); // TL_ACCESS_ACK_DATA_CORRUPT
            // Optionally, verify corrupted data if known
        end else begin
            `EXPECT("ReadData: tl_d_opcode", tl_d_opcode, 3'b010); // TL_ACCESS_ACK_DATA
            `EXPECT("ReadData: tl_d_data", tl_d_data, expected_value);
        end

        // Assert tl_d_ready to acknowledge reception
        tl_d_ready = 1'b1;

        @(posedge clk);
        tl_d_ready = 1'b0;

        // Deassert tl_d_ready after response is captured
        @(posedge clk);
    end
endtask

// ====================================
// Test Sequence
// ====================================
initial begin
    $dumpfile("tl_memory_tb.vcd");
    $dumpvars(0, tl_memory_tb);

    test = 0;

    // Initialize TileLink A and D channel signals
    tl_a_valid = 1'b0;
    tl_a_opcode = 3'b000;
    tl_a_param  = 3'b000;
    tl_a_size   = 3'b000;
    tl_a_source = {SID_WIDTH{1'b0}};
    tl_a_address= {XLEN{1'b0}};
    tl_a_mask   = {(XLEN/8){1'b0}};
    tl_a_data   = {XLEN{1'b0}};

    tl_d_ready = 1'b0;

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
    // Output starting ram
    // ====================================
    `DISPLAY_MEM_RANGE_ARRAY(mock_mem.block_ram_inst, MEM_WIDTH, 'h00, 'h3f);

    // ====================================
    // Test: Write Bytes to address 0x00...0x0F
    // ====================================
    `TEST("memory", "Write Byte all alignments");
    WriteData(32'h00, 3'b000, 4'b0001, 32'h00000011, 0, 0);
    WriteData(32'h01, 3'b000, 4'b0001, 32'h00000022, 0, 0);
    WriteData(32'h02, 3'b000, 4'b0010, 32'h00000033, 0, 0);
    WriteData(32'h03, 3'b000, 4'b0010, 32'h00000044, 0, 0);
    WriteData(32'h04, 3'b000, 4'b0100, 32'h00000055, 0, 0);
    WriteData(32'h05, 3'b000, 4'b0100, 32'h00000066, 0, 0);
    WriteData(32'h06, 3'b000, 4'b1000, 32'h00000077, 0, 0);
    WriteData(32'h07, 3'b000, 4'b1000, 32'h00000088, 0, 0);
    `EXPECT("Byte at 0x00 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h00), 'h11);
    `EXPECT("Byte at 0x01 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h01), 'h22);
    `EXPECT("Byte at 0x02 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h02), 'h33);
    `EXPECT("Byte at 0x03 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h03), 'h44);
    `EXPECT("Byte at 0x04 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h04), 'h55);
    `EXPECT("Byte at 0x05 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h05), 'h66);
    `EXPECT("Byte at 0x06 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h06), 'h77);
    `EXPECT("Byte at 0x07 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h07), 'h88);
    if (XLEN >=64) begin
        `TEST("memory", "Write Byte Extended Alignments");
        WriteData(32'h08, 3'b000, 8'b00010000, 64'h00000099, 0, 0);
        WriteData(32'h09, 3'b000, 8'b00010000, 64'h000000AA, 0, 0);
        WriteData(32'h0A, 3'b000, 8'b00100000, 64'h000000BB, 0, 0);
        WriteData(32'h0B, 3'b000, 8'b00100000, 64'h000000CC, 0, 0);
        WriteData(32'h0C, 3'b000, 8'b01000000, 64'h000000DD, 0, 0);
        WriteData(32'h0D, 3'b000, 8'b01000000, 64'h000000EE, 0, 0);
        WriteData(32'h0E, 3'b000, 8'b10000000, 64'h000000FF, 0, 0);
        WriteData(32'h0F, 3'b000, 8'b10000000, 64'h000000ED, 0, 0);
        `EXPECT("Byte at 0x08 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h08), 'h99);
        `EXPECT("Byte at 0x09 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h09), 'hAA);
        `EXPECT("Byte at 0x0A is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0A), 'hBB);
        `EXPECT("Byte at 0x0B is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0B), 'hCC);
        `EXPECT("Byte at 0x0C is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0C), 'hDD);
        `EXPECT("Byte at 0x0D is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0D), 'hEE);
        `EXPECT("Byte at 0x0E is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0E), 'hFF);
        `EXPECT("Byte at 0x0F is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0F), 'hED);
    end

    // ====================================
    // Test: Write Half-Words to address 0x10...0x1F
    // ====================================
    `TEST("memory", "Write Half-Words all valid alignments");
    WriteData(32'h10, 3'b001, 4'b0011, 32'h00001122, 0, 0);
    WriteData(32'h12, 3'b001, 4'b0011, 32'h00003344, 0, 0);
    WriteData(32'h14, 3'b001, 4'b1100, 32'h00005566, 0, 0);
    WriteData(32'h16, 3'b001, 4'b1100, 32'h00007788, 0, 0);
    `EXPECT("Byte at 0x10 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h10), 'h22);
    `EXPECT("Byte at 0x11 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h11), 'h11);
    `EXPECT("Byte at 0x12 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h12), 'h44);
    `EXPECT("Byte at 0x13 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h13), 'h33);
    `EXPECT("Byte at 0x14 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h14), 'h66);
    `EXPECT("Byte at 0x15 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h15), 'h55);
    `EXPECT("Byte at 0x16 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h16), 'h88);
    `EXPECT("Byte at 0x17 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h17), 'h77);
    if (XLEN >=64) begin
        `TEST("memory", "Write Half-Words Extended Alignments");
        WriteData(32'h18, 3'b001, 8'b00110000, 64'h000099AA, 0, 0);
        WriteData(32'h1A, 3'b001, 8'b00110000, 64'h0000BBCC, 0, 0);
        WriteData(32'h1C, 3'b001, 8'b11000000, 64'h0000DDEE, 0, 0);
        WriteData(32'h1E, 3'b001, 8'b11000000, 64'h0000FFED, 0, 0);
        `EXPECT("Byte at 0x18 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h18), 'hAA);
        `EXPECT("Byte at 0x19 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h19), 'h99);
        `EXPECT("Byte at 0x1A is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h1A), 'hCC);
        `EXPECT("Byte at 0x1B is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h1B), 'hBB);
        `EXPECT("Byte at 0x1C is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h1C), 'hEE);
        `EXPECT("Byte at 0x1D is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h1D), 'hDD);
        `EXPECT("Byte at 0x1E is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h1E), 'hED);
        `EXPECT("Byte at 0x1F is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h1F), 'hFF);
    end

    // ====================================
    // Test: Write Half-Words invalid alignments
    // ====================================
    `TEST("memory", "Write Half-Words invalid alignments");
    WriteData(32'h16, 3'b001, 4'b1110, 32'h00007788, 1, 0); // Misaligned mask
    WriteData(32'h16, 3'b001, 4'b0111, 32'h00007788, 1, 0); // Misaligned mask
    WriteData(32'h16, 3'b001, 4'b0110, 32'h00007788, 1, 0); // Misaligned mask
    WriteData(32'h16, 3'b001, 4'b0001, 32'h00007788, 1, 0); // Misaligned mask
    WriteData(32'h16, 3'b001, 4'b0010, 32'h00007788, 1, 0); // Misaligned mask
    WriteData(32'h16, 3'b001, 4'b0100, 32'h00007788, 1, 0); // Misaligned mask
    WriteData(32'h16, 3'b001, 4'b1000, 32'h00007788, 1, 0); // Misaligned mask
    WriteData(32'h16, 3'b001, 4'b1010, 32'h00007788, 1, 0); // Misaligned mask
    if (XLEN >=64) begin
        `TEST("memory", "Write Half-Words Extended invalid alignments");
        WriteData(32'h18, 3'b001, 8'b00011000, 64'h000099AA, 1, 0); // Misaligned mask
        WriteData(32'h18, 3'b001, 8'b01100000, 64'h000099AA, 1, 0); // Misaligned mask
        WriteData(32'h18, 3'b001, 8'b00111000, 64'h000099AA, 1, 0); // Misaligned mask
        WriteData(32'h18, 3'b001, 8'b10001000, 64'h000099AA, 1, 0); // Misaligned mask
    end

    // ====================================
    // Test: Write Words to address 0x20...0x3F
    // ====================================
    `TEST("memory", "Write Words all alignments");
    WriteData(32'h20, 3'b010, 4'b1111, 32'h11223344, 0, 0);
    WriteData(32'h24, 3'b010, 4'b1111, 32'h55667788, 0, 0);
    `EXPECT("Byte at 0x20 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h20), 'h44);
    `EXPECT("Byte at 0x21 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h21), 'h33);
    `EXPECT("Byte at 0x22 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h22), 'h22);
    `EXPECT("Byte at 0x23 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h23), 'h11);
    `EXPECT("Byte at 0x24 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h24), 'h88);
    `EXPECT("Byte at 0x25 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h25), 'h77);
    `EXPECT("Byte at 0x26 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h26), 'h66);
    `EXPECT("Byte at 0x27 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h27), 'h55);
    if (XLEN >=64) begin
        `TEST("memory", "Write Words Extended Alignments");
        WriteData(32'h28, 3'b010, 8'b11110000, 64'h99AABBCC, 0, 0);
        WriteData(32'h2C, 3'b010, 8'b11110000, 64'hDDEEFFED, 0, 0);
        `EXPECT("Byte at 0x28 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h28), 'hCC);
        `EXPECT("Byte at 0x29 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h29), 'hBB);
        `EXPECT("Byte at 0x2A is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h2A), 'hAA);
        `EXPECT("Byte at 0x2B is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h2B), 'h99);
        `EXPECT("Byte at 0x2C is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h2C), 'hED);
        `EXPECT("Byte at 0x2D is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h2D), 'hFF);
        `EXPECT("Byte at 0x2E is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h2E), 'hEE);
        `EXPECT("Byte at 0x2F is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h2F), 'hDD);
    end

    // ====================================
    // Test: Write Double-Words to address 0x30...0x3F
    // ====================================
    if (XLEN >=64) begin
        `TEST("memory", "Write Double-Words all alignments");
        WriteData(32'h30, 3'b011, 8'b11111111, 64'h1122334455667788, 0, 0);
        WriteData(32'h38, 3'b011, 8'b11111111, 64'h99AABBCCDDEEFFED, 0, 0);
        `EXPECT("Byte at 0x30 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h30), 'h88);
        `EXPECT("Byte at 0x31 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h31), 'h77);
        `EXPECT("Byte at 0x32 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h32), 'h66);
        `EXPECT("Byte at 0x33 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h33), 'h55);
        `EXPECT("Byte at 0x34 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h34), 'h44);
        `EXPECT("Byte at 0x35 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h35), 'h33);
        `EXPECT("Byte at 0x36 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h36), 'h22);
        `EXPECT("Byte at 0x37 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h37), 'h11);
        `EXPECT("Byte at 0x38 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h38), 'hED);
        `EXPECT("Byte at 0x39 is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h39), 'hFF);
        `EXPECT("Byte at 0x3A is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h3A), 'hEE);
        `EXPECT("Byte at 0x3B is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h3B), 'hDD);
        `EXPECT("Byte at 0x3C is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h3C), 'hCC);
        `EXPECT("Byte at 0x3D is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h3D), 'hBB);
        `EXPECT("Byte at 0x3E is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h3E), 'hAA);
        `EXPECT("Byte at 0x3F is valid", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h3F), 'h99);
    end

    // ====================================
    // Test: Read Bytes to address 0x00...0x0F
    // ====================================
    `TEST("memory", "Read Byte all alignments");
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
    `TEST("memory", "Read Half-Word all alignments");
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
    // Test: Read Words to address 0x20...0x3F
    // ====================================
    `TEST("memory", "Read Word all alignments");
    ReadData(32'h20, 3'b010, 'h11223344, 0, 0);
    ReadData(32'h24, 3'b010, 'h55667788, 0, 0);
    if (XLEN >=64) begin
        ReadData(32'h28, 3'b010, 'h99AABBCC, 0, 0);
        ReadData(32'h2C, 3'b010, 'hDDEEFFED, 0, 0);
    end

    // ====================================
    // Test: Read Double-Word to address 0x30...0x3F
    // ====================================
    if (XLEN >=64) begin
        `TEST("memory", "Read Double-Word all alignments");
        ReadData(32'h30, 3'b011, 'h1122334455667788, 0, 0);
        ReadData(32'h38, 3'b011, 'h99AABBCCDDEEFFED, 0, 0);
    end

    // ====================================
    // Test: Denied and Corrupt Reads
    // ====================================
    `TEST("memory", "Denied Reads using dbg_denied_read_address");
    dbg_denied_read_address = 32'h10; // Mark address 0x10 as denied
    ReadData(32'h10, 3'b001, 'h0000, 1, 0); // Expect denied
    dbg_denied_read_address = {XLEN{1'b1}}; // Clear denied condition

    `TEST("memory", "Corrupt Reads using dbg_corrupt_read_address");
    dbg_corrupt_read_address = 32'h12; // Mark address 0x12 as corrupt
    ReadData(32'h12, 3'b001, 'h0000, 0, 1); // Expect corrupt
    dbg_corrupt_read_address = {XLEN{1'b1}}; // Clear corrupt condition

    // ====================================
    // Test: Denied and Corrupt Writes
    // ====================================
    `TEST("memory", "Denied Writes using dbg_denied_write_address");
    dbg_denied_write_address = 32'h20; // Mark address 0x20 as denied
    WriteData(32'h20, 3'b010, 8'b11110000, 32'hDEADBEEF, 1, 0); // Expect denied
    dbg_denied_write_address = {XLEN{1'b1}}; // Clear denied condition

    `TEST("memory", "Corrupt Writes using dbg_corrupt_write_address");
    dbg_corrupt_write_address = 32'h24; // Mark address 0x24 as corrupt
    WriteData(32'h24, 3'b010, 8'b11110000, 32'hBADF00D, 0, 1); // Expect corrupt
    dbg_corrupt_write_address = {XLEN{1'b1}}; // Clear corrupt condition

    // ====================================
    // Finish Testbench
    // ====================================
    `DISPLAY_MEM_RANGE_ARRAY(mock_mem.block_ram_inst, MEM_WIDTH, 'h00, 'h3f);
    `FINISH;
end

endmodule
