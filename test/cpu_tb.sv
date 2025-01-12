`timescale 1ns / 1ps
`default_nettype none

`define DEBUG // Turn on debugging ports
// `define LOG

`include "src/cpu.sv"
`include "src/tl_memory.sv"

`ifndef XLEN
`define XLEN 32
`endif

module cpu_tb;
`include "test/test_macros.sv"

// ====================================
// Parameters
// ====================================
parameter XLEN = `XLEN;
parameter SID_WIDTH = 8;    // Source ID length for TileLink
parameter MEM_SIZE = 4096;  // Memory size (supports addresses up to 0x0FFF)

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
rv_cpu #(
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
    $dumpfile("cpu_tb.vcd");
    $dumpvars(0, cpu_tb);

    // ====================================
    // Load immediate (lui, addi)
    // ====================================

    $display("\n== Verify li (load immediate) works to load data into registers");
    $display("== Note: li is translated into lui rd imm, addi rd x0 imm");

    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "lui x2, 0x12345, addi x2, x2, 0x678: Load 0x12345678 into x2")
    // Loading 0x12345678 into x2
    // Instruction: lui x2, 0x12345 -> 0x12345137
    mock_mem.memory['h0000] = 8'h37;
    mock_mem.memory['h0001] = 8'h51;
    mock_mem.memory['h0002] = 8'h34;
    mock_mem.memory['h0003] = 8'h12;

    // Instruction: addi x2, x2, 0x678 -> 0x67810113
    mock_mem.memory['h0004] = 8'h13;
    mock_mem.memory['h0005] = 8'h01;
    mock_mem.memory['h0006] = 8'h81;
    mock_mem.memory['h0007] = 8'h67;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h0008] = 8'h6F;
    mock_mem.memory['h0009] = 8'h00;
    mock_mem.memory['h000A] = 8'h00;
    mock_mem.memory['h000B] = 8'h00;

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

    `TEST("rv_cpu", "lb x2, 0x11(x0): Load byte x2 with 0x56 (positive) from address 0x0011(x0)")
    // Instruction: lb x2, 0x11(x0) -> 0x01100103
    mock_mem.memory['h0000] = 8'h03;
    mock_mem.memory['h0001] = 8'h01;
    mock_mem.memory['h0002] = 8'h10; 
    mock_mem.memory['h0003] = 8'h01;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h0004] = 8'h6F;
    mock_mem.memory['h0005] = 8'h00;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h00;

    // Data at address 0x0011: 0x56
    mock_mem.memory['h0011] = 8'h56;

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

    `TEST("rv_cpu", "lb x3, 0x12(x0): Load byte x3 with 0xF6 (negative) from address 0x0012(x0)")
    // Instruction: lb x3, 0x12(x0) -> 0x01200183
    mock_mem.memory['h0000] = 8'h83;
    mock_mem.memory['h0001] = 8'h01;
    mock_mem.memory['h0002] = 8'h20;
    mock_mem.memory['h0003] = 8'h01;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h000C] = 8'h6F;
    mock_mem.memory['h000D] = 8'h00;
    mock_mem.memory['h000E] = 8'h00;
    mock_mem.memory['h000F] = 8'h00;

    // Data at address 0x0012: 0xF6
    mock_mem.memory['h0012] = 8'hF6;

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

    `TEST("rv_cpu", "lbu x2, 0x11(x0): Load byte x2 with 0xF6 from address 0x0011(x0)")
    // Instruction: lbu x2, 0x11(x0) -> 0x01104103
    mock_mem.memory['h0000] = 8'h03;
    mock_mem.memory['h0001] = 8'h41;
    mock_mem.memory['h0002] = 8'h10;
    mock_mem.memory['h0003] = 8'h01;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h0004] = 8'h6F;
    mock_mem.memory['h0005] = 8'h00;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h00;

    // Data at address 0x0011: 0x56
    mock_mem.memory['h0011] = 8'hF6;

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

    `TEST("rv_cpu", "lh x3, 0x10(x0): Load half-word x3 with 0x5678 from address 0x0010(x0)")
    // Instruction: lh x3, 0x10(x0) -> 0x01001183
    mock_mem.memory['h0000] = 8'h83;
    mock_mem.memory['h0001] = 8'h11;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h01;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h0004] = 8'h6F;
    mock_mem.memory['h0005] = 8'h00;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h00;

    // Data at address 0x0010: 0x5678 (little endian: 0x78, 0x56)
    mock_mem.memory['h0010] = 8'h78;
    mock_mem.memory['h0011] = 8'h56;

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

    `TEST("rv_cpu", "lhu x3, 0x10(x0): Load half-word x3 with 0x5678 from address 0x0010(x0)")
    // Instruction: lhu x3, 0x10(x0) -> 0x01005183
    mock_mem.memory['h0000] = 8'h83;
    mock_mem.memory['h0001] = 8'h51;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h01;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h0004] = 8'h6F;
    mock_mem.memory['h0005] = 8'h00;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h00;

    // Data at address 0x0010: 0x5678 (little endian: 0x78, 0x56)
    mock_mem.memory['h0010] = 8'h78; 
    mock_mem.memory['h0011] = 8'h56;

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

    `TEST("rv_cpu", "lw x1, 0x10(x0): Load x1 with 0x12345678 from address 0x0010(x0)")
    // Instruction: lw x1, 0x10(x0) -> 0x01002083
    mock_mem.memory['h0000] = 8'h83;
    mock_mem.memory['h0001] = 8'h20;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h01;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h0004] = 8'h6F;
    mock_mem.memory['h0005] = 8'h00;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h00;

    // Data at address 0x0010: 0x12345678
    mock_mem.memory['h0010] = 8'h78;
    mock_mem.memory['h0011] = 8'h56;
    mock_mem.memory['h0012] = 8'h34;
    mock_mem.memory['h0013] = 8'h12;

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

    `TEST("rv_cpu", "sb x2, 0(x1): Store a byte from x2 into the memory address stored in x1")
    // Loading 0x00000050 into x1
    // Instruction: addi x1, x0 0x50 -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // Loading 0x12345678 into x2
    // Instruction: lui x2, 0x12345 -> 0x12345137
    mock_mem.memory['h0004] = 8'h37;
    mock_mem.memory['h0005] = 8'h51;
    mock_mem.memory['h0006] = 8'h34;
    mock_mem.memory['h0007] = 8'h12;

    // Instruction: addi x2, x2, 0x678 -> 0x67810113
    mock_mem.memory['h0008] = 8'h13;
    mock_mem.memory['h0009] = 8'h01;
    mock_mem.memory['h000A] = 8'h81;
    mock_mem.memory['h000B] = 8'h67;

    // Instruction: sb x2, 0(x1) -> 0x00208023
    mock_mem.memory['h000C] = 8'h23;
    mock_mem.memory['h000D] = 8'h80;
    mock_mem.memory['h000E] = 8'h20; 
    mock_mem.memory['h000F] = 8'h00;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // Known values in store locations
    mock_mem.memory['h0050] = 8'hAA;
    mock_mem.memory['h0051] = 8'hBB;
    mock_mem.memory['h0052] = 8'hCC;
    mock_mem.memory['h0053] = 8'hDD;

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x1 register with test data", cpu_x1, 32'h00000050)
    `EXPECT("Verify x2 register with test data", cpu_x2, 32'h12345678)
    `EXPECT("Verify memory at 0x00000050 has byte 0x78", mock_mem.memory['h0050], 8'h78)
    `EXPECT("Verify memory at 0x00000051 has byte 0xAA", mock_mem.memory['h0051], 8'hBB)
    `EXPECT("Verify memory at 0x00000052 has byte 0xBB", mock_mem.memory['h0052], 8'hCC)
    `EXPECT("Verify memory at 0x00000053 has byte 0xCC", mock_mem.memory['h0053], 8'hDD)


    // ----------------------------
    // Store Half-Word (SH)
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "sb x2, 0(x1): Store a half-word from x2 into the memory address stored in x1")
    // Loading 0x00000050 into x1
    // Instruction: addi x1, x0 0x50 -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // Loading 0x12345678 into x2
    // Instruction: lui x2, 0x12345 -> 0x12345137
    mock_mem.memory['h0004] = 8'h37;
    mock_mem.memory['h0005] = 8'h51;
    mock_mem.memory['h0006] = 8'h34;
    mock_mem.memory['h0007] = 8'h12;

    // Instruction: addi x2, x2, 0x678 -> 0x67810113
    mock_mem.memory['h0008] = 8'h13;
    mock_mem.memory['h0009] = 8'h01;
    mock_mem.memory['h000A] = 8'h81;
    mock_mem.memory['h000B] = 8'h67;

    // Instruction: sb x2, 0(x1) -> 0x00209023
    mock_mem.memory['h000C] = 8'h23;
    mock_mem.memory['h000D] = 8'h90;
    mock_mem.memory['h000E] = 8'h20; 
    mock_mem.memory['h000F] = 8'h00;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // Known values in store locations
    mock_mem.memory['h0050] = 8'hAA;
    mock_mem.memory['h0051] = 8'hBB;
    mock_mem.memory['h0052] = 8'hCC;
    mock_mem.memory['h0053] = 8'hDD;

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x1 register with test data", cpu_x1, 32'h00000050)
    `EXPECT("Verify x2 register with test data", cpu_x2, 32'h12345678)
    `EXPECT("Verify memory at 0x00000050 has byte 0x78", mock_mem.memory['h0050], 8'h78)
    `EXPECT("Verify memory at 0x00000051 has byte 0x56", mock_mem.memory['h0051], 8'h56)
    `EXPECT("Verify memory at 0x00000052 has byte 0xCC", mock_mem.memory['h0052], 8'hCC)
    `EXPECT("Verify memory at 0x00000053 has byte 0xDD", mock_mem.memory['h0053], 8'hDD)


    // ----------------------------
    // Store Word (SW)
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "sb x2, 0(x1): Store a word from x2 into the memory address stored in x1")
    // Loading 0x00000050 into x1
    // Instruction: addi x1, x0 0x50 -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // Loading 0x12345678 into x2
    // Instruction: lui x2, 0x12345 -> 0x12345137
    mock_mem.memory['h0004] = 8'h37;
    mock_mem.memory['h0005] = 8'h51;
    mock_mem.memory['h0006] = 8'h34;
    mock_mem.memory['h0007] = 8'h12;

    // Instruction: addi x2, x2, 0x678 -> 0x67810113
    mock_mem.memory['h0008] = 8'h13;
    mock_mem.memory['h0009] = 8'h01;
    mock_mem.memory['h000A] = 8'h81;
    mock_mem.memory['h000B] = 8'h67;

    // Instruction: sb x2, 0(x1) -> 0x0020A023
    mock_mem.memory['h000C] = 8'h23;
    mock_mem.memory['h000D] = 8'hA0;
    mock_mem.memory['h000E] = 8'h20; 
    mock_mem.memory['h000F] = 8'h00;

    // Instruction: jal x0, 0 -> 0x0000006F (to halt)
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // Known values in store locations
    mock_mem.memory['h0050] = 8'hAA;
    mock_mem.memory['h0051] = 8'hBB;
    mock_mem.memory['h0052] = 8'hCC;
    mock_mem.memory['h0053] = 8'hDD;

    @(posedge clk);
    reset = 0;
    wait (cpu_halt == 1 || cpu_trap == 1);

    `EXPECT("Verify x1 register with test data", cpu_x1, 32'h00000050)
    `EXPECT("Verify x2 register with test data", cpu_x2, 32'h12345678)
    `EXPECT("Verify memory at 0x00000050 has byte 0x78", mock_mem.memory['h0050], 8'h78)
    `EXPECT("Verify memory at 0x00000051 has byte 0x56", mock_mem.memory['h0051], 8'h56)
    `EXPECT("Verify memory at 0x00000052 has byte 0x56", mock_mem.memory['h0052], 8'h34)
    `EXPECT("Verify memory at 0x00000053 has byte 0x56", mock_mem.memory['h0053], 8'h12)

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

    `TEST("rv_cpu", "BEQ taken when x1 == x2")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.memory['h0004] = 8'h13;
    mock_mem.memory['h0005] = 8'h01;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h05;

    // BNE x1, x2, +12     -> 0x00208663
    mock_mem.memory['h0008] = 8'h63;
    mock_mem.memory['h0009] = 8'h86;
    mock_mem.memory['h000A] = 8'h20;
    mock_mem.memory['h000B] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h000C] = 8'h93;
    mock_mem.memory['h000D] = 8'h01;
    mock_mem.memory['h000E] = 8'h10;
    mock_mem.memory['h000F] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0014] = 8'h93;
    mock_mem.memory['h0015] = 8'h01;
    mock_mem.memory['h0016] = 8'h20;
    mock_mem.memory['h0017] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0018] = 8'h6F;
    mock_mem.memory['h0019] = 8'h00;
    mock_mem.memory['h001A] = 8'h00;
    mock_mem.memory['h001B] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BEQ Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BEQ not taken when x1 != x2")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // addi x2, x0, 0x51   -> 0x01000113
    mock_mem.memory['h0004] = 8'h13;
    mock_mem.memory['h0005] = 8'h01;
    mock_mem.memory['h0006] = 8'h10;
    mock_mem.memory['h0007] = 8'h05;

    // BNE x1, x2, +12     -> 0x00208663
    mock_mem.memory['h0008] = 8'h63;
    mock_mem.memory['h0009] = 8'h86;
    mock_mem.memory['h000A] = 8'h20;
    mock_mem.memory['h000B] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h000C] = 8'h93;
    mock_mem.memory['h000D] = 8'h01;
    mock_mem.memory['h000E] = 8'h10;
    mock_mem.memory['h000F] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0014] = 8'h93;
    mock_mem.memory['h0015] = 8'h01;
    mock_mem.memory['h0016] = 8'h20;
    mock_mem.memory['h0017] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0018] = 8'h6F;
    mock_mem.memory['h0019] = 8'h00;
    mock_mem.memory['h001A] = 8'h00;
    mock_mem.memory['h001B] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BNE Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BNE not taken when x1 == x2")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // addi x2, x0, 0x51   -> 0x05000093
    mock_mem.memory['h0004] = 8'h13;
    mock_mem.memory['h0005] = 8'h01;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h05;

    // BNE x1, x2, +12     -> 0x00209663
    mock_mem.memory['h0008] = 8'h63;
    mock_mem.memory['h0009] = 8'h96;
    mock_mem.memory['h000A] = 8'h20;
    mock_mem.memory['h000B] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h000C] = 8'h93;
    mock_mem.memory['h000D] = 8'h01;
    mock_mem.memory['h000E] = 8'h10;
    mock_mem.memory['h000F] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0014] = 8'h93;
    mock_mem.memory['h0015] = 8'h01;
    mock_mem.memory['h0016] = 8'h20;
    mock_mem.memory['h0017] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0018] = 8'h6F;
    mock_mem.memory['h0019] = 8'h00;
    mock_mem.memory['h001A] = 8'h00;
    mock_mem.memory['h001B] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)


    // ----------------------------
    // BNE Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BNE taken when x1 != x2")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // addi x2, x0, 0x51   -> 0x05100113
    mock_mem.memory['h0004] = 8'h13;
    mock_mem.memory['h0005] = 8'h01;
    mock_mem.memory['h0006] = 8'h10;
    mock_mem.memory['h0007] = 8'h05;

    // BNE x1, x2, +12     -> 0x00209663
    mock_mem.memory['h0008] = 8'h63;
    mock_mem.memory['h0009] = 8'h96;
    mock_mem.memory['h000A] = 8'h20;
    mock_mem.memory['h000B] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h000C] = 8'h93;
    mock_mem.memory['h000D] = 8'h01;
    mock_mem.memory['h000E] = 8'h10;
    mock_mem.memory['h000F] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0014] = 8'h93;
    mock_mem.memory['h0015] = 8'h01;
    mock_mem.memory['h0016] = 8'h20;
    mock_mem.memory['h0017] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0018] = 8'h6F;
    mock_mem.memory['h0019] = 8'h00;
    mock_mem.memory['h001A] = 8'h00;
    mock_mem.memory['h001B] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BLT Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BLT not taken when x1 == x2")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // addi x2, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0004] = 8'h13;
    mock_mem.memory['h0005] = 8'h00;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h05;

    // BLT x1, x2, +12     -> 0x0020C663
    mock_mem.memory['h0008] = 8'h63;
    mock_mem.memory['h0009] = 8'hC6;
    mock_mem.memory['h000A] = 8'h20;
    mock_mem.memory['h000B] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h000C] = 8'h93;
    mock_mem.memory['h000D] = 8'h01;
    mock_mem.memory['h000E] = 8'h10;
    mock_mem.memory['h000F] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0014] = 8'h93;
    mock_mem.memory['h0015] = 8'h01;
    mock_mem.memory['h0016] = 8'h20;
    mock_mem.memory['h0017] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0018] = 8'h6F;
    mock_mem.memory['h0019] = 8'h00;
    mock_mem.memory['h001A] = 8'h00;
    mock_mem.memory['h001B] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BLT Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BLT not taken when x1 > x2 (x2 signed)")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // lui x2, 0xFFFFF   -> 0xFFFFF137
    mock_mem.memory['h0004] = 8'h37;
    mock_mem.memory['h0005] = 8'hF1;
    mock_mem.memory['h0006] = 8'hFF;
    mock_mem.memory['h0007] = 8'hFF;

    // addi x2, x2, -20   -> 0xFEC10113
    mock_mem.memory['h0008] = 8'h13;
    mock_mem.memory['h0009] = 8'h01;
    mock_mem.memory['h000A] = 8'hC1;
    mock_mem.memory['h000B] = 8'hFE;

    // BLT x1, x2, +12     -> 0x0020C663
    mock_mem.memory['h000C] = 8'h63;
    mock_mem.memory['h000D] = 8'hC6;
    mock_mem.memory['h000E] = 8'h20;
    mock_mem.memory['h000F] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h0010] = 8'h93;
    mock_mem.memory['h0011] = 8'h01;
    mock_mem.memory['h0012] = 8'h10;
    mock_mem.memory['h0013] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0014] = 8'h6F;
    mock_mem.memory['h0015] = 8'h00;
    mock_mem.memory['h0016] = 8'h00;
    mock_mem.memory['h0017] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0018] = 8'h93;
    mock_mem.memory['h0019] = 8'h01;
    mock_mem.memory['h001A] = 8'h20;
    mock_mem.memory['h001B] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h001C] = 8'h6F;
    mock_mem.memory['h001D] = 8'h00;
    mock_mem.memory['h001E] = 8'h00;
    mock_mem.memory['h001F] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BLT Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BLT taken when x1 < x2 (x1 signed)")

    // Load Instructions
    // lui x1, 0xFFFFF   -> 0xFFFFF0B7
    mock_mem.memory['h0004] = 8'hB7;
    mock_mem.memory['h0005] = 8'hF0;
    mock_mem.memory['h0006] = 8'hFF;
    mock_mem.memory['h0007] = 8'hFF;

    // addi x1, x1, -20   -> 0xFEC08093
    mock_mem.memory['h0008] = 8'h93;
    mock_mem.memory['h0009] = 8'h80;
    mock_mem.memory['h000A] = 8'hC0;
    mock_mem.memory['h000B] = 8'hFE;

    // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.memory['h0000] = 8'h13;
    mock_mem.memory['h0001] = 8'h01;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // BLT x1, x2, +12     -> 0x0020C663
    mock_mem.memory['h000C] = 8'h63;
    mock_mem.memory['h000D] = 8'hC6;
    mock_mem.memory['h000E] = 8'h20;
    mock_mem.memory['h000F] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h0010] = 8'h93;
    mock_mem.memory['h0011] = 8'h01;
    mock_mem.memory['h0012] = 8'h10;
    mock_mem.memory['h0013] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0014] = 8'h6F;
    mock_mem.memory['h0015] = 8'h00;
    mock_mem.memory['h0016] = 8'h00;
    mock_mem.memory['h0017] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0018] = 8'h93;
    mock_mem.memory['h0019] = 8'h01;
    mock_mem.memory['h001A] = 8'h20;
    mock_mem.memory['h001B] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h001C] = 8'h6F;
    mock_mem.memory['h001D] = 8'h00;
    mock_mem.memory['h001E] = 8'h00;
    mock_mem.memory['h001F] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BLTU Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BLTU not taken when x1 == x2")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // addi x2, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0004] = 8'h13;
    mock_mem.memory['h0005] = 8'h00;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h05;

    // BLTU x1, x2, +12    -> 0x0020E663
    mock_mem.memory['h0008] = 8'h63;
    mock_mem.memory['h0009] = 8'he6;
    mock_mem.memory['h000A] = 8'h20;
    mock_mem.memory['h000B] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h000C] = 8'h93;
    mock_mem.memory['h000D] = 8'h01;
    mock_mem.memory['h000E] = 8'h10;
    mock_mem.memory['h000F] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0014] = 8'h93;
    mock_mem.memory['h0015] = 8'h01;
    mock_mem.memory['h0016] = 8'h20;
    mock_mem.memory['h0017] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0018] = 8'h6F;
    mock_mem.memory['h0019] = 8'h00;
    mock_mem.memory['h001A] = 8'h00;
    mock_mem.memory['h001B] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BLTU Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BLTU taken when x1 < x2 (x2 unsigned)")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // lui x2, 0xFFFFF   -> 0xFFFFF137
    mock_mem.memory['h0004] = 8'h37;
    mock_mem.memory['h0005] = 8'hF1;
    mock_mem.memory['h0006] = 8'hFF;
    mock_mem.memory['h0007] = 8'hFF;

    // addi x2, x2, -20   -> 0xFEC10113
    mock_mem.memory['h0008] = 8'h13;
    mock_mem.memory['h0009] = 8'h01;
    mock_mem.memory['h000A] = 8'hC1;
    mock_mem.memory['h000B] = 8'hFE;

    // BLTU x1, x2, +12    -> 0x0020E663
    mock_mem.memory['h000C] = 8'h63;
    mock_mem.memory['h000D] = 8'he6;
    mock_mem.memory['h000E] = 8'h20;
    mock_mem.memory['h000F] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h0010] = 8'h93;
    mock_mem.memory['h0011] = 8'h01;
    mock_mem.memory['h0012] = 8'h10;
    mock_mem.memory['h0013] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0014] = 8'h6F;
    mock_mem.memory['h0015] = 8'h00;
    mock_mem.memory['h0016] = 8'h00;
    mock_mem.memory['h0017] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0018] = 8'h93;
    mock_mem.memory['h0019] = 8'h01;
    mock_mem.memory['h001A] = 8'h20;
    mock_mem.memory['h001B] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h001C] = 8'h6F;
    mock_mem.memory['h001D] = 8'h00;
    mock_mem.memory['h001E] = 8'h00;
    mock_mem.memory['h001F] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BLTU Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BLTU not taken when x1 > x2 (x1 unsigned)")

    // Load Instructions
    // lui x1, 0xFFFFF   -> 0xFFFFF0B7
    mock_mem.memory['h0004] = 8'hB7;
    mock_mem.memory['h0005] = 8'hF0;
    mock_mem.memory['h0006] = 8'hFF;
    mock_mem.memory['h0007] = 8'hFF;

    // addi x1, x1, -20   -> 0xFEC08093
    mock_mem.memory['h0008] = 8'h93;
    mock_mem.memory['h0009] = 8'h80;
    mock_mem.memory['h000A] = 8'hC0;
    mock_mem.memory['h000B] = 8'hFE;

    // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.memory['h0000] = 8'h13;
    mock_mem.memory['h0001] = 8'h01;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // BLTU x1, x2, +12    -> 0x0020E663
    mock_mem.memory['h000C] = 8'h63;
    mock_mem.memory['h000D] = 8'hE6;
    mock_mem.memory['h000E] = 8'h20;
    mock_mem.memory['h000F] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h0010] = 8'h93;
    mock_mem.memory['h0011] = 8'h01;
    mock_mem.memory['h0012] = 8'h10;
    mock_mem.memory['h0013] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0014] = 8'h6F;
    mock_mem.memory['h0015] = 8'h00;
    mock_mem.memory['h0016] = 8'h00;
    mock_mem.memory['h0017] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0018] = 8'h93;
    mock_mem.memory['h0019] = 8'h01;
    mock_mem.memory['h001A] = 8'h20;
    mock_mem.memory['h001B] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h001C] = 8'h6F;
    mock_mem.memory['h001D] = 8'h00;
    mock_mem.memory['h001E] = 8'h00;
    mock_mem.memory['h001F] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 2 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BGE Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BGE taken when x1 == x2")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // addi x2, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0004] = 8'h13;
    mock_mem.memory['h0005] = 8'h00;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h05;

    // BLT x1, x2, +12     -> 0x0020D663
    mock_mem.memory['h0008] = 8'h63;
    mock_mem.memory['h0009] = 8'hD6;
    mock_mem.memory['h000A] = 8'h20;
    mock_mem.memory['h000B] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h000C] = 8'h93;
    mock_mem.memory['h000D] = 8'h01;
    mock_mem.memory['h000E] = 8'h10;
    mock_mem.memory['h000F] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0014] = 8'h93;
    mock_mem.memory['h0015] = 8'h01;
    mock_mem.memory['h0016] = 8'h20;
    mock_mem.memory['h0017] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0018] = 8'h6F;
    mock_mem.memory['h0019] = 8'h00;
    mock_mem.memory['h001A] = 8'h00;
    mock_mem.memory['h001B] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BGE Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BGE taken when x1 > x2 (x2 signed)")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // lui x2, 0xFFFFF   -> 0xFFFFF137
    mock_mem.memory['h0004] = 8'h37;
    mock_mem.memory['h0005] = 8'hF1;
    mock_mem.memory['h0006] = 8'hFF;
    mock_mem.memory['h0007] = 8'hFF;

    // addi x2, x2, -20   -> 0xFEC10113
    mock_mem.memory['h0008] = 8'h13;
    mock_mem.memory['h0009] = 8'h01;
    mock_mem.memory['h000A] = 8'hC1;
    mock_mem.memory['h000B] = 8'hFE;

    // BLT x1, x2, +12     -> 0x0020D663
    mock_mem.memory['h000C] = 8'h63;
    mock_mem.memory['h000D] = 8'hD6;
    mock_mem.memory['h000E] = 8'h20;
    mock_mem.memory['h000F] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h0010] = 8'h93;
    mock_mem.memory['h0011] = 8'h01;
    mock_mem.memory['h0012] = 8'h10;
    mock_mem.memory['h0013] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0014] = 8'h6F;
    mock_mem.memory['h0015] = 8'h00;
    mock_mem.memory['h0016] = 8'h00;
    mock_mem.memory['h0017] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0018] = 8'h93;
    mock_mem.memory['h0019] = 8'h01;
    mock_mem.memory['h001A] = 8'h20;
    mock_mem.memory['h001B] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h001C] = 8'h6F;
    mock_mem.memory['h001D] = 8'h00;
    mock_mem.memory['h001E] = 8'h00;
    mock_mem.memory['h001F] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BGE Not Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BGE not taken when x1 < x2 (x1 signed)")

    // Load Instructions
    // lui x1, 0xFFFFF   -> 0xFFFFF0B7
    mock_mem.memory['h0004] = 8'hB7;
    mock_mem.memory['h0005] = 8'hF0;
    mock_mem.memory['h0006] = 8'hFF;
    mock_mem.memory['h0007] = 8'hFF;

    // addi x1, x1, -20   -> 0xFEC08093
    mock_mem.memory['h0008] = 8'h93;
    mock_mem.memory['h0009] = 8'h80;
    mock_mem.memory['h000A] = 8'hC0;
    mock_mem.memory['h000B] = 8'hFE;

    // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.memory['h0000] = 8'h13;
    mock_mem.memory['h0001] = 8'h01;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // BLT x1, x2, +12     -> 0x0020D663
    mock_mem.memory['h000C] = 8'h63;
    mock_mem.memory['h000D] = 8'hD6;
    mock_mem.memory['h000E] = 8'h20;
    mock_mem.memory['h000F] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h0010] = 8'h93;
    mock_mem.memory['h0011] = 8'h01;
    mock_mem.memory['h0012] = 8'h10;
    mock_mem.memory['h0013] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0014] = 8'h6F;
    mock_mem.memory['h0015] = 8'h00;
    mock_mem.memory['h0016] = 8'h00;
    mock_mem.memory['h0017] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0018] = 8'h93;
    mock_mem.memory['h0019] = 8'h01;
    mock_mem.memory['h001A] = 8'h20;
    mock_mem.memory['h001B] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h001C] = 8'h6F;
    mock_mem.memory['h001D] = 8'h00;
    mock_mem.memory['h001E] = 8'h00;
    mock_mem.memory['h001F] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 2 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BGEU Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BLTU taken when x1 == x2")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // addi x2, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0004] = 8'h13;
    mock_mem.memory['h0005] = 8'h00;
    mock_mem.memory['h0006] = 8'h00;
    mock_mem.memory['h0007] = 8'h05;

    // BGEU x1, x2, +12    -> 0x0020F663
    mock_mem.memory['h0008] = 8'h63;
    mock_mem.memory['h0009] = 8'hF6;
    mock_mem.memory['h000A] = 8'h20;
    mock_mem.memory['h000B] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h000C] = 8'h93;
    mock_mem.memory['h000D] = 8'h01;
    mock_mem.memory['h000E] = 8'h10;
    mock_mem.memory['h000F] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0010] = 8'h6F;
    mock_mem.memory['h0011] = 8'h00;
    mock_mem.memory['h0012] = 8'h00;
    mock_mem.memory['h0013] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0014] = 8'h93;
    mock_mem.memory['h0015] = 8'h01;
    mock_mem.memory['h0016] = 8'h20;
    mock_mem.memory['h0017] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0018] = 8'h6F;
    mock_mem.memory['h0019] = 8'h00;
    mock_mem.memory['h001A] = 8'h00;
    mock_mem.memory['h001B] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ----------------------------
    // BLTU NOT Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BGEU taken when x1 < x2 (x2 unsigned)")

    // Load Instructions
    // addi x1, x0, 0x50   -> 0x05000093
    mock_mem.memory['h0000] = 8'h93;
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // lui x2, 0xFFFFF   -> 0xFFFFF137
    mock_mem.memory['h0004] = 8'h37;
    mock_mem.memory['h0005] = 8'hF1;
    mock_mem.memory['h0006] = 8'hFF;
    mock_mem.memory['h0007] = 8'hFF;

    // addi x2, x2, -20   -> 0xFEC10113
    mock_mem.memory['h0008] = 8'h13;
    mock_mem.memory['h0009] = 8'h01;
    mock_mem.memory['h000A] = 8'hC1;
    mock_mem.memory['h000B] = 8'hFE;

    // BGEU x1, x2, +12    -> 0x0020F663
    mock_mem.memory['h000C] = 8'h63;
    mock_mem.memory['h000D] = 8'hF6;
    mock_mem.memory['h000E] = 8'h20;
    mock_mem.memory['h000F] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h0010] = 8'h93;
    mock_mem.memory['h0011] = 8'h01;
    mock_mem.memory['h0012] = 8'h10;
    mock_mem.memory['h0013] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0014] = 8'h6F;
    mock_mem.memory['h0015] = 8'h00;
    mock_mem.memory['h0016] = 8'h00;
    mock_mem.memory['h0017] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0018] = 8'h93;
    mock_mem.memory['h0019] = 8'h01;
    mock_mem.memory['h001A] = 8'h20;
    mock_mem.memory['h001B] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h001C] = 8'h6F;
    mock_mem.memory['h001D] = 8'h00;
    mock_mem.memory['h001E] = 8'h00;
    mock_mem.memory['h001F] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 1 (branch not taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h01)

    // ----------------------------
    // BGEU Taken
    // ----------------------------
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "BGEU taken when x1 > x2 (x1 unsigned)")

    // Load Instructions
    // lui x1, 0xFFFFF   -> 0xFFFFF0B7
    mock_mem.memory['h0004] = 8'hB7;
    mock_mem.memory['h0005] = 8'hF0;
    mock_mem.memory['h0006] = 8'hFF;
    mock_mem.memory['h0007] = 8'hFF;

    // addi x1, x1, -20   -> 0xFEC08093
    mock_mem.memory['h0008] = 8'h93;
    mock_mem.memory['h0009] = 8'h80;
    mock_mem.memory['h000A] = 8'hC0;
    mock_mem.memory['h000B] = 8'hFE;

    // addi x2, x0, 0x50   -> 0x05000113
    mock_mem.memory['h0000] = 8'h13;
    mock_mem.memory['h0001] = 8'h01;
    mock_mem.memory['h0002] = 8'h00;
    mock_mem.memory['h0003] = 8'h05;

    // BGEU x1, x2, +12    -> 0x0020F663
    mock_mem.memory['h000C] = 8'h63;
    mock_mem.memory['h000D] = 8'hF6;
    mock_mem.memory['h000E] = 8'h20;
    mock_mem.memory['h000F] = 8'h00;

    // addi x3, x0, 1      -> 0x00100193
    mock_mem.memory['h0010] = 8'h93;
    mock_mem.memory['h0011] = 8'h01;
    mock_mem.memory['h0012] = 8'h10;
    mock_mem.memory['h0013] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h0014] = 8'h6F;
    mock_mem.memory['h0015] = 8'h00;
    mock_mem.memory['h0016] = 8'h00;
    mock_mem.memory['h0017] = 8'h00;

    // addi x3, x0, 2      -> 0x00200193 (Branch target)
    mock_mem.memory['h0018] = 8'h93;
    mock_mem.memory['h0019] = 8'h01;
    mock_mem.memory['h001A] = 8'h20;
    mock_mem.memory['h001B] = 8'h00;

    // jal x0, 0           -> 0x0000006F
    mock_mem.memory['h001C] = 8'h6F;
    mock_mem.memory['h001D] = 8'h00;
    mock_mem.memory['h001E] = 8'h00;
    mock_mem.memory['h001F] = 8'h00;

    @(posedge clk);
    reset = 0;
    #1000; // Wait sufficient time for instructions to execute

    // Expect x3 to be incremented by 2 (branch taken)
    `EXPECT("Verify x3 register", cpu_x3, 8'h02)

    // ====================================
    // Jump commands
    // ====================================
    $display("\n==\n== Verify jump instructions (jal, jalr, ret)\n==");

    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `TEST("rv_cpu", "Mini program - set the stack pointer, jump, make room on stack, store item on stack)")

    mock_mem.memory['h0000] = 8'h93; // addi x1,x0,1
    mock_mem.memory['h0001] = 8'h00;
    mock_mem.memory['h0002] = 8'h10;
    mock_mem.memory['h0003] = 8'h00;
    mock_mem.memory['h0004] = 8'h23; // sw x1,28(x2) 
    mock_mem.memory['h0005] = 8'h2E;
    mock_mem.memory['h0006] = 8'h11;
    mock_mem.memory['h0007] = 8'h00;
    mock_mem.memory['h0008] = 8'h6F; // jal x0, 0
    mock_mem.memory['h0009] = 8'h00;
    mock_mem.memory['h000A] = 8'h00;
    mock_mem.memory['h000B] = 8'h00;

    @(posedge clk);
    reset = 0;
    #500; // Wait sufficient time for instructions to execute

    `EXPECT("Verify x1 register", cpu_x1, 32'h0000_0001)
    `EXPECT("Verify memory 0x001C", mock_mem.memory['h001C], 8'h01)
    `EXPECT("Verify memory 0x001D", mock_mem.memory['h001D], 8'h00)
    `EXPECT("Verify memory 0x001E", mock_mem.memory['h001E], 8'h00)
    `EXPECT("Verify memory 0x001F", mock_mem.memory['h001F], 8'h00)

    `FINISH;
end

endmodule
