`timescale 1ns / 1ps
`default_nettype none

`define DEBUG
// `define LOG_SWITCH
// `define LOG_MEM_INTERFACE
// `define LOG_MEMORY

`include "tl_switch.sv"
`include "tl_interface.sv"
`include "tl_memory.sv"

`ifndef XLEN
`define XLEN 32
`endif

module tl_switch_tb;
`include "test/test_macros.sv"

// ====================================
// Parameters
// ====================================
parameter XLEN = `XLEN;
parameter SID_WIDTH = 8;     // Source ID length for TileLink (updated to match tl_switch)
parameter MEM_SIZE = 4096;   // Memory size (supports addresses up to 0x0FFF)
parameter MAX_RETRIES = 3;   // Maximum number of retry attempts
parameter TRACK_DEPTH = 4;

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
// TileLink A Channel (Master Side)
// ====================================
wire                 switch_a_valid;
wire                 switch_a_ready;
wire [2:0]           switch_a_opcode;
wire [2:0]           switch_a_param;
wire [2:0]           switch_a_size;
wire [SID_WIDTH-1:0] switch_a_source;
wire [XLEN-1:0]      switch_a_address;
wire [XLEN/8-1:0]    switch_a_mask;
wire [XLEN-1:0]      switch_a_data;

// ====================================
// TileLink D Channel (Master Side)
// ====================================
wire                 switch_d_valid;
wire                 switch_d_ready;
wire [2:0]           switch_d_opcode;
wire [1:0]           switch_d_param;
wire [2:0]           switch_d_size;
wire [SID_WIDTH-1:0] switch_d_source;
wire [XLEN-1:0]      switch_d_data;
wire                 switch_d_corrupt;
wire                 switch_d_denied;

// ====================================
// TileLink A Channel (Slave Side)
// ====================================
wire                 switch_s_a_valid;
wire                 switch_s_a_ready;
wire [2:0]           switch_s_a_opcode;
wire [2:0]           switch_s_a_param;
wire [2:0]           switch_s_a_size;
wire [SID_WIDTH-1:0] switch_s_a_source;
wire [XLEN-1:0]      switch_s_a_address;
wire [XLEN/8-1:0]    switch_s_a_mask;
wire [XLEN-1:0]      switch_s_a_data;

// ====================================
// TileLink D Channel (Slave Side)
// ====================================
wire                 switch_s_d_valid;
wire                 switch_s_d_ready;
wire [2:0]           switch_s_d_opcode;
wire [1:0]           switch_s_d_param;
wire [2:0]           switch_s_d_size;
wire [SID_WIDTH-1:0] switch_s_d_source;
wire [XLEN-1:0]      switch_s_d_data;
wire                 switch_s_d_corrupt;
wire                 switch_s_d_denied;

// ====================================
// Base Addresses for Slaves
// ====================================
wire [XLEN-1:0]      switch_base_addr;
wire [XLEN-1:0]      switch_addr_mask;

assign switch_base_addr = 32'h0000_0000;
assign switch_addr_mask = 32'h0000_1000; // Covers addresses 0x0000 to 0x0FFF

wire [TRACK_DEPTH*SID_WIDTH-1:0] dbg_request_entry_source_id;
wire [TRACK_DEPTH*SID_WIDTH-1:0] dbg_request_entry_master_idx;
wire [TRACK_DEPTH-1:0]           dbg_request_entry_corrupt;
wire [TRACK_DEPTH-1:0]           dbg_request_entry_denied;
wire [TRACK_DEPTH-1:0]           dbg_table_valid;

// ====================================
// Instantiate the TL-UL Switch
// ====================================
tl_switch #(
    .NUM_INPUTS(1),
    .NUM_OUTPUTS(1),
    .XLEN(XLEN),
    .SID_WIDTH(SID_WIDTH),
    .TRACK_DEPTH(TRACK_DEPTH)
) switch_inst (
    .clk(clk),
    .reset(reset),

    // ======================
    // TileLink A Channel - Masters
    // ======================
    .a_valid({switch_a_valid}),
    .a_ready({switch_a_ready}),
    .a_address({switch_a_address}),
    .a_opcode({switch_a_opcode}),
    .a_param({switch_a_param}),
    .a_size({switch_a_size}),
    .a_source({switch_a_source}),
    // Pad a_mask to 8 bits
    .a_mask({switch_a_mask}),
    .a_data({switch_a_data}),

    // ======================
    // TileLink D Channel - Masters
    // ======================
    .d_valid({switch_d_valid}),
    .d_ready({switch_d_ready}),
    .d_opcode(switch_d_opcode),
    .d_param({switch_d_param}),
    .d_size({switch_d_size}),
    .d_source({switch_d_source}),
    .d_data({switch_d_data}),
    .d_corrupt({switch_d_corrupt}),
    .d_denied({switch_d_denied}),

    // ======================
    // TileLink A Channel - Slaves
    // ======================
    .s_a_valid({switch_s_a_valid}),
    .s_a_ready({switch_s_a_ready}),
    .s_a_address({switch_s_a_address}),
    .s_a_opcode({switch_s_a_opcode}),
    .s_a_param({switch_s_a_param}),
    .s_a_size({switch_s_a_size}),
    .s_a_source({switch_s_a_source}),
    // Pad s_a_mask to 8 bits
    .s_a_mask({switch_s_a_mask}),
    .s_a_data({switch_s_a_data}),

    // ======================
    // TileLink D Channel - Slaves
    // ======================
    .s_d_valid({switch_s_d_valid}),
    .s_d_ready({switch_s_d_ready}),
    // Pad s_d_opcode to 3 bits
    .s_d_opcode({switch_s_d_opcode}),
    .s_d_param({switch_s_d_param}),
    .s_d_size({switch_s_d_size}),
    .s_d_source({switch_s_d_source}),
    .s_d_data({switch_s_d_data}),
    .s_d_corrupt({switch_s_d_corrupt}),
    .s_d_denied({switch_s_d_denied}),

    // ======================
    // Base Addresses for Slaves
    // ======================
    .base_addr({switch_base_addr}),
    .addr_mask({switch_addr_mask})
);

// ====================================
// Instantiate the Memory Interface (CPU Side)
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

    // TileLink A Channel (Master Side)
    .tl_a_valid(switch_a_valid),
    .tl_a_ready(switch_a_ready),
    .tl_a_opcode(switch_a_opcode),
    .tl_a_param(switch_a_param),
    .tl_a_size(switch_a_size),
    .tl_a_source(switch_a_source),
    .tl_a_address(switch_a_address),
    .tl_a_mask(switch_a_mask),
    .tl_a_data(switch_a_data),

    // TileLink D Channel (Master Side)
    .tl_d_valid(switch_d_valid),
    .tl_d_ready(switch_d_ready),
    .tl_d_opcode({switch_d_opcode}),
    .tl_d_param(switch_d_param),
    .tl_d_size(switch_d_size),
    .tl_d_source(switch_d_source),
    .tl_d_data(switch_d_data),
    .tl_d_corrupt(switch_d_corrupt),
    .tl_d_denied(switch_d_denied)
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

    // TileLink A Channel (Slave Side)
    .tl_a_valid (switch_s_a_valid),
    .tl_a_ready (switch_s_a_ready),
    .tl_a_opcode(switch_s_a_opcode),
    .tl_a_param (switch_s_a_param),
    .tl_a_size  (switch_s_a_size),
    .tl_a_source(switch_s_a_source),
    .tl_a_address(switch_s_a_address),
    // Pad tl_a_mask to 8 bits
    .tl_a_mask  ({switch_s_a_mask}),
    .tl_a_data  (switch_s_a_data),

    // TileLink D Channel (Slave Side)
    .tl_d_valid (switch_s_d_valid),
    .tl_d_ready (switch_s_d_ready),
    .tl_d_opcode(switch_s_d_opcode),
    .tl_d_param (switch_s_d_param),
    .tl_d_size  (switch_s_d_size),
    .tl_d_source(switch_s_d_source),
    .tl_d_data  (switch_s_d_data),
    .tl_d_corrupt(switch_s_d_corrupt),
    .tl_d_denied (switch_s_d_denied),

    // Debug inputs (for error simulation)
    .dbg_corrupt_read_address(dbg_corrupt_read_address),
    .dbg_denied_read_address(dbg_denied_read_address),
    .dbg_corrupt_write_address(dbg_corrupt_write_address),
    .dbg_denied_write_address(dbg_denied_write_address)
);

// ====================================
// Helper Tasks
// ====================================

// Task to perform a read operation
task automatic perform_read (
    input [XLEN-1:0]   address,
    input [2:0]        size,
    output [XLEN-1:0]  rdata
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

    rdata = cpu_rdata;

    @(posedge clk);

    if (cpu_valid != 1'b0 && cpu_rdata != 1'b0 &&
        cpu_denied != 1'b0 && cpu_corrupt != 1'b0) begin
        $display("CPU interface not idle!");
        $stop;
    end

    cpu_ready = 1'b0; // Deassert ready
end
endtask

// Task to perform a write operation
task automatic perform_write (
    input [XLEN-1:0]   address,
    input [2:0]        size,
    input [XLEN-1:0]   value,
    input [XLEN/8-1:0] mask
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

    `ifdef LOG_SWITCH `LOG("tl_switch_tb", ("/perform_write 1/ cpu_ready=%0d cpu_read=%0d cpu_ack=%0d cpu_valid=%0d", cpu_ready, cpu_read, cpu_ack, cpu_valid)); `endif
    @(posedge clk);
    wait (cpu_ack == 1'b1);
    `ifdef LOG_SWITCH `LOG("tl_switch_tb", ("/perform_write 2/ cpu_ready=%0d cpu_read=%0d cpu_ack=%0d cpu_valid=%0d", cpu_ready, cpu_read, cpu_ack, cpu_valid)); `endif
    cpu_ready    = 1'b0;    // CPU Request is acknowledged

    // Wait for CPU to acknowledge the write
    @(posedge clk);
    `ifdef LOG_SWITCH `LOG("tl_switch_tb", ("/perform_write 3/ cpu_ready=%0d cpu_read=%0d cpu_ack=%0d cpu_valid=%0d", cpu_ready, cpu_read, cpu_ack, cpu_valid)); `endif
    wait (cpu_valid == 1'b1);
    `ifdef LOG_SWITCH `LOG("tl_switch_tb", ("/perform_write 4/ cpu_ready=%0d cpu_read=%0d cpu_ack=%0d cpu_valid=%0d", cpu_ready, cpu_read, cpu_ack, cpu_valid)); `endif

    @(posedge clk);
    `ifdef LOG_SWITCH `LOG("tl_switch_tb", ("/perform_write 5/ cpu_ready=%0d cpu_read=%0d cpu_ack=%0d cpu_valid=%0d", cpu_ready, cpu_read, cpu_ack, cpu_valid)); `endif

    if (cpu_valid != 1'b0 && cpu_rdata != 1'b0 &&
        cpu_denied != 1'b0 && cpu_corrupt != 1'b0) begin
        $display("CPU interface not idle!");
        $stop;
    end

    cpu_ready = 1'b0; // Deassert ready
    wait (cpu_valid == 1'b0);

    // Cleanup
    @(posedge clk);

    `EXPECT("Slave valid line to be low", switch_s_a_valid, 1'b0);
    `EXPECT("Slave ready line to be high", switch_s_a_ready, 1'b1);
end
endtask

// Temporary variables and registers
logic [XLEN-1:0] read_data;

reg should_expect_denied;
reg should_expect_corrupt;

// Declare Debug Signals
reg [XLEN-1:0] dbg_corrupt_read_address;
reg [XLEN-1:0] dbg_denied_read_address;
reg [XLEN-1:0] dbg_corrupt_write_address;
reg [XLEN-1:0] dbg_denied_write_address;
reg            dbg_wait;

// ====================================
// Test Sequence
// ====================================
initial begin
    $dumpfile("tl_switch_tb.vcd");
    $dumpvars(0, tl_switch_tb);

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
    // Write Byte and Read Byte
    // ====================================
    `TEST("tl_switch", "Write Byte and Read Byte")

    // Write byte 0xAB to address 0x0004
    perform_write(32'h00000004, 3'b000, 32'h000000AB, 8'b00000001);

    // Verify that mock_memory has the byte written
    `EXPECT("Memory at 0x0004 holds 0xAB", mock_mem.block_ram_inst.memory[32'h0004], 8'hAB)

    // Read byte from address 0x0004
    perform_read(32'h00000004, 3'b000, read_data);
    `EXPECT("Read Byte Data", read_data, 32'h000000AB)

    // ====================================
    // Write Halfword and Read Halfword
    // ====================================
    `TEST("tl_switch", "Write Halfword and Read Halfword")

    // Write halfword 0xCDEF to address 0x0008
    perform_write(32'h00000008, 3'b001, 32'h0000CDEF, 8'b00000011);

    // Verify that mock_memory has the halfword written
    `EXPECT("Memory at 0x0008 holds 0xEF", mock_mem.block_ram_inst.memory[32'h0008], 8'hEF)
    `EXPECT("Memory at 0x0009 holds 0xCD", mock_mem.block_ram_inst.memory[32'h0009], 8'hCD)

    // Read halfword from address 0x0008
    perform_read(32'h00000008, 3'b001, read_data);
    `EXPECT("Read Halfword Data", read_data, 32'h0000CDEF)

    // ====================================
    // Write Word and Read Word
    // ====================================
    `TEST("tl_switch", "Write Word and Read Word")

    // Write word 0x12345678 to address 0x000C
    perform_write(32'h0000000C, 3'b010, 32'h12345678, 8'b00001111);

    // Verify that mock_memory has the word written
    `EXPECT("Memory at 0x000C holds 0x78", mock_mem.block_ram_inst.memory[32'h000C], 8'h78)
    `EXPECT("Memory at 0x000D holds 0x56", mock_mem.block_ram_inst.memory[32'h000D], 8'h56)
    `EXPECT("Memory at 0x000E holds 0x34", mock_mem.block_ram_inst.memory[32'h000E], 8'h34)
    `EXPECT("Memory at 0x000F holds 0x12", mock_mem.block_ram_inst.memory[32'h000F], 8'h12)

    // Read word from address 0x000C
    perform_read(32'h0000000C, 3'b010, read_data);
    `EXPECT("Read Word Data", read_data, 32'h12345678)

    // ====================================
    // Write with Partial Byte Mask
    // ====================================
    `TEST("tl_switch", "Write with Partial Byte Mask")

    // Initialize memory at 0x0010 to 0xFF via write operations
    perform_write(32'h00000010, 3'b000, 32'h000000FF, 8'b00000001);
    perform_write(32'h00000011, 3'b000, 32'h000000FF, 8'b00000001);
    perform_write(32'h00000012, 3'b000, 32'h000000FF, 8'b00000001);
    perform_write(32'h00000013, 3'b000, 32'h000000FF, 8'b00000001);
    perform_write(32'h00000010, 3'b000, 32'h00000055, 8'b00000001);

    // Verify that only the first byte is updated
    `EXPECT("Memory at 0x0010 holds 0x55", mock_mem.block_ram_inst.memory[32'h0010], 8'h55)
    `EXPECT("Memory at 0x0011 holds 0xFF", mock_mem.block_ram_inst.memory[32'h0011], 8'hFF)
    `EXPECT("Memory at 0x0012 holds 0xFF", mock_mem.block_ram_inst.memory[32'h0012], 8'hFF)
    `EXPECT("Memory at 0x0013 holds 0xFF", mock_mem.block_ram_inst.memory[32'h0013], 8'hFF)

    // Read word from address 0x0010
    perform_read(32'h00000010, 3'b010, read_data);
    `EXPECT("Read Word After Partial Byte Write", read_data, 32'hFFFFFF55)
    @(posedge clk); // Allow clock cycle for read data to settle

    // ====================================
    // Read from Invalid Address (Denied)
    // ====================================
    `TEST("tl_switch", "Read from Invalid Address (Denied)")

    // Configure mock_memory to deny read from address 0x0100
    dbg_denied_read_address = 32'h00000100;
    @(posedge clk); // Allow clock cycle for debug signal to take effect

    // Attempt to read from address 0x0100
    should_expect_denied = 1;
    perform_read(32'h00000100, 3'b010, read_data);

    // Verify that read_data remains zero (assuming mock_memory returns 0 on denied read)
    `EXPECT("Read Data after denied read", read_data, 32'h00000000)

    // Reset denied_read_address for next tests
    reset = 1;
    #10;
    @(posedge clk);
    reset = 0;
    @(posedge clk);
    dbg_denied_read_address = {XLEN{1'b0}};
    @(posedge clk); // Allow clock cycle for reset to take effect

    // ====================================
    // Write to Invalid Address (Denied)
    // ====================================
    `TEST("tl_switch", "Write to Invalid Address (Denied)")

    // Configure mock_memory to deny write to address 0x0200
    dbg_denied_write_address = 32'h00000200;
    @(posedge clk); // Allow clock cycle for debug signal to take effect

    // Attempt to write to address 0x0200
    should_expect_denied = 1;
    perform_write(32'h00000200, 3'b010, 32'hDEADBEEF, 8'b11111111);

    // Verify that mock_memory did not update the memory
    `EXPECT("Memory at 0x0200 remains 0x00", mock_mem.block_ram_inst.memory[32'h0200], 8'hxx)
    `EXPECT("Memory at 0x0201 remains 0x00", mock_mem.block_ram_inst.memory[32'h0201], 8'hxx)
    `EXPECT("Memory at 0x0202 remains 0x00", mock_mem.block_ram_inst.memory[32'h0202], 8'hxx)
    `EXPECT("Memory at 0x0203 remains 0x00", mock_mem.block_ram_inst.memory[32'h0203], 8'hxx)

    // Reset denied_write_address for next tests
    reset = 1;
    #10;
    @(posedge clk);
    reset = 0;
    @(posedge clk);
    dbg_denied_write_address = {XLEN{1'b0}};
    @(posedge clk); // Allow clock cycle for reset to take effect

    // ====================================
    // Read with Corrupt Response
    // ====================================
    `TEST("tl_switch", "Read with Corrupt Response")

    // Configure mock_memory to corrupt read from address 0x0300
    dbg_corrupt_read_address = 32'h00000300;
    @(posedge clk); // Allow clock cycle for debug signal to take effect

    // Initialize memory at 0x0300 to 0xABCD1234 via write operations
    perform_write(32'h00000300, 3'b010, 32'hABCD1234, 8'b11111111);

    // Read from address 0x0300 (should be corrupted)
    should_expect_corrupt = 1;
    perform_read(32'h00000300, 3'b010, read_data);

    // Depending on mock_memory's corruption behavior, verify read_data
    // For this example, assume corrupt read returns 0
    `EXPECT("Read Data after corrupt read", read_data, 32'h00000000)
    @(posedge clk); // Allow clock cycle for read data to settle

    // Reset nmi_corrupt and corrupt_read_address for next tests
    reset = 1;
    #10;
    @(posedge clk);
    reset = 0;
    @(posedge clk);
    dbg_corrupt_read_address = {XLEN{1'b0}};
    @(posedge clk); // Allow clock cycle for reset to take effect

    // ====================================
    // Write with Corrupt Response
    // ====================================
    `TEST("tl_switch", "Write with Corrupt Response")

    // Configure mock_memory to corrupt write to address 0x0400
    dbg_corrupt_write_address = 32'h00000400;
    @(posedge clk); // Allow clock cycle for debug signal to take effect

    // Attempt to write to address 0x0400 (should be corrupted)
    should_expect_corrupt = 1;
    perform_write(32'h00000400, 3'b010, 32'hCAFEBABE, 8'b11111111);

    // Verify that mock_memory's memory remains unchanged or is corrupted
    // For this example, assume corrupt write does not update memory
    `EXPECT("Memory at 0x0400 remains 0x00", mock_mem.block_ram_inst.memory[32'h0400], 8'hxx)
    `EXPECT("Memory at 0x0401 remains 0x00", mock_mem.block_ram_inst.memory[32'h0401], 8'hxx)
    `EXPECT("Memory at 0x0402 remains 0x00", mock_mem.block_ram_inst.memory[32'h0402], 8'hxx)
    `EXPECT("Memory at 0x0403 remains 0x00", mock_mem.block_ram_inst.memory[32'h0403], 8'hxx)

    // Reset nmi_corrupt and corrupt_write_address for next tests
    reset = 1;
    #10;
    @(posedge clk);
    reset = 0;
    @(posedge clk);
    dbg_corrupt_write_address = {XLEN{1'b0}};
    @(posedge clk); // Allow clock cycle for reset to take effect

    // ====================================
    // Exceed Maximum Retries
    // ====================================
    `TEST("tl_switch", "Exceed Maximum Retries and Abort")

    // Configure mock_memory to deny write to address 0x0600
    dbg_denied_write_address = 32'h00000600;
    @(posedge clk); // Allow clock cycle for debug signal to take effect

    // Attempt to write to address 0x0600, which will timeout after MAX_RETRIES
    should_expect_denied = 1;
    perform_write(32'h00000600, 3'b010, 32'hFEEDFACE, 8'b11111111);

    // Verify that mock_memory did not update the memory
    `EXPECT("Memory at 0x0600 remains 0x00", mock_mem.block_ram_inst.memory[32'h0600], 8'hxx)
    `EXPECT("Memory at 0x0601 remains 0x00", mock_mem.block_ram_inst.memory[32'h0601], 8'hxx)
    `EXPECT("Memory at 0x0602 remains 0x00", mock_mem.block_ram_inst.memory[32'h0602], 8'hxx)
    `EXPECT("Memory at 0x0603 remains 0x00", mock_mem.block_ram_inst.memory[32'h0603], 8'hxx)

    // Reset denied_write_address for final tests
    reset = 1;
    #10;
    @(posedge clk);
    reset = 0;
    @(posedge clk);
    dbg_denied_write_address = {XLEN{1'b0}};
    @(posedge clk); // Allow clock cycle for reset to take effect

    // ====================================
    // Finish Testbench
    // ====================================
    `FINISH;
end

endmodule
