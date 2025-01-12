`timescale 1ns / 1ps
`default_nettype none

`define DEBUG       // Needed for debug signals
// `define LOG_UNKNOWN_INST
// `define LOG_CPU
// `define LOG_MEM_INTERFACE
// `define LOG_REG
// `define LOG_MEMORY
// `define LOG_CLOCKED
// `define LOG_SWITCH
// `define LOG_UART
// `define LOG_CSR

// Include necessary modules
`include "src/cpu.sv"
`include "src/tl_switch.sv"
`include "src/tl_memory.sv"

module cpu_runner;

`ifndef XLEN
`define XLEN 32
`endif

// ====================================
// Parameters
// ====================================
parameter XLEN = `XLEN;
parameter SID_WIDTH = 2;           // Source ID length for TileLink

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

// CPU TileLink Signals
logic                   cpu_tl_a_valid;
logic                   cpu_tl_a_ready;
logic [2:0]             cpu_tl_a_opcode;
logic [2:0]             cpu_tl_a_param;
logic [2:0]             cpu_tl_a_size;
logic [SID_WIDTH-1:0]   cpu_tl_a_source;
logic [XLEN-1:0]        cpu_tl_a_address;
logic [XLEN/8-1:0]      cpu_tl_a_mask;
logic [XLEN-1:0]        cpu_tl_a_data;

logic                   cpu_tl_d_valid;
logic                   cpu_tl_d_ready;
logic [2:0]             cpu_tl_d_opcode;
logic [1:0]             cpu_tl_d_param;
logic [2:0]             cpu_tl_d_size;
logic [SID_WIDTH-1:0]   cpu_tl_d_source;
logic [XLEN-1:0]        cpu_tl_d_data;
logic                   cpu_tl_d_corrupt;
logic                   cpu_tl_d_denied;

logic                   dbg_halt;
logic                   trap;
logic [XLEN-1:0]        dbg_pc;

// Memory TileLink Signals
logic                   memory_s_a_valid;
logic                   memory_s_a_ready;
logic [2:0]             memory_s_a_opcode;
logic [2:0]             memory_s_a_param;
logic [2:0]             memory_s_a_size;
logic [SID_WIDTH-1:0]   memory_s_a_source;
logic [XLEN-1:0]        memory_s_a_address;
logic [XLEN/8-1:0]      memory_s_a_mask;
logic [XLEN-1:0]        memory_s_a_data;

logic                   memory_s_d_valid;
logic                   memory_s_d_ready;
logic [2:0]             memory_s_d_opcode;
logic [1:0]             memory_s_d_param;
logic [2:0]             memory_s_d_size;
logic [SID_WIDTH-1:0]   memory_s_d_source;
logic [XLEN-1:0]        memory_s_d_data;
logic                   memory_s_d_corrupt;
logic                   memory_s_d_denied;

logic [XLEN-1:0]        memory_base_address;
logic [XLEN-1:0]        memory_size;

assign memory_base_address = 'h0000_0000;
assign memory_size         = 65535;

// External signals
logic [0:0]             external_irq;
logic [0:0]             external_nmi;

// ====================================
// Instantiate the CPU (TileLink Master)
// ====================================
rv_cpu #(
    .XLEN(XLEN),
    .SID_WIDTH(SID_WIDTH),
    .START_ADDRESS(32'h0000_0000) // force start address to 0
) uut (
    .clk(clk),
    .reset(reset),

    `ifdef SUPPORT_ZICSR
    // No interrupts in this test
    .external_irq(external_irq),
    .external_nmi(external_nmi),
    `endif

    // TileLink A Channel
    .tl_a_valid   (cpu_tl_a_valid),
    .tl_a_ready   (cpu_tl_a_ready),
    .tl_a_opcode  (cpu_tl_a_opcode),
    .tl_a_param   (cpu_tl_a_param),
    .tl_a_size    (cpu_tl_a_size),
    .tl_a_source  (cpu_tl_a_source),
    .tl_a_address (cpu_tl_a_address),
    .tl_a_mask    (cpu_tl_a_mask),
    .tl_a_data    (cpu_tl_a_data),

    // TileLink D Channel
    .tl_d_valid   (cpu_tl_d_valid),
    .tl_d_ready   (cpu_tl_d_ready),
    .tl_d_opcode  (cpu_tl_d_opcode),
    .tl_d_param   (cpu_tl_d_param),
    .tl_d_size    (cpu_tl_d_size),
    .tl_d_source  (cpu_tl_d_source),
    .tl_d_data    (cpu_tl_d_data),
    .trap         (trap),

    // Debug Signals
    .dbg_pc(dbg_pc),
    .dbg_halt(dbg_halt)
);

// ====================================
// Instantiate the TileLink Switch
// ====================================
tl_switch #(
    .NUM_INPUTS    (1),
    .NUM_OUTPUTS   (1),
    .XLEN          (XLEN),
    .SID_WIDTH     (SID_WIDTH),
    .TRACK_DEPTH   (16)
) switch_inst (
    .clk        (clk),
    .reset      (reset),

    // ======================
    // TileLink A Channel - Masters (CPU)
    // ======================
    .a_valid    (cpu_tl_a_valid),
    .a_ready    (cpu_tl_a_ready),
    .a_opcode   (cpu_tl_a_opcode),
    .a_param    (cpu_tl_a_param),
    .a_size     (cpu_tl_a_size),
    .a_source   (cpu_tl_a_source),
    .a_address  (cpu_tl_a_address),
    .a_mask     (cpu_tl_a_mask),
    .a_data     (cpu_tl_a_data),

    // ======================
    // TileLink D Channel - Masters (CPU)
    // ======================
    .d_valid    (cpu_tl_d_valid),
    .d_ready    (cpu_tl_d_ready),
    .d_opcode   (cpu_tl_d_opcode),
    .d_param    (cpu_tl_d_param),
    .d_size     (cpu_tl_d_size),
    .d_source   (cpu_tl_d_source),
    .d_data     (cpu_tl_d_data),
    .d_corrupt  (cpu_tl_d_corrupt),
    .d_denied   (cpu_tl_d_denied),

    // ======================
    // A Channel - Slaves (Memory)
    // ======================
    .s_a_valid   ({ memory_s_a_valid   }),
    .s_a_ready   ({ memory_s_a_ready   }),
    .s_a_opcode  ({ memory_s_a_opcode  }),
    .s_a_param   ({ memory_s_a_param   }),
    .s_a_size    ({ memory_s_a_size    }),
    .s_a_source  ({ memory_s_a_source  }),
    .s_a_mask    ({ memory_s_a_mask    }),
    .s_a_address ({ memory_s_a_address }),
    .s_a_data    ({ memory_s_a_data    }),

    // ======================
    // D Channel - Slaves (Memory)
    // ======================
    .s_d_valid    ({ memory_s_d_valid   }),
    .s_d_ready    ({ memory_s_d_ready   }),
    .s_d_opcode   ({ memory_s_d_opcode  }),
    .s_d_param    ({ memory_s_d_param   }),
    .s_d_size     ({ memory_s_d_size    }),
    .s_d_source   ({ memory_s_d_source  }),
    .s_d_data     ({ memory_s_d_data    }),
    .s_d_corrupt  ({ memory_s_d_corrupt }),
    .s_d_denied   ({ memory_s_d_denied  }),

    // ======================
    // Base Addresses for Slaves
    // ======================
    .base_addr    ({ memory_base_address }),
    .addr_mask    ({ memory_size         })
);

// ====================================
// Instantiate Mock Memory
// ====================================
tl_memory #(
    .XLEN(XLEN),
    .SID_WIDTH(SID_WIDTH),
    .SIZE(65535)
) mock_mem (
    .clk        (clk),
    .reset      (reset),

    // TileLink A Channel
    .tl_a_valid   (memory_s_a_valid   ),
    .tl_a_ready   (memory_s_a_ready   ),
    .tl_a_opcode  (memory_s_a_opcode  ),
    .tl_a_param   (memory_s_a_param   ),
    .tl_a_size    (memory_s_a_size    ),
    .tl_a_source  (memory_s_a_source  ),
    .tl_a_address (memory_s_a_address ),
    .tl_a_mask    (memory_s_a_mask    ),
    .tl_a_data    (memory_s_a_data    ),

    // TileLink D Channel
    .tl_d_valid   (memory_s_d_valid   ),
    .tl_d_ready   (memory_s_d_ready   ),
    .tl_d_opcode  (memory_s_d_opcode  ),
    .tl_d_param   (memory_s_d_param   ),
    .tl_d_size    (memory_s_d_size    ),
    .tl_d_source  (memory_s_d_source  ),
    .tl_d_data    (memory_s_d_data    ),
    .tl_d_corrupt (memory_s_d_corrupt ),
    .tl_d_denied  (memory_s_d_denied  )
);

integer addr;

`define DISPLAY_MEM_RANGE_ARRAY(MEM, START_ADDR, END_ADDR) \
    for (addr = START_ADDR; addr <= END_ADDR; addr = addr + 16) begin \
        reg [7:0] bytes [0:15]; \
        integer i; \
        for (i = 0; i < 16; i = i + 1) begin \
            bytes[i] = MEM.memory[addr + i]; \
        end \
        $display("%04h : %02h %02h %02h %02h | %02h %02h %02h %02h | %02h %02h %02h %02h | %02h %02h %02h %02h", \
                    addr, bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], \
                    bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]); \
    end

// ====================================
// Clock Cycle Counter
// ====================================
integer cycle_count;

initial begin
    cycle_count = 0; // Initialize the cycle counter
end

always @(posedge clk) begin
    if (!reset) begin
        cycle_count <= cycle_count + 1;
    end
end

// ====================================
// Simulation Sequence
// ====================================
initial begin
    $dumpfile("cpu_runner.vcd");
    $dumpvars(0, cpu_runner);

    $display("Loading program...");
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    `include "etc/program.sv"

    @(posedge clk);
    $display("Program loaded...");

    reset = 0;
    $display("Running rv%0di%00s%00s%00s...", `XLEN,
    `ifdef SUPPORT_M "m" `else "" `endif,
    `ifdef SUPPORT_B "b" `else "" `endif,
    `ifdef SUPPORT_ZICSR "_zicsr" `else "" `endif);

    wait (dbg_halt == 1 || trap == 1);

    if(dbg_halt == 1) $display("Stop reason: HALT");
    if(trap == 1) $display("Stop reason: TRAP");
    $display("Number of clock cycles: %00d pc=0x%0h", cycle_count, dbg_pc);
    $display("Memory Contents from 0xFF00 to 0xFFFF:");
    $display("----------------------------------------------------------------");
    $display("            0  1  2  3 |  4  5  6  7 |  8  9  A  B |  C  D  E  F");
    $display("----------------------------------------------------------------");
    `DISPLAY_MEM_RANGE_ARRAY(mock_mem, 16'hFF00, 16'hFFFF);
    $display("----------------------------------------------------------------");

    $finish;
end

endmodule
