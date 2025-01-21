///////////////////////////////////////////////////////////////////////////////////////////////////
// soc Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module soc
 * @brief Top level module for the System-on-Chip.
 *
 */

`timescale 1ns / 1ps
`default_nettype none

// Include necessary modules
`include "src/cpu.sv"
`include "src/tl_switch.sv"
`include "src/tl_memory.sv"
`include "src/tl_ul_bios.sv"

`ifndef XLEN
`define XLEN 32
`endif

module top
(
    input        CLK,       // System Clock
    input        BTN_S1,    // Button for reset
    output [5:0] LED,       // LEDs
    input        UART_RX,   // Receive line
    output       UART_TX    // Transmit line
);

// ====================================
// Parameters
// ====================================
parameter XLEN          = 32;
parameter SID_WIDTH     = 8;
parameter NUM_INPUTS    = 1;
parameter NUM_OUTPUTS   = 2;
parameter TRACK_DEPTH   = 16;
parameter CLK_FREQ_MHZ  = 27;

// ====================================
// Clock and Reset
// ====================================

wire clk;
wire reset;

assign clk   = CLK;
assign reset = BTN_S1;

// ====================================
// LEDs
// ====================================
logic [5:0] leds;
assign LED   = ~leds;

// ====================================
// Master 1 (CPU)
// ====================================

// A Channel
wire                   cpu_tl_a_valid;
wire                   cpu_tl_a_ready;
wire [2:0]             cpu_tl_a_opcode;
wire [2:0]             cpu_tl_a_param;
wire [2:0]             cpu_tl_a_size;
wire [SID_WIDTH-1:0]   cpu_tl_a_source;
wire [XLEN-1:0]        cpu_tl_a_address;
wire [XLEN/8-1:0]      cpu_tl_a_mask;
wire [XLEN-1:0]        cpu_tl_a_data;

// D Channel
wire                   cpu_tl_d_valid;
wire                   cpu_tl_d_ready;
wire [2:0]             cpu_tl_d_opcode;
wire [1:0]             cpu_tl_d_param;
wire [2:0]             cpu_tl_d_size;
wire [SID_WIDTH-1:0]   cpu_tl_d_source;
wire [XLEN-1:0]        cpu_tl_d_data;
wire                   cpu_tl_d_corrupt;
wire                   cpu_tl_d_denied;

// ====================================
// Slave - memory
// ====================================

logic [XLEN-1:0]       memory_base_address;
logic [XLEN-1:0]       memory_size;
assign memory_base_address = 32'h0000_0000;
assign memory_size         = 32'h0000_FFFF;

// A Channel
wire                   memory_s_a_valid;
wire                   memory_s_a_ready;
wire [2:0]             memory_s_a_opcode;
wire [2:0]             memory_s_a_param;
wire [2:0]             memory_s_a_size;
wire [SID_WIDTH-1:0]   memory_s_a_source;
wire [XLEN/8-1:0]      memory_s_a_mask;
wire [XLEN-1:0]        memory_s_a_address;
wire [XLEN-1:0]        memory_s_a_data;

// D Channel
wire                   memory_s_d_valid;
wire                   memory_s_d_ready;
wire [2:0]             memory_s_d_opcode;
wire [1:0]             memory_s_d_param;
wire [2:0]             memory_s_d_size;
wire [SID_WIDTH-1:0]   memory_s_d_source;
wire [XLEN-1:0]        memory_s_d_data;
wire                   memory_s_d_corrupt;
wire                   memory_s_d_denied;

// ====================================
// Slave - bios
// ====================================

logic [XLEN-1:0] bios_base_address;
logic [XLEN-1:0] bios_size;
assign bios_base_address = 32'h8000_0000;
assign bios_size         = 32'h0000_00FF;

// A Channel
wire bios_s_a_valid;
wire bios_s_a_ready;
wire [2:0] bios_s_a_opcode;
wire [2:0] bios_s_a_param;
wire [2:0] bios_s_a_size;
wire [SID_WIDTH-1:0] bios_s_a_source;
wire [XLEN/8-1:0] bios_s_a_mask;
wire [XLEN-1:0] bios_s_a_address;
wire [XLEN-1:0] bios_s_a_data;

// D Channel
wire bios_s_d_valid;
wire bios_s_d_ready;
wire [2:0] bios_s_d_opcode;
wire [1:0] bios_s_d_param;
wire [2:0] bios_s_d_size;
wire [SID_WIDTH-1:0] bios_s_d_source;
wire [XLEN-1:0] bios_s_d_data;
wire bios_s_d_corrupt;
wire bios_s_d_denied;


// ====================================
// Instantiate the TileLink Switch
// ====================================
tl_switch #(
    .NUM_INPUTS    (NUM_INPUTS),
    .NUM_OUTPUTS   (NUM_OUTPUTS),
    .XLEN          (XLEN),
    .SID_WIDTH     (SID_WIDTH),
    .TRACK_DEPTH   (TRACK_DEPTH)
) switch_inst (
    .clk           (clk),
    .reset         (reset),

    // ======================
    // TileLink A Channel - Masters
    // ======================
    .a_valid     ({ cpu_tl_a_valid   }),
    .a_ready     ({ cpu_tl_a_ready   }),
    .a_opcode    ({ cpu_tl_a_opcode  }),
    .a_param     ({ cpu_tl_a_param   }),
    .a_size      ({ cpu_tl_a_size    }),
    .a_source    ({ cpu_tl_a_source  }),
    .a_address   ({ cpu_tl_a_address }),
    .a_mask      ({ cpu_tl_a_mask    }),
    .a_data      ({ cpu_tl_a_data    }),

    // ======================
    // TileLink D Channel - Masters
    // ======================
    .d_valid     ({ cpu_tl_d_valid   }),
    .d_ready     ({ cpu_tl_d_ready   }),
    .d_opcode    ({ cpu_tl_d_opcode  }),
    .d_param     ({ cpu_tl_d_param   }),
    .d_size      ({ cpu_tl_d_size    }),
    .d_source    ({ cpu_tl_d_source  }),
    .d_data      ({ cpu_tl_d_data    }),
    .d_corrupt   ({ cpu_tl_d_corrupt }),
    .d_denied    ({ cpu_tl_d_denied  }),

    // ======================
    // A Channel - Slaves
    // ======================
    .s_a_valid   ({ bios_s_a_valid    , memory_s_a_valid     }),
    .s_a_ready   ({ bios_s_a_ready    , memory_s_a_ready     }),
    .s_a_opcode  ({ bios_s_a_opcode   , memory_s_a_opcode    }),
    .s_a_param   ({ bios_s_a_param    , memory_s_a_param     }),
    .s_a_size    ({ bios_s_a_size     , memory_s_a_size      }),
    .s_a_source  ({ bios_s_a_source   , memory_s_a_source    }),
    .s_a_mask    ({ bios_s_a_mask     , memory_s_a_mask      }),
    .s_a_address ({ bios_s_a_address  , memory_s_a_address   }),
    .s_a_data    ({ bios_s_a_data     , memory_s_a_data      }),

    // ======================
    // D Channel - Slaves
    // ======================
    .s_d_valid   ({ bios_s_d_valid    , memory_s_d_valid     }),
    .s_d_ready   ({ bios_s_d_ready    , memory_s_d_ready     }),
    .s_d_opcode  ({ bios_s_d_opcode   , memory_s_d_opcode    }),
    .s_d_param   ({ bios_s_d_param    , memory_s_d_param     }),
    .s_d_size    ({ bios_s_d_size     , memory_s_d_size      }),
    .s_d_source  ({ bios_s_d_source   , memory_s_d_source    }),
    .s_d_data    ({ bios_s_d_data     , memory_s_d_data      }),
    .s_d_corrupt ({ bios_s_d_corrupt  , memory_s_d_corrupt   }),
    .s_d_denied  ({ bios_s_d_denied   , memory_s_d_denied    }),

    // ======================
    // Base Addresses for Slaves
    // ======================
    .base_addr   ({ bios_base_address , memory_base_address  }),
    .addr_mask   ({ bios_size         , memory_size          })
);

// ====================================
// Instantiate the CPU
// ====================================
rv_cpu #(
    .MHARTID_VAL     (32'h0000_0000),
    .XLEN            (XLEN),
    .SID_WIDTH       (SID_WIDTH),
    .START_ADDRESS   (32'h8000_0000),
    .MTVEC_RESET_VAL (32'h0000_0000),
    .NMI_COUNT       (1),
    .IRQ_COUNT       (1)
) cpu_inst (
    .clk        (clk),
    .reset      (reset),

    `ifdef SUPPORT_ZICSR
    .external_irq ({ uart_irq }),
    .external_nmi ({ 1'b0 }),
    `endif

    // TileLink A Channel (Master to Switch)
    .tl_a_valid    (cpu_tl_a_valid),
    .tl_a_ready    (cpu_tl_a_ready),
    .tl_a_opcode   (cpu_tl_a_opcode),
    .tl_a_param    (cpu_tl_a_param),
    .tl_a_size     (cpu_tl_a_size),
    .tl_a_source   (cpu_tl_a_source),
    .tl_a_address  (cpu_tl_a_address),
    .tl_a_mask     (cpu_tl_a_mask),
    .tl_a_data     (cpu_tl_a_data),

    // TileLink D Channel (Switch to Master)
    .tl_d_valid    (cpu_tl_d_valid),
    .tl_d_ready    (cpu_tl_d_ready),
    .tl_d_opcode   (cpu_tl_d_opcode),
    .tl_d_param    (cpu_tl_d_param),
    .tl_d_size     (cpu_tl_d_size),
    .tl_d_source   (cpu_tl_d_source),
    .tl_d_data     (cpu_tl_d_data),
    .tl_d_corrupt  (cpu_tl_d_corrupt),
    .tl_d_denied   (cpu_tl_d_denied),

    .test          (leds),
    .trap          ()
);

// ====================================
// Instantiate Memory 
// ====================================
tl_memory #(
    .XLEN           (XLEN),
    .SIZE           ('h10000),
    .SID_WIDTH      (SID_WIDTH)
) memory_inst (
    .clk            (clk),
    .reset          (reset),

    // TileLink A Channel
    .tl_a_valid     (memory_s_a_valid),
    .tl_a_ready     (memory_s_a_ready),
    .tl_a_opcode    (memory_s_a_opcode),
    .tl_a_param     (memory_s_a_param),
    .tl_a_size      (memory_s_a_size),
    .tl_a_source    (memory_s_a_source),
    .tl_a_address   (memory_s_a_address),
    .tl_a_mask      (memory_s_a_mask),
    .tl_a_data      (memory_s_a_data),

    // TileLink D Channel
    .tl_d_valid     (memory_s_d_valid),
    .tl_d_ready     (memory_s_d_ready),
    .tl_d_opcode    (memory_s_d_opcode),
    .tl_d_param     (memory_s_d_param),
    .tl_d_size      (memory_s_d_size),
    .tl_d_source    (memory_s_d_source),
    .tl_d_data      (memory_s_d_data),
    .tl_d_corrupt   (memory_s_d_corrupt),
    .tl_d_denied    (memory_s_d_denied)
);

// ====================================
// Instantiate Bios
// ====================================
tl_ul_bios #(
    .XLEN           (XLEN),
    .SID_WIDTH      (SID_WIDTH),
    .SIZE           ('h100)
) bios_inst (
    .clk            (clk),
    .reset          (reset),

    // TileLink A Channel
    .tl_a_valid     (bios_s_a_valid),
    .tl_a_ready     (bios_s_a_ready),
    .tl_a_opcode    (bios_s_a_opcode),
    .tl_a_param     (bios_s_a_param),
    .tl_a_size      (bios_s_a_size),
    .tl_a_source    (bios_s_a_source),
    .tl_a_address   (bios_s_a_address),
    .tl_a_mask      (bios_s_a_mask),
    .tl_a_data      (bios_s_a_data),

    // TileLink D Channel
    .tl_d_valid     (bios_s_d_valid),
    .tl_d_ready     (bios_s_d_ready),
    .tl_d_opcode    (bios_s_d_opcode),
    .tl_d_param     (bios_s_d_param),
    .tl_d_size      (bios_s_d_size),
    .tl_d_source    (bios_s_d_source),
    .tl_d_data      (bios_s_d_data),
    .tl_d_corrupt   (bios_s_d_corrupt),
    .tl_d_denied    (bios_s_d_denied)
);

endmodule
