`ifndef __P_MEMORY__
`define __P_MEMORY__
///////////////////////////////////////////////////////////////////////////////////////////////////
// p_memory Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module p_memory
 * @brief Parallel Bus Memory Module for Handling Read and Write Transactions.
 *
 * The `p_memory` module emulates a memory subsystem that interfaces with a parallel bus. It
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

`include "block_ram.sv"
`include "log.sv"

module p_memory #(
    parameter int XLEN = 32,
    parameter int SIZE = 1024,
    parameter int WIDTH = 8
) (
    input  wire                 clk,
    input  wire                 reset,

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
    `ASSERT((SIZE % (WIDTH / 8) == 0), "SIZE must be a multiple of WIDTH/8 to ensure proper byte alignment.");
    `ifdef LOG_MEMORY `LOG("p_memory", ("memory address size is %00d bits", $clog2(SIZE/(WIDTH/8)))); `endif
end

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
reg [XLEN/8-1:0]    req_wstrb;
reg [XLEN-1:0]      req_wdata;

// Registers to hold computed response data before asserting bus_valid
reg [XLEN-1:0]      resp_data;
reg                 resp_denied;
reg                 resp_corrupt;

// Function to calculate maximum address based on access size
function int max_valid_address(input [2:0] size);
    case (size)
        3'b000 : max_valid_address = SIZE - 1;            // Byte
        3'b001 : max_valid_address = SIZE - 2;            // Halfword
        3'b010 : max_valid_address = SIZE - 4;            // Word
        3'b011 : max_valid_address = SIZE - 8;            // Double-Word
        3'b100 : max_valid_address = SIZE - 16;           // Quad-Word (if XLEN >= 128)
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
block_ram #(
    .SIZE           (SIZE),
    .WIDTH          (WIDTH)
) block_ram_inst (
	.clk            (clk),
	.reset          (reset),
	.write_en       (block_write_en),
	.write_address  (block_write_address),
	.write_data     (block_write_data),
	.read_address   (block_read_address),
	.read_data      (block_read_data)
);

localparam BLOCK_ADDRESS_SIZE = $clog2(SIZE/(WIDTH/8));
reg                             block_write_en;
reg [BLOCK_ADDRESS_SIZE - 1:0]  block_write_address;
reg [WIDTH-1:0]                 block_write_data;
reg [BLOCK_ADDRESS_SIZE - 1:0]  block_read_address;
reg [WIDTH-1:0]                 block_read_data;

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
localparam int MEM_PARTS_LOG2 = $clog2(MEM_PARTS);
reg [MEM_PARTS_LOG2:0] mem_count;      // Internal Counter for mem ops
reg                    mem_read;       // Input set high for read mem op
reg                    mem_write;      // Input set high for write mem op
reg                    mem_start;      // Input set high to start mem op
reg                    mem_done;       // Output will be high when mem op is done
reg [1:0]              mem_read_state; // 00 = set addr, 01 = wait, 10 = read data
reg [XLEN-1:0]         mem_idata_reg;  // Input memory data register
reg [XLEN-1:0]         mem_odata_reg;  // Output memory data register

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        // Reset all control and data registers
        mem_count           <= 0;
        mem_done            <= 0;
        mem_read_state      <= 0;
        block_write_en      <= 0;
        block_write_address <= 0;
        block_write_data    <= 0;
        block_read_address  <= 0;
        mem_odata_reg       <= 0;
    end else if (mem_start && ~mem_done) begin
        if (mem_write && ~mem_read) begin
            if (mem_count < MEM_PARTS) begin
                `ifdef LOG_MEMORY `LOG("p_memory", ("/MEM_WRITE/ xlen=%0d width=%0d block_write_address=0x%0h block_write_data=0x%0h", XLEN, WIDTH, mem_word_addr + mem_count, mem_idata_reg[WIDTH*(mem_count+1)-1 -: WIDTH])); `endif
                block_write_address <= mem_word_addr[BLOCK_ADDRESS_SIZE - 1 : 0] + mem_count;
                block_write_data    <= mem_idata_reg[WIDTH*(mem_count+1)-1 -: WIDTH];
                block_write_en      <= 1'b1;

                // Increment the counter for the next part
                mem_count <= (mem_count + 1) & {MEM_PARTS_LOG2{1'b1}};
                mem_done  <= 1'b0;

                // Memory operation completed
                if (mem_count == MEM_PARTS - 1) begin
                    mem_done  <= 1'b1;
                    mem_count <= 1'b0;
                end
            end
        end

        if (~mem_write && mem_read) begin
            if (mem_count < MEM_PARTS) begin
                if (mem_read_state == 2'b00) begin
                    `ifdef LOG_MEMORY `LOG("p_memory", ("/MEM_READ/ xlen=%0d width=%0d block_read_address=0x%0h mem_part=%0d", XLEN, WIDTH, mem_word_addr + mem_count, mem_count)); `endif
                    block_read_address <= mem_word_addr[BLOCK_ADDRESS_SIZE - 1 : 0] + mem_count;
                    mem_read_state     <= 2'b01;
                    if (mem_count == 0) begin
                        mem_odata_reg <= {XLEN{1'b0}};
                    end
                end else if (mem_read_state == 2'b10) begin
                    `ifdef LOG_MEMORY `LOG("p_memory", ("/MEM_READ/ xlen=%0d width=%0d block_read_address=0x%0h mem_part=%0d block_read_data=%00h", XLEN, WIDTH, block_read_address, mem_count, block_read_data)); `endif
                    mem_read_state <= 2'b00;
                    mem_odata_reg <= mem_odata_reg | block_read_data << (WIDTH * mem_count);

                    // Increment the counter for the next part
                    mem_count <= (mem_count + 1) & {MEM_PARTS_LOG2{1'b1}};
                    mem_done  <= 1'b0;

                    // Memory operation completed
                    if (mem_count == MEM_PARTS - 1) begin
                        mem_done  <= 1'b1;
                        mem_count <= 1'b0;
                    end
                end else begin
                    // Just wait for block_read_data to be valid
                    mem_read_state <= 2'b10;
                end
            end
        end
    end else begin
        // When not active, ensure mem_done is deasserted and control signals are reset
        mem_done            <= 1'b0;
        mem_count           <= 0;
        mem_read_state      <= 2'b00;
        block_write_en      <= 1'b0;
        block_write_address <= 0;
        block_write_data    <= 0;
        block_read_address  <= 0;
    end
end

// Bus Request
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        state        <= IDLE;
        bus_ready    <= '0;
        resp_denied  <= 1'b0;
        resp_corrupt <= 1'b0;
        mem_start    <= 1'b0;
    `ifdef DEBUG
    end else if (dbg_wait == 1) begin
        // Do nothing
    `endif
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

                    // Check for debug conditions
                    `ifdef DEBUG
                    if (bus_rw) begin
                        // For read requests
                        if (bus_addr == dbg_corrupt_read_address) begin
                            resp_corrupt <= 1'b1;
                            `ifdef LOG_MEMORY `LOG("p_memory", ("Corrupt read at address %h", bus_addr)); `endif
                        end
                        if (bus_addr == dbg_denied_read_address) begin
                            resp_denied <= 1'b1;
                            `ifdef LOG_MEMORY `LOG("p_memory", ("Denied read at address %h", bus_addr)); `endif
                        end
                    end else begin
                        // For write requests
                        if (bus_addr == dbg_corrupt_write_address) begin
                            resp_corrupt <= 1'b1;
                            `ifdef LOG_MEMORY `LOG("p_memory", ("Corrupt write at address %h", bus_addr)); `endif
                        end
                        if (bus_addr == dbg_denied_write_address) begin
                            resp_denied <= 1'b1;
                            `ifdef LOG_MEMORY `LOG("p_memory", ("Denied write at address %h", bus_addr)); `endif
                        end
                    end
                    `endif

                    if (bus_addr > max_valid_address(req_size)) begin
                        `ifdef LOG_MEMORY `LOG("p_memory", ("Invalid address access: 0x%h", bus_addr)); `endif
                        resp_denied <= 1'b1;
                    end

                    `ifdef LOG_MEMORY `LOG("p_memory", ("/IDLE/ bus_addr=%0h", bus_addr)); `endif
                    state <= FETCH;
                end
            end

            FETCH: begin
                // If denied or corrupted, set response accordingly
                if (resp_denied) begin
                    resp_data <= {XLEN{1'b0}};
                    state     <= RESPOND;
                end else if (resp_corrupt) begin
                    // Optionally, set resp_data to a corrupted value
                    // For demonstration, flipping the LSB
                    resp_data <= req_read ? (resp_data ^ {{(XLEN-1){1'b0}}, 1'b1}) : {XLEN{1'b1}};
                    state     <= RESPOND;
                end else begin
                    // Initiate multi-part memory read
                    if (!mem_done) begin
                        `ifdef LOG_MEMORY `LOG("p_memory", ("/FETCH/ bus_addr=%0h", bus_addr)); `endif
                        mem_read  <= 1'b1;  // Indicate a read operation
                        mem_write <= 1'b0;
                        mem_start <= 1'b1;  // Start the memory access
                        state <= FETCH;
                    end else if (mem_done) begin
                        mem_start     <= 1'b0;
                        mem_idata_reg <= mem_odata_reg;
                        state <= PROCESS;
                    end
                end
            end

            PROCESS: begin
                // Read Request
                if (req_read) begin
                    case (req_size)
                        3'b000: begin
                            // Byte
                            resp_data <= {{(XLEN-8){1'b0}}, mem_odata_reg[ 8*byte_offset +: 8 ]};
                            `ifdef LOG_MEMORY `LOG("p_memory", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-8){1'b0}}, mem_odata_reg[ 8*byte_offset +: 8 ]}, req_size)); `endif
                        end
                        3'b001: begin
                            // Halfword
                            resp_data <= {{(XLEN-16){1'b0}}, mem_odata_reg[ 8*byte_offset +: 16 ]};
                            `ifdef LOG_MEMORY `LOG("p_memory", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-16){1'b0}}, mem_odata_reg[ 8*byte_offset +: 16 ]}, req_size)); `endif
                        end
                        3'b010: begin
                            // Word
                            resp_data <= {{(XLEN-32){1'b0}}, mem_odata_reg[ 8*byte_offset +: 32 ]};
                            `ifdef LOG_MEMORY `LOG("p_memory", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-32){1'b0}}, mem_odata_reg[ 8*byte_offset +: 32 ]}, req_size)); `endif
                        end
                        3'b011: begin
                            // Double-word
                            if (XLEN >= 64) begin
                                resp_data  <= mem_odata_reg[ 8*byte_offset +: 64 ];
                                `ifdef LOG_MEMORY `LOG("p_memory", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-64){1'b0}}, mem_odata_reg[ 8*byte_offset +: 64 ]}, req_size)); `endif
                            end else begin
                                resp_data <= {(XLEN){1'b0}};
                            end
                        end
                        3'b100: if (XLEN >= 128) begin
                            resp_data   <= {{(XLEN-128){1'b0}}, mem_odata_reg[ 8*byte_offset +: 128 ]};
                            `ifdef LOG_MEMORY `LOG("p_memory", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {{(XLEN-128){1'b0}}, mem_odata_reg[ 8*byte_offset +: 128 ]}, req_size)); `endif
                        end
                        default: begin
                            resp_data <= {(XLEN){1'b0}};
                            `ifdef LOG_MEMORY `ERROR("p_memory", ("/PROCESS/ READ req_address=%0h, resp_data=%0h req_size=%0b", req_address, {(XLEN){1'b0}}, req_size)); `endif
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
                                mem_idata_reg[ 8*byte_offset +: 8 ] <= req_wdata[7:0];
                            end else begin
                                `ifdef LOG_MEMORY `ERROR("p_memory", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                resp_denied <= 1'b1;
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
                                    `ifdef LOG_MEMORY `ERROR("p_memory", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                    resp_denied <= 1'b1;
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
                                    `ifdef LOG_MEMORY `ERROR("p_memory", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                    resp_denied <= 1'b1;
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
                                    `ifdef LOG_MEMORY `ERROR("p_memory", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                    resp_denied <= 1'b1;
                                end
                            end else if (XLEN == 64) begin
                                if (wstrb_count == 4 &&
                                    ((req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3]) ||
                                    (req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && req_wstrb[7])))
                                begin
                                    mem_idata_reg[ 8*byte_offset +: 32 ] <= req_wdata[31:0];
                                end else begin
                                    `ifdef LOG_MEMORY `ERROR("p_memory", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                    resp_denied <= 1'b1;
                                end
                            end
                        end
                        3'b011: if (XLEN >= 64) begin // double-word
                            if (wstrb_count == 8 &&
                                (req_wstrb[0] && req_wstrb[1] && req_wstrb[2] && req_wstrb[3] && req_wstrb[4] && req_wstrb[5] && req_wstrb[6] && bus_wstrb[7]))
                            begin
                                mem_idata_reg[ 8*byte_offset +: 64 ] <= req_wdata[63:0];
                            end else begin
                                `ifdef LOG_MEMORY `ERROR("p_memory", ("/PROCESS/ WRITE Alignment Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                                resp_denied <= 1'b1;
                            end
                        end
                        default: begin
                            `ifdef LOG_MEMORY `ERROR("p_memory", ("/PROCESS/ WRITE Size Error req_address=%0h, resp_data=%0h req_size=%0b bus_wstrb=%0b", req_address, req_wdata, req_size, bus_wstrb)); `endif
                            resp_denied <= 1'b1;
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
                    `ifdef LOG_MEMORY `LOG("p_memory", ("/WRITE_BACK/ bus_addr=%0h", bus_addr)); `endif
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
                `ifdef LOG_MEMORY `LOG("p_memory", ("/RESPOND/ resp_data=0x%08h resp_corrupt=%0b resp_denied=%0b", resp_data, resp_corrupt, resp_denied)); `endif
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
                    `ifdef LOG_MEMORY `LOG("p_memory", ("/COMPLETED/ resp_data=0x%08h resp_corrupt=%0b resp_denied=%0b", bus_rdata, bus_corrupt, bus_denied)); `endif
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

`endif // __P_MEMORY__
