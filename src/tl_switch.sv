`ifndef __TL_SWITCH__
`define __TL_SWITCH__
///////////////////////////////////////////////////////////////////////////////////////////////////
// tl_switch Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module tl_switch
 * @brief TileLink-UL Switch for Routing Requests and Responses Between Masters and Slaves.
 *
 */

`timescale 1ns / 1ps
`default_nettype none

`include "log.sv"

`ifdef LOG_SWITCH
`define LOG_SWITCH_A
`define LOG_SWITCH_D
`endif

module tl_switch #(
    parameter NUM_INPUTS    = 4,
    parameter NUM_OUTPUTS   = 4,
    parameter XLEN          = 32,
    parameter SID_WIDTH     = 8,
    parameter TRACK_DEPTH   = 16
)(
    input  wire                               clk,
    input  wire                               reset,

    // ======================
    // TileLink A Channel - Masters
    // ======================
    input  wire  [NUM_INPUTS-1:0]             a_valid,      // Indicates that each master has a valid request
    output reg   [NUM_INPUTS-1:0]             a_ready,      // Indicates that the switch has accepted requests from each master
    input  wire  [NUM_INPUTS*3-1:0]           a_opcode,     // Operation codes for each master’s request
    input  wire  [NUM_INPUTS*3-1:0]           a_param,      // Additional parameters for each master’s request
    input  wire  [NUM_INPUTS*3-1:0]           a_size,       // Size of each request in log2(Bytes per beat).
    input  wire  [NUM_INPUTS*SID_WIDTH-1:0]   a_source,     // Source IDs for each master’s request
    input  wire  [NUM_INPUTS*XLEN-1:0]        a_address,    // Addresses for each master’s request
    input  wire  [NUM_INPUTS*(XLEN/8)-1:0]    a_mask,       // Write byte masks for each master’s write requests
    input  wire  [NUM_INPUTS*XLEN-1:0]        a_data,       // Data payloads for each master’s write requests

    // ======================
    // TileLink D Channel - Masters
    // ======================
    output reg   [NUM_INPUTS-1:0]            d_valid,       // Indicates that the switch has a valid response for each master
    input  wire  [NUM_INPUTS-1:0]            d_ready,       // Indicates that each master is ready to accept responses
    output reg   [NUM_INPUTS*3-1:0]          d_opcode,      // Response codes for each master’s response
    output reg   [NUM_INPUTS*2-1:0]          d_param,       // Additional parameters for each master’s response
    output reg   [NUM_INPUTS*3-1:0]          d_size,        // Size of each request in log2(Bytes per beat)
    output reg   [NUM_INPUTS*SID_WIDTH-1:0]  d_source,      // Source IDs corresponding to each master’s response
    output reg   [NUM_INPUTS*XLEN-1:0]       d_data,        // Data payloads for read responses from each slave
    output reg   [NUM_INPUTS-1:0]            d_corrupt,     // Indicates corruption in the data payload for each slave’s response
    output reg   [NUM_INPUTS-1:0]            d_denied,      // Indicates that the request was denied for each slave’s response

    // ======================
    // A Channel - Slaves
    // ======================
    output reg   [NUM_OUTPUTS-1:0]           s_a_valid,      // Indicates that each master has a valid request
    input  wire  [NUM_OUTPUTS-1:0]           s_a_ready,      // Indicates that the switch has accepted requests from each master
    output reg   [NUM_OUTPUTS*3-1:0]         s_a_opcode,     // Operation codes for each master’s request 
    output reg   [NUM_OUTPUTS*2-1:0]         s_a_param,      // Additional parameters for each master’s request 
    output reg   [NUM_OUTPUTS*3-1:0]         s_a_size,       // Size of each request in log2(Bytes per beat). 
    output reg   [NUM_OUTPUTS*SID_WIDTH-1:0] s_a_source,     // Source IDs for each master’s request 
    output reg   [NUM_OUTPUTS*XLEN-1:0]      s_a_address,    // Addresses for each master’s request 
    output reg   [NUM_OUTPUTS*(XLEN/8)-1:0]  s_a_mask,       // Write byte masks for each master’s write requests 
    output reg   [NUM_OUTPUTS*XLEN-1:0]      s_a_data,       // Data payloads for each master’s write requests 

    // ======================
    // D Channel - Slaves
    // ======================
    input  wire  [NUM_OUTPUTS-1:0]            s_d_valid,     // Indicates that the switch has a valid response for each master 
    output reg   [NUM_OUTPUTS-1:0]            s_d_ready,     // Indicates that each master is ready to accept responses 
    input  wire  [NUM_OUTPUTS*3-1:0]          s_d_opcode,    // Response codes for each master’s response 
    input  wire  [NUM_OUTPUTS*2-1:0]          s_d_param,     // Additional parameters for each master’s response 
    input  wire  [NUM_OUTPUTS*3-1:0]          s_d_size,      // Size of each request in log2(Bytes per beat) 
    input  wire  [NUM_OUTPUTS*SID_WIDTH-1:0]  s_d_source,    // Source IDs corresponding to each master’s response 
    input  wire  [NUM_OUTPUTS*XLEN-1:0]       s_d_data,      // Data payloads for read responses from each slave 
    input  wire  [NUM_OUTPUTS-1:0]            s_d_corrupt,   // Indicates corruption in the data payload for each slave’s response 
    input  wire  [NUM_OUTPUTS-1:0]            s_d_denied,    // Indicates that the request was denied for each slave’s response 

    // ======================
    // Base Addresses for Slaves
    // ======================
    input  wire [NUM_OUTPUTS*XLEN-1:0]        base_addr,     // Holds the base address for a slave
    input  wire [NUM_OUTPUTS*XLEN-1:0]        addr_mask      // Holds the address space size for a slave
);

initial begin
    `ASSERT((XLEN == 32 || XLEN == 64), "XLEN must be 32 or 64.");
    `ASSERT((NUM_INPUTS >= 1), "NUM_INPUTS must be 1 or more.");
    `ASSERT((NUM_OUTPUTS >= 1), "NUM_OUTPUTS must be 1 or more.");
    `ASSERT((SID_WIDTH >= 2), "SID_WIDTH must be 2 or more.");
    `ASSERT(((TRACK_DEPTH & (TRACK_DEPTH - 1)) == 0), "TRACK_DEPTH must be a power of 2.");
end

// ======================
// Internal Definitions
// ======================

localparam int NUM_INPUTS_LOG2  = (NUM_INPUTS > 1)  ? $clog2(NUM_INPUTS)  : 1;
localparam int NUM_OUTPUTS_LOG2 = (NUM_OUTPUTS > 1) ? $clog2(NUM_OUTPUTS) : 1;
localparam int TRACK_DEPTH_LOG2 = (TRACK_DEPTH > 1) ? $clog2(TRACK_DEPTH) : 1;

// ======================
// Stats
// ======================

logic [XLEN-1:0] stats_global_requests;
logic [XLEN-1:0] stats_global_responces;
logic [XLEN-1:0] stats_global_autoresponces;

initial begin
    stats_global_requests      = {XLEN{1'b0}};
    stats_global_responces     = {XLEN{1'b0}};
    stats_global_autoresponces = {XLEN{1'b0}};
end

// ======================
// Request Tracking Table
// ======================

logic [NUM_INPUTS_LOG2-1:0]  tracking_entry_master_idx [0:TRACK_DEPTH-1]; // Master IDX in request
logic [NUM_OUTPUTS_LOG2:0]   tracking_entry_slave_idx  [0:TRACK_DEPTH-1]; // Slave IDX in request  - 1 bit larger for invlaid
logic [SID_WIDTH-1:0]        tracking_entry_source_id  [0:TRACK_DEPTH-1]; // Source ID of request
logic                        tracking_entry_auto_resp  [0:TRACK_DEPTH-1]; // A router sets high when there should be an atuo-responce
logic                        tracking_entry_finished   [0:TRACK_DEPTH-1]; // D router sets high when finished
logic                        tracking_entry_valid      [0:TRACK_DEPTH-1]; // High is entry is valid, Low if not

// ======================
// Address Lookup Table
// ======================

reg [XLEN:0] lookup_base_addr [0:NUM_OUTPUTS-1];
reg [XLEN:0] lookup_top_addr  [0:NUM_OUTPUTS-1];

genvar al_idx;
generate
for (al_idx = 0; al_idx < NUM_OUTPUTS; al_idx++) begin : lookup_table
    initial begin
        `ifdef LOG_SWITCH_MAP
        int hex_width;
        string format_str;
        hex_width = XLEN / 4;
        format_str = $sformatf("Slave %%0d: 0x%%0%0dX ... 0x%%0%0dX", hex_width, hex_width);
        `endif

        lookup_base_addr[al_idx] = base_addr[al_idx*XLEN +: XLEN];
        // Calculate the top_address for each slave from the base and mask
        lookup_top_addr[al_idx]  = {1'b0, base_addr[al_idx*XLEN +: XLEN]} +
                                   {1'b0, addr_mask[al_idx*XLEN +: XLEN]};

        `ASSERT((!lookup_top_addr[al_idx][XLEN]), "Carry-over detected in lookup_top_addr");

        `ifdef LOG_SWITCH_MAP
        `LOG("tl_switch", (format_str, al_idx, lookup_base_addr[al_idx][XLEN-1:0], lookup_top_addr[al_idx][XLEN-1:0]));
        `endif
    end
end
endgenerate

// ======================
// Master Address Decode
// ======================

// One bit larger so we can mark as invalid
reg [NUM_OUTPUTS_LOG2:0] master_slave_idx      [0:NUM_INPUTS-1];
reg [XLEN-1:0]           master_mapped_address [0:NUM_INPUTS-1];

genvar ad_idx;
generate
for (ad_idx = 0; ad_idx < NUM_INPUTS; ad_idx++) begin : master_decode
    always_comb begin
        // Default assignments
        master_slave_idx[ad_idx]      = {(NUM_OUTPUTS_LOG2+1){1'b1}};
        master_mapped_address[ad_idx] = {XLEN{1'b0}}; // Assign a default value

        for (integer al_lookup = 0; al_lookup < NUM_OUTPUTS; al_lookup++) begin
            if ((a_address[ad_idx*XLEN +: XLEN] >= lookup_base_addr[al_lookup]) &&
                (a_address[ad_idx*XLEN +: XLEN] <= lookup_top_addr[al_lookup])) begin
                master_slave_idx[ad_idx]      = {1'b0, al_lookup[NUM_OUTPUTS_LOG2-1:0]};
                master_mapped_address[ad_idx] = a_address[ad_idx*XLEN +: XLEN] - lookup_base_addr[al_lookup][XLEN-1:0];
            end
        end
    end
end
endgenerate

// ======================
// A Channel Router
// ======================

typedef enum logic [2:0] {
    A_RESET_TRACKING = 3'b000,
    A_NEXT_MASTER    = 3'b001,
    A_TRACKING_SCAN  = 3'b010,
    A_SLAVE_READY    = 3'b011,
    A_SLAVE_ACK      = 3'b100,
    A_SLAVE_FINISH   = 3'b101,
    A_NEXT_TRACKING  = 3'b110
} a_channel_fsm;
a_channel_fsm a_fsm_state;

reg [NUM_INPUTS_LOG2-1:0] a_m_idx;   // A Channel Master Index
reg [TRACK_DEPTH_LOG2-1:0] a_t_idx;  // A Channel Tracking Index
reg [TRACK_DEPTH_LOG2:0] a_mts;      // A Channel Master's Tracking Slot

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        // Reset counters
        a_m_idx <= {NUM_INPUTS_LOG2{1'b0}};
        a_t_idx <= {TRACK_DEPTH_LOG2{1'b0}};
        a_fsm_state <= A_RESET_TRACKING;

        // Reset channel acks
        a_ready <= {NUM_INPUTS{1'b0}};
        s_a_valid <= {NUM_OUTPUTS{1'b0}};
    end else begin
        case (a_fsm_state)
            A_RESET_TRACKING: begin
                `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_RESET_TRACKING/ a_t_idx=%0d", a_t_idx)); `endif

                tracking_entry_master_idx[a_t_idx] <= {NUM_INPUTS_LOG2{1'b0}};
                tracking_entry_slave_idx[a_t_idx]  <= {NUM_OUTPUTS_LOG2+1{1'b0}};
                tracking_entry_source_id[a_t_idx]  <= {SID_WIDTH{1'b0}};
                tracking_entry_auto_resp[a_t_idx]  <= 1'b0;
                tracking_entry_valid[a_t_idx]      <= 1'b0;

                if (a_t_idx == TRACK_DEPTH-1) begin
                    a_t_idx <= {TRACK_DEPTH_LOG2{1'b0}};
                    a_fsm_state <= A_NEXT_MASTER;
                end else begin
                    a_t_idx <= a_t_idx + 1'b1;
                    a_fsm_state <= A_RESET_TRACKING;
                end
            end

            A_NEXT_MASTER: begin
                `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_NEXT_MASTER/")); `endif

                a_mts = TRACK_DEPTH; // No slot found

                if (a_m_idx == NUM_INPUTS-1) begin
                    a_m_idx <= {NUM_INPUTS_LOG2{1'b0}};
                end else begin
                    a_m_idx <= a_m_idx + 1'b1;
                end

                a_fsm_state <= A_TRACKING_SCAN;
            end

            A_TRACKING_SCAN: begin
                `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_TRACKING_SCAN/ a_m_idx=%0d a_t_idx=%0d", a_m_idx, a_t_idx)); `endif

                if (tracking_entry_valid[a_t_idx] && tracking_entry_master_idx[a_t_idx] == a_m_idx &&
                    tracking_entry_source_id[a_t_idx] == a_source[a_m_idx*SID_WIDTH +: SID_WIDTH])
                begin
                    a_mts <= a_t_idx;
                end

                if (a_t_idx == TRACK_DEPTH-1) begin
                    a_t_idx <= {TRACK_DEPTH_LOG2{1'b0}};
                    a_fsm_state <= A_SLAVE_READY;
                end else begin
                    a_t_idx <= a_t_idx + 1'b1;
                    a_fsm_state <= A_TRACKING_SCAN;
                end
            end

            A_SLAVE_READY: begin
                if (a_mts == TRACK_DEPTH && a_valid[a_m_idx] && ~a_ready[a_m_idx] && 
                    ~tracking_entry_valid[a_t_idx] && ~tracking_entry_finished[a_t_idx]) 
                begin
                    // Auto-respond if slave_idx is invalid
                    if (master_slave_idx[a_m_idx] == {(NUM_OUTPUTS_LOG2+1){1'b1}}) begin
                        `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_SLAVE_READY/ auto-respond a_m_idx=%0d a_mts=%0d slave=%0d", a_m_idx, a_mts, master_slave_idx[a_m_idx])); `endif
                        tracking_entry_master_idx[a_t_idx] <= a_m_idx;
                        tracking_entry_slave_idx[a_t_idx]  <= master_slave_idx[a_m_idx];
                        tracking_entry_source_id[a_t_idx]  <= a_source[a_m_idx*SID_WIDTH +: SID_WIDTH];
                        tracking_entry_valid[a_t_idx]      <= 1'b1;
                        a_ready[a_m_idx]                   <= 1'b1;

                        a_mts       <= a_t_idx;
                        a_fsm_state <= A_SLAVE_FINISH;
                    end

                    // Otherwise forward to that slave if it is free
                    else if (~s_a_valid[ master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0] ]) begin
                        `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_SLAVE_READY/ forwarding request a_m_idx=%0d a_mts=%0d slave=%0d", a_m_idx, a_mts, master_slave_idx[a_m_idx])); `endif
                        tracking_entry_master_idx[a_t_idx]  <= a_m_idx;
                        tracking_entry_slave_idx[a_t_idx]   <= master_slave_idx[a_m_idx];
                        tracking_entry_source_id[a_t_idx]   <= a_source[a_m_idx*SID_WIDTH +: SID_WIDTH];
                        tracking_entry_valid[a_t_idx]       <= 1'b1;
                        a_ready[a_m_idx]                    <= 1'b1;

                        s_a_valid[master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0]]                           <= a_valid[a_m_idx];
                        s_a_opcode[(master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0])*3 +: 3]                 <= a_opcode[a_m_idx*3 +: 3];
                        s_a_param[(master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0])*2 +: 2]                  <= a_param[a_m_idx*2 +: 2];
                        s_a_size[(master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0])*3 +: 3]                   <= a_size[a_m_idx*3 +: 3];
                        s_a_source[(master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0])*SID_WIDTH +: SID_WIDTH] <= a_source[a_m_idx*SID_WIDTH +: SID_WIDTH];
                        s_a_address[(master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0])*XLEN +: XLEN]          <= master_mapped_address[a_m_idx];
                        s_a_mask[(master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0])*(XLEN/8) +: (XLEN/8)]     <= a_mask[a_m_idx*(XLEN/8) +: (XLEN/8)];
                        s_a_data[(master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0])*XLEN +: XLEN]             <= a_data[a_m_idx*XLEN +: XLEN];

                        a_mts       <= a_t_idx;
                        a_fsm_state <= A_SLAVE_ACK;
                    end

                    // Otherwise slave is still busy, move on
                    else begin
                        `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_SLAVE_READY/ busy a_m_idx=%0d a_mts=%0d slave=%0d", a_m_idx, a_mts, master_slave_idx[a_m_idx])); `endif
                        a_fsm_state <= A_NEXT_TRACKING;
                    end
                end else begin
                    `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_SLAVE_READY/ auto-respond a_t_idx=%0d a_m_idx=%0d a_mts=%0d a_valid=%0d a_ready=%0d tracking_entry_valid=%0d tracking_entry_finished=%0d", a_t_idx, a_m_idx, a_mts, a_valid[a_m_idx], a_ready[a_m_idx], tracking_entry_valid[a_t_idx], tracking_entry_finished[a_t_idx])); `endif
                    a_fsm_state <= A_NEXT_TRACKING;
                end
            end

            A_SLAVE_ACK: begin
                a_ready[a_m_idx] <= 1'b0;
                if (s_a_valid[master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0]] &&
                    s_a_ready[master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0]] ) 
                begin
                    `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_SLAVE_ACK/ a_m_idx=%0d a_mts=%0d slave=%0d", a_m_idx, a_mts, master_slave_idx[a_m_idx])); `endif
                    s_a_valid[master_slave_idx[a_m_idx][NUM_OUTPUTS_LOG2-1:0]] <= 1'b0;
                end
                a_fsm_state <= A_NEXT_TRACKING;
            end

            A_SLAVE_FINISH: begin
                `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_SLAVE_FINISH/ a_m_idx=%0d a_mts=%0d", a_m_idx, a_mts)); `endif
                a_ready[a_m_idx] <= 1'b0; // Clear the request Ack
                tracking_entry_auto_resp[a_t_idx] <= 1'b1;
                a_fsm_state <= A_NEXT_TRACKING;
            end

            A_NEXT_TRACKING: begin
                `ifdef LOG_SWITCH_A`LOG("tl_switch", ("/A_NEXT_TRACKING/ a_m_idx=%0d a_mts=%0d", a_m_idx, a_mts)); `endif

                // Start resetting the tracker
                if (tracking_entry_valid[a_t_idx] == 1'b1 && tracking_entry_finished[a_t_idx] == 1'b1) begin
                    tracking_entry_valid[a_t_idx] <= 1'b0;
                end

                if (a_t_idx == TRACK_DEPTH-1) begin
                    a_t_idx <= {TRACK_DEPTH_LOG2{1'b0}};
                    a_fsm_state <= A_NEXT_MASTER;
                end else begin
                    a_t_idx <= a_t_idx + 1'b1;
                    a_fsm_state <= A_SLAVE_READY;
                end
            end

            default: a_fsm_state <= A_RESET_TRACKING;
        endcase
    end
end

// ======================
// D Channel Router
// ======================

typedef enum logic [2:0] {
    D_RESET_TRACKING   = 3'b000,
    D_NEXT_SLAVE       = 3'b001,
    D_TRACKING_SCAN    = 3'b010,
    D_SLAVE_VALID      = 3'b011,
    D_MASTER_ACK       = 3'b100,
    D_AUTO_RESPOND     = 3'b101,
    D_AUTO_RESPOND_ACK = 3'b110,
    D_FINISH           = 3'b111
} d_channel_fsm;
d_channel_fsm d_fsm_state;

reg [NUM_OUTPUTS_LOG2-1:0] d_s_idx;  // A Channel Slace Index
reg [TRACK_DEPTH_LOG2-1:0] d_t_idx;  // A Channel Tracking Index
reg [TRACK_DEPTH_LOG2:0] d_sts;      // A Channel Slave's Tracking Slot

initial begin
    s_d_ready = {NUM_INPUTS{1'b0}};
end;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        // Reset counters
        d_s_idx <= {NUM_OUTPUTS_LOG2{1'b0}};
        d_t_idx <= {TRACK_DEPTH_LOG2{1'b0}};
        d_fsm_state <= D_RESET_TRACKING;
    end else begin
        case (d_fsm_state)
            D_RESET_TRACKING: begin
                `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_RESET_TRACKING/ d_t_idx=%0d", d_t_idx)); `endif

                tracking_entry_finished[d_t_idx] <= 1'b0;

                if (d_t_idx == TRACK_DEPTH-1) begin
                    d_t_idx <= {TRACK_DEPTH_LOG2{1'b0}};
                    d_fsm_state <= D_NEXT_SLAVE;
                end else begin
                    d_t_idx <= d_t_idx + 1'b1;
                    d_fsm_state <= D_RESET_TRACKING;
                end
            end

            D_NEXT_SLAVE: begin
                `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_NEXT_SLAVE/ d_s_idx=%0d of %0d", d_s_idx, NUM_OUTPUTS-1)); `endif

                d_sts = TRACK_DEPTH; // No slot found

                if (d_s_idx == NUM_OUTPUTS-1) begin
                    d_s_idx <= {NUM_OUTPUTS_LOG2{1'b0}};
                end else begin
                    d_s_idx <= d_s_idx + 1'b1;
                end

                d_fsm_state <= D_TRACKING_SCAN;
            end

            D_TRACKING_SCAN: begin
                `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_TRACKING_SCAN/ d_s_idx=%0d d_t_idx=%0d", d_s_idx, d_t_idx)); `endif


                // Finish resetting the tracker
                if (tracking_entry_valid[d_t_idx] == 1'b0 && tracking_entry_finished[d_t_idx] == 1'b1) begin
                    `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_TRACKING_SCAN/ tracker reset d_t_idx=%0d", d_t_idx)); `endif
                    tracking_entry_finished[d_t_idx] <= 1'b0;
                end

                // Set start to auto respond
                else if (tracking_entry_auto_resp[d_t_idx] == 1'b1) begin
                    d_sts <= d_t_idx;
                    d_fsm_state <= D_AUTO_RESPOND;
                end

                // Check if this a valid tracker for the current slave
                else if (s_d_valid[d_s_idx] && tracking_entry_valid[d_t_idx] && tracking_entry_slave_idx[d_t_idx] == d_s_idx &&
                    tracking_entry_source_id[d_t_idx] == s_d_source[d_s_idx*SID_WIDTH +: SID_WIDTH])
                begin
                    d_sts <= d_t_idx;
                    d_fsm_state <= D_SLAVE_VALID;
                end

                // Move to the next tracker
                else if (d_t_idx == TRACK_DEPTH-1) begin
                    d_t_idx <= {TRACK_DEPTH_LOG2{1'b0}};
                    d_fsm_state <= D_NEXT_SLAVE;
                end else begin
                    d_t_idx <= d_t_idx + 1'b1;
                    d_fsm_state <= D_TRACKING_SCAN;
                end
            end

            D_SLAVE_VALID: begin
                if (d_sts < TRACK_DEPTH && s_d_valid[d_s_idx]) begin
                    `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_SLAVE_VALID/ Response from Slave %0d to Master %0d tracking at %0h. data=%0h", d_s_idx, tracking_entry_master_idx[d_sts], d_sts, s_d_data[d_s_idx*XLEN +: XLEN])); `endif
                    d_valid[tracking_entry_master_idx[d_sts]]                          <= s_d_valid[d_s_idx];
                    d_opcode[tracking_entry_master_idx[d_sts]*3 +: 3]                  <= s_d_opcode[d_s_idx*3 +: 3];
                    d_param[tracking_entry_master_idx[d_sts]*2 +: 2]                   <= s_d_param[d_s_idx*2 +: 2];
                    d_size[tracking_entry_master_idx[d_sts]*3 +:3]                     <= s_d_size[d_s_idx*3 +: 3];
                    d_source[tracking_entry_master_idx[d_sts]*SID_WIDTH +: SID_WIDTH]  <= s_d_source[d_s_idx*SID_WIDTH +: SID_WIDTH];
                    d_data[tracking_entry_master_idx[d_sts]*XLEN +: XLEN]              <= s_d_data[d_s_idx*XLEN +: XLEN];
                    d_corrupt[tracking_entry_master_idx[d_sts]]                        <= s_d_corrupt[d_s_idx];
                    d_denied[tracking_entry_master_idx[d_sts]]                         <= s_d_denied[d_s_idx];
                    d_fsm_state <= D_MASTER_ACK;
                end else begin
                    `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_SLAVE_VALID/ waiting d_s_idx=%0d d_sts=%0d", d_s_idx, d_sts)); `endif
                    d_fsm_state <= D_NEXT_SLAVE;
                end
            end

            D_MASTER_ACK: begin
                if (d_ready[tracking_entry_master_idx[d_sts]]) begin
                    `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_MASTER_ACK/ Response is acknowleged from Slave %0d to Master %0d tracking at %0h.", d_s_idx, tracking_entry_master_idx[d_sts], d_sts)); `endif
                    // Ack the slave
                    s_d_ready[d_s_idx] <= 1;
                    d_fsm_state <= D_FINISH;
                end else begin
                    `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_MASTER_ACK/ waiting d_s_idx=%0d d_sts=%0d", d_s_idx, d_sts)); `endif
                end
            end

            D_AUTO_RESPOND: begin
                `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_AUTO_RESPOND/ Auto Response to Master %0d tracking at %0h.", tracking_entry_master_idx[d_sts], d_sts)); `endif
                d_valid[tracking_entry_master_idx[d_sts]]                         <= 1'b1;
                d_opcode[tracking_entry_master_idx[d_sts]*3 +: 3]                 <= 3'b111;
                d_param[tracking_entry_master_idx[d_sts]*2 +: 2]                  <= 3'b00;
                d_size[tracking_entry_master_idx[d_sts]*3 +: 3]                   <= 3'b000;
                d_source[tracking_entry_master_idx[d_sts]*SID_WIDTH +: SID_WIDTH] <= tracking_entry_source_id[d_sts];
                d_data[tracking_entry_master_idx[d_sts]*XLEN +: XLEN]             <= {XLEN{1'b0}};
                d_corrupt[tracking_entry_master_idx[d_sts]]                       <= 1'b0;
                d_denied[tracking_entry_master_idx[d_sts]]                        <= 1'b1;

                d_fsm_state <= D_AUTO_RESPOND_ACK;
            end

            D_AUTO_RESPOND_ACK: begin
                if (d_ready[tracking_entry_master_idx[d_sts]]) begin
                    `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_AUTO_RESPOND_ACK/ Auto Response to Master %0d is acknowleged tracking at %0h.", tracking_entry_master_idx[d_sts], d_sts)); `endif
                    stats_global_responces <= stats_global_responces + 1;
                    stats_global_autoresponces <= stats_global_autoresponces + 1;
                    d_fsm_state <= D_FINISH;
                end
            end

            D_FINISH: begin
                `ifdef LOG_SWITCH_D `LOG("tl_switch", ("/D_FINISH/ d_s_idx=%0d", d_s_idx)); `endif
                // Cleanup, mark the tracking record as invalid so it can be reused
                // turn off the slave ack
                s_d_ready[d_s_idx]                        <= 0;
                d_valid[tracking_entry_master_idx[d_sts]] <= 0;
                tracking_entry_finished[d_sts]            <= 1;

                d_fsm_state <= D_NEXT_SLAVE;
                stats_global_responces <= stats_global_responces + 1;
            end

            default: d_fsm_state <= D_RESET_TRACKING;
        endcase
    end
end

endmodule

`endif // __TL_SWITCH__
