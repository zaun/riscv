`ifndef __TL_UL_BIOS__
`define __TL_UL_BIOS__
///////////////////////////////////////////////////////////////////////////////////////////////////
// tl_ul_bios Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module tl_ul_bios
 * @brief TileLink-UL Compliant Memory Module pre-loaded with a BIOS.
 */

`timescale 1ns / 1ps
`default_nettype none

`include "log.sv"

module tl_ul_bios #(
    parameter int XLEN = 32,
    parameter int SIZE = 256,
    parameter int WIDTH = 8,
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
    output reg  [2:0]           tl_d_opcode,
    output reg  [1:0]           tl_d_param,
    output reg  [2:0]           tl_d_size,
    output reg  [SID_WIDTH-1:0] tl_d_source,
    output reg  [XLEN-1:0]      tl_d_data,
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

initial begin
    `ASSERT((XLEN == 32 || XLEN == 64), "XLEN must be 32 or 64.");
    `ASSERT((WIDTH >= 8), "WIDTH must be at least 8 bits.");
    `ASSERT((WIDTH % 8 == 0), "WIDTH must be divisible by 8 to ensure byte alignment.");
    `ASSERT((XLEN % WIDTH == 0), "XLEN must be divisible by WIDTH to ensure valid memory operations.");
    `ASSERT((SID_WIDTH >= 2), "SID_WIDTH must be 2 or more.");
    `ASSERT((SIZE % (WIDTH / 8) == 0), "SIZE must be a multiple of WIDTH/8 to ensure proper byte alignment.");
end

// Local parameters
localparam [2:0] TL_ACCESS_ACK              = 3'b000;
localparam [2:0] TL_ACCESS_ACK_DATA         = 3'b010;
localparam [2:0] TL_ACCESS_ACK_DATA_CORRUPT = 3'b101;
localparam [2:0] TL_ACCESS_ACK_ERROR        = 3'b111;
localparam [2:0] PUT_FULL_DATA_OPCODE       = 3'b000;
localparam [2:0] GET_OPCODE                 = 3'b100;

// States
typedef enum logic [2:0] {
    IDLE            = 3'b000,
    FETCH           = 3'b001,
    PROCESS         = 3'b010,
    WRITE_BACK      = 3'b011,
    RESPOND         = 3'b100,
    RESPOND_WAIT    = 3'b101 
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

// Keep a count of req_wstrb bits
reg [$clog2(XLEN/8+1)-1:0] wstrb_count;
integer i;
always_comb begin
    wstrb_count = 0;
    for (i = 0; i < XLEN/8; i++) begin
        wstrb_count = wstrb_count + req_wstrb[i];
    end
end

// Memory array, addresses and offsets.
reg [WIDTH-1:0] memory [0 : (SIZE/(WIDTH/8)) - 1];

localparam int WORD_SHIFT        = $clog2(WIDTH/8);
localparam int BYTE_OFFSET_WIDTH = (WIDTH > 8) ? $clog2(WIDTH/8) : 1;
wire [BYTE_OFFSET_WIDTH-1:0] byte_offset;
wire [XLEN-1:0] mem_word_addr;

generate
    if (WIDTH > 8) begin
        assign byte_offset = req_address[BYTE_OFFSET_WIDTH-1:0];
        assign mem_word_addr = req_address[XLEN-1:BYTE_OFFSET_WIDTH];
    end else begin
        assign byte_offset = 0;
        assign mem_word_addr = req_address;
    end
endgenerate

// Memory Access
localparam int MEM_PARTS = XLEN / WIDTH;    // Number of reads/writes for each XLEN of data
localparam int MEM_PARTS_LOG2 = (MEM_PARTS > 1) ? $clog2(MEM_PARTS) : 1;
reg [MEM_PARTS_LOG2:0] mem_count;      // internal Counter for mem ops
reg                    mem_read;       // input set high for read mem op
reg                    mem_write;      // input set high for read mem op
reg                    mem_start;      // input set high to start mem op
reg                    mem_done;       // output will be high when mem op is done
reg [XLEN-1:0]         mem_idata_reg;   // input memory data register
reg [XLEN-1:0]         mem_odata_reg;   // input memory data register
always_ff @(posedge clk) begin
    if (mem_start && ~mem_done) begin
        if (mem_count < MEM_PARTS) begin
            if (mem_read) begin
                // Read the current WIDTH bits from memory and place them into the correct position in mem_odata_reg
                if (mem_count == 0) begin
                    `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/MEM_READ/ xlen=%0d width=%0d mem_word_addr=0x%0h mem_part=%0d mem_odata_reg=0x%00h", XLEN, WIDTH, mem_word_addr, mem_count, memory[mem_word_addr + mem_count] << (WIDTH * mem_count))); `endif
                    mem_odata_reg <= memory[mem_word_addr + mem_count] << (WIDTH * mem_count);
                end else begin
                    `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/MEM_READ/ xlen=%0d width=%0d mem_word_addr=0x%0h mem_part=%0d mem_odata_reg=0x%00h", XLEN, WIDTH, mem_word_addr, mem_count, mem_odata_reg | (memory[mem_word_addr + mem_count] << (WIDTH * mem_count)))); `endif
                    mem_odata_reg <= mem_odata_reg | (memory[mem_word_addr + mem_count] << (WIDTH * mem_count));
                end
            end else if (mem_write) begin
                // Extract the relevant WIDTH bits from mem_odata_reg and write them to the current memory address
                `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/MEM_WRITE/ xlen=%0d width=%0d mem_word_addr=0x%0h mem_part=%0d part_data=0x%0h", XLEN, WIDTH, mem_word_addr, mem_count, mem_odata_reg[WIDTH*mem_count +: WIDTH])); `endif
                memory[mem_word_addr + mem_count] <= mem_idata_reg[WIDTH*mem_count +: WIDTH];
            end

            // Increment the counter for the next part
            mem_count <= (mem_count + 1) & {MEM_PARTS_LOG2{1'b1}};
            mem_done  <= 0;

            // Memory operation completed
            if (mem_count == MEM_PARTS - 1) begin
                `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/MEM_DONE/")); `endif
                mem_done   <= 1;
                mem_count  <= 0;
            end
        end
    end else begin
        // When not active, ensure mem_done is deasserted
        mem_done <= 0;
        mem_count  <= 0;
    end
end

// Initialize memory from bios.hex
initial begin
    // $readmemh("../etc/bios/bios.hex", memory);
    $readmemh("etc/bios/bios.hex", memory);
end

// Capture A-Channel request
always_ff @(posedge clk or posedge reset) begin
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
        mem_start    <= 1'b0;
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
                            `ifdef LOG_BIOS `LOG("tl_ul_bios", ("Corrupt read at address %h", tl_a_address)); `endif
                        end
                        if (tl_a_address == dbg_denied_read_address) begin
                            resp_denied <= 1'b1;
                            `ifdef LOG_BIOS `LOG("tl_ul_bios", ("Denied read at address %h", tl_a_address)); `endif
                        end
                    end else begin
                        // For write requests
                        if (tl_a_address == dbg_corrupt_write_address) begin
                            resp_corrupt <= 1'b1;
                            `ifdef LOG_BIOS `LOG("tl_ul_bios", ("Corrupt write at address %h", tl_a_address)); `endif
                        end
                        if (tl_a_address == dbg_denied_write_address) begin
                            resp_denied <= 1'b1;
                            `ifdef LOG_BIOS `LOG("tl_ul_bios", ("Denied write at address %h", tl_a_address)); `endif
                        end
                    end
                    `endif

                    if (tl_a_address > max_valid_address(req_size)) begin
                        `ifdef LOG_BIOS `LOG("tl_ul_bios", ("Invalid address access: 0x%h", req_address)); `endif
                        resp_denied <= 1'b1;
                    end

                    `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/IDLE/ tl_a_address=%0h", tl_a_address)); `endif
                    state <= FETCH;
                end
            end

            FETCH: begin
                // If denied or corrupted, set response accordingly
                if (resp_denied) begin
                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                    resp_param  <= 2'b10; // Error param
                    resp_data   <= {XLEN{1'b0}};
                    state <= RESPOND;
                end else if (resp_corrupt) begin
                    resp_opcode <= TL_ACCESS_ACK_DATA_CORRUPT;
                    resp_param  <= 2'b01; // Error param
                    // Optionally, set resp_data to a corrupted value
                    // For demonstration, flipping the LSB
                    resp_data <= req_read ? (resp_data ^ {{(XLEN-1){1'b0}}, 1'b1}) : {XLEN{1'b1}};
                    state <= RESPOND;
                end else begin
                    // Initiate multi-part memory read
                    if (!mem_done) begin
                        `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/FETCH/ tl_a_address=%0h", tl_a_address)); `endif
                        mem_read  <= 1'b1;  // Indicate a read operation
                        mem_write <= 1'b0;
                        mem_start <= 1'b1;  // Start the memory access
                        state <= FETCH;
                    end else if (mem_done) begin
                        mem_start <= 1'b0;
                        mem_idata_reg <= mem_odata_reg;
                        state <= PROCESS;
                    end
                end
            end

            PROCESS: begin
                // Initialize response flags
                resp_param   <= 2'b00;
                resp_source  <= req_source;

                if (req_read) begin
                    resp_opcode <= TL_ACCESS_ACK_DATA;
                    case (req_size)
                        3'b000: begin
                            // Byte
                            resp_data <= {{(XLEN-8){1'b0}}, mem_odata_reg[ 8*byte_offset +: 8 ]};
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                            `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-8){1'b0}}, mem_odata_reg[ 8*byte_offset +: 8 ]}, req_size)); `endif
                        end
                        3'b001: begin
                            // Halfword
                            resp_data <= {{(XLEN-16){1'b0}}, mem_odata_reg[ 8*byte_offset +: 16 ]};
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                            `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-16){1'b0}}, mem_odata_reg[ 8*byte_offset +: 16 ]}, req_size)); `endif
                        end
                        3'b010: begin
                            // Word
                            resp_data <= {{(XLEN-16){1'b0}}, mem_odata_reg[ 8*byte_offset +: 32 ]};
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                            `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-32){1'b0}}, mem_odata_reg[ 8*byte_offset +: 32 ]}, req_size)); `endif
                        end
                        3'b011: begin
                            // Double-word
                            if (XLEN >= 64) begin
                                resp_data  <= mem_odata_reg[ 8*byte_offset +: 64 ];
                                resp_opcode <= TL_ACCESS_ACK_DATA;
                                `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-64){1'b0}}, mem_odata_reg[ 8*byte_offset +: 64 ]}, req_size)); `endif
                            end else begin
                                resp_data <= {(XLEN){1'b0}};
                                resp_opcode <= TL_ACCESS_ACK_DATA;
                            end
                        end
                        3'b100: if (XLEN >= 128) begin
                            resp_data   <= {{(XLEN-128){1'b0}}, mem_odata_reg[ 8*byte_offset +: 128 ]};
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                            `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-128){1'b0}}, mem_odata_reg[ 8*byte_offset +: 128 ]}, req_size)); `endif
                        end
                        default: begin
                            resp_data <= {(XLEN){1'b0}};
                            resp_opcode <= TL_ACCESS_ACK_DATA;
                            `ifdef LOG_BIOS `ERROR("tl_ul_bios", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {(XLEN){1'b0}}, req_size)); `endif
                        end
                    endcase

                end else begin
                    resp_opcode <= TL_ACCESS_ACK;
                    resp_data   <= {XLEN{1'b0}};
                    // Handle write operations based on store size
                    case (req_size)
                        3'b000: begin // byte
                            if (wstrb_count == 1) begin
                                mem_idata_reg[ 8*byte_offset +: 8 ] <= req_wdata[7:0];
                            end else begin
                                `ifdef LOG_BIOS `ERROR("tl_ul_bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                resp_opcode <= TL_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                            end
                        end
                        3'b001: begin // half-word
                            if (XLEN == 32) begin
                                if (wstrb_count == 2 &&
                                    ((req_wstrb[0] && req_wstrb[1]) ||
                                    (req_wstrb[2] && req_wstrb[3])))
                                begin
                                    mem_idata_reg[ 8*byte_offset +: 16 ] <= req_wdata[15:0];

                                end else begin
                                    `ifdef LOG_BIOS `ERROR("tl_ul_bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end else if (XLEN == 64) begin
                                if (wstrb_count == 2 &&
                                    ((req_wstrb[0] && req_wstrb[1]) ||
                                    (req_wstrb[2] && req_wstrb[3]) ||
                                    (req_wstrb[4] && req_wstrb[5]) ||
                                    (req_wstrb[6] && req_wstrb[7])))
                                begin
                                    mem_idata_reg[ 8*byte_offset +: 16 ] <= req_wdata[15:0];
                                end else begin
                                    `ifdef LOG_BIOS `ERROR("tl_ul_bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end
                        end
                        3'b010: begin // word
                            if (XLEN == 32) begin
                                if (wstrb_count == 4 &&
                                    ((req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3])))
                                begin
                                    mem_idata_reg[ 8*byte_offset +: 32 ] <= req_wdata[31:0];
                                end else begin
                                    `ifdef LOG_BIOS `ERROR("tl_ul_bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end else if (XLEN == 64) begin
                                if (wstrb_count == 4 &&
                                    ((req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3]) ||
                                    (req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && req_wstrb[7])))
                                begin
                                    mem_idata_reg[ 8*byte_offset +: 32 ] <= req_wdata[31:0];
                                end else begin
                                    `ifdef LOG_BIOS `ERROR("tl_ul_bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                    resp_opcode <= TL_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                end
                            end
                        end
                        3'b011: if (XLEN >= 64) begin // double-word
                            if (wstrb_count == 8 &&
                                (req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3] && req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && tl_a_mask[7]))
                            begin
                                mem_idata_reg[ 8*byte_offset +: 64 ] <= req_wdata[63:0];
                            end else begin
                                `ifdef LOG_BIOS `ERROR("tl_ul_bios", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                                resp_opcode <= TL_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                            end
                        end
                        default: begin
                            `ifdef LOG_BIOS `ERROR("tl_ul_bios", ("/PROCESS/ WRITE Size Error req_address=%0h, resp_data=%0h req_size=%0b tl_a_mask=%0b", req_address, req_wdata, req_size, tl_a_mask)); `endif
                            resp_opcode <= TL_ACCESS_ACK_ERROR;
                            resp_denied <= 1'b1;
                            resp_param  <= 2'b10; // Error param
                        end
                    endcase
                end

                if (~req_read) begin
                    state <= WRITE_BACK;
                end else begin
                    state <= RESPOND;
                end
            end

            WRITE_BACK: begin
                if (!mem_done) begin
                    `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/WRITE_BACK/ tl_a_address=%0h", tl_a_address)); `endif
                    mem_read  <= 1'b0;
                    mem_write <= 1'b1;  // Indicate a write operation
                    mem_start <= 1'b1;  // Start the memory access
                    state <= WRITE_BACK;
                end else if (mem_done) begin
                    mem_start <= 1'b0;
                    state <= RESPOND;
                end
            end

            RESPOND: begin
                `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/RESPOND/ resp_data=0x%08h resp_opcode=%0b resp_corrupt=%0b resp_denied=%0b", resp_data, resp_opcode, resp_corrupt, resp_denied)); `endif
                // Assign response signals
                tl_d_opcode  <= resp_opcode;
                tl_d_param   <= resp_param;
                tl_d_size    <= req_size;
                tl_d_source  <= resp_source;
                tl_d_data    <= resp_data;
                tl_d_corrupt <= resp_corrupt;
                tl_d_denied  <= resp_denied;
                tl_d_valid   <= 1'b1;
                state        <= RESPOND_WAIT;
            end

            RESPOND_WAIT: begin
                if (tl_d_ready) begin
                    `ifdef LOG_BIOS `LOG("tl_ul_bios", ("/COMPLETED/ resp_data=0x%08h resp_opcode=%0b resp_corrupt=%0b resp_denied=%0b", tl_d_data, tl_d_opcode, tl_d_corrupt, tl_d_denied)); `endif
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

`endif // __TL_UL_BIOS__
