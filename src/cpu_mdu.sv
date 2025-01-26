`ifndef __CPU_MDU__
`define __CPU_MDU__
///////////////////////////////////////////////////////////////////////////////////////////////////
// MDU Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module cpu_mdu
 * @brief Performs multiplication and division operations.
 *
 * The MDU module executes multiplication and division operations based on the
 * `control` signal. It is designed to support riscv m instructions.
 */

`timescale 1ns / 1ps
`default_nettype none

`include "log.sv"

// ──────────────────────────
// MDU Operation Encoding
// ──────────────────────────
`define MDU_MUL    3'b000 // 0 Multiply two signed operands
`define MDU_MULH   3'b001 // 1 Multiply high signed operands
`define MDU_MULHSU 3'b010 // 2 Multiply high signed and unsigned operands
`define MDU_MULHU  3'b011 // 3 Multiply high unsigned operands
`define MDU_DIV    3'b100 // 4 Divide signed operand_a by signed operand_b
`define MDU_DIVU   3'b101 // 5 Divide unsigned operand_a by unsigned operand_b
`define MDU_REM    3'b110 // 6 Remainder of signed division
`define MDU_REMU   3'b111 // 7 Remainder of unsigned division

module cpu_mdu #(
    parameter XLEN = 32
) (
    input  wire              clk,
    input  wire              reset,

    input  wire [XLEN-1:0]   operand_a,
    input  wire [XLEN-1:0]   operand_b,
    input  wire [2:0]        control,    // Encoded M-extension operation
    input  wire              start,      // Start signal for the MDU
    output reg  [XLEN-1:0]   result,
    output reg               ready       // High when MDU completes
);

// ──────────────────────────
// Internally, handle signed versions of operand_a/b
// ──────────────────────────
logic signed [XLEN-1:0] operand_a_signed;
logic signed [XLEN-1:0] operand_b_signed;
assign operand_a_signed = operand_a;
assign operand_b_signed = operand_b;

// ──────────────────────────
// Internal signals
// ──────────────────────────
logic signed [2*XLEN-1:0] mul_result;
logic signed [XLEN-1:0]   div_result;
logic signed [XLEN-1:0]   rem_result;
logic [5:0]               op_reg;
logic                     mdu_active;
logic [5:0]               counter;

// ──────────────────────────
// MDU State Machine
// ──────────────────────────
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        mdu_active <= 1'b0;
        counter    <= 6'd0;
        ready      <= 1'b0;
        result     <= {XLEN{1'b0}};
        mul_result <= {2*XLEN{1'b0}};
        div_result <= {XLEN{1'b0}};
        rem_result <= {XLEN{1'b0}};
        op_reg     <= 6'b0;
    end 
    else begin
        // Start new MDU op
        if (start && !mdu_active) begin
            mdu_active <= 1'b1;
            ready      <= 1'b0;
            counter    <= XLEN;   // simplistic “latency”
            op_reg     <= control;

            // Initialize multiplication / division
            case (control)
                `MDU_MUL: begin // MUL (signed x signed)
                    `ifdef LOG_MDU `LOG("mdu", (" MUL a=0x%00h b=0x%00h", operand_a_signed, operand_b_signed)); `endif
                    mul_result <= { {XLEN{operand_a_signed[XLEN-1]}}, operand_a_signed }
                                * { {XLEN{operand_b_signed[XLEN-1]}}, operand_b_signed };
                end
                `MDU_MULH: begin // MULH (signed x signed high)
                    `ifdef LOG_MDU `LOG("mdu", (" MULH a=0x%00h b=0x%00h", operand_a_signed, operand_b_signed)); `endif
                    mul_result <= { {XLEN{operand_a_signed[XLEN-1]}}, operand_a_signed }
                                * { {XLEN{operand_b_signed[XLEN-1]}}, operand_b_signed };
                end
                `MDU_MULHSU: begin // MULHSU (signed x unsigned high)
                    `ifdef LOG_MDU `LOG("mdu", (" MULHSU a=0x%00h b=0x%00h", operand_a_signed, operand_b_signed)); `endif
                    mul_result <= { {XLEN{operand_a_signed[XLEN-1]}}, operand_a_signed }
                                * { {XLEN{1'b0}}, operand_b };
                end
                `MDU_MULHU: begin // MULHU (unsigned x unsigned high)
                    `ifdef LOG_MDU `LOG("mdu", (" MULHU a=0x%00h b=0x%00h", operand_a_signed, operand_b_signed)); `endif
                    mul_result <= { {XLEN{1'b0}}, operand_a }
                                * { {XLEN{1'b0}}, operand_b };
                end
                `MDU_DIV: begin // DIV (signed ÷ signed)
                    `ifdef LOG_MDU `LOG("mdu", (" DIVU a=0x%00h b=0x%00h", operand_a, operand_b)); `endif
                    if (operand_b != 0) begin
                        div_result <= operand_a_signed / operand_b_signed;
                        rem_result <= operand_a_signed % operand_b_signed;
                    end else begin
                        // Division by zero behavior
                        div_result <= (operand_a_signed[XLEN-1] == 1) 
                                        ? -1 
                                        : { (XLEN-1){1'b1} };
                        rem_result <= operand_a_signed;
                    end
                end
                `MDU_DIVU: begin // DIVU (unsigned ÷ unsigned)
                    `ifdef LOG_MDU `LOG("mdu", (" DIV a=0x%00h b=0x%00h", operand_a, operand_b)); `endif
                    if (operand_b != 0) begin
                        div_result <= operand_a / operand_b;
                        rem_result <= operand_a % operand_b;
                    end else begin
                        div_result <= {XLEN{1'b1}};  // all 1s
                        rem_result <= operand_a;
                    end
                end
                `MDU_REM: begin // REM (signed remainder)
                    `ifdef LOG_MDU `LOG("mdu", (" REM a=0x%00h b=0x%00h", operand_a, operand_b)); `endif
                    if (operand_b != 0) begin
                        rem_result <= operand_a_signed % operand_b_signed;
                    end else begin
                        rem_result <= operand_a_signed; 
                    end
                end
                `MDU_REMU: begin // REMU (unsigned remainder)
                    `ifdef LOG_MDU `LOG("mdu", (" REMU a=0x%00h b=0x%00h", operand_a, operand_b)); `endif
                    if (operand_b != 0) begin
                        rem_result <= operand_a % operand_b;
                    end else begin
                        rem_result <= operand_a;
                    end
                end
                default: begin
                    mul_result <= {2*XLEN{1'b0}};
                    div_result <= {XLEN{1'b0}};
                    rem_result <= {XLEN{1'b0}};
                end
            endcase
        end else if (mdu_active && counter > 0) begin
            // If an op is in progress, decrement the counter
            counter <= counter - 1;
        end else if (mdu_active && counter == 0) begin
            // Finished
            mdu_active <= 1'b0;
            ready      <= 1'b1;
            // Pick the final result
            case (op_reg)
                `MDU_MUL:    result <= mul_result[XLEN-1 : 0];
                `MDU_MULH:   result <= mul_result[2*XLEN-1 : XLEN];
                `MDU_MULHSU: result <= mul_result[2*XLEN-1 : XLEN];
                `MDU_MULHU:  result <= mul_result[2*XLEN-1 : XLEN];
                `MDU_DIV,
                `MDU_DIVU:   result <= div_result;
                `MDU_REM,
                `MDU_REMU:   result <= rem_result;
                default:     result <= {XLEN{1'b0}};
            endcase
        end else begin
            // Idle
            ready <= 1'b0;
        end
    end
end

endmodule

`endif // __CPU_MDU__
