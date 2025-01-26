///////////////////////////////////////////////////////////////////////////////////////////////////
// tl_interface Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module tl_interface
 * @brief TileLink-UL Interface for Converting CPU Requests to TileLink Transactions.
 *
 * The `tl_interface` module serves as an interface between a CPU and a TileLink-UL
 * (TileLink Uncached Lightweight) bus. It handles the conversion of CPU logical read/write
 * requests into TileLink Little-Endian transactions on write and converts Little-Endian responses
 * back to CPU logical values on read. The module supports various data sizes depending on the bus
 * data width (`XLEN`) and includes a retry mechanism for handling denied or corrupt responses up
 * to a configurable maximum number of retries.
 *
 * @note This module does not check for address alignment beyond validating the write byte mask.
 * Double-word operations are only supported if `XLEN` is 64 or greater.
 *
 * **Parameters:**
 * - `XLEN` (default: 32): Specifies the bus data width. Double-word operations are supported only
 *                         if `XLEN` ≥ 64.
 * - `SID_WIDTH` (default: 2): Defines the length of the Source ID for TileLink transactions.
 * - `MAX_RETRIES` (default: 3): Sets the maximum number of retry attempts for failed transactions.
 *
 * **Interfaces:**
 *
 * **CPU Interface:**
 * - `cpu_ready`: Indicates that the CPU has a valid request.
 * - `cpu_address`: The address for the CPU request.
 * - `cpu_wdata`: The write data from the CPU.
 * - `cpu_wstrb`: Byte-wise write strobe from the CPU.
 * - `cpu_size`: Specifies the size of the operation.
                 (0: byte, 1: halfword, 2: word, 3: doubleword)
 * - `cpu_read`: Indicates if the operation is a read (`1`) or write (`0`).
 * - `cpu_ack`: CPU request acknowledgment signal, asserted when a request is captured.
 * - `cpu_rdata`: The read data returned to the CPU for read operations.
 * - `cpu_denied`: Indicates if the CPU request was denied after maximum retries.
 * - `cpu_corrupt`: Indicates if the data returned to the CPU is corrupt.
 * - `cpu_valid`: Signals that the CPU response is valid.
 *
 * **TileLink Interface:**
 * ***TileLink A Channel:***
 * - `tl_a_valid`: Indicates that the TileLink A channel has valid data.
 * - `tl_a_ready`: Indicates that the TileLink A channel is ready to accept data.
 * - `tl_a_opcode`: Specifies the operation type for the TileLink A channel.
 * - `tl_a_param`: Provides additional parameters for the TileLink A channel operation.
 * - `tl_a_size`: Specifies the size of each beat in the TileLink A channel.
 * - `tl_a_source`: The source ID for the TileLink A channel transaction.
 * - `tl_a_address`: The address for the TileLink A channel transaction.
 * - `tl_a_mask`: Byte-wise mask for write operations on the TileLink A channel.
 * - `tl_a_data`: Data to be written in TileLink A channel write operations.
 *
 * ***TileLink D Channel:***
 * - `tl_d_valid`: Indicates that the TileLink D channel has valid data.
 * - `tl_d_ready`: Indicates that the TileLink D channel is ready to accept data.
 * - `tl_d_opcode`: Specifies the response type from the TileLink D channel.
 * - `tl_d_param`: Provides additional parameters for the TileLink D channel response.
 * - `tl_d_size`: Specifies the size of each beat in the TileLink D channel.
 * - `tl_d_source`: The source ID for the TileLink D channel response.
 * - `tl_d_data`: Data returned from the TileLink D channel.
 * - `tl_d_corrupt`: Indicates if the data from the TileLink D channel is corrupt.
 * - `tl_d_denied`: Indicates if the TileLink D channel response was denied.
 *
 * The module operates as a finite state machine with states for idling, sending requests, waiting
 * for responses, writing read data back to the CPU, and completing transactions. It ensures proper
 * handling of different data sizes (subject to `XLEN`), validates write byte masks, and retries on
 * communication failures up to the configured maximum number of retries.
 */

`timescale 1ns / 1ps
`default_nettype none

`include "src/log.sv"

module tl_interface #(
    parameter XLEN = 32,                        // Bus data width
    parameter SID_WIDTH = 2,                    // Source ID length
    parameter MAX_RETRIES = 3                   // Maximum number of retry attempts
) (
    input  wire                 clk,
    input  wire                 reset,

    // CPU Interface
    input  wire                 cpu_ready,      // CPU request ready
    input  wire [XLEN-1:0]      cpu_address,    // CPU request address
    input  wire [XLEN-1:0]      cpu_wdata,      // CPU request write data
    input  wire [XLEN/8-1:0]    cpu_wstrb,
    input  wire [2:0]           cpu_size,       // 0:byte, 1:halfword, 2:word, 3:doubleword
    input  wire                 cpu_read,       // 1:read, 0:write
    output reg                  cpu_ack,        // CPU request acknowledgment
    output reg  [XLEN-1:0]      cpu_rdata,      // CPU result data
    output reg                  cpu_denied,     // CPU result is denied
    output reg                  cpu_corrupt,    // CPU result is corrupt
    output reg                  cpu_valid,      // CPU result valid

    // TileLink A Channel
    output reg                  tl_a_valid,
    input  wire                 tl_a_ready,
    output reg  [2:0]           tl_a_opcode,    // Operation type
    output reg  [2:0]           tl_a_param,     // Parameters for operation
    output reg  [2:0]           tl_a_size,      // Log2(Bytes per beat)
    output wire [SID_WIDTH-1:0] tl_a_source,    // Source ID
    output reg  [XLEN-1:0]      tl_a_address,   // Address
    output reg  [XLEN/8-1:0]    tl_a_mask,      // Write byte mask
    output reg  [XLEN-1:0]      tl_a_data,      // Data for write ops

    // TileLink D Channel
    input  wire                 tl_d_valid,
    output reg                  tl_d_ready,
    input  wire [2:0]           tl_d_opcode,    // Response type
    input  wire [1:0]           tl_d_param,     // Response params
    input  wire [2:0]           tl_d_size,
    input  wire [SID_WIDTH-1:0] tl_d_source,
    input  wire [XLEN-1:0]      tl_d_data,
    input  wire                 tl_d_corrupt,
    input  wire                 tl_d_denied,

    output wire [5:0]           test
);

// Local parameters for TileLink A-channel opcodes
localparam [2:0] TL_A_PUT_FULL_DATA_OPCODE    = 3'b000;  // Write full data
localparam [2:0] TL_A_GET_OPCODE              = 3'b100;  // Read data

// Local parameters for TileLink D-channel opcodes
localparam [2:0] TL_D_ACCESS_ACK              = 3'b000;  // Acknowledge access (no data)
localparam [2:0] TL_D_ACCESS_ACK_DATA         = 3'b010;  // Acknowledge access with data
localparam [2:0] TL_D_ACCESS_ACK_DATA_CORRUPT = 3'b101;  // Access with corrupt data
localparam [2:0] TL_D_ACCESS_ACK_ERROR        = 3'b111;  // Acknowledge access with an error

localparam DEFAULT_PARAM                      = 3'b000;  // Default TL param

reg [5:0] test_reg;
assign test = {cpu_ready, cpu_ack, test_reg[3:0]};

// FSM States
typedef enum logic [2:0] {
    IDLE        = 3'b000,
    SEND_REQ    = 3'b001,
    REQ_ACK     = 3'b010,
    WAIT_RESP   = 3'b011,
    WRITE_RDATA = 3'b100,
    COMPLETE    = 3'b101
} state_t;
state_t current_state, next_state;

// Registers to hold CPU request data
reg [XLEN-1:0]   req_address;
reg [XLEN-1:0]   req_wdata;
reg [XLEN/8-1:0] req_wstrb;
reg [2:0]        req_size;
reg              req_read;

// Retry mechanism
reg [$clog2(MAX_RETRIES+1)-1:0] retry_count;

// Error states
reg       do_retry_max;
reg       do_cpu_denied;
reg       do_cpu_corrupt;

// Read data hold
reg [XLEN-1:0] read_data_hold;

// Assign a new source ID for each transaction
// this module only support a single transacetion
// at a time. This is only for logging/debugging
reg [SID_WIDTH-1:0] current_source_id;
assign tl_a_source = current_source_id;
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        current_source_id <= {SID_WIDTH{1'b0}};
    end else if (tl_a_valid && tl_a_ready) begin
        current_source_id <= current_source_id + 1;
    end
end

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

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        // Initialize all registers on reset
        tl_a_valid       <= 1'b0;
        tl_a_opcode      <= 3'b000;
        tl_a_param       <= 3'b000;
        tl_a_size        <= 3'b000;
        tl_a_address     <= {XLEN{1'b0}};
        tl_a_mask        <= {XLEN/8{1'b0}};
        tl_a_data        <= {XLEN{1'b0}};
        tl_d_ready       <= 1'b0;
        cpu_valid        <= 1'b0;
        retry_count      <= 2'd0;
        do_retry_max     <= 1'b0;
        do_cpu_denied    <= 1'b0;
        do_cpu_corrupt   <= 1'b0;
        cpu_ack          <= 1'b0;
        cpu_denied       <= 1'b0;
        cpu_corrupt      <= 1'b0;
        test_reg         <= 6'b100000;
        read_data_hold   <= {XLEN{1'b0}};
    end else begin
        // `ifdef LOG_MEM_INTERFACE `LOG("tl_interface", ("ack=%0b cpu_valid=%0b cpu_rdata=%0h cpu_denied=%0b cpu_corrupt=%0b", cpu_ack, cpu_valid, cpu_rdata, cpu_denied, cpu_corrupt)); `endif
        // Default assignments
        tl_a_valid       <= 1'b0;
        tl_d_ready       <= 1'b0;
        do_retry_max     <= 1'b0;

        case (current_state)
            IDLE: begin
                // Reset outputs
                cpu_ack       <= 1'b0;
                cpu_rdata     <= 1'b0;
                cpu_denied    <= 1'b0;
                cpu_corrupt   <= 1'b0;
                cpu_valid     <= 1'b0;

                if (cpu_ready && ~cpu_ack) begin
                    `ifdef LOG_MEM_INTERFACE `LOG("tl_interface", ("Captured CPU request - Read: %0d, Address: 0x%h, Size: %0d", cpu_read, cpu_address, cpu_size)); `endif

                    // Capture CPU request
                    req_address <= cpu_address;
                    req_wdata   <= cpu_wdata;
                    req_wstrb   <= cpu_wstrb;
                    req_size    <= cpu_size;
                    req_read    <= cpu_read;
                    cpu_ack     <= 1'b1;
                    next_state  <= SEND_REQ;

                    if (~cpu_read) begin
                        test_reg <= 6'b000001;
                        case (cpu_size)
                            3'b000: begin // Store Byte (SB - 8bits)
                                // Addresses from the CPU are byte aligned for byte
                                // reads, cpu_wstrb is the byte for the word-aligned address
                                // so it not needed to determin the cpu_wdata bytes.
                                if (count_wstrb_bits(cpu_wstrb) == 1) begin
                                    req_wdata <= { {(XLEN-8){1'b0}}, cpu_wdata[7:0] };
                                end else begin
                                    `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Captured CPU Byte request - invalid mask b%00b", cpu_wstrb)); `endif
                                    // Invalid alignment
                                    do_cpu_denied  <= 1'b1;
                                    read_data_hold <= {XLEN{1'b0}};
                                    next_state     <= WRITE_RDATA;
                                end
                            end
                            3'b001: if (XLEN == 32) begin // Store Half-Word (SH - 16bits)
                                // Addresses from the CPU are half-word aligned for half-word
                                // reads, cpu_wstrb is the bytes for the word-aligned address
                                // so it not needed to determin the cpu_wdata bytes.
                                if (count_wstrb_bits(cpu_wstrb) == 2 &&
                                    ((cpu_wstrb[0] && cpu_wstrb[1]) ||
                                    (cpu_wstrb[2] && cpu_wstrb[3])))
                                begin
                                    req_wdata <= { {(XLEN-16){1'b0}}, cpu_wdata[15:0] };
                                end else begin
                                    `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Captured CPU Half-Word request - invalid mask b%0b", cpu_wstrb)); `endif
                                    // Invalid alignment
                                    do_cpu_denied  <= 1'b1;
                                    read_data_hold <= {XLEN{1'b0}};
                                    next_state     <= WRITE_RDATA;
                                end
                            end else if (XLEN == 64) begin
                                if (count_wstrb_bits(cpu_wstrb) == 2 &&
                                    ((cpu_wstrb[0] && cpu_wstrb[1]) ||
                                    (cpu_wstrb[2] && cpu_wstrb[3]) ||
                                    (cpu_wstrb[4] && cpu_wstrb[5]) ||
                                    (cpu_wstrb[6] && cpu_wstrb[7])))
                                begin
                                    req_wdata <= { {(XLEN-16){1'b0}}, cpu_wdata[15:0] };
                                end else begin
                                    `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Captured CPU Half-Word request - invalid mask b%0b", cpu_wstrb)); `endif
                                    // Invalid alignment
                                    do_cpu_denied  <= 1'b1;
                                    read_data_hold <= {XLEN{1'b0}};
                                    next_state     <= WRITE_RDATA;
                                end
                            end
                            3'b010: if (XLEN == 32) begin // Store Word (SW 32-bits)
                                // Addresses from the CPU are word aligned for word
                                // reads, cpu_wstrb is the bytes for the word-aligned address
                                // so it not needed to determin the cpu_wdata bytes.
                                if (count_wstrb_bits(cpu_wstrb) == 4 &&
                                    ((cpu_wstrb[0] && cpu_wstrb[1] && cpu_wstrb[2] && cpu_wstrb[3])))
                                begin
                                    req_wdata <= { {(XLEN-32){1'b0}}, cpu_wdata[31:0] };
                                end else begin
                                    `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Captured CPU Word request - invalid mask b%0b", cpu_wstrb)); `endif
                                    // Invalid alignment
                                    do_cpu_denied  <= 1'b1;
                                    read_data_hold <= {XLEN{1'b0}};
                                    next_state     <= WRITE_RDATA;
                                end
                            end else if (XLEN == 64) begin
                                if (count_wstrb_bits(cpu_wstrb) == 4 &&
                                    ((cpu_wstrb[0] && cpu_wstrb[1] && cpu_wstrb[2] && cpu_wstrb[3]) ||
                                    (cpu_wstrb[4] && cpu_wstrb[5] && cpu_wstrb[6] && cpu_wstrb[7])))
                                begin
                                    req_wdata <= { {(XLEN-32){1'b0}}, cpu_wdata[31:0] };
                                end else begin
                                    `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Captured CPU Word request - invalid mask b%0b", cpu_wstrb)); `endif
                                    // Invalid alignment
                                    do_cpu_denied  <= 1'b1;
                                    read_data_hold <= {XLEN{1'b0}};
                                    next_state     <= WRITE_RDATA;
                                end
                            end
                            3'b011: if (XLEN >= 64) begin // Store Double-Word (SD 64-bits)
                                // Addresses from the CPU are double-word aligned for double-word
                                // reads, cpu_wstrb is the bytes for the word-aligned address
                                // so it not needed to determin the cpu_wdata bytes.
                                if (count_wstrb_bits(cpu_wstrb) == 8 &&
                                    (cpu_wstrb[0] && cpu_wstrb[1] && cpu_wstrb[2] && cpu_wstrb[3] && cpu_wstrb[4] && cpu_wstrb[5] && cpu_wstrb[6] && cpu_wstrb[7]))
                                begin
                                    req_wdata <= { {(XLEN-64){1'b0}}, cpu_wdata[63:0] };
                                end else begin
                                    `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Captured CPU Double-Word request - invalid mask b%0b", cpu_wstrb)); `endif
                                    // Invalid alignment
                                    do_cpu_denied  <= 1'b1;
                                    read_data_hold <= {XLEN{1'b0}};
                                    next_state     <= WRITE_RDATA;
                                end
                            end
                            default: begin
                                `ifdef LOG_MEM_INTERFACE `ERROR("tl_interface", ("Captured CPU Double-Word request - invalid size b%0b", cpu_size)); `endif
                                // Invalid request size
                                do_cpu_denied  <= 1'b1;
                                read_data_hold <= {XLEN{1'b0}};
                                next_state     <= WRITE_RDATA;
                            end
                        endcase
                    end
                end else begin
                    test_reg <= 6'b000010;
                    next_state <= IDLE;
                end
            end

            SEND_REQ: begin
                test_reg <= 6'b000100;

                // Resend TileLink A Channel request until tl_a_ready is asserted
                tl_a_opcode  <= req_read ? TL_A_GET_OPCODE : TL_A_PUT_FULL_DATA_OPCODE;
                tl_a_param   <= DEFAULT_PARAM;
                tl_a_size    <= req_size;
                tl_a_address <= req_address;
                tl_a_mask    <= req_wstrb;
                tl_a_data    <= req_wdata;
                tl_a_valid   <= 1'b1;
                cpu_ack      <= 1'b0;
                next_state   <= REQ_ACK;
            end

            REQ_ACK: begin
                if (tl_a_ready) begin
                    test_reg <= 6'b001000;
                    `ifdef LOG_MEM_INTERFACE
                        if (req_read) begin
                            `LOG("tl_interface", ("Sending TileLink A Channel GET request accepted - Address: 0x%h", req_address));
                        end else begin
                            `LOG("tl_interface", ("Sending TileLink A Channel PUT_FULL_DATA request accepted - Address: 0x%h, Mask: 0x%h, Data: 0x%h", req_address, req_wstrb, req_wdata));
                        end
                    `endif
                    tl_a_valid <= 1'b0;
                    next_state <= WAIT_RESP;
                end else begin
                    `ifdef LOG_MEM_INTERFACE `LOG("tl_interface", ("SEND_REQ waiting for tl_a_ready")); `endif
                    next_state  <= SEND_REQ;
                end
            end

            WAIT_RESP: begin
                cpu_ack    <= 1'b0;
                if (tl_d_valid) begin
                    test_reg <= 6'b010000;
                    tl_d_ready <= 1'b1; // Acknowledge the response
                    `ifdef LOG_MEM_INTERFACE `LOG("tl_interface", ("Received TileLink D Channel response - Opcode: %0b, Data: 0x%h, tl_d_denied=%0b, tl_d_corrupt=%0b", tl_d_opcode, tl_d_data, tl_d_denied, tl_d_corrupt)); `endif

                    if (tl_d_denied || tl_d_corrupt) begin
                        if (retry_count < MAX_RETRIES) begin
                            retry_count <= retry_count + 1;
                            `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Response denied/corrupt, retrying (%0d/%0d)", retry_count, MAX_RETRIES)); `endif
                            next_state <= SEND_REQ;
                        end else begin
                            `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Response denied/corrupt after max retries, transitioning to WRITE_RDATA tl_d_denied=%0b tl_d_corrupt=%0b", tl_d_denied, tl_d_corrupt)); `endif
                            if (tl_d_denied) do_cpu_denied <= 1'b1;
                            if (tl_d_corrupt) do_cpu_corrupt <= 1'b1;
                            read_data_hold <= {XLEN{1'b0}};
                            next_state     <= WRITE_RDATA;
                        end
                    end else begin
                        // Successful response
                        if (req_read && tl_d_opcode == TL_D_ACCESS_ACK_DATA) begin
                            case (req_size)
                                3'b000: read_data_hold <= { {(XLEN-8){1'b0}}, tl_d_data[7:0] };
                                3'b001: read_data_hold <= { {(XLEN-16){1'b0}}, tl_d_data[15:0] };
                                3'b010: read_data_hold <= { {(XLEN-32){1'b0}}, tl_d_data[31:0] };
                                3'b011: if (XLEN >= 64) begin
                                    read_data_hold <= { {(XLEN-64){1'b0}}, tl_d_data[64:0] };
                                end
                                default: read_data_hold <= {XLEN{1'b0}};
                            endcase
                            `ifdef LOG_MEM_INTERFACE `LOG("tl_interface", ("Read data received - 0x%h", tl_d_data)); `endif
                        end else if (req_read && tl_d_opcode == TL_D_ACCESS_ACK_DATA_CORRUPT) begin
                            `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Read corrupt data received - 0x%h", tl_d_data)); `endif
                            do_cpu_corrupt <= 1'b1;
                        end else if (req_read && tl_d_opcode == TL_D_ACCESS_ACK_ERROR) begin
                            `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Read error data received - 0x%h", tl_d_data)); `endif
                            do_cpu_denied <= 1'b1;
                        end else if (req_read) begin
                            `ifdef LOG_MEM_INTERFACE `WARN("tl_interface", ("Unexpected Read response on D channel: 0x%0h", tl_d_opcode)); `endif
                            do_cpu_corrupt <= 1'b1;
                        end else if (!req_read) begin
                            `ifdef LOG_MEM_INTERFACE `LOG("tl_interface", ("Write operation acknowledged")); `endif
                        end

                        retry_count <= 2'd0;
                        next_state  <= WRITE_RDATA;
                    end
                end else begin
                    // Waiting for D Channel response
                    next_state <= WAIT_RESP;
                end
            end

            WRITE_RDATA: begin
                test_reg <= 6'b100000;
                `ifdef LOG_MEM_INTERFACE `LOG("tl_interface", ("Assigning read data to CPU - 0x%h denied=%0d corrupt=%0d", read_data_hold, do_cpu_denied || do_retry_max, do_cpu_corrupt)); `endif
                cpu_ack      <= 1'b0;
                if (req_read) begin
                    cpu_rdata <= read_data_hold;
                end else begin
                    cpu_rdata <= {XLEN{1'b0}};
                end
                if (do_cpu_denied || do_retry_max) cpu_denied <= 1'b1;
                if (do_cpu_corrupt) cpu_corrupt <= 1'b1;
                cpu_valid  <= 1'b1;
                next_state <= COMPLETE;
            end

            COMPLETE: begin
             // test_reg <= 6'b000110;
                `ifdef LOG_MEM_INTERFACE `LOG("tl_interface", ("Memory operation complete, valid signals asserted")); `endif
                do_retry_max   <= 1'b0;
                do_cpu_denied  <= 1'b0;
                do_cpu_corrupt <= 1'b0;
                read_data_hold <= {XLEN{1'b0}};
                retry_count    <= 2'd0;
                cpu_valid      <= 1'b0;
                next_state     <= IDLE;
            end

            default: begin
                next_state <= IDLE;
            end
        endcase
    end
end

// FSM State Transition
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        current_state <= IDLE;
    end else begin
        current_state <= next_state;
    end
end

endmodule
