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
parameter NUM_OUTPUTS   = 4;
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
// Slave 3 (bios)
// ====================================

logic [XLEN-1:0] bios_base_address;
logic [XLEN-1:0] bios_size;
assign bios_base_address = 32'h8000_0000;
assign bios_size         = 32'h0000_FFFF;

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
// Instantiate the CPU
// ====================================
rv_cpu #(
    .MHARTID_VAL     (32'h0000_0000),
    .XLEN            (XLEN),
    .SID_WIDTH       (SID_WIDTH),
    .START_ADDRESS   (32'h0000_0000),
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
    .tl_a_valid    (bios_s_a_valid),
    .tl_a_ready    (bios_s_a_ready),
    .tl_a_opcode   (bios_s_a_opcode),
    .tl_a_param    (bios_s_a_param),
    .tl_a_size     (bios_s_a_size),
    .tl_a_source   (bios_s_a_source),
    .tl_a_address  (bios_s_a_address),
    .tl_a_mask     (bios_s_a_mask),
    .tl_a_data     (bios_s_a_data),

    // TileLink D Channel (Switch to Master)
    .tl_d_valid    (bios_s_d_valid),
    .tl_d_ready    (bios_s_d_ready),
    .tl_d_opcode   (bios_s_d_opcode),
    .tl_d_param    (bios_s_d_param),
    .tl_d_size     (bios_s_d_size),
    .tl_d_source   (bios_s_d_source),
    .tl_d_data     (bios_s_d_data),
    .tl_d_corrupt  (bios_s_d_corrupt),
    .tl_d_denied   (bios_s_d_denied),

    .test          (leds),
    .trap          ()
);

// ====================================
// Instantiate Bios
// ====================================
tl_ul_bios #(
    .XLEN       (XLEN),
    .SID_WIDTH  (SID_WIDTH)
) bios_inst (
    .clk            (clk),
    .reset          (reset),

    // TileLink A Channel
    .tl_a_valid     (bios_s_a_valid),
    .tl_a_ready     (bios_s_a_ready),
    .tl_a_opcode    (bios_s_a_opcode),           // 3 bits
    .tl_a_param     (bios_s_a_param),            // 3 bits
    .tl_a_size      (bios_s_a_size),             // 3 bits
    .tl_a_source    (bios_s_a_source),           // SID_WIDTH bits
    .tl_a_address   (bios_s_a_address),          // XLEN bits
    .tl_a_mask      (bios_s_a_mask),             // (XLEN/8) bits
    .tl_a_data      (bios_s_a_data),             // XLEN bits

    // TileLink D Channel
    .tl_d_valid     (bios_s_d_valid),
    .tl_d_ready     (bios_s_d_ready),
    .tl_d_opcode    (bios_s_d_opcode),           // 3 bits
    .tl_d_param     (bios_s_d_param),            // 2 bits
    .tl_d_size      (bios_s_d_size),             // 3 bits
    .tl_d_source    (bios_s_d_source),           // SID_WIDTH bits
    .tl_d_data      (bios_s_d_data),             // XLEN bits
    .tl_d_corrupt   (bios_s_d_corrupt),          // 1 bit
    .tl_d_denied    (bios_s_d_denied)            // 1 bit
);

endmodule
