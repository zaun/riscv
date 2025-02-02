`ifndef __TL_UL_OUTPUT__
`define __TL_UL_OUTPUT__
///////////////////////////////////////////////////////////////////////////////////////////////////
// tl_ul_output Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module tl_ul_output
 * @brief TileLink-UL Compliant Memory Module for Handling Read and Write Transactions to a Single
 *        Output Register.
 * 
 * @details
 * The `tl_ul_output` module implements a TileLink UltraLite (TL-UL) compliant memory interface
 * that manages read and write transactions targeting a single output register. The module supports
 * parameterization for data width (`XLEN`), source ID width (`SID_WIDTH`), and the number of output
 * bits (`OUTPUTS`).
 * 
 * **Parameters:**
 * - `XLEN` (default: 32): The width of the data bus.
 * - `SID_WIDTH` (default: 2): The width of the source ID.
 * - `OUTPUTS` (default: 8): The number of bits exposed on the output port.
 * 
 * **Ports:**
 * - `clk`: Clock signal.
 * - `reset`: Asynchronous reset signal.
 * - `outputs`: Output port exposing the lower `OUTPUTS` bits of the internal register.
 * 
 * **TileLink A Channel (Request Interface):**
 * - `tl_a_valid`: Indicates a valid request.
 * - `tl_a_ready`: Indicates the module is ready to accept a request.
 * - `tl_a_opcode`: Operation code specifying the type of transaction (e.g., GET, PUT_FULL_DATA).
 * - `tl_a_param`: Additional parameters for the transaction.
 * - `tl_a_size`: Size of the transaction (byte, half-word, word, etc.).
 * - `tl_a_source`: Source ID of the request.
 * - `tl_a_address`: Address for the transaction.
 * - `tl_a_mask`: Write strobe mask indicating which bytes are to be written.
 * - `tl_a_data`: Data to be written for write operations.
 * 
 * **TileLink D Channel (Response Interface):**
 * - `tl_d_valid`: Indicates a valid response.
 * - `tl_d_ready`: Indicates the receiver is ready to accept the response.
 * - `tl_d_opcode`: Response operation code (e.g., ACK, ACK_DATA, ERROR).
 * - `tl_d_param`: Additional parameters for the response.
 * - `tl_d_size`: Size of the response data.
 * - `tl_d_source`: Source ID corresponding to the original request.
 * - `tl_d_data`: Data returned for read operations.
 * - `tl_d_corrupt`: Indicates if the response data is corrupted.
 * - `tl_d_denied`: Indicates if the request was denied due to errors.
 * 
 * **Internal Logic:**
 * - **State Machine:** Implements a four-state FSM (`IDLE`, `PROCESS`, `RESPOND`, `RESPOND_WAIT`)
 *                      to manage request handling and response generation.
 * - **Request Handling:** Captures incoming requests, determines if they are read or write
 *                         operations, and processes them accordingly.
 *   - **Read Operations:** Extracts the requested data segment from the internal register based on
 *                          the address and size.
 *   - **Write Operations:** Writes data to the internal register with alignment and mask checks to
 *                           ensure data integrity.
 * - **Response Generation:** Constructs appropriate TileLink D channel responses based on the
 *                            outcome of the request processing, handling acknowledgments, data
 *                            returns, and error conditions.
 * - **Output Assignment:** Continuously drives the lower `OUTPUTS` bits of the internal register
 *                          to the `output_data` port.
 * 
 * **Error Handling:**
 * - **Alignment Errors:** Detects misaligned write addresses or incorrect write strobes and responds
 *                         with an error acknowledgment.
 * - **Size Errors:** Handles unsupported transaction sizes by returning error responses.
 * 
 * **Logging:**
 * - Utilizes logging macros (`LOG_MMIO`, `LOG`, `ERROR`) to record significant events and errors
 *   for debugging and verification purposes.
 * 
 * **Usage Notes:**
 * - Ensure that the `XLEN` parameter aligns with the desired data width and that write strobe
 *   operations are correctly parameterized.
 * - Verify that the `OUTPUTS` parameter does not exceed the width of the internal register `XLEN`.
 * - Confirm that the included `src/log.sv` file defines the necessary logging macros.
 *
 */

`timescale 1ns / 1ps
`default_nettype none

`include "log.sv"

module tl_ul_output #(
    parameter int XLEN      = 32,
    parameter int SID_WIDTH = 2,
    parameter int OUTPUTS   = 8
) (
    input  wire                 clk,
    input  wire                 reset,

    // Outputs
    output wire [OUTPUTS-1:0]   outputs,

    // TileLink A Channel
    input  wire                 tl_a_valid,
    output reg                  tl_a_ready,
    input  wire [2:0]           tl_a_opcode,
    input  wire [2:0]           tl_a_param,     // Included for TileLink, not used by module
    input  wire [2:0]           tl_a_size,
    input  wire [SID_WIDTH-1:0] tl_a_source,
    input  wire [XLEN-1:0]      tl_a_address,
    input  wire [XLEN/8-1:0]    tl_a_mask,
    input  wire [XLEN-1:0]      tl_a_data,

    // TileLink D Channel
    output reg                  tl_d_valid,
    input  wire                 tl_d_ready,
    output reg [2:0]            tl_d_opcode,
    output reg [1:0]            tl_d_param,
    output reg [2:0]            tl_d_size,
    output reg [SID_WIDTH-1:0]  tl_d_source,
    output reg [XLEN-1:0]       tl_d_data,
    output reg                  tl_d_corrupt,
    output reg                  tl_d_denied
);

// Local parameters
localparam [2:0] TL_ACCESS_ACK              = 3'b000;
localparam [2:0] TL_ACCESS_ACK_DATA         = 3'b010;
localparam [2:0] TL_ACCESS_ACK_DATA_CORRUPT = 3'b101;
localparam [2:0] TL_ACCESS_ACK_ERROR        = 3'b111;
localparam [2:0] PUT_FULL_DATA_OPCODE       = 3'b000;
localparam [2:0] GET_OPCODE                 = 3'b100;

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
reg [SID_WIDTH-1:0] req_source;
reg [XLEN/8-1:0]    req_wstrb;
reg [XLEN-1:0]      req_wdata;

// Registers to hold computed response data before asserting tl_d_valid
reg [XLEN-1:0]      resp_data;
reg [2:0]           resp_opcode;
reg [1:0]           resp_param;
reg [2:0]           resp_size;
reg [SID_WIDTH-1:0] resp_source;
reg                 resp_denied;
reg                 resp_corrupt;


function integer count_wstrb_bits;
    input [XLEN/8-1:0] wstrb;
    integer j;
    begin
        count_wstrb_bits = 0;
        for (j = 0; j < XLEN/8; j = j + 1) begin
            count_wstrb_bits = count_wstrb_bits + wstrb[j];
        end
    end
endfunction

// Capture A-Channel request
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state        <= IDLE;
        register     <= {XLEN{1'b0}};
        tl_a_ready   <= 1'b0;
        tl_d_valid   <= 1'b0;
        tl_d_opcode  <= 3'b000;
        tl_d_param   <= 2'b00;
        tl_d_size    <= 3'b000;
        tl_d_source  <= {SID_WIDTH{1'b0}};
        tl_d_data    <= {XLEN{1'b0}};
        tl_d_corrupt <= 1'b0;
        tl_d_denied  <= 1'b0;
        resp_denied  <= 1'b0;
        resp_corrupt <= 1'b0;
    end else begin
        // Defaults
        tl_a_ready <= (state == IDLE);

        case (state)
            IDLE: begin
                if (tl_a_valid && tl_a_ready) begin
                    // Capture request
                    req_address  <= tl_a_address;
                    req_size     <= tl_a_size;
                    req_read     <= (tl_a_opcode == GET_OPCODE);
                    req_source   <= tl_a_source;
                    req_wstrb    <= tl_a_mask;
                    req_wdata    <= tl_a_data;

                    `ifdef LOG_MMIO `LOG("mmio", ("/IDLE/ tl_a_address=%0h", tl_a_address)); `endif
                    state <= PROCESS;
                end
            end

            PROCESS: begin
                // Initialize response flags
                resp_param   <= 2'b00;
                resp_source  <= req_source;

                // Handle normal read or write
                resp_param  <= 2'b00; // Normal acknowledgment
                if (req_read) begin
                    // Handle read
                    case (req_size)
                        3'b000: begin
                            // Byte
                            resp_data <= {{(XLEN-8){1'b0}}, register[(req_address[1:0]) * 8 +: 8]};
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                            `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ READ Byte req_address=0x%00h, resp_data=0x%00h", req_address, {{(XLEN-8){1'b0}}, register[(req_address[1:0]) * 8 +: 8]})); `endif
                        end
                        3'b001: begin
                            // Halfword
                            resp_data <= {{(XLEN-16){1'b0}}, register[(req_address[1] * 16) +: 16]};
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                            `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ READ Half-Word req_address=0x%00h, resp_data=0x%00h", req_address, {{(XLEN-16){1'b0}}, register[(req_address[1] * 16) +: 16]})); `endif
                        end
                        3'b010: begin
                            // Word
                            resp_data <= {{(XLEN-32){1'b0}}, register[(req_address[1:0] * 32) +: 32]};
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                            `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ READ Word req_address=0x%00h, resp_data=0x%00h", req_address, {{(XLEN-32){1'b0}}, register[(req_address[1:0] * 32) +: 32]})); `endif
                        end
                        3'b011: begin
                            // Double-word
                            if (XLEN >= 64) begin
                                resp_data <= {{(XLEN-64){1'b0}}, register[(req_address[2] * 64) +: 64]};
                                resp_opcode <= TL_ACCESS_ACK_DATA;
                                `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ READ Double-Word req_address=0x%00h, resp_data=0x%00h", req_address, {{(XLEN-64){1'b0}}, register[(req_address[2] * 64) +: 64]})); `endif
                            end else begin
                                resp_data <= {(XLEN){1'b0}};
                                resp_opcode <= TL_ACCESS_ACK_DATA;
                                `ifdef LOG_MMIO `ERROR("mmio", ("/PROCESS/ READ Double-Word on 32bits")); `endif
                            end
                        end
                        3'b100: if (XLEN >= 128) begin
                            resp_data <= register[(req_address[3] * 128) +: 128];
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                        end
                        default: begin
                            resp_data <= {(XLEN){1'b0}};
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                            `ifdef LOG_MMIO `ERROR("mmio", ("/PROCESS/ READ Unknon Size req_address=%0h, resp_data=%0h req_size=%0b", req_address, {(XLEN){1'b0}}, req_size)); `endif
                        end
                    endcase
                end else begin
                    resp_opcode <= TL_ACCESS_ACK;
                    resp_data   <= {XLEN{1'b0}};
                    // Handle write operations based on store size
                    case (req_size)
                        3'b000: begin // byte
                            if (count_wstrb_bits(req_wstrb) == 1) begin
                                register[(req_address % 4) * 8 +: 8] <= req_wdata[7:0];
                                `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ WRITE Byte req_address=0x%00h, req_wdata=0x%00h (b%00b)", req_address, req_wdata, req_wdata[7:0])); `endif
                            end else begin
                                `ifdef LOG_MMIO `ERROR("mmio", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                resp_opcode <= TL_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                            end
                        end
                        3'b001: begin // half-word
                            if (XLEN == 32) begin
                                if (count_wstrb_bits(req_wstrb) == 2 &&
                                    ((req_wstrb[0] && req_wstrb[1]) ||
                                    (req_wstrb[2] && req_wstrb[3])))
                                begin
                                    register[req_address[1] * 16 +: 16] <= req_wdata[15:0];
                                    `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ Half-Word Byte req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                                end else begin
                                    `ifdef LOG_MMIO `ERROR("mmio", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end else if (XLEN == 64) begin
                                if (count_wstrb_bits(req_wstrb) == 2 &&
                                    ((req_wstrb[0] && req_wstrb[1]) ||
                                    (req_wstrb[2] && req_wstrb[3]) ||
                                    (req_wstrb[4] && req_wstrb[5]) ||
                                    (req_wstrb[6] && req_wstrb[7])))
                                begin
                                    register[req_address[1] * 16 +: 16] <= req_wdata[15:0];
                                    `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ Half-Word Byte req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                                end else begin
                                    `ifdef LOG_MMIO `ERROR("mmio", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end
                        end
                        3'b010: begin // word
                            if (XLEN == 32) begin
                                if (count_wstrb_bits(req_wstrb) == 4 &&
                                    ((req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3])))
                                begin
                                    register[req_address[1:0] * 32 +: 32] <= req_wdata[31:0];
                                    `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ WRITE Word req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                                end else begin
                                    `ifdef LOG_MMIO `ERROR("mmio", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end else if (XLEN == 64) begin
                                if (count_wstrb_bits(req_wstrb) == 4 &&
                                    ((req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3]) ||
                                    (req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && req_wstrb[7])))
                                begin
                                    register[req_address[1:0] * 32 +: 32] <= req_wdata[31:0];
                                    `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ WRITE Word req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                                end else begin
                                    `ifdef LOG_MMIO `ERROR("mmio", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end
                        end
                        3'b011: if (XLEN >= 64) begin // double-word
                            if (count_wstrb_bits(req_wstrb) == 8 &&
                                (req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3] && req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && tl_a_mask[7]))
                            begin
                                register[(req_address[2:0] % 4) * 64 +: 64] <= req_wdata[63:0];
                                `ifdef LOG_MMIO `LOG("mmio", ("/PROCESS/ WRITE Double-Word req_address=0x%00h, req_wdata=0x%00h", req_address, req_wdata)); `endif
                            end else begin
                                `ifdef LOG_MMIO `ERROR("mmio", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                resp_opcode <= TL_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                            end
                        end
                        default: begin
                            `ifdef LOG_MMIO `ERROR("mmio", ("/PROCESS/ WRITE Size Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                            resp_opcode <= TL_ACCESS_ACK_ERROR;
                            resp_denied <= 1'b1;
                            resp_param  <= 2'b10; // Error param
                        end
                    endcase
                end
                state <= RESPOND;
            end

            RESPOND: begin
                `ifdef LOG_MMIO `LOG("mmio", ("/RESPOND/ resp_data=0x%08h resp_opcode=%0b resp_corrupt=%0b resp_denied=%0b", resp_data, resp_opcode, resp_corrupt, resp_denied)); `endif
                // Assign response signals
                tl_d_opcode  <= resp_opcode;
                tl_d_param   <= resp_param;
                tl_d_size    <= req_size;
                tl_d_source  <= resp_source;
                tl_d_data    <= resp_data;
                tl_d_corrupt <= resp_corrupt;
                tl_d_denied  <= resp_denied;
                tl_d_valid   <= 1'b1;
                state <= RESPOND_WAIT;
            end

            RESPOND_WAIT: begin
                if (tl_d_ready) begin
                    // Handshake done, go back to IDLE
                    tl_d_opcode  <= 3'b000;
                    tl_d_param   <= 2'b00;
                    tl_d_size    <= 3'b000;
                    tl_d_source  <= {SID_WIDTH{1'b0}};
                    tl_d_data    <= {XLEN{1'b0}};
                    tl_d_corrupt <= 1'b0;
                    tl_d_denied  <= 1'b0;
                    resp_denied  <= 1'b0;
                    resp_corrupt <= 1'b0;
                    tl_d_valid   <= 1'b0;
                    state <= IDLE;
                end else begin
                    state <= RESPOND_WAIT;
                end
            end

            default: state <= IDLE;
        endcase
    end
end
endmodule

`endif // __TL_UL_OUTPUT__
