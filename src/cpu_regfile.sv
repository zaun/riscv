///////////////////////////////////////////////////////////////////////////////////////////////////
// Register File Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module cpu_regfile
 * @brief Implements the general-purpose registers for the CPU.
 *
 * The `cpu_regfile` module provides XLEN general-purpose registers (x0 to xXLEN -1) as per the
 * RISC-V specification. Register x0 is hardwired to zero. It allows simultaneous reading of two
 * source registers and writing to a destination register.
 *
 * Features:
 * - Supports register reads and writes.
 * - Ensures x0 is always zero.
 *
 * Developers should be aware that:
 * - Writes to register x0 are ignored.
 */

`timescale 1ns / 1ps
`default_nettype none

`include "src/log.sv"

module cpu_regfile #(
    parameter XLEN = 32  // Data width: 32 or 64 bits
) (
    input  logic            clk,
    input  logic            reset,
    input  logic [4:0]      rs1_addr,
    input  logic [4:0]      rs2_addr,
    input  logic [4:0]      rd_addr,
    input  logic [XLEN-1:0] rd_data,
    input  logic            rd_write_en,
    output logic [XLEN-1:0] rs1_data,
    output logic [XLEN-1:0] rs2_data,

    // Debug output
    output logic [XLEN-1:0] dbg_x1,
    output logic [XLEN-1:0] dbg_x2,
    output logic [XLEN-1:0] dbg_x3
);

logic [XLEN-1:0] reg_array [31:0];

integer i;

`ifdef LOG_REG 
function [127:0] get_register_name;
    input [4:0] rd_addr;
    begin
        case (rd_addr)
            5'd0 : get_register_name = "zero";
            5'd1 : get_register_name = "ra";
            5'd2 : get_register_name = "sp";
            5'd3 : get_register_name = "gp";
            5'd4 : get_register_name = "tp";
            5'd5 : get_register_name = "t0";
            5'd6 : get_register_name = "t1";
            5'd7 : get_register_name = "t2";
            5'd8 : get_register_name = "s0/fp";
            5'd9 : get_register_name = "s1";
            5'd10: get_register_name = "a0";
            5'd11: get_register_name = "a1";
            5'd12: get_register_name = "a2";
            5'd13: get_register_name = "a3";
            5'd14: get_register_name = "a4";
            5'd15: get_register_name = "a5";
            5'd16: get_register_name = "a6";
            5'd17: get_register_name = "a7";
            5'd18: get_register_name = "s2";
            5'd19: get_register_name = "s3";
            5'd20: get_register_name = "s4";
            5'd21: get_register_name = "s5";
            5'd22: get_register_name = "s6";
            5'd23: get_register_name = "s7";
            5'd24: get_register_name = "s8";
            5'd25: get_register_name = "s9";
            5'd26: get_register_name = "s10";
            5'd27: get_register_name = "s11";
            5'd28: get_register_name = "t3";
            5'd29: get_register_name = "t4";
            5'd30: get_register_name = "t5";
            5'd31: get_register_name = "t6";
            default: get_register_name = "unknown";
        endcase
    end
endfunction
`endif


// Reset and Write Logic
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        for (i = 0; i < 32; i = i + 1)
            reg_array[i] <= {XLEN{1'b0}};
    end else begin
        if (rd_write_en && rd_addr != 5'b0) begin
            reg_array[rd_addr] <= rd_data;
        end
    end

    `ifdef LOG_REG 
    if (rd_write_en) begin
        `INFO("cpu_regfile", ("Time %0t: Writing 0x%0h to %0s(x%0d)", $time, rd_data, get_register_name(rd_addr), rd_addr)); 
    end
    `endif
end

// Read Ports
assign rs1_data = reg_array[rs1_addr];
assign rs2_data = reg_array[rs2_addr];

// Debug Ports
assign dbg_x1 = reg_array[1];
assign dbg_x2 = reg_array[2];
assign dbg_x3 = reg_array[3];

endmodule
