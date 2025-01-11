///////////////////////////////////////////////////////////////////////////////////////////////////
// tl_ul_bios Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module tl_ul_bios
 * @brief TileLink-UL Compliant Memory Module pre-loaded with a BIOS.
 */
 
`timescale 1ns / 1ps
`default_nettype none

`include "src/log.sv"

module tl_ul_bios #(
    parameter int XLEN = 32,
    parameter int SID_WIDTH = 2
) (
    input  wire                 clk,
    input  wire                 reset,

    // TileLink A Channel
    input  wire                 tl_a_valid,
    output reg                  tl_a_ready,
    input  wire [2:0]           tl_a_opcode,
    input  wire [2:0]           tl_a_param,
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

    `ifdef DEBUG
    // Debug inputs
    ,input  wire                dbg_wait
    ,input  wire [XLEN-1:0]     dbg_corrupt_read_address
    ,input  wire [XLEN-1:0]     dbg_denied_read_address
    ,input  wire [XLEN-1:0]     dbg_corrupt_write_address
    ,input  wire [XLEN-1:0]     dbg_denied_write_address
    `endif
);

// Local parameters
localparam       SIZE                       = 'hFF;
localparam [2:0] TL_ACCESS_ACK              = 3'b000;
localparam [2:0] TL_ACCESS_ACK_DATA         = 3'b010;
localparam [2:0] TL_ACCESS_ACK_DATA_CORRUPT = 3'b101;
localparam [2:0] TL_ACCESS_ACK_ERROR        = 3'b111;
localparam [2:0] PUT_FULL_DATA_OPCODE       = 3'b000;
localparam [2:0] GET_OPCODE                 = 3'b100;

// Memory array
reg [7:0] memory [0:SIZE - 1];

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

// Initialize memory from bios.hex
initial begin
    // $readmemh("../etc/bios/bios.hex", memory);
    $readmemh("etc/bios/bios.hex", memory);
end

// Function to calculate maximum address based on access size
function int max_valid_address(input [2:0] size);
    case (size)
        3'b000: max_valid_address = SIZE - 1;            // Byte
        3'b001: max_valid_address = SIZE - 2;            // Halfword
        3'b010: max_valid_address = SIZE - 4;            // Word
        3'b011: max_valid_address = SIZE - 8;            // Double-Word
        3'b100: max_valid_address = SIZE - 16;           // Quad-Word (if XLEN >= 128)
        default: max_valid_address = SIZE - 1;
    endcase
endfunction

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
    `ifdef DEBUG
    end else if (dbg_wait == 1) begin
        // Do nothing
    `endif
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

                    // Check for debug conditions
                    `ifdef DEBUG
                    if (tl_a_opcode == GET_OPCODE) begin
                        // For read requests
                        if (tl_a_address == dbg_corrupt_read_address) begin
                            resp_corrupt <= 1'b1;
                            `ifdef LOG_BIOS `LOG("bios", ("Corrupt read at address %h", tl_a_address)); `endif
                        end
                        if (tl_a_address == dbg_denied_read_address) begin
                            resp_denied <= 1'b1;
                            `ifdef LOG_BIOS `LOG("bios", ("Denied read at address %h", tl_a_address)); `endif
                        end
                    end else begin
                        // For write requests
                        if (tl_a_address == dbg_corrupt_write_address) begin
                            resp_corrupt <= 1'b1;
                            `ifdef LOG_BIOS `LOG("bios", ("Corrupt write at address %h", tl_a_address)); `endif
                        end
                        if (tl_a_address == dbg_denied_write_address) begin
                            resp_denied <= 1'b1;
                            `ifdef LOG_BIOS `LOG("bios", ("Denied write at address %h", tl_a_address)); `endif
                        end
                    end
                    `endif

                    if (tl_a_address > max_valid_address(req_size)) begin
                        `ifdef LOG_BIOS `LOG("bios", ("Invalid address access: 0x%h", req_address)); `endif
                        resp_denied <= 1'b1;
                    end

                    `ifdef LOG_BIOS `LOG("bios", ("/IDLE/ tl_a_address=%0h", tl_a_address)); `endif
                    state <= PROCESS;
                end
            end

            PROCESS: begin
                // Initialize response flags
                resp_param   <= 2'b00;
                resp_source  <= req_source;

                // If denied or corrupted, set response accordingly
                if (resp_denied) begin
                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                    resp_param  <= 2'b10; // Error param
                    resp_data   <= {XLEN{1'b0}};
                end else if (resp_corrupt) begin
                    resp_opcode <= TL_ACCESS_ACK_DATA_CORRUPT;
                    resp_param  <= 2'b01; // Error param
                    // Optionally, set resp_data to a corrupted value
                    // For demonstration, flipping the LSB
                    resp_data <= req_read ? (resp_data ^ {{(XLEN-1){1'b0}}, 1'b1}) : {XLEN{1'b1}};
                end else begin
                    // Handle normal read or write
                    resp_param  <= 2'b00; // Normal acknowledgment
                    if (req_read) begin
                        // Handle read
                        case (req_size)
                            3'b000: begin
                                // Byte
                                resp_data <= {{(XLEN-8){1'b0}}, memory[req_address]};
                                resp_opcode <= TL_ACCESS_ACK_DATA;
                                `ifdef LOG_BIOS `LOG("bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-8){1'b0}}, memory[req_address]}, req_size)); `endif
                            end
                            3'b001: begin
                                // Halfword
                                resp_data <= {{(XLEN-16){1'b0}}, memory[req_address], memory[req_address + 1]};
                                resp_opcode <= TL_ACCESS_ACK_DATA;
                                `ifdef LOG_BIOS `LOG("bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-16){1'b0}}, memory[req_address], memory[req_address + 1]}, req_size)); `endif
                            end
                            3'b010: begin
                                // Word
                                resp_data <= {{(XLEN-32){1'b0}}, memory[req_address], memory[req_address + 1], memory[req_address + 2], memory[req_address + 3]};
                                resp_opcode <= TL_ACCESS_ACK_DATA;
                                `ifdef LOG_BIOS `LOG("bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-32){1'b0}}, memory[req_address], memory[req_address + 1], memory[req_address + 2], memory[req_address + 3]}, req_size)); `endif
                            end
                            3'b011: begin
                                // Double-word
                                if (XLEN >= 64) begin
                                    resp_data <= {memory[req_address], memory[req_address + 1],
                                                memory[req_address + 2], memory[req_address + 3],
                                                memory[req_address + 4], memory[req_address + 5],
                                                memory[req_address + 6], memory[req_address + 7]};
                                    resp_opcode <= TL_ACCESS_ACK_DATA;
                                `ifdef LOG_BIOS `LOG("bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {memory[req_address], memory[req_address + 1],
                                                memory[req_address + 2], memory[req_address + 3],
                                                memory[req_address + 4], memory[req_address + 5],
                                                memory[req_address + 6], memory[req_address + 7]}, req_size)); `endif
                                end else begin
                                    resp_data <= {(XLEN){1'b0}};
                                    resp_opcode <= TL_ACCESS_ACK_DATA;
                                end
                            end
                            3'b100: if (XLEN >= 128) begin
                                resp_data <= {memory[req_address], memory[req_address + 1],
                                            memory[req_address + 2], memory[req_address + 3],
                                            memory[req_address + 4], memory[req_address + 5],
                                            memory[req_address + 6], memory[req_address + 7],
                                            memory[req_address + 8], memory[req_address + 9],
                                            memory[req_address + 10], memory[req_address + 11],
                                            memory[req_address + 12], memory[req_address + 13],
                                            memory[req_address + 14], memory[req_address + 15]};
                                resp_opcode <= TL_ACCESS_ACK_DATA;
                                `ifdef LOG_BIOS `LOG("bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {memory[req_address], memory[req_address + 1],
                                            memory[req_address + 2], memory[req_address + 3],
                                            memory[req_address + 4], memory[req_address + 5],
                                            memory[req_address + 6], memory[req_address + 7],
                                            memory[req_address + 8], memory[req_address + 9],
                                            memory[req_address + 10], memory[req_address + 11],
                                            memory[req_address + 12], memory[req_address + 13],
                                            memory[req_address + 14], memory[req_address + 15]}, req_size)); `endif
                            end
                            default: begin
                                resp_data <= {(XLEN){1'b0}};
                                resp_opcode <= TL_ACCESS_ACK_DATA;
                                `ifdef LOG_BIOS `ERROR("bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {(XLEN){1'b0}}, req_size)); `endif
                            end
                        endcase
                    end else begin
                        resp_opcode <= TL_ACCESS_ACK;
                        resp_data   <= {XLEN{1'b0}};
                        // Handle write operations based on store size
                        case (req_size)
                            3'b000: begin // byte
                                if (count_wstrb_bits(req_wstrb) == 1) begin
                                    memory[req_address + 0] <= req_wdata[7:0];
                                end else begin
                                    `ifdef LOG_BIOS `ERROR("bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end
                            3'b001: begin // half-word
                                if (count_wstrb_bits(req_wstrb) == 2 &&
                                    ((req_wstrb[0] && req_wstrb[1]) ||
                                    (req_wstrb[2] && req_wstrb[3]) ||
                                    (XLEN >= 64 && req_wstrb[4] && req_wstrb[5]) ||
                                    (XLEN >= 64 && req_wstrb[6] && req_wstrb[7])))
                                begin
                                    memory[req_address + 0] <= req_wdata[15:8];
                                    memory[req_address + 1] <= req_wdata[7:0];
                                end else begin
                                    `ifdef LOG_BIOS `ERROR("bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end
                            3'b010: begin // word
                                if (count_wstrb_bits(req_wstrb) == 4 &&
                                    ((req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3]) ||
                                    (XLEN >= 64 && req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && req_wstrb[7])))
                                begin
                                    memory[req_address + 0] <= req_wdata[31:24];
                                    memory[req_address + 1] <= req_wdata[23:16];
                                    memory[req_address + 2] <= req_wdata[15:8];
                                    memory[req_address + 3] <= req_wdata[7:0];
                                end else begin
                                    `ifdef LOG_BIOS `ERROR("bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end
                            3'b011: if (XLEN >= 64) begin // double-word
                                if (count_wstrb_bits(req_wstrb) == 8 &&
                                    (req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3] && req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && tl_a_mask[7]))
                                begin
                                    memory[req_address + 0] <= req_wdata[63:56];
                                    memory[req_address + 1] <= req_wdata[55:48];
                                    memory[req_address + 2] <= req_wdata[47:40];
                                    memory[req_address + 3] <= req_wdata[39:32];
                                    memory[req_address + 4] <= req_wdata[31:24];
                                    memory[req_address + 5] <= req_wdata[23:16];
                                    memory[req_address + 6] <= req_wdata[15:8];
                                    memory[req_address + 7] <= req_wdata[7:0];
                                end else begin
                                    `ifdef LOG_BIOS `ERROR("bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end
                            default: begin
                                `ifdef LOG_BIOS `ERROR("bios", ("/PROCESS/ WRITE Size Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                resp_opcode <= TL_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                            end
                        endcase
                        `ifdef LOG_BIOS `LOG("bios", ("/PROCESS/ WRITE req_address=%0h, req_wdata=%0h", req_address, req_wdata)); `endif
                    end
                end
                state <= RESPOND;
            end

            RESPOND: begin
                `ifdef LOG_BIOS `LOG("bios", ("/RESPOND/ resp_data=0x%08h resp_opcode=%0b resp_corrupt=%0b resp_denied=%0b", resp_data, resp_opcode, resp_corrupt, resp_denied)); `endif
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
