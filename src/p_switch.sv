`ifndef __P_SWITCH__
`define __P_SWITCH__
///////////////////////////////////////////////////////////////////////////////////////////////////
// p_switch Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module p_switch
 * @brief A Parallel Switch for Routing Requests and Responses Between Sources and Targets.
 *
 * This module implements a clocked parallel switch that routes requests from multiple sources
 * to multiple targets. Each source asserts a valid request with an address, a read/write (rw)
 * signal, and write data. The target is selected from the MSBs of the source address.
 * A round-robin counter cycles through the sources (one per cycle) so that a request is
 * accepted if its target is free.
 *
 * Operation:
 * 1. When a source (selected by the round-robin counter) asserts src_a_valid and is not
 *    assigned (src_a_assigned is 0), the target ID is computed from its address:
 *      target_id = src_a_addr[source_id][XLEN-1:XLEN-$clog2(TARGET_COUNT)]
 * 2. If the target is free (tgt_a_valid[target_id] is 0), the request is assigned by driving
 *    tgt_a_valid, tgt_a_rw, tgt_a_addr, and tgt_a_wdata. src_a_assigned is set, and the computed target ID
 *    is stored in src_a_target.
 * 3. For an outstanding request (src_a_assigned is 1), on later cycles the switch checks if the
 *    target (using the stored src_a_target value) has finished by testing tgt_a_ready.
 * 4. When tgt_a_ready is asserted (with tgt_a_valid still set), the response is routed back via
 *    src_a_ready, src_a_rdata, src_a_denied, and src_a_corrupt. Then tgt_a_valid and src_a_assigned are
 *    cleared.
 * 5. If a source aborts its request (src_a_valid goes low) while assigned, the stored src_a_target
 *    is used to free the target and clear src_a_assigned.
 *
 * Note:
 * - The source address must remain stable during a transaction; otherwise, src_a_target is used.
 * - The src_a_rw signal is passed to the target via tgt_a_rw to indicate read or write.
 * - If multiple sources map to the same target, only the first processed is assigned.
 *   Other sources wait until the target is freed.
 *
 * Timing Examples:
 *
 * 1. Single Source Transaction:
 *       Cycle    :       0       1       2       3       4       5
 * -------------------------------------------------------------------
 * src_a_valid[0]   :       0       1       1       1       1       0
 * src_a_rw[0]      :       X       1       1       1       1       X
 * src_a_addr[0]    :       X     0x10    0x10    0x10    0x10      X
 * src_a_wdata[0]   :       X       X       X       X       X       X
 * src_a_ready[0]   :       X       0       0       0       1       X
 * src_a_rdata[0]   :       X       X       X       X     0xABCD    X
 * src_a_denied[0]  :       X       X       X       X       0       X
 * src_a_corrupt[0] :       X       X       X       X       0       X
 *
 * tgt_a_valid[0]   :       X       0       1       1       1       0
 * tgt_a_rw[0]      :       X       X       1       1       1       X
 * tgt_a_addr[0]    :       X       X     0x10    0x10    0x10      X
 * tgt_a_wdata[0]   :       X       X       X       X       X       X
 * tgt_a_ready[0]   :       X       X       0       1       1       X
 * tgt_a_rdata[0]   :       X       X       X     0xABCD  0xABCD    X
 * tgt_a_denied[0]  :       X       X       X       0       0       X
 * tgt_a_corrupt[0] :       X       X       X       0       0       X
 *
 *
 * 2. Multiple Source Transactions:
 *       Cycle    :       0       1       2       3       4       5       6
 * ---------------------------------------------------------------------------
 * src_a_valid[0]   :       0       1       1       1       1       0       X
 * src_a_rw[0]      :       X       1       1       1       1       X       X
 * src_a_addr[0]    :       X     0x10    0x10    0x10    0x10      X       X
 * src_a_wdata[0]   :       X       X       X       X       X       X       X
 * src_a_ready[0]   :       X       0       0       0       1       X       X
 * src_a_rdata[0]   :       X       X       X       X     0xABCD    X       X
 * src_a_denied[0]  :       X       X       X       X       0       X       X
 * src_a_corrupt[0] :       X       X       X       X       0       X       X

 * src_a_valid[1]   :       0       0       1       1       1       1       0
 * src_a_rw[1]      :       X       X       1       1       1       1       X
 * src_a_addr[1]    :       X       X     0x20    0x20    0x20    0x20      X
 * src_a_wdata[1]   :       X       X       X       X       X       X       X
 * src_a_ready[1]   :       X       X       0       0       0       1       X
 * src_a_rdata[1]   :       X       X       X       X       X     0x1234    X
 * src_a_denied[1]  :       X       X       X       X       X       0       X
 * src_a_corrupt[1] :       X       X       X       X       X       0       X
 *
 * tgt_a_valid[0]   :       X       0       1       1       1       0       X
 * tgt_a_rw[0]      :       X       X       1       1       1       X       X
 * tgt_a_addr[0]    :       X       X     0x10    0x10    0x10      X       X
 * tgt_a_wdata[0]   :       X       X       X       X       X       X       X
 * tgt_a_ready[0]   :       X       X       0       1       1       X       X
 * tgt_a_rdata[0]   :       X       X       X     0xABCD  0xABCD    X       X
 * tgt_a_denied[0]  :       X       X       X       0       0       X       X
 * tgt_a_corrupt[0] :       X       X       X       0       0       X       X
 *
 * tgt_a_valid[1]   :       X       X       0       1       1       1       0
 * tgt_a_rw[1]      :       X       X       X       1       1       1       X
 * tgt_a_addr[1]    :       X       X       X     0x20    0x20    0x20      X
 * tgt_a_wdata[1]   :       X       X       X       X       X       X       X
 * tgt_a_ready[1]   :       X       X       X       0       1       1       X
 * tgt_a_rdata[1]   :       X       X       X       X     0x1234  0x1234    X
 * tgt_a_denied[1]  :       X       X       X       X       0       0       X
 * tgt_a_corrupt[1] :       X       X       X       X       0       0       X
 *
 * 3. Source Abort:
 *    - If a source aborts its request (src_a_valid goes low) while assigned,
 *      the stored src_a_target is used to free the target and clear src_a_assigned.
 *
 */

`timescale 1ns / 1ps
`default_nettype none

`include "log.sv"

module p_switch #(
  parameter int XLEN         = 32, // Bus width
  parameter int SOURCE_COUNT = 1,  // Number of sources
  parameter int TARGET_COUNT = 1   // Number of targets
) (
    input  wire                                clk,
    input  wire                                reset,

    // Source side I/O:
    input  wire [SOURCE_COUNT-1:0]          src_valid,   // Asserts valid when there is a request
    input  wire [SOURCE_COUNT-1:0]          src_rw,      // Read/Write signal from each source
    input  wire [SOURCE_COUNT*XLEN-1:0]     src_addr,    // Address from each source
    input  wire [SOURCE_COUNT*XLEN-1:0]     src_wdata,   // Write data from each source
    input  wire [SOURCE_COUNT*(XLEN/8)-1:0] src_wstrb,   // Write byte masks for request
    input  wire [SOURCE_COUNT*3-1:0]        src_size,    // Size of each request in log2(Bytes per beat)
    output wire [SOURCE_COUNT-1:0]          src_ready,   // Ready signal back to each source
    output wire [SOURCE_COUNT*XLEN-1:0]     src_rdata,   // Read data returned to each source
    output wire [SOURCE_COUNT-1:0]          src_denied,  // Denied signal back to each source
    output wire [SOURCE_COUNT-1:0]          src_corrupt, // Corrupt signal back to each source

    // Target side I/O:
    input  wire [TARGET_COUNT-1:0]          tgt_ready,   // Asserts when work is completed
    input  wire [TARGET_COUNT*XLEN-1:0]     tgt_rdata,   // Read data from each target
    input  wire [TARGET_COUNT-1:0]          tgt_denied,  // Denied signal back to each source
    input  wire [TARGET_COUNT-1:0]          tgt_corrupt, // Corrupt signal back to each source
    output wire [TARGET_COUNT-1:0]          tgt_valid,   // Valid signal to each target
    output wire [TARGET_COUNT-1:0]          tgt_rw,      // Read/Write signal to each target
    output wire [TARGET_COUNT*XLEN-1:0]     tgt_addr,    // Address sent to each target
    output wire [TARGET_COUNT*XLEN-1:0]     tgt_wdata,   // Write data sent to each target
    output wire [TARGET_COUNT*(XLEN/8)-1:0] tgt_wstrb,   // Write byte masks for request
    output wire [TARGET_COUNT*3-1:0]        tgt_size     // Size of each request in log2(Bytes per beat)
);

localparam int SOURCE_COUNT_CLOG2 = (SOURCE_COUNT > 1) ? $clog2(SOURCE_COUNT) : 1;
localparam int TARGET_COUNT_CLOG2 = (TARGET_COUNT > 1) ? $clog2(TARGET_COUNT) : 1;

initial begin
    `ifdef LOG_SWITCH_MAP
    int i;
    int hex_width;
    int start_address, end_address;
    string format_str;
    `endif

    `ASSERT((XLEN == 32 || XLEN == 64), "XLEN must be 32 or 64.");
    `ASSERT((SOURCE_COUNT > 0), "SOURCE_COUNT number be 1 or larger.");
    `ASSERT((TARGET_COUNT > 0), "TARGET_COUNT number be 1 or larger.");

    `ifdef LOG_SWITCH_MAP
    hex_width = XLEN / 4;
    format_str = $sformatf("Target %%0d: 0x%%0%0dX ... 0x%%0%0dX", hex_width, hex_width);
    for (i = 0; i < TARGET_COUNT; i = i + 1) begin
        if (TARGET_COUNT == 1) begin
            // Single target gets the entire address space.
            start_address = 0;
            end_address   = {XLEN{1'b1}};
        end else begin
            // With more than one target, use the upper bits of the address.
            start_address = i << (XLEN - TARGET_COUNT_CLOG2);
            end_address   = ((i + 1) << (XLEN - TARGET_COUNT_CLOG2)) - 1;
        end
        `LOG("p_switch", (format_str, i, start_address, end_address));
    end
    `endif
end

// Internal arrays
wire              src_a_valid   [SOURCE_COUNT-1:0];
wire              src_a_rw      [SOURCE_COUNT-1:0];
wire [XLEN-1:0]   src_a_addr    [SOURCE_COUNT-1:0];
wire [XLEN-1:0]   src_a_wdata   [SOURCE_COUNT-1:0];
wire [XLEN/8-1:0] src_a_wstrb   [SOURCE_COUNT-1:0];
wire [2:0]        src_a_size    [SOURCE_COUNT-1:0];
reg               src_a_ready   [SOURCE_COUNT-1:0];
reg  [XLEN-1:0]   src_a_rdata   [SOURCE_COUNT-1:0];
reg               src_a_denied  [SOURCE_COUNT-1:0];
reg               src_a_corrupt [SOURCE_COUNT-1:0];

wire              tgt_a_ready   [TARGET_COUNT-1:0];
wire [XLEN-1:0]   tgt_a_rdata   [TARGET_COUNT-1:0];
wire              tgt_a_denied  [TARGET_COUNT-1:0];
wire              tgt_a_corrupt [TARGET_COUNT-1:0];
reg               tgt_a_valid   [TARGET_COUNT-1:0];
reg               tgt_a_rw      [TARGET_COUNT-1:0];
reg  [XLEN-1:0]   tgt_a_addr    [TARGET_COUNT-1:0];
reg  [XLEN-1:0]   tgt_a_wdata   [TARGET_COUNT-1:0];
reg  [XLEN/8-1:0] tgt_a_wstrb   [TARGET_COUNT-1:0];
reg  [2:0]        tgt_a_size    [TARGET_COUNT-1:0];

 // Unflatten the input using a generate loop.
genvar idx;
generate
    for (idx = 0; idx < SOURCE_COUNT; idx++) begin
        assign src_a_valid[idx]            = src_valid[idx];
        assign src_a_rw[idx]               = src_rw[idx];
        assign src_a_addr[idx]             = src_addr[idx * XLEN +: XLEN];
        assign src_a_wdata[idx]            = src_wdata[idx * XLEN +: XLEN];
        assign src_a_wstrb[idx]            = src_wstrb[idx * (XLEN/8) +: (XLEN/8)];
        assign src_a_size[idx]             = src_size[idx * 3 +: 3];
        assign src_ready[idx]              = src_a_ready[idx];
        assign src_rdata[idx*XLEN +: XLEN] = src_a_rdata[idx];
        assign src_denied[idx]             = src_a_denied[idx];
        assign src_corrupt[idx]            = src_a_corrupt[idx];
    end
    for (idx = 0; idx < TARGET_COUNT; idx++) begin
        assign tgt_a_ready[idx]                    = tgt_ready[idx];
        assign tgt_a_rdata[idx]                    = tgt_rdata[idx * XLEN +: XLEN];
        assign tgt_a_denied[idx]                   = tgt_denied[idx];
        assign tgt_a_corrupt[idx]                  = tgt_corrupt[idx];
        assign tgt_valid[idx]                      = tgt_a_valid[idx];
        assign tgt_rw[idx]                         = tgt_a_rw[idx];
        assign tgt_addr[idx*XLEN +: XLEN]          = tgt_a_addr[idx];
        assign tgt_wdata[idx*XLEN +: XLEN]         = tgt_a_wdata[idx];
        assign tgt_wstrb[idx*(XLEN/8) +: (XLEN/8)] = tgt_a_wstrb[idx];
        assign tgt_size[idx*3 +: 3]                = tgt_a_size[idx];
    end
endgenerate

// Round-robin counter to process one source per cycle.
logic [SOURCE_COUNT_CLOG2-1:0] src_a_counter;

// Flag for each source indicating that its request has already been accepted.
logic [SOURCE_COUNT-1:0] src_a_assigned;

// Register to store the computed target ID when a source is assigned.
logic [TARGET_COUNT_CLOG2-1:0] src_a_target [SOURCE_COUNT];

integer i;
always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        for (int j = 0; j < SOURCE_COUNT; j++) begin
            src_a_ready[j]    <= 0;
            src_a_rdata[j]    <= 0;
            src_a_denied[j]   <= 0;
            src_a_corrupt[j]  <= 0;
            src_a_assigned[j] <= 0;
            src_a_target[j]   <= 0;
        end

        for (int k = 0; k < TARGET_COUNT; k++) begin
            tgt_a_valid[k]  <= 0;
            tgt_a_rw[k]     <= 0;
            tgt_a_addr[k]   <= '0;
            tgt_a_wdata[k]  <= '0;
            tgt_a_wstrb[k]  <= '0;
            tgt_a_size[k]   <= '0;
        end

        src_a_counter  <= 0;
    end else begin
        // current source id
        int source_id;
        int target_id;
        source_id = src_a_counter;

        `ifdef LOG_SWITCH_VERBOSE `LOG("p_switch", ("Source %00d, src_valid=%00d src_ready=%00d, Target %00d, tgt_valid=%00d, tgt_ready=%00d", source_id, src_a_valid[source_id], src_a_ready[source_id], src_a_target[source_id], tgt_a_valid[src_a_target[source_id]], tgt_a_ready[src_a_target[source_id]])); `endif

        // Process the current source if it has a valid request.
        if (src_a_valid[source_id] && !src_a_ready[source_id]) begin
            // If this source hasn't been assigned yet, try to assign its request.
            if (!src_a_assigned[source_id]) begin
                target_id = (TARGET_COUNT == 1) ? 0  : src_a_addr[source_id][XLEN-1:(XLEN - TARGET_COUNT_CLOG2)];

                if (!tgt_a_valid[target_id]) begin
                    `ifdef LOG_SWITCH `LOG("p_switch", ("Source %0d request sent to target %0d address 0x%00h / target address 0x%00h.", source_id, target_id, src_a_addr[source_id], src_a_addr[source_id] - (target_id << (XLEN - TARGET_COUNT_CLOG2)))); `endif

                    // Assign the request to the target.
                    tgt_a_valid[target_id]    <= 1;
                    tgt_a_rw[target_id]       <= src_a_rw[source_id];
                    tgt_a_addr[target_id]     <= src_a_addr[source_id] - (target_id << (XLEN - TARGET_COUNT_CLOG2));
                    tgt_a_wdata[target_id]    <= src_a_wdata[source_id];
                    tgt_a_wstrb[target_id]    <= src_a_wstrb[source_id];
                    tgt_a_size[target_id]     <= src_a_size[source_id];
                    src_a_target[source_id]   <= target_id;
                    src_a_assigned[source_id] <= 1;
                end
            end

            // The source has an outstanding request.
            else begin

                // Check if the target has finished processing (i.e. is ready).
                if (tgt_a_valid[target_id] && tgt_a_ready[target_id]) begin
                    `ifdef LOG_SWITCH `LOG("p_switch", ("Target %0d response sent to source %0d data 0x%00h.", target_id, source_id, tgt_a_rdata[target_id])); `endif

                    // Route the response back to the source.
                    src_a_ready[source_id]    <= '1;
                    src_a_rdata[source_id]    <= tgt_a_rdata[target_id];
                    src_a_denied[source_id]   <= tgt_a_denied[target_id];
                    src_a_corrupt[source_id]  <= tgt_a_corrupt[target_id];

                    // Free the target for a new request.
                    tgt_a_valid[target_id]    <= 0;

                    // Mark this source as no longer assigned.
                    src_a_target[source_id]   <= 0;
                    src_a_assigned[source_id] <= 0;
                end
            end
        end

        else if (!src_a_valid[source_id] && src_a_ready[source_id]) begin
            src_a_ready[source_id]   <= '0;
            src_a_rdata[source_id]   <= 0;
            src_a_denied[source_id]  <= '0;
            src_a_corrupt[source_id] <= '0;
        end


        // Source aborts request
        else if (!src_a_valid[source_id] && src_a_assigned[source_id]) begin
            target_id = src_a_target[source_id];

            `ifdef LOG_SWITCH `LOG("p_switch", ("Source %0d aborted request, target %0d aborted.", src_a_counter, target_id)); `endif

            tgt_a_valid[target_id]    <= 0;
            src_a_target[source_id]   <= 0;
            src_a_assigned[source_id] <= 0;
        end

        // Advance the round-robin counter.
        src_a_counter <= (src_a_counter == SOURCE_COUNT-1) ? 0 : src_a_counter + 1;
    end
end

endmodule

`endif // __P_SWITCH__
