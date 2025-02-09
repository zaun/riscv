`timescale 1ns / 1ps
`default_nettype none

`define DEBUG // Turn on debugging ports
// `define LOG_MEMORY

`include "tl_cpu.sv"
`include "tl_memory.sv"

`ifndef XLEN
`define XLEN 32
`endif

module tl_cpu_tb;
`include "test/test_macros.sv"

// ====================================
// Parameters
// ====================================
parameter XLEN = `XLEN;
parameter SID_WIDTH = 8;    // Source ID length for TileLink
parameter MEM_SIZE = 4096;  // Memory size (supports addresses up to 0x0FFF)
parameter MEM_WIDTH = 32;

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

// TileLink Signals
logic                   tl_a_valid;
logic                   tl_a_ready;
logic [2:0]             tl_a_opcode;
logic [2:0]             tl_a_param;
logic [2:0]             tl_a_size;
logic [SID_WIDTH-1:0]   tl_a_source;
logic [XLEN-1:0]        tl_a_address;
logic [XLEN/8-1:0]      tl_a_mask;
logic [XLEN-1:0]        tl_a_data;

logic                   tl_d_valid;
logic                   tl_d_ready;
logic [2:0]             tl_d_opcode;
logic [1:0]             tl_d_param;
logic [2:0]             tl_d_size;
logic [SID_WIDTH-1:0]   tl_d_source;
logic [XLEN-1:0]        tl_d_data;
logic                   tl_d_corrupt;
logic                   tl_d_denied;

// Debugging
wire [31:0]             cpu_pc;
wire [31:0]             cpu_x1;
wire [31:0]             cpu_x2;
wire [31:0]             cpu_x3;
wire                    cpu_halt;
wire                    cpu_trap;

// ====================================
// Instantiate the CPU (TileLink Master)
// The CPU includes the cpu_mem_interface internally with the timing fix.
// ====================================
tl_cpu #(
    .XLEN(XLEN),
    .START_ADDRESS(32'h0000_0000) // force start address to 0
) uut (
    .clk(clk),
    .reset(reset),

    // No interrupts in this test
    // .external_irq(),
    // .external_nmi(),

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

    .trap(cpu_trap),

    // Debug
    .dbg_pc(cpu_pc),
    .dbg_x1(cpu_x1),
    .dbg_x2(cpu_x2),
    .dbg_x3(cpu_x3),
    .dbg_halt(cpu_halt)
);

// ====================================
// Instantiate Mock Memory (with timing fix)
// ====================================
tl_memory #(
    .XLEN(XLEN),
    .WIDTH(MEM_WIDTH),
    .SID_WIDTH(SID_WIDTH),
    .SIZE(MEM_SIZE)
) mock_mem (
    .clk          (clk),
    .reset        (reset),

    // TileLink A Channel
    .tl_a_valid   (tl_a_valid),
    .tl_a_ready   (tl_a_ready),
    .tl_a_opcode  (tl_a_opcode),
    .tl_a_param   (tl_a_param),
    .tl_a_size    (tl_a_size),
    .tl_a_source  (tl_a_source),
    .tl_a_address (tl_a_address),
    .tl_a_mask    (tl_a_mask),
    .tl_a_data    (tl_a_data),

    // TileLink D Channel
    .tl_d_valid   (tl_d_valid),
    .tl_d_ready   (tl_d_ready),
    .tl_d_opcode  (tl_d_opcode),
    .tl_d_param   (tl_d_param),
    .tl_d_size    (tl_d_size),
    .tl_d_source  (tl_d_source),
    .tl_d_data    (tl_d_data),
    .tl_d_corrupt (tl_d_corrupt),
    .tl_d_denied  (tl_d_denied),

    // Debug inputs
    .dbg_corrupt_read_address(),
    .dbg_denied_read_address(),
    .dbg_corrupt_write_address(),
    .dbg_denied_write_address()
);

// ====================================
// Simulation Sequence
// ====================================
initial begin
    $dumpfile("tl_cpu_tb.vcd");
    $dumpvars(0, tl_cpu_tb);

    // ====================================
    // Load immediate (lui, addi)
    // ====================================

    $display("\n== Verify li (load immediate) works to load data into registers");
    $display("== Note: li is translated into lui rd imm, addi rd x0 imm");

    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "lui x2, 0x12345, addi x2, x2, 0x678: Load 0x12345678 into x2")
    // Loading 0x12345678 into x2
    mock_mem.block_ram_inst.memory['h0000] = 32'h12345137; // lui x2, 0x12345 -> 0x12345137
    mock_mem.block_ram_inst.memory['h0001] = 32'h67810113; // addi x2, x2, 0x678 -> 0x67810113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0000006F; // jal x0, 0 -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);
    `EXPECT("Verify x2 register", cpu_x2, 32'h12345678)

    // ====================================
    // Load commands
    // ====================================

    $display("\n==\n== Verify load instructions (lb, lbu, lh, lhu, lw)\n==");

    // ----------------------------
    // Load Byte (LB) with Positive Value
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "lb x2, 0x11(x0): Load byte x2 with 0x56 (positive) from address 0x0011(x0)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h01100103; // lb x2, 0x11(x0) -> 0x01100103
    mock_mem.block_ram_inst.memory['h0001] = 32'h0000006F; // jal x0, 0 -> 0x0000006F

    // Data at address 0x0011: 0x56
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h11, 8'h56);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);
    `EXPECT("Verify x2 register", cpu_x2, 8'h56)

    // ----------------------------
    // Load Byte (LB) with Negative Value
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "lb x3, 0x12(x0): Load byte x3 with 0xF6 (negative) from address 0x0012(x0)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h01200183; // lb x3, 0x12(x0) -> 0x01200183
    mock_mem.block_ram_inst.memory['h0001] = 32'h0000006F; // jal x0, 0 -> 0x0000006F

    // Data at address 0x0012: 0xF6
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h12, 8'hF6);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);
    `EXPECT("Verify x3 register", cpu_x3, 32'hFFFFFFF6)

    // ----------------------------
    // Load Byte (LBU)
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "lbu x2, 0x11(x0): Load byte x2 with 0xF6 from address 0x0011(x0)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h01104103; // lbu x2, 0x11(x0) -> 0x01104103
    mock_mem.block_ram_inst.memory['h0001] = 32'h0000006F; // jal x0, 0 -> 0x0000006F

    // Data at address 0x0011: 0x56
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h11, 8'hF6);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x2 register", cpu_x2, 8'hF6)

    // ----------------------------
    // Load Half-Word (LH)
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "lh x3, 0x10(x0): Load half-word x3 with 0x5678 from address 0x0010(x0)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h01001183; // lh x3, 0x10(x0) -> 0x01001183
    mock_mem.block_ram_inst.memory['h0001] = 32'h0000006F; // jal x0, 0 -> 0x0000006F


    // Data at address 0x0010: 0x5678 (little endian: 0x78, 0x56)
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h10, 8'h78);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h11, 8'h56);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x3 register", cpu_x3, 16'h5678)

    // ----------------------------
    // Load Half-Unsigned (LHU)
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "lhu x3, 0x10(x0): Load half-word x3 with 0x5678 from address 0x0010(x0)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h01005183; // lhu x3, 0x10(x0) -> 0x01005183
    mock_mem.block_ram_inst.memory['h0001] = 32'h0000006F; // jal x0, 0 -> 0x0000006F


    // Data at address 0x0010: 0x5678 (little endian: 0x78, 0x56)
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h10, 8'h78);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h11, 8'h56);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x3 register", cpu_x3, 16'h5678);

    // ----------------------------
    // Load Word (LW)
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "lw x1, 0x10(x0): Load x1 with 0x12345678 from address 0x0010(x0)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h01002083; // lw x1, 0x10(x0) -> 0x01002083
    mock_mem.block_ram_inst.memory['h0001] = 32'h0000006F; // jal x0, 0 -> 0x0000006F

    // Data at address 0x0010: 0x12345678
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h10, 8'h78);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h11, 8'h56);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h12, 8'h34);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h13, 8'h12);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x1 register", cpu_x1, 32'h12345678)

    // ====================================
    // Store commands
    // ====================================

    $display("\n==\n== Verify store instructions (sb, sh, sw)\n==");

    // ----------------------------
    // Store Byte (SB)
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "sb x2, 0(x1): Store a byte from x2 into the memory address stored in x1")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0 0x50 -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h12345137; // lui x2, 0x12345 -> 0x12345137
    mock_mem.block_ram_inst.memory['h0002] = 32'h67810113; // addi x2, x2, 0x678 -> 0x67810113
    mock_mem.block_ram_inst.memory['h0003] = 32'h00208023; // sb x2, 0(x1) -> 0x00208023
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; //jal x0, 0 -> 0x0000006F

    // Known values in store locations
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h50, 8'hAA);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h51, 8'hBB);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h52, 8'hCC);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h53, 8'hDD);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x1 register with test data", cpu_x1, 32'h00000050)
    `EXPECT("Verify x2 register with test data", cpu_x2, 32'h12345678)
    `EXPECT("Verify memory at 0x50 has byte 0x78", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0050), 8'h78)
    `EXPECT("Verify memory at 0x51 has byte 0xAA", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0051), 8'hBB)
    `EXPECT("Verify memory at 0x52 has byte 0xBB", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0052), 8'hCC)
    `EXPECT("Verify memory at 0x53 has byte 0xCC", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0053), 8'hDD)

    // ----------------------------
    // Store Half-Word (SH)
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "sb x2, 0(x1): Store a half-word from x2 into the memory address stored in x1")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0 0x50 -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h12345137; // lui x2, 0x12345 -> 0x12345137
    mock_mem.block_ram_inst.memory['h0002] = 32'h67810113; // addi x2, x2, 0x678 -> 0x67810113
    mock_mem.block_ram_inst.memory['h0003] = 32'h00209023; // sb x2, 0(x1) -> 0x00209023
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0 -> 0x0000006F

    // Known values in store locations
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h50, 8'hAA);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h51, 8'hBB);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h52, 8'hCC);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h53, 8'hDD);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x1 register with test data", cpu_x1, 32'h00000050)
    `EXPECT("Verify x2 register with test data", cpu_x2, 32'h12345678)
    `EXPECT("Verify memory at 0x50 has byte 0x78", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0050), 8'h78)
    `EXPECT("Verify memory at 0x51 has byte 0x56", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0051), 8'h56)
    `EXPECT("Verify memory at 0x52 has byte 0xCC", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0052), 8'hCC)
    `EXPECT("Verify memory at 0x53 has byte 0xDD", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0053), 8'hDD)


    // ----------------------------
    // Store Word (SW)
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "sb x2, 0(x1): Store a word from x2 into the memory address stored in x1")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0 0x50 -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h12345137; // lui x2, 0x12345 -> 0x12345137
    mock_mem.block_ram_inst.memory['h0002] = 32'h67810113; // addi x2, x2, 0x678 -> 0x67810113
    mock_mem.block_ram_inst.memory['h0003] = 32'h0020A023; // sb x2, 0(x1) -> 0x0020A023
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0 -> 0x0000006F

    // Known values in store locations
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h50, 8'hAA);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h51, 8'hBB);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h52, 8'hCC);
    `SET_BYTE_IN_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h53, 8'hDD);

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x1 register with test data", cpu_x1, 32'h00000050)
    `EXPECT("Verify x2 register with test data", cpu_x2, 32'h12345678)
    `EXPECT("Verify memory at 0x00000050 has byte 0x78", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0050), 8'h78)
    `EXPECT("Verify memory at 0x00000051 has byte 0x56", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0051), 8'h56)
    `EXPECT("Verify memory at 0x00000052 has byte 0x56", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0052), 8'h34)
    `EXPECT("Verify memory at 0x00000053 has byte 0x56", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h0053), 8'h12)

    // ====================================
    // Branch commands
    // ====================================

    $display("\n==\n== Verify branch instructions (beq, blt, bltu, bge, bgeu)\n==");

    // ----------------------------
    // BEQ Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BEQ taken when x1 == x2")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h00208663; // BEQ x1, x2, +12     -> 0x00208663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 2 (branch  taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BEQ Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BEQ not taken when x1 != x2")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05100113; // addi x2, x0, 0x51   -> 0x05100113
    mock_mem.block_ram_inst.memory['h0002] = 32'h00208663; // BEQ x1, x2, +12     -> 0x00208663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193 (Branch target)
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BNE Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BNE not taken when x1 == x2")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h00209663; // BNE x1, x2, +12     -> 0x00209663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193 (Branch target)
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)


    // ----------------------------
    // BNE Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BNE taken when x1 != x2")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05100113; // addi x2, x0, 0x51   -> 0x05100113
    mock_mem.block_ram_inst.memory['h0002] = 32'h00209663; // BNE x1, x2, +12     -> 0x00209663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BLT Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BLT not taken when x1 == x2")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020c663; // BLT x1, x2, +12     -> 0x0020c663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193 (Branch target)
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BLT Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BLT not taken when x1 > x2 (x2 signed)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05100093; // addi x1, x0, 0x51   -> 0x05100093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020c663; // BLT x1, x2, +12     -> 0x0020c663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193 (Branch target)
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BLT Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BLT taken when x1 < x2 (x1 signed)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05100113; // addi x2, x0, 0x51   -> 0x05100113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020c663; // BLT x1, x2, +12     -> 0x0020c663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BLTU Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BLTU not taken when x1 == x2")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020E663; // BLTU x1, x2, +12    -> 0x0020E663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193 (Branch target)
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BLTU Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BLTU taken when x1 < x2 (x2 unsigned)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05100113; // addi x2, x0, 0x51   -> 0x05100113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020E663; // BLTU x1, x2, +12    -> 0x0020E663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BLTU Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BLTU not taken when x1 > x2 (x1 unsigned)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05100093; // addi x1, x0, 0x51   -> 0x05100093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020E663; // BLTU x1, x2, +12    -> 0x0020E663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193 (Branch target)
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BGE Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BGE taken when x1 == x2")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020d663; // BGE x1, x2, +12     -> 0x0020d663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BGE Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BGE taken when x1 > x2 (x2 signed)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05100093; // addi x1, x0, 0x51   -> 0x05100093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020D663; // BGE x1, x2, +12     -> 0x0020D663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BGE Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BGE not taken when x1 < x2 (x1 signed)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05100113; // addi x2, x0, 0x51   -> 0x05100113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020D663; // BGE x1, x2, +12     -> 0x0020D663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193 (Branch target)
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BGEU Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BGEU taken when x1 == x2")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020F663; // BGEU x1, x2, +12    -> 0x0020F663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BLTU NOT Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BGEU taken when x1 < x2 (x2 unsigned)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05000093; // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05100113; // addi x2, x0, 0x51   -> 0x05100113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020F663; // BGEU x1, x2, +12    -> 0x0020F663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193 (Branch target)
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BGEU Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("tl_cpu.sv", "BGEU taken when x1 > x2 (x1 unsigned)")
    mock_mem.block_ram_inst.memory['h0000] = 32'h05100093; // addi x1, x0, 0x51   -> 0x05100093
    mock_mem.block_ram_inst.memory['h0001] = 32'h05000113; // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.block_ram_inst.memory['h0002] = 32'h0020F663; // BGEU x1, x2, +12    -> 0x0020F663
    mock_mem.block_ram_inst.memory['h0003] = 32'h00100193; // addi x3, x0, 1      -> 0x00100193
    mock_mem.block_ram_inst.memory['h0004] = 32'h0000006F; // jal x0, 0           -> 0x0000006F
    mock_mem.block_ram_inst.memory['h0005] = 32'h00200193; // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.block_ram_inst.memory['h0006] = 32'h0000006F; // jal x0, 0           -> 0x0000006F

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    // Expect x3 to be 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ====================================
    // Jump commands
    // ====================================
    $display("\n==\n== Verify jump instructions (jal, jalr, ret)\n==");

    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    // `TEST("tl_cpu.sv", "Mini program")

    // mock_mem.block_ram_inst.memory['h0000] = 32'h00100093; // addi x1,x0,0x1
    // mock_mem.block_ram_inst.memory['h0001] = 32'h01000113; // addi x2,x0,0x10
    // mock_mem.block_ram_inst.memory['h0002] = 32'h00112623; // sw x1,0xC(x2) 
    // mock_mem.block_ram_inst.memory['h0003] = 32'h0000006f; // jal x0, 0

    // @(posedge clk);
    // reset = 0;
    // #500; // Wait sufficient time for instructions to execute

    // `EXPECT("Verify x1 register", cpu_x1, 32'h0000_0001)
    // `EXPECT("Verify memory 0x001C", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h001C), 8'h01)
    // `EXPECT("Verify memory 0x001D", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h001D), 8'h00)
    // `EXPECT("Verify memory 0x001E", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h001E), 8'h00)
    // `EXPECT("Verify memory 0x001F", `GET_BYTE_FROM_MEM(mock_mem.block_ram_inst.memory, MEM_WIDTH, 'h001F), 8'h00)

    `FINISH;
end

endmodule
