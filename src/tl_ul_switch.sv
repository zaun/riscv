///////////////////////////////////////////////////////////////////////////////////////////////////
// tl_ul_switch Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module tl_ul_switch
 * @brief TileLink-UL Switch for Routing Requests and Responses Between Masters and Slaves.
 *
 */

`timescale 1ns / 1ps
`default_nettype none

`include "src/log.sv"

module tl_ul_switch #(
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
    output logic [NUM_INPUTS-1:0]             a_ready,      // Indicates that the switch has accepted requests from each master
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
    output logic [NUM_INPUTS-1:0]            d_valid,       // Indicates that the switch has a valid response for each master
    input  wire  [NUM_INPUTS-1:0]            d_ready,       // Indicates that each master is ready to accept responses
    output logic [NUM_INPUTS*3-1:0]          d_opcode,      // Response codes for each master’s response
    output logic [NUM_INPUTS*2-1:0]          d_param,       // Additional parameters for each master’s response
    output logic [NUM_INPUTS*3-1:0]          d_size,        // Size of each request in log2(Bytes per beat)
    output logic [NUM_INPUTS*SID_WIDTH-1:0]  d_source,      // Source IDs corresponding to each master’s response
    output logic [NUM_INPUTS*XLEN-1:0]       d_data,        // Data payloads for read responses from each slave
    output logic [NUM_INPUTS-1:0]            d_corrupt,     // Indicates corruption in the data payload for each slave’s response
    output logic [NUM_INPUTS-1:0]            d_denied,      // Indicates that the request was denied for each slave’s response

    // ======================
    // A Channel - Slaves
    // ======================
    output logic [NUM_OUTPUTS-1:0]           s_a_valid,      //
    input  wire  [NUM_OUTPUTS-1:0]           s_a_ready,      //
    output logic [NUM_OUTPUTS*3-1:0]         s_a_opcode,     // 
    output logic [NUM_OUTPUTS*3-1:0]         s_a_param,      // 
    output logic [NUM_OUTPUTS*3-1:0]         s_a_size,       // 
    output logic [NUM_OUTPUTS*SID_WIDTH-1:0] s_a_source,     // 
    output logic [NUM_OUTPUTS*XLEN-1:0]      s_a_address,    // 
    output logic [NUM_OUTPUTS*(XLEN/8)-1:0]  s_a_mask,       // 
    output logic [NUM_OUTPUTS*XLEN-1:0]      s_a_data,       // 

    // ======================
    // D Channel - Slaves
    // ======================
    input  wire  [NUM_OUTPUTS-1:0]            s_d_valid,     // 
    output logic [NUM_OUTPUTS-1:0]            s_d_ready,     // 
    input  wire  [NUM_OUTPUTS*3-1:0]          s_d_opcode,    // 
    input  wire  [NUM_OUTPUTS*2-1:0]          s_d_param,     // 
    input  wire  [NUM_OUTPUTS*3-1:0]          s_d_size,      // 
    input  wire  [NUM_OUTPUTS*SID_WIDTH-1:0]  s_d_source,    // 
    input  wire  [NUM_OUTPUTS*XLEN-1:0]       s_d_data,      // 
    input  wire  [NUM_OUTPUTS-1:0]            s_d_corrupt,   // 
    input  wire  [NUM_OUTPUTS-1:0]            s_d_denied,    // 

    // ======================
    // Base Addresses for Slaves
    // ======================
    input  wire [NUM_OUTPUTS*XLEN-1:0]       base_addr,      // 
    input  wire [NUM_OUTPUTS*XLEN-1:0]       addr_mask       // 
);

// ======================
// Internal Definitions
// ======================

localparam int NUM_INPUTS_LOG2  = (NUM_INPUTS > 1)  ? $clog2(NUM_INPUTS)  : 1;
localparam int NUM_OUTPUTS_LOG2 = (NUM_OUTPUTS > 1) ? $clog2(NUM_OUTPUTS) : 1;
localparam int TRACK_DEPTH_LOG2 = (TRACK_DEPTH > 1) ? $clog2(TRACK_DEPTH) : 1;

typedef enum logic [2:0] {
    WAIT_SLAVE_READY,
    WAIT_SLAVE_ACK,
    A_FINISH
} a_channel_state;

typedef enum logic [2:0] {
    WAIT_SLAVE_RESP,
    WAIT_MASTER_ACK,
    FINISH,
    AUTO_RESPOND,
    WAIT_AUTO_RESPOND_ACK
} d_channel_state;

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

logic [NUM_INPUTS_LOG2-1:0]  tracking_entry_master_idx [0:TRACK_DEPTH-1];
logic [NUM_OUTPUTS_LOG2:0]   tracking_entry_slave_idx  [0:TRACK_DEPTH-1]; // 1 bit larger for invlaid
logic [SID_WIDTH-1:0]        tracking_entry_source_id  [0:TRACK_DEPTH-1];
logic                        tracking_entry_complete   [0:TRACK_DEPTH-1];
logic                        tracking_entry_valid      [0:TRACK_DEPTH-1];
a_channel_state              tracking_entry_a_state    [0:TRACK_DEPTH-1];
d_channel_state              tracking_entry_d_state    [0:TRACK_DEPTH-1];

// Initialize tracking table
integer ti;
initial begin
    for (ti = 0; ti < TRACK_DEPTH; ti = ti + 1) begin
        tracking_entry_master_idx[ti]  = {NUM_INPUTS_LOG2{1'b0}};
        tracking_entry_slave_idx[ti]   = {NUM_OUTPUTS_LOG2+1{1'b0}};
        tracking_entry_source_id[ti]   = {SID_WIDTH{1'b0}};
        tracking_entry_complete[ti]    = 1'b0;
        tracking_entry_valid[ti]       = 1'b0;
        tracking_entry_d_state[ti]     = WAIT_SLAVE_RESP;
        tracking_entry_a_state[ti]     = WAIT_SLAVE_READY;
    end
end

// ======================
// Address Lookup Table
// ======================

reg [XLEN:0] lookup_base_addr [0:NUM_OUTPUTS-1];
reg [XLEN:0] lookup_top_addr  [0:NUM_OUTPUTS-1];

genvar al_idx;
generate
for (al_idx = 0; al_idx < NUM_OUTPUTS; al_idx++) begin : lookup_table
    initial begin
        lookup_base_addr[al_idx] = base_addr[al_idx*XLEN +: XLEN];
        // Calculate the top_address for each slave from the base and mask
        lookup_top_addr[al_idx]  = {1'b0, base_addr[al_idx*XLEN +: XLEN]} +
                                   {1'b0, addr_mask[al_idx*XLEN +: XLEN]};
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
                master_mapped_address[ad_idx] = a_address[ad_idx*XLEN +: XLEN] - lookup_base_addr[al_lookup];
            end
        end
    end
end
endgenerate

// ======================
// A Channel Router
// ======================

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        // Reset channel acks
        a_ready <= {NUM_INPUTS{1'b0}};
        s_a_valid <= {NUM_OUTPUTS{1'b0}};

        // Reset the tracking table
        for (ti = 0; ti < TRACK_DEPTH; ti = ti + 1) begin
            tracking_entry_master_idx[ti]  <= {NUM_INPUTS_LOG2{1'b0}};
            tracking_entry_slave_idx[ti]   <= {NUM_OUTPUTS_LOG2+1{1'b0}};
            tracking_entry_source_id[ti]   <= {SID_WIDTH{1'b0}};
            tracking_entry_complete[ti]    <= 1'b0;
            tracking_entry_valid[ti]       <= 1'b0;
            tracking_entry_d_state[ti]     <= WAIT_SLAVE_RESP;
            tracking_entry_a_state[ti]     <= WAIT_SLAVE_READY;
        end
    end else begin
        for (int master_idx = 0; master_idx < NUM_INPUTS; master_idx++) begin : handle_master_requests
            integer master_slot_idx;
            master_slot_idx = -1;
            for (int tracking_idx = 0; tracking_idx < TRACK_DEPTH; tracking_idx = tracking_idx + 1) begin
                if (tracking_entry_valid[tracking_idx] && tracking_entry_master_idx[tracking_idx] == master_idx &&
                    tracking_entry_source_id[tracking_idx] == a_source[master_idx*SID_WIDTH +: SID_WIDTH])
                begin
                    master_slot_idx = tracking_idx;
                end
            end

            for (int tracking_idx = 0; tracking_idx < TRACK_DEPTH; tracking_idx = tracking_idx + 1) begin
                case (tracking_entry_a_state[tracking_idx])
                    WAIT_SLAVE_READY: begin
                        // Wait for an open spot
                        if ((master_slot_idx == -1 && a_valid[master_idx] && ~a_ready[master_idx] && ~tracking_entry_valid[tracking_idx])) begin
                            // Auto respond denied
                            if (master_slave_idx[master_idx] == {(NUM_OUTPUTS_LOG2+1){1'b1}}) begin
                                `ifdef LOG_SWITCH `WARN("tl_ul_switch", ("Request from Master %0d tracking at %0h auto denied, invalid slave.", master_idx, tracking_idx)); `endif
                                tracking_entry_master_idx[tracking_idx] <= master_idx;
                                tracking_entry_slave_idx[tracking_idx]  <= master_slave_idx[master_idx];
                                tracking_entry_source_id[tracking_idx]  <= a_source[master_idx*SID_WIDTH +: SID_WIDTH];
                                tracking_entry_complete[tracking_idx]   <= 1'b1;
                                tracking_entry_valid[tracking_idx]      <= 1'b1;

                                a_ready[master_idx]                     <= 1'b1;

                                tracking_entry_a_state[tracking_idx]    <= A_FINISH;
                                master_slot_idx = tracking_idx;
                            end

                            // Wait for requested slave to be free before tracking and forwarding
                            else if (~s_a_valid[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])]) begin
                                `ifdef LOG_SWITCH `LOG("tl_ul_switch", ("Request from Master %0d to Slave %0d tracking at %0h.", master_idx, master_slave_idx[master_idx], tracking_idx)); `endif
                                tracking_entry_master_idx[tracking_idx] <= master_idx;
                                tracking_entry_slave_idx[tracking_idx]  <= master_slave_idx[master_idx];
                                tracking_entry_source_id[tracking_idx]  <= a_source[master_idx*SID_WIDTH +: SID_WIDTH];
                                tracking_entry_complete[tracking_idx]   <= 1'b0;
                                tracking_entry_valid[tracking_idx]      <= 1'b1;
                                a_ready[master_idx]                     <= 1'b1;

                                s_a_valid[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])]                         <= a_valid[master_idx];
                                s_a_opcode[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])*3 +: 3]                 <= a_opcode[master_idx*3 +: 3];
                                s_a_param[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])*2 +: 2]                  <= a_param[master_idx*2 +: 2];
                                s_a_size[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])*3 +: 3]                   <= a_size[master_idx*3 +: 3];
                                s_a_source[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])*SID_WIDTH +: SID_WIDTH] <= a_source[master_idx*SID_WIDTH +: SID_WIDTH];
                                s_a_address[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])*XLEN +: XLEN]          <= master_mapped_address[master_idx];
                                s_a_mask[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])*(XLEN/8) +: (XLEN/8)]     <= a_mask[master_idx*(XLEN/8) +: (XLEN/8)];
                                s_a_data[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])*XLEN +: XLEN]             <= a_data[master_idx*XLEN +: XLEN];

                                a_ready[master_idx]                     <= 1'b1;

                                tracking_entry_a_state[tracking_idx]    <= WAIT_MASTER_ACK;
                                master_slot_idx = tracking_idx;
                            end

                            else begin
                                $display("master_idx=%0d tracking_idx=%0d", master_idx, tracking_idx);
                            end
                        end
                    end

                    WAIT_SLAVE_ACK: begin
                        a_ready[master_idx] <= 1'b0;

                        if(s_a_valid[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])] && s_a_ready[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])]) begin
                            `ifdef LOG_SWITCH `LOG("tl_ul_switch", ("Request Slave %0d acknowleged from Master %0d", master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0], master_idx)); `endif
                            s_a_valid[(master_slave_idx[master_idx][NUM_OUTPUTS_LOG2-1:0])] <= 1'b0;
                        end
                        tracking_entry_a_state[tracking_idx] <= WAIT_SLAVE_READY;
                    end

                    A_FINISH: begin
                        `ifdef LOG_SWITCH `LOG("tl_ul_switch", ("Request from Master %0d tracking at %0h starting auto denied response.", master_idx, tracking_idx)); `endif
                        a_ready[master_idx] <= 1'b0; // Clear the request Ack
                        tracking_entry_a_state[tracking_idx] <= WAIT_SLAVE_READY;
                        tracking_entry_d_state[tracking_idx] <= AUTO_RESPOND;
                    end

                    default: ;
                endcase
            end
        end
    end
end

// ======================
// D Channel Router
// ======================

initial begin
    s_d_ready = {NUM_INPUTS{1'b0}};
end;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
    end else begin
        // Handle Slave responces
        for (int slave_idx = 0; slave_idx < NUM_OUTPUTS; slave_idx++) begin : handle_slave_responces
            if (s_d_valid[slave_idx]) begin
                for (int tracking_idx = 0; tracking_idx < TRACK_DEPTH; tracking_idx = tracking_idx + 1) begin
                    if (tracking_entry_valid[tracking_idx] && tracking_entry_slave_idx[tracking_idx] == slave_idx &&
                        tracking_entry_source_id[tracking_idx] == s_d_source[slave_idx*SID_WIDTH +: SID_WIDTH])
                    begin
                        case (tracking_entry_d_state[tracking_idx])
                            WAIT_SLAVE_RESP: begin
                                if (s_d_valid[slave_idx]) begin
                                    `ifdef LOG_SWITCH `LOG("tl_ul_switch", ("Response from Slave %0d to Master %0d tracking at %0h. data=%0h", slave_idx, tracking_entry_master_idx[tracking_idx], tracking_idx, s_d_data[slave_idx*XLEN +: XLEN])); `endif
                                    d_valid[tracking_entry_master_idx[tracking_idx]]                          <= s_d_valid[slave_idx];
                                    d_opcode[tracking_entry_master_idx[tracking_idx]*3 +: 3]                  <= s_d_opcode[slave_idx*3 +: 3];
                                    d_param[tracking_entry_master_idx[tracking_idx]*2 +: 2]                   <= s_d_param[slave_idx*2 +: 2];
                                    d_size[tracking_entry_master_idx[tracking_idx]*3 +:3]                     <= s_d_size[slave_idx*3 +: 3];
                                    d_source[tracking_entry_master_idx[tracking_idx]*SID_WIDTH +: SID_WIDTH]  <= s_d_source[slave_idx*SID_WIDTH +: SID_WIDTH];
                                    d_data[tracking_entry_master_idx[tracking_idx]*XLEN +: XLEN]              <= s_d_data[slave_idx*XLEN +: XLEN];
                                    d_corrupt[tracking_entry_master_idx[tracking_idx]]                        <= s_d_corrupt[slave_idx];
                                    d_denied[tracking_entry_master_idx[tracking_idx]]                         <= s_d_denied[slave_idx];
                                    tracking_entry_d_state[tracking_idx]                                      <= WAIT_MASTER_ACK;
                                end
                            end

                            WAIT_MASTER_ACK: begin
                                if (d_ready[tracking_entry_master_idx[tracking_idx]]) begin
                                    `ifdef LOG_SWITCH `LOG("tl_ul_switch", ("Response is acknowleged from Slave %0d to Master %0d tracking at %0h.", slave_idx, tracking_entry_master_idx[tracking_idx], tracking_idx)); `endif
                                    // Ack the slave
                                    s_d_ready[slave_idx]                             <= 1;
                                    tracking_entry_d_state[tracking_idx]             <= FINISH;
                                end
                            end

                            FINISH: begin
                                // Cleanup, mark the tracking record as invalid so it can be reused
                                // turn off the slave ack
                                s_d_ready[slave_idx]                             <= 0;
                                d_valid[tracking_entry_master_idx[tracking_idx]] <= 0;
                                tracking_entry_valid[tracking_idx]               <= 0;
                                tracking_entry_d_state[tracking_idx]             <= WAIT_SLAVE_RESP;

                                stats_global_responces <= stats_global_responces + 1;
                            end

                            default: ;
                        endcase
                    end
                end
            end
        end

        // Handle auto-denied responces
        for (int tracking_idx = 0; tracking_idx < TRACK_DEPTH; tracking_idx = tracking_idx + 1) begin
            if (tracking_entry_valid[tracking_idx] && tracking_entry_complete[tracking_idx]) begin
                case(tracking_entry_d_state[tracking_idx])
                    AUTO_RESPOND: begin
                        `ifdef LOG_SWITCH `LOG("tl_ul_switch", ("Auto Response to Master %0d tracking at %0h.", tracking_entry_master_idx[tracking_idx], tracking_idx)); `endif
                        d_valid[tracking_entry_master_idx[tracking_idx]]                         <= 1'b1;
                        d_opcode[tracking_entry_master_idx[tracking_idx]*3 +: 3]                 <= 3'b111;
                        d_param[tracking_entry_master_idx[tracking_idx]*2 +: 2]                  <= 3'b00;
                        d_size[tracking_entry_master_idx[tracking_idx]*3 +: 3]                   <= 3'b000;
                        d_source[tracking_entry_master_idx[tracking_idx]*SID_WIDTH +: SID_WIDTH] <= tracking_entry_source_id[tracking_idx];
                        d_data[tracking_entry_master_idx[tracking_idx]*XLEN +: XLEN]             <= {XLEN{1'b0}};
                        d_corrupt[tracking_entry_master_idx[tracking_idx]]                       <= 1'b0;
                        d_denied[tracking_entry_master_idx[tracking_idx]]                        <= 1'b1;

                        tracking_entry_d_state[tracking_idx] <= WAIT_AUTO_RESPOND_ACK;
                    end

                    WAIT_AUTO_RESPOND_ACK: begin
                        if (d_ready[tracking_entry_master_idx[tracking_idx]]) begin
                            `ifdef LOG_SWITCH `LOG("tl_ul_switch", ("Auto Response to Master %0d is acknowleged tracking at %0h.", tracking_entry_master_idx[tracking_idx], tracking_idx)); `endif
                            d_valid[tracking_entry_master_idx[tracking_idx]] <= 0;
                            tracking_entry_valid[tracking_idx]               <= 0;
                            tracking_entry_complete[tracking_idx]            <= 0;

                            stats_global_responces <= stats_global_responces + 1;
                            stats_global_autoresponces <= stats_global_autoresponces + 1;

                            tracking_entry_d_state[tracking_idx] <= WAIT_SLAVE_RESP;
                        end
                    end

                    default: ;
                endcase
            end
        end
    end
end

endmodule
