///////////////////////////////////////////////////////////////////////////////////////////////////
// p_soc Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module p_soc
 * @brief Top level module for the System-on-Chip.
 *
 */

`timescale 1ns / 1ps
`default_nettype none

// Include necessary modules
`include "p_cpu.sv"
`include "p_bios.sv"
`include "p_memory.sv"
`include "p_output.sv"
`include "p_switch.sv"
// `include "p_uart.sv"


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
parameter SOURCE_COUNT  = 1;
parameter TARGET_COUNT  = 4;
parameter CLK_FREQ_MHZ  = 27;

// ====================================
// LEDs
// ====================================
logic [5:0] leds;
assign LED   = ~leds;

// ====================================
// Clock and Reset
// ====================================

wire clk;
wire reset;

assign clk   = CLK;
assign reset = BTN_S1;

// ====================================
// Source 1 (CPU)
// ====================================

wire                  cpu_valid;   // Each source asserts valid when it has a request
wire                  cpu_rw;      // Read/Write signal from each source
wire [XLEN-1:0]       cpu_addr;    // Address from each source
wire [XLEN-1:0]       cpu_wdata;   // Write data from each source
wire [XLEN/8-1:0]     cpu_wstrb;   // Ready signal back to each source
wire [2:0]            cpu_size;    // Size of each request in log2(Bytes per beat)
wire                  cpu_ready;   // Ready signal back to each source
wire [XLEN-1:0]       cpu_rdata;   // Read data returned to each source
wire                  cpu_denied;  // Denied signal back to each source
wire                  cpu_corrupt; // Corrupt signal back to each source

// Other signals
wire [5:0]            test;
wire                  trap;

// ====================================
// Target 1 (memory)
// ====================================

wire                  mem_valid;   // Valid signal to each target
wire                  mem_rw;      // Read/Write signal to each target
wire [XLEN-1:0]       mem_addr;    // Address sent to each target
wire [XLEN-1:0]       mem_wdata;   // Write data sent to each target
wire [XLEN/8-1:0]     mem_wstrb;   // Write byte masks for request
wire [2:0]            mem_size;    // Size of each request in log2(Bytes per beat)
wire                  mem_ready;   // Asserts when work is completed
wire [XLEN-1:0]       mem_rdata;   // Read data from each target
wire                  mem_denied;  // Denied signal back to each source
wire                  mem_corrupt; // Corrupt signal back to each source

// ====================================
// Target 2 (bios)
// ====================================

wire                  bios_valid;   // Valid signal to each target
wire                  bios_rw;      // Read/Write signal to each target
wire [XLEN-1:0]       bios_addr;    // Address sent to each target
wire [XLEN-1:0]       bios_wdata;   // Write data sent to each target
wire [XLEN/8-1:0]     bios_wstrb;   // Write byte masks for request
wire [2:0]            bios_size;    // Size of each request in log2(Bytes per beat)
wire                  bios_ready;   // Asserts when work is completed
wire [XLEN-1:0]       bios_rdata;   // Read data from each target
wire                  bios_denied;  // Denied signal back to each source
wire                  bios_corrupt; // Corrupt signal back to each source

// ====================================
// Target 3 (outputs)
// ====================================

wire                  out_valid;   // Valid signal to each target
wire                  out_rw;      // Read/Write signal to each target
wire [XLEN-1:0]       out_addr;    // Address sent to each target
wire [XLEN-1:0]       out_wdata;   // Write data sent to each target
wire [XLEN/8-1:0]     out_wstrb;   // Write byte masks for request
wire [2:0]            out_size;    // Size of each request in log2(Bytes per beat)
wire                  out_ready;   // Asserts when work is completed
wire [XLEN-1:0]       out_rdata;   // Read data from each target
wire                  out_denied;  // Denied signal back to each source
wire                  out_corrupt; // Corrupt signal back to each source

// ====================================
// Target 4 (UART)
// ====================================

wire uart_irq;
wire uart_rx;
wire uart_tx;

wire                  uart_valid;   // Valid signal to each target
wire                  uart_rw;      // Read/Write signal to each target
wire [XLEN-1:0]       uart_addr;    // Address sent to each target
wire [XLEN-1:0]       uart_wdata;   // Write data sent to each target
wire [XLEN/8-1:0]     uart_wstrb;   // Write byte masks for request
wire [2:0]            uart_size;    // Size of each request in log2(Bytes per beat)
wire                  uart_ready;   // Asserts when work is completed
wire [XLEN-1:0]       uart_rdata;   // Read data from each target
wire                  uart_denied;  // Denied signal back to each source
wire                  uart_corrupt; // Corrupt signal back to each source


// ====================================
// Instantiate the Parallel Switch
// ====================================
p_switch #(
    .SOURCE_COUNT  (SOURCE_COUNT),
    .TARGET_COUNT  (TARGET_COUNT),
    .XLEN          (XLEN)
) switch_inst (
    .clk         (clk),
    .reset       (reset),

    // ====================================
    // Sources (CPU)
    // ====================================
    .src_valid   ({ cpu_valid   }),
    .src_rw      ({ cpu_rw      }),
    .src_addr    ({ cpu_addr    }),
    .src_wdata   ({ cpu_wdata   }),
    .src_wstrb   ({ cpu_wstrb   }),
    .src_size    ({ cpu_size    }),
    .src_ready   ({ cpu_ready   }),
    .src_rdata   ({ cpu_rdata   }),
    .src_denied  ({ cpu_denied  }),
    .src_corrupt ({ cpu_corrupt }),

    // ====================================
    // Targets (Memories / Peripherals) [index 0 is to the right]
    // ====================================
    .tgt_valid   ({ uart_valid,   out_valid,   bios_valid,   mem_valid   }),
    .tgt_rw      ({ uart_rw,      out_rw,      bios_rw,      mem_rw      }),
    .tgt_addr    ({ uart_addr,    out_addr,    bios_addr,    mem_addr    }),
    .tgt_wdata   ({ uart_wdata,   out_wdata,   bios_wdata,   mem_wdata   }),
    .tgt_wstrb   ({ uart_wstrb,   out_wstrb,   bios_wstrb,   mem_wstrb   }),
    .tgt_size    ({ uart_size,    out_size,    bios_size,    mem_size    }),
    .tgt_ready   ({ uart_ready,   out_ready,   bios_ready,   mem_ready   }),
    .tgt_rdata   ({ uart_rdata,   out_rdata,   bios_rdata,   mem_rdata   }),
    .tgt_denied  ({ uart_denied,  out_denied,  bios_denied,  mem_denied  }),
    .tgt_corrupt ({ uart_corrupt, out_corrupt, bios_corrupt, mem_corrupt })
);

// ====================================
// Instantiate the CPU
// ====================================
p_cpu #(
    .MHARTID_VAL     (32'h0000_0000),
    .XLEN            (XLEN),
    .START_ADDRESS   (32'h4000_0000),
    .MTVEC_RESET_VAL (32'h0000_0000),
    .NMI_COUNT       (1),
    .IRQ_COUNT       (1)
) cpu_inst (
    .clk          (clk),
    .reset        (reset),

    `ifdef SUPPORT_ZICSR
    .external_irq ({ uart_irq }),
    .external_nmi ({ 1'b0 }),
    `endif

    .bus_valid    (cpu_valid),
    .bus_rw       (cpu_rw),
    .bus_addr     (cpu_addr),
    .bus_wdata    (cpu_wdata),
    .bus_wstrb    (cpu_wstrb),
    .bus_size     (cpu_size),
    .bus_ready    (cpu_ready),
    .bus_rdata    (cpu_rdata),
    .bus_denied   (cpu_denied),
    .bus_corrupt  (cpu_corrupt),

    .test         (test),
    .trap         (trap)

    `ifdef DEBUG
    // Debug outputs
    ,.dbg_halt    (dbg_halt)
    ,.dbg_trap    (dbg_trap)
    ,.dbg_pc      (dbg_pc)
    ,.dbg_x1      ()
    ,.dbg_x2      ()
    ,.dbg_x3      ()
    `endif
);

// ====================================
// Instantiate Memory
// ====================================
p_memory #(
    .XLEN        (XLEN),
    .SIZE        (16'hFFF)
) memory_inst (
    .clk         (clk),
    .reset       (reset),

    .bus_valid   (mem_valid),
    .bus_rw      (mem_rw),
    .bus_addr    (mem_addr),
    .bus_wdata   (mem_wdata),
    .bus_wstrb   (mem_wstrb),
    .bus_size    (mem_size),
    .bus_ready   (mem_ready),
    .bus_rdata   (mem_rdata),
    .bus_denied  (mem_denied),
    .bus_corrupt (mem_corrupt)
);

// ====================================
// Instantiate Bios
// ====================================
p_bios #(
    .XLEN        (XLEN)
) bios_inst (
    .clk         (clk),
    .reset       (reset),

    .bus_valid   (bios_valid),
    .bus_rw      (bios_rw),
    .bus_addr    (bios_addr),
    .bus_wdata   (bios_wdata),
    .bus_wstrb   (bios_wstrb),
    .bus_size    (bios_size),
    .bus_ready   (bios_ready),
    .bus_rdata   (bios_rdata),
    .bus_denied  (bios_denied),
    .bus_corrupt (bios_corrupt)
);

// ====================================
// Instantiate Outputs
// ====================================
p_output #(
    .XLEN        (XLEN),
    .OUTPUTS     (6)
) output_inst (
    .clk         (clk),
    .reset       (reset),

    .outputs     (leds),

    .bus_valid   (out_valid),
    .bus_rw      (out_rw),
    .bus_addr    (out_addr),
    .bus_wdata   (out_wdata),
    .bus_wstrb   (out_wstrb),
    .bus_size    (out_size),
    .bus_ready   (out_ready),
    .bus_rdata   (out_rdata),
    .bus_denied  (out_denied),
    .bus_corrupt (out_corrupt)
);

// ====================================
// Instantiate UART
// ====================================
// p_uart #(
//     .XLEN          (XLEN),
//     .CLK_FREQ_MHZ  (CLK_FREQ_MHZ)
// ) uart_inst (
//     .clk         (clk),
//     .reset       (reset),

//     .bus_valid   (uart_valid),
//     .bus_rw      (uart_rw),
//     .bus_addr    (uart_addr),
//     .bus_wdata   (uart_wdata),
//     .bus_wstrb   (uart_wstrb),
//     .bus_size    (uart_size),
//     .bus_ready   (uart_ready),
//     .bus_rdata   (uart_rdata),
//     .bus_denied  (uart_denied),
//     .bus_corrupt (uart_corrupt),

//     // UART Interface
//     .rx          (uart_rx),     // Connect to testbench's rx_sim
//     .tx          (uart_tx),     // Connect to testbench's tx wire
//     .irq         (uart_irq)     // Connect to testbench's irq wire
// );

endmodule
