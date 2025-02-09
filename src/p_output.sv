`ifndef __P_OUTPUT__
`define __P_OUTPUT__
///////////////////////////////////////////////////////////////////////////////////////////////////
// p_output Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module p_output
 * @brief Parallel Bus Memory Module for Handling Read and Write Transactions.
 *
 * The `p_output` module emulates a memory subsystem that interfaces with a parallel bus. It
 * requests, performs read and write operations on an internal memory array, and responds via the
 * bus. The module supports various access sizes, including byte, half-word, word, double-word, and 
 * quad-word operations, depending on the `XLEN` parameter.
 *
 * **Parameters:**
 * - `XLEN` (default: 32): Specifies the bus data width. Double-word operations are supported only
 *                         if `XLEN` ≥ 64.
 * - `SIZE` (default: 1024): Defines the size of the memory array in bytes.
 * - `WIDTH` (default: 8): Defines the memory data width
 *
 * **Interface:**
 * 
 * @note Ensure that the `SIZE` parameter adequately represents the memory size to prevent
 *       address overflows based on the access sizes supported.
 * 
 */

`timescale 1ns / 1ps
`default_nettype none

`include "log.sv"

module p_output #(
    parameter int XLEN      = 32,
    parameter int OUTPUTS   = 8
) (
    input  wire                 clk,
    input  wire                 reset,

    // Outputs
    output wire [OUTPUTS-1:0]   outputs,

    input  wire                 bus_valid,   // Valid signal to each target
    input  wire                 bus_rw,      // Read/Write signal to each target
    input  wire [XLEN-1:0]      bus_addr,    // Address sent to each target
    input  wire [XLEN-1:0]      bus_wdata,   // Write data sent to each target
    input  wire [XLEN/8-1:0]    bus_wstrb,   // Write byte masks for request
    input  wire [2:0]           bus_size,    // Size of each request in log2(Bytes per beat)
    output reg                  bus_ready,   // Asserts when work is completed
    output reg  [XLEN-1:0]      bus_rdata,   // Read data from each target
    output reg                  bus_denied,  // Denied signal back to each source
    output reg                  bus_corrupt  // Corrupt signal back to each source
);

initial begin
    `ASSERT((XLEN == 32 || XLEN == 64), "XLEN must be 32 or 64.");
end

reg [XLEN-1:0] register;

assign outputs = register[OUTPUTS-1:0];

// States
typedef enum logic [1:0] {
    IDLE,
    PROCESS,
    RESPOND,
    RESPOND_WAIT
} mem_state_t;
mem_state_t state;

// Registers to hold request info
reg [XLEN-1:0]      req_address;
reg [2:0]           req_size;
reg                 req_read;
reg [XLEN/8-1:0]    req_wstrb;
reg [XLEN-1:0]      req_wdata;

// Registers to hold computed response data before asserting bus_valid
reg [XLEN-1:0]      resp_data;
reg                 resp_denied;
reg                 resp_corrupt;

// Keep a count of req_wstrb bits
reg [$clog2(XLEN/8+1)-1:0] wstrb_count;
integer i;
always_comb begin
    wstrb_count = 0;
    for (i = 0; i < XLEN/8; i++) begin
        wstrb_count = wstrb_count + req_wstrb[i];
    end
end

// Capture A-Channel request
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state        <= IDLE;
        bus_ready    <= '0;
        resp_denied  <= 1'b0;
        resp_corrupt <= 1'b0;
    end else begin
        // Defaults
        bus_ready <= '0;

        case (state)
            IDLE: begin
                if (bus_valid) begin
                    // Capture request
                    req_address  <= bus_addr;
                    req_read     <= bus_rw;
                    req_size     <= bus_size;
                    req_wstrb    <= bus_wstrb;
                    req_wdata    <= bus_wdata;

                    `ifdef LOG_BIOS `LOG("p_output", ("/IDLE/ bus_addr=%0h", bus_addr)); `endif
                    state <= PROCESS;
                end
            end

            PROCESS: begin
                // Read Request
                if (req_read) begin
                    case (req_size)
                        3'b000: begin
                            // Byte
                            resp_data <= {{(XLEN-8){1'b0}}, register[(req_address[1:0]) * 8 +: 8]};
                            `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ READ Byte req_address=0x%00h, resp_data=0x%00h", req_address, {{(XLEN-8){1'b0}}, register[(req_address[1:0]) * 8 +: 8]})); `endif
                        end
                        3'b001: begin
                            // Halfword
                            resp_data <= {{(XLEN-16){1'b0}}, register[(req_address[1] * 16) +: 16]};
                            `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ READ Half-Word req_address=0x%00h, resp_data=0x%00h", req_address, {{(XLEN-16){1'b0}}, register[(req_address[1] * 16) +: 16]})); `endif
                        end
                        3'b010: begin
                            // Word
                            resp_data <= {{(XLEN-32){1'b0}}, register[(req_address[1:0] * 32) +: 32]};
                            `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ READ Word req_address=0x%00h, resp_data=0x%00h", req_address, {{(XLEN-32){1'b0}}, register[(req_address[1:0] * 32) +: 32]})); `endif
                        end
                        3'b011: begin
                            // Double-word
                            if (XLEN >= 64) begin
                                resp_data <= {{(XLEN-64){1'b0}}, register[(req_address[2] * 64) +: 64]};
                                `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ READ Double-Word req_address=0x%00h, resp_data=0x%00h", req_address, {{(XLEN-64){1'b0}}, register[(req_address[2] * 64) +: 64]})); `endif
                            end else begin
                                resp_data <= {(XLEN){1'b0}};
                                `ifdef LOG_MMIO `ERROR("p_output", ("/PROCESS/ READ Double-Word on 32bits")); `endif
                            end
                        end
                        3'b100: if (XLEN >= 128) begin
                            resp_data <= register[(req_address[3] * 128) +: 128];
                        end
                        default: begin
                            resp_data <= {(XLEN){1'b0}};
                            `ifdef LOG_MMIO `ERROR("p_output", ("/PROCESS/ READ Unknon Size req_address=%0h, resp_data=%0h req_size=%0b", req_address, {(XLEN){1'b0}}, req_size)); `endif
                        end
                    endcase
                end
                
                // Write Request
                else begin
                    resp_data   <= {XLEN{1'b0}};
                    // Handle write operations based on store size
                    case (req_size)
                        3'b000: begin // byte
                            if (wstrb_count == 1) begin
                                register[(req_address % 4) * 8 +: 8] <= req_wdata[7:0];
                                `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ WRITE Byte req_address=0x%00h, req_wdata=0x%00h (b%00b)", req_address, req_wdata, req_wdata[7:0])); `endif
                            end else begin
                                `ifdef LOG_MMIO `ERROR("p_output", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                resp_denied <= 1'b1;
                            end
                        end
                        3'b001: begin // half-word
                            if (XLEN == 32) begin
                                if (wstrb_count == 2 &&
                                    ((req_wstrb[0] && req_wstrb[1]) ||
                                    (req_wstrb[2] && req_wstrb[3])))
                                begin
                                    register[req_address[1] * 16 +: 16] <= req_wdata[15:0];
                                    `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ Half-Word Byte req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                                end else begin
                                    `ifdef LOG_MMIO `ERROR("p_output", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                    resp_denied <= 1'b1;
                                end
                            end else if (XLEN == 64) begin
                                if (wstrb_count == 2 &&
                                    ((req_wstrb[0] && req_wstrb[1]) ||
                                    (req_wstrb[2] && req_wstrb[3]) ||
                                    (req_wstrb[4] && req_wstrb[5]) ||
                                    (req_wstrb[6] && req_wstrb[7])))
                                begin
                                    register[req_address[1] * 16 +: 16] <= req_wdata[15:0];
                                    `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ Half-Word Byte req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                                end else begin
                                    `ifdef LOG_MMIO `ERROR("p_output", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                    resp_denied <= 1'b1;
                                end
                            end
                        end
                        3'b010: begin // word
                            if (XLEN == 32) begin
                                if (wstrb_count == 4 &&
                                    ((req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3])))
                                begin
                                    register[req_address[1:0] * 32 +: 32] <= req_wdata[31:0];
                                    `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ WRITE Word req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                                end else begin
                                    `ifdef LOG_MMIO `ERROR("p_output", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                    resp_denied <= 1'b1;
                                end
                            end else if (XLEN == 64) begin
                                if (wstrb_count == 4 &&
                                    ((req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3]) ||
                                    (req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && req_wstrb[7])))
                                begin
                                    register[req_address[1:0] * 32 +: 32] <= req_wdata[31:0];
                                    `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ WRITE Word req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                                end else begin
                                    `ifdef LOG_MMIO `ERROR("p_output", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                    resp_denied <= 1'b1;
                                end
                            end
                        end
                        3'b011: if (XLEN >= 64) begin // double-word
                            if (wstrb_count == 8 &&
                                (req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3] && req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && bus_wstrb[7]))
                            begin
                                register[(req_address[2:0] % 4) * 64 +: 64] <= req_wdata[63:0];
                                `ifdef LOG_MMIO `LOG("p_output", ("/PROCESS/ WRITE Double-Word req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                            end else begin
                                `ifdef LOG_MMIO `ERROR("p_output", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                resp_denied <= 1'b1;
                            end
                        end
                        default: begin
                            `ifdef LOG_MMIO `ERROR("p_output", ("/PROCESS/ WRITE Size Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                            resp_denied <= 1'b1;
                        end
                    endcase
                end
                state <= RESPOND;
            end

            RESPOND: begin
                `ifdef LOG_BIOS `LOG("p_output", ("/RESPOND/ resp_data=0x%08h resp_corrupt=%0b resp_denied=%0b", resp_data, resp_corrupt, resp_denied)); `endif
                // Assign response signals
                bus_rdata   <= resp_data;
                bus_corrupt <= resp_corrupt;
                bus_denied  <= resp_denied;
                bus_ready   <= 1'b1;
                state       <= RESPOND_WAIT;
            end

            RESPOND_WAIT: begin
                // Wait for bus to go invalid
                if (~bus_valid) begin
                    `ifdef LOG_BIOS `LOG("p_output", ("/COMPLETED/ resp_data=0x%08h resp_corrupt=%0b resp_denied=%0b", bus_rdata, bus_corrupt, bus_denied)); `endif
                    // Handshake done, go back to IDLE
                    bus_rdata    <= {XLEN{1'b0}};
                    bus_corrupt  <= 1'b0;
                    bus_denied   <= 1'b0;
                    resp_denied  <= 1'b0;
                    resp_corrupt <= 1'b0;
                    bus_ready    <= 1'b0;
                    state        <= IDLE;
                end else begin
                    state <= RESPOND_WAIT;
                end
            end

            default: state <= IDLE;
        endcase
    end
end
endmodule

`endif // __P_OUTPUT__
