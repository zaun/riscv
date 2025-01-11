`timescale 1ns / 1ps
`default_nettype none

`define DEBUG // Turn on debugging ports
// `define LOG_MEMORY

`include "src/tl_ul_memory.sv"

`ifndef XLEN
`define XLEN 32
`endif

module tl_ul_memory_tb;
`include "test/test_macros.sv"

// ====================================
// Parameters
// ====================================
parameter XLEN = `XLEN;
parameter SID_WIDTH = 2;     // Source ID length for TileLink
parameter MEM_SIZE = 4096;   // Memory size (supports addresses up to 0x0FFF)

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
tl_ul_memory #(
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
    $dumpfile("tl_ul_memory_tb.vcd");
    $dumpvars(0, tl_ul_memory_tb);

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
    `EXPECT("Byte at 0x00 is valid", mock_mem.memory['h00], 'h11);
    `EXPECT("Byte at 0x01 is valid", mock_mem.memory['h01], 'h22);
    `EXPECT("Byte at 0x02 is valid", mock_mem.memory['h02], 'h33);
    `EXPECT("Byte at 0x03 is valid", mock_mem.memory['h03], 'h44);
    `EXPECT("Byte at 0x04 is valid", mock_mem.memory['h04], 'h55);
    `EXPECT("Byte at 0x05 is valid", mock_mem.memory['h05], 'h66);
    `EXPECT("Byte at 0x06 is valid", mock_mem.memory['h06], 'h77);
    `EXPECT("Byte at 0x07 is valid", mock_mem.memory['h07], 'h88);
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
    // Test: Write Half-Words to address 0x10...0x1F
    // ====================================
    `TEST("memory", "Write Half-Words all valid alignments");
    WriteData(32'h10, 3'b001, 4'b0011, 32'h00001122, 0, 0);
    WriteData(32'h12, 3'b001, 4'b0011, 32'h00003344, 0, 0);
    WriteData(32'h14, 3'b001, 4'b1100, 32'h00005566, 0, 0);
    WriteData(32'h16, 3'b001, 4'b1100, 32'h00007788, 0, 0);
    `EXPECT("Byte at 0x10 is valid", mock_mem.memory['h10], 'h11);
    `EXPECT("Byte at 0x11 is valid", mock_mem.memory['h11], 'h22);
    `EXPECT("Byte at 0x12 is valid", mock_mem.memory['h12], 'h33);
    `EXPECT("Byte at 0x13 is valid", mock_mem.memory['h13], 'h44);
    `EXPECT("Byte at 0x14 is valid", mock_mem.memory['h14], 'h55);
    `EXPECT("Byte at 0x15 is valid", mock_mem.memory['h15], 'h66);
    `EXPECT("Byte at 0x16 is valid", mock_mem.memory['h16], 'h77);
    `EXPECT("Byte at 0x17 is valid", mock_mem.memory['h17], 'h88);
    if (XLEN >=64) begin
        `TEST("memory", "Write Half-Words Extended Alignments");
        WriteData(32'h18, 3'b001, 8'b00110000, 64'h000099AA, 0, 0);
        WriteData(32'h1A, 3'b001, 8'b00110000, 64'h0000BBCC, 0, 0);
        WriteData(32'h1C, 3'b001, 8'b11000000, 64'h0000DDEE, 0, 0);
        WriteData(32'h1E, 3'b001, 8'b11000000, 64'h0000FFED, 0, 0);
        `EXPECT("Byte at 0x18 is valid", mock_mem.memory['h18], 'h99);
        `EXPECT("Byte at 0x19 is valid", mock_mem.memory['h19], 'hAA);
        `EXPECT("Byte at 0x1A is valid", mock_mem.memory['h1A], 'hBB);
        `EXPECT("Byte at 0x1B is valid", mock_mem.memory['h1B], 'hCC);
        `EXPECT("Byte at 0x1C is valid", mock_mem.memory['h1C], 'hDD);
        `EXPECT("Byte at 0x1D is valid", mock_mem.memory['h1D], 'hEE);
        `EXPECT("Byte at 0x1E is valid", mock_mem.memory['h1E], 'hFF);
        `EXPECT("Byte at 0x1F is valid", mock_mem.memory['h1F], 'hED);
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
    `EXPECT("Byte at 0x20 is valid", mock_mem.memory['h20], 'h11);
    `EXPECT("Byte at 0x21 is valid", mock_mem.memory['h21], 'h22);
    `EXPECT("Byte at 0x22 is valid", mock_mem.memory['h22], 'h33);
    `EXPECT("Byte at 0x23 is valid", mock_mem.memory['h23], 'h44);
    `EXPECT("Byte at 0x24 is valid", mock_mem.memory['h24], 'h55);
    `EXPECT("Byte at 0x25 is valid", mock_mem.memory['h25], 'h66);
    `EXPECT("Byte at 0x26 is valid", mock_mem.memory['h26], 'h77);
    `EXPECT("Byte at 0x27 is valid", mock_mem.memory['h27], 'h88);
    if (XLEN >=64) begin
        `TEST("memory", "Write Words Extended Alignments");
        WriteData(32'h28, 3'b010, 8'b11110000, 64'h99AABBCC, 0, 0);
        WriteData(32'h2C, 3'b010, 8'b11110000, 64'hDDEEFFED, 0, 0);
        `EXPECT("Byte at 0x28 is valid", mock_mem.memory['h28], 'h99);
        `EXPECT("Byte at 0x29 is valid", mock_mem.memory['h29], 'hAA);
        `EXPECT("Byte at 0x2A is valid", mock_mem.memory['h2A], 'hBB);
        `EXPECT("Byte at 0x2B is valid", mock_mem.memory['h2B], 'hCC);
        `EXPECT("Byte at 0x2C is valid", mock_mem.memory['h2C], 'hDD);
        `EXPECT("Byte at 0x2D is valid", mock_mem.memory['h2D], 'hEE);
        `EXPECT("Byte at 0x2E is valid", mock_mem.memory['h2E], 'hFF);
        `EXPECT("Byte at 0x2F is valid", mock_mem.memory['h2F], 'hED);
    end

    // ====================================
    // Test: Write Double-Words to address 0x30...0x3F
    // ====================================
    if (XLEN >=64) begin
        `TEST("memory", "Write Double-Words all alignments");
        WriteData(32'h30, 3'b011, 8'b11111111, 64'h1122334455667788, 0, 0);
        WriteData(32'h38, 3'b011, 8'b11111111, 64'h99AABBCCDDEEFFED, 0, 0);
        `EXPECT("Byte at 0x30 is valid", mock_mem.memory['h30], 'h11);
        `EXPECT("Byte at 0x31 is valid", mock_mem.memory['h31], 'h22);
        `EXPECT("Byte at 0x32 is valid", mock_mem.memory['h32], 'h33);
        `EXPECT("Byte at 0x33 is valid", mock_mem.memory['h33], 'h44);
        `EXPECT("Byte at 0x34 is valid", mock_mem.memory['h34], 'h55);
        `EXPECT("Byte at 0x35 is valid", mock_mem.memory['h35], 'h66);
        `EXPECT("Byte at 0x36 is valid", mock_mem.memory['h36], 'h77);
        `EXPECT("Byte at 0x37 is valid", mock_mem.memory['h37], 'h88);
        `EXPECT("Byte at 0x38 is valid", mock_mem.memory['h38], 'h99);
        `EXPECT("Byte at 0x39 is valid", mock_mem.memory['h39], 'hAA);
        `EXPECT("Byte at 0x3A is valid", mock_mem.memory['h3A], 'hBB);
        `EXPECT("Byte at 0x3B is valid", mock_mem.memory['h3B], 'hCC);
        `EXPECT("Byte at 0x3C is valid", mock_mem.memory['h3C], 'hDD);
        `EXPECT("Byte at 0x3D is valid", mock_mem.memory['h3D], 'hEE);
        `EXPECT("Byte at 0x3E is valid", mock_mem.memory['h3E], 'hFF);
        `EXPECT("Byte at 0x3F is valid", mock_mem.memory['h3F], 'hED);
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
    `TEST("memory", "Final Memory Dump");
    $display("\nTest memory dump:");
    `DISPLAY_MEM_RANGE_ARRAY(mock_mem, 'h00, 'h3f);
    `FINISH;
end

endmodule
