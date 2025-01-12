`default_nettype none

// Include necessary modules
`include "src/cpu.sv"
`include "src/tl_ul_bios.sv"
`include "src/tl_memory.sv"
`include "src/tl_ul_output.sv"
`include "src/tl_switch.sv"
`include "src/tl_ul_uart.sv"


`ifndef XLEN
`define XLEN 32
`endif

module top
(
    input        CLK,       // System Clock
    input        BTN_S1,    // Button for reset
    output [5:0] LED,       // LEDs
    input        UART_RX,   // Receive line
    output       UART_TX    // Transmit line
);

// ====================================
// Parameters
// ====================================
parameter XLEN          = 32;
parameter SID_WIDTH     = 8;
parameter NUM_INPUTS    = 1;
parameter NUM_OUTPUTS   = 4;
parameter TRACK_DEPTH   = 16;
parameter CLK_FREQ_MHZ  = 27;

// ====================================
// LEDs
// ====================================
logic [5:0] leds;
assign LED[0]   = ~leds[0];
assign LED[3:1] = ~test[2:0];
assign LED[4]   = ~slow_clk;
assign LED[5]   = ~led_toggle;

// LED Heartbeat
// 1 sec on, 1 sec off. 0.5Hz
reg [25:0] counter;
reg        led_toggle;
localparam integer MAX_COUNT_HEARTBEAT = CLK_FREQ_MHZ * 1000000;
always @(posedge CLK or posedge reset) begin
    if (reset) begin
        counter     <= 26'd0;
        led_toggle  <= 1'b0;
    end else if (counter >= (MAX_COUNT_HEARTBEAT - 1)) begin
        counter     <= 26'd0;
        led_toggle  <= ~led_toggle;
    end else begin
        counter <= counter + 25'd1;
    end
end

// ====================================
// Clock and Reset
// ====================================

// Clock Divider Registers
reg [25:0] clk_divider = 25'd0;
reg slow_clk = 1'b0;

wire clk;
wire reset;

// 0.25 sec on, 0.25 sec off. 2Hz
localparam integer MAX_COUNT_SLOWCLOCK = (CLK_FREQ_MHZ * 1000000) / 4;
always @(posedge CLK or posedge reset) begin
    if (reset) begin
        clk_divider     <= 26'd0;
        slow_clk  <= 1'b0;
    end else if (clk_divider >= (MAX_COUNT_SLOWCLOCK - 1)) begin
        clk_divider     <= 26'd0;
        slow_clk  <= ~slow_clk;
    end else begin
        clk_divider <= clk_divider + 25'd1;
    end
end

assign clk   = slow_clk;
assign reset = BTN_S1;

// ====================================
// Master 1 (CPU)
// ====================================

// A Channel
wire                   cpu_tl_a_valid;
wire                   cpu_tl_a_ready;
wire [2:0]             cpu_tl_a_opcode;
wire [2:0]             cpu_tl_a_param;
wire [2:0]             cpu_tl_a_size;
wire [SID_WIDTH-1:0]   cpu_tl_a_source;
wire [XLEN-1:0]        cpu_tl_a_address;
wire [XLEN/8-1:0]      cpu_tl_a_mask;
wire [XLEN-1:0]        cpu_tl_a_data;

// D Channel
wire                   cpu_tl_d_valid;
wire                   cpu_tl_d_ready;
wire [2:0]             cpu_tl_d_opcode;
wire [1:0]             cpu_tl_d_param;
wire [2:0]             cpu_tl_d_size;
wire [SID_WIDTH-1:0]   cpu_tl_d_source;
wire [XLEN-1:0]        cpu_tl_d_data;
wire                   cpu_tl_d_corrupt;
wire                   cpu_tl_d_denied;

// Other signals
wire [2:0]             test;
wire                   trap;

// ====================================
// Slave 1 (memory1)
// ====================================

logic [XLEN-1:0] memory1_base_address;
logic [XLEN-1:0] memory1_size;
assign memory1_base_address = 32'h0000_0000;
assign memory1_size         = 32'h0000_FFFF;

// A Channel
wire memory1_s_a_valid;
wire memory1_s_a_ready;
wire [2:0] memory1_s_a_opcode;
wire [2:0] memory1_s_a_param;
wire [2:0] memory1_s_a_size;
wire [SID_WIDTH-1:0] memory1_s_a_source;
wire [XLEN/8-1:0] memory1_s_a_mask;
wire [XLEN-1:0] memory1_s_a_address;
wire [XLEN-1:0] memory1_s_a_data;

// D Channel
wire memory1_s_d_valid;
wire memory1_s_d_ready;
wire [2:0] memory1_s_d_opcode;
wire [1:0] memory1_s_d_param;
wire [2:0] memory1_s_d_size;
wire [SID_WIDTH-1:0] memory1_s_d_source;
wire [XLEN-1:0] memory1_s_d_data;
wire memory1_s_d_corrupt;
wire memory1_s_d_denied;

// ====================================
// Slave 2 (UART)
// ====================================

wire uart_irq;
wire uart_rx;
wire uart_tx;

logic [XLEN-1:0] uart_base_address;
logic [XLEN-1:0] uart_size;
assign uart_base_address = 32'h0001_0000;
assign uart_size         = 32'h0000_0010;

// A Channel
wire                 uart_s_a_valid;
wire                 uart_s_a_ready;
wire [2:0]           uart_s_a_opcode;
wire [2:0]           uart_s_a_param;
wire [2:0]           uart_s_a_size;
wire [SID_WIDTH-1:0] uart_s_a_source;
wire [XLEN/8-1:0]    uart_s_a_mask;
wire [XLEN-1:0]      uart_s_a_address;
wire [XLEN-1:0]      uart_s_a_data;

// D Channel
wire                 uart_s_d_valid;
wire                 uart_s_d_ready;
wire [2:0]           uart_s_d_opcode;
wire [1:0]           uart_s_d_param;
wire [2:0]           uart_s_d_size;
wire [SID_WIDTH-1:0] uart_s_d_source;
wire [XLEN-1:0]      uart_s_d_data;
wire                 uart_s_d_corrupt;
wire                 uart_s_d_denied;

// ====================================
// Slave 3 (bios)
// ====================================

logic [XLEN-1:0] bios_base_address;
logic [XLEN-1:0] bios_size;
assign bios_base_address = 32'h8000_0000;
assign bios_size         = 32'h0000_FFFF;

// A Channel
wire bios_s_a_valid;
wire bios_s_a_ready;
wire [2:0] bios_s_a_opcode;
wire [2:0] bios_s_a_param;
wire [2:0] bios_s_a_size;
wire [SID_WIDTH-1:0] bios_s_a_source;
wire [XLEN/8-1:0] bios_s_a_mask;
wire [XLEN-1:0] bios_s_a_address;
wire [XLEN-1:0] bios_s_a_data;

// D Channel
wire bios_s_d_valid;
wire bios_s_d_ready;
wire [2:0] bios_s_d_opcode;
wire [1:0] bios_s_d_param;
wire [2:0] bios_s_d_size;
wire [SID_WIDTH-1:0] bios_s_d_source;
wire [XLEN-1:0] bios_s_d_data;
wire bios_s_d_corrupt;
wire bios_s_d_denied;

// ====================================
// Slave 4 (outputs)
// ====================================

logic [XLEN-1:0] outputs_base_address;
logic [XLEN-1:0] outputs_size;
assign outputs_base_address = 32'h0002_0000;
assign outputs_size         = 32'h0000_0010;

// A Channel
wire outputs_s_a_valid;
wire outputs_s_a_ready;
wire [2:0] outputs_s_a_opcode;
wire [2:0] outputs_s_a_param;
wire [2:0] outputs_s_a_size;
wire [SID_WIDTH-1:0] outputs_s_a_source;
wire [XLEN/8-1:0] outputs_s_a_mask;
wire [XLEN-1:0] outputs_s_a_address;
wire [XLEN-1:0] outputs_s_a_data;

// D Channel
wire outputs_s_d_valid;
wire outputs_s_d_ready;
wire [2:0] outputs_s_d_opcode;
wire [1:0] outputs_s_d_param;
wire [2:0] outputs_s_d_size;
wire [SID_WIDTH-1:0] outputs_s_d_source;
wire [XLEN-1:0] outputs_s_d_data;
wire outputs_s_d_corrupt;
wire outputs_s_d_denied;


// ====================================
// Instantiate the TileLink Switch
// ====================================
tl_switch #(
    .NUM_INPUTS    (NUM_INPUTS),
    .NUM_OUTPUTS   (NUM_OUTPUTS),
    .XLEN          (XLEN),
    .SID_WIDTH     (SID_WIDTH),
    .TRACK_DEPTH   (TRACK_DEPTH)
) switch_inst (
    .clk        (clk),
    .reset      (reset),

    // ======================
    // TileLink A Channel - Masters (CPU)
    // ======================
    .a_valid    ({ cpu_tl_a_valid }),
    .a_ready    ({ cpu_tl_a_ready }),
    .a_opcode   ({ cpu_tl_a_opcode }),
    .a_param    ({ cpu_tl_a_param }),
    .a_size     ({ cpu_tl_a_size }),
    .a_source   ({ cpu_tl_a_source }),
    .a_address  ({ cpu_tl_a_address }),
    .a_mask     ({ cpu_tl_a_mask }),
    .a_data     ({ cpu_tl_a_data }),

    // ======================
    // TileLink D Channel - Masters (CPU)
    // ======================
    .d_valid    ({ cpu_tl_d_valid }),
    .d_ready    ({ cpu_tl_d_ready }),
    .d_opcode   ({ cpu_tl_d_opcode }),
    .d_param    ({ cpu_tl_d_param }),
    .d_size     ({ cpu_tl_d_size }),
    .d_source   ({ cpu_tl_d_source }),
    .d_data     ({ cpu_tl_d_data }),
    .d_corrupt  ({ cpu_tl_d_corrupt }),
    .d_denied   ({ cpu_tl_d_denied }),

    // ======================
    // A Channel - Slaves (Memories)
    // ======================
    .s_a_valid   ({ memory1_s_a_valid,   uart_s_a_valid,   bios_s_a_valid,   outputs_s_a_valid   }),
    .s_a_ready   ({ memory1_s_a_ready,   uart_s_a_ready,   bios_s_a_ready,   outputs_s_a_ready   }),
    .s_a_opcode  ({ memory1_s_a_opcode,  uart_s_a_opcode,  bios_s_a_opcode,  outputs_s_a_opcode  }),
    .s_a_param   ({ memory1_s_a_param,   uart_s_a_param,   bios_s_a_param,   outputs_s_a_param   }),
    .s_a_size    ({ memory1_s_a_size,    uart_s_a_size,    bios_s_a_size,    outputs_s_a_size    }),
    .s_a_source  ({ memory1_s_a_source,  uart_s_a_source,  bios_s_a_source,  outputs_s_a_source  }),
    .s_a_mask    ({ memory1_s_a_mask,    uart_s_a_mask,    bios_s_a_mask,    outputs_s_a_mask    }),
    .s_a_address ({ memory1_s_a_address, uart_s_a_address, bios_s_a_address, outputs_s_a_address }),
    .s_a_data    ({ memory1_s_a_data,    uart_s_a_data,    bios_s_a_data,    outputs_s_a_data    }),

    // ======================
    // D Channel - Slaves (Memories)
    // ======================
    .s_d_valid    ({ memory1_s_d_valid,   uart_s_d_valid,   bios_s_d_valid,   outputs_s_d_valid   }),
    .s_d_ready    ({ memory1_s_d_ready,   uart_s_d_ready,   bios_s_d_ready,   outputs_s_d_ready   }),
    .s_d_opcode   ({ memory1_s_d_opcode,  uart_s_d_opcode,  bios_s_d_opcode,  outputs_s_d_opcode  }),
    .s_d_param    ({ memory1_s_d_param,   uart_s_d_param,   bios_s_d_param,   outputs_s_d_param   }),
    .s_d_size     ({ memory1_s_d_size,    uart_s_d_size,    bios_s_d_size,    outputs_s_d_size    }),
    .s_d_source   ({ memory1_s_d_source,  uart_s_d_source,  bios_s_d_source,  outputs_s_d_source  }),
    .s_d_data     ({ memory1_s_d_data,    uart_s_d_data,    bios_s_d_data,    outputs_s_d_data    }),
    .s_d_corrupt  ({ memory1_s_d_corrupt, uart_s_d_corrupt, bios_s_d_corrupt, outputs_s_d_corrupt }),
    .s_d_denied   ({ memory1_s_d_denied,  uart_s_d_denied,  bios_s_d_denied,  outputs_s_d_denied  }),

    // ======================
    // Base Addresses for Slaves
    // ======================
    .base_addr    ({ memory1_base_address, uart_base_address, bios_base_address, outputs_base_address }),
    .addr_mask    ({ memory1_size,         uart_size,         bios_size,         outputs_size         })
);

// ====================================
// Instantiate the CPU
// ====================================
rv_cpu #(
    .MHARTID_VAL     (32'h0000_0000),
    .XLEN            (XLEN),
    .SID_WIDTH       (SID_WIDTH),
    .START_ADDRESS   (32'h8000_0000),
    .MTVEC_RESET_VAL (32'h0000_0000),
    .NMI_COUNT       (1),
    .IRQ_COUNT       (1)
) cpu_inst (
    .clk        (clk),
    .reset      (reset),

    `ifdef SUPPORT_ZICSR
    .external_irq ({ uart_irq }),
    .external_nmi ({ 1'b0 }),
    `endif

    // TileLink A Channel (Master to Switch)
    .tl_a_valid    (cpu_tl_a_valid),
    .tl_a_ready    (cpu_tl_a_ready),
    .tl_a_opcode   (cpu_tl_a_opcode),
    .tl_a_param    (cpu_tl_a_param),
    .tl_a_size     (cpu_tl_a_size),
    .tl_a_source   (cpu_tl_a_source),
    .tl_a_address  (cpu_tl_a_address),
    .tl_a_mask     (cpu_tl_a_mask),
    .tl_a_data     (cpu_tl_a_data),

    // TileLink D Channel (Switch to Master)
    .tl_d_valid    (cpu_tl_d_valid),
    .tl_d_ready    (cpu_tl_d_ready),
    .tl_d_opcode   (cpu_tl_d_opcode),
    .tl_d_param    (cpu_tl_d_param),
    .tl_d_size     (cpu_tl_d_size),
    .tl_d_source   (cpu_tl_d_source),
    .tl_d_data     (cpu_tl_d_data),
    .tl_d_corrupt  (cpu_tl_d_corrupt),
    .tl_d_denied   (cpu_tl_d_denied),

    .test          (test),
    .trap          (trap)

    `ifdef DEBUG
    // Debug outputs
    ,.dbg_halt     (dbg_halt)
    ,.dbg_trap     (dbg_trap)
    ,.dbg_pc       (dbg_pc)
    ,.dbg_x1       ()
    ,.dbg_x2       ()
    ,.dbg_x3       ()
    `endif
);

// ====================================
// Instantiate Memory 1
// ====================================
tl_memory #(
    .XLEN       (XLEN),
    .SIZE       (16'hFFF),
    .SID_WIDTH  (SID_WIDTH)
) memory1_inst (
    .clk            (clk),
    .reset          (reset),

    // TileLink A Channel
    .tl_a_valid     (memory1_s_a_valid),
    .tl_a_ready     (memory1_s_a_ready),
    .tl_a_opcode    (memory1_s_a_opcode),           // 3 bits
    .tl_a_param     (memory1_s_a_param),            // 3 bits
    .tl_a_size      (memory1_s_a_size),             // 3 bits
    .tl_a_source    (memory1_s_a_source),           // SID_WIDTH bits
    .tl_a_address   (memory1_s_a_address),          // XLEN bits
    .tl_a_mask      (memory1_s_a_mask),             // (XLEN/8) bits
    .tl_a_data      (memory1_s_a_data),             // XLEN bits

    // TileLink D Channel
    .tl_d_valid     (memory1_s_d_valid),
    .tl_d_ready     (memory1_s_d_ready),
    .tl_d_opcode    (memory1_s_d_opcode),           // 3 bits
    .tl_d_param     (memory1_s_d_param),            // 2 bits
    .tl_d_size      (memory1_s_d_size),             // 3 bits
    .tl_d_source    (memory1_s_d_source),           // SID_WIDTH bits
    .tl_d_data      (memory1_s_d_data),             // XLEN bits
    .tl_d_corrupt   (memory1_s_d_corrupt),          // 1 bit
    .tl_d_denied    (memory1_s_d_denied)            // 1 bit
);

// ====================================
// Instantiate UART
// ====================================
tl_ul_uart #(
    .XLEN          (XLEN),
    .SID_WIDTH     (SID_WIDTH),
    .CLK_FREQ_MHZ  (CLK_FREQ_MHZ)
) uart_inst (
    .clk            (clk),
    .reset          (reset),

    // TileLink A Channel (Slave from Switch)
    .tl_a_valid     (uart_s_a_valid),
    .tl_a_ready     (uart_s_a_ready),
    .tl_a_opcode    (uart_s_a_opcode),
    .tl_a_param     (uart_s_a_param),
    .tl_a_size      (uart_s_a_size),
    .tl_a_source    (uart_s_a_source),
    .tl_a_address   (uart_s_a_address),
    .tl_a_mask      (uart_s_a_mask),
    .tl_a_data      (uart_s_a_data),

    // TileLink D Channel (Slave to Switch)
    .tl_d_valid     (uart_s_d_valid),
    .tl_d_ready     (uart_s_d_ready),
    .tl_d_opcode    (uart_s_d_opcode),
    .tl_d_param     (uart_s_d_param),
    .tl_d_size      (uart_s_d_size),
    .tl_d_source    (uart_s_d_source),
    .tl_d_data      (uart_s_d_data),
    .tl_d_corrupt   (uart_s_d_corrupt),
    .tl_d_denied    (uart_s_d_denied),

    // UART Interface
    .rx             (uart_rx),     // Connect to testbench's rx_sim
    .tx             (uart_tx),     // Connect to testbench's tx wire
    .irq            (uart_irq)     // Connect to testbench's irq wire
);

// ====================================
// Instantiate Bios
// ====================================
tl_ul_bios #(
    .XLEN       (XLEN),
    .SID_WIDTH  (SID_WIDTH)
) bios_inst (
    .clk            (clk),
    .reset          (reset),

    // TileLink A Channel
    .tl_a_valid     (bios_s_a_valid),
    .tl_a_ready     (bios_s_a_ready),
    .tl_a_opcode    (bios_s_a_opcode),           // 3 bits
    .tl_a_param     (bios_s_a_param),            // 3 bits
    .tl_a_size      (bios_s_a_size),             // 3 bits
    .tl_a_source    (bios_s_a_source),           // SID_WIDTH bits
    .tl_a_address   (bios_s_a_address),          // XLEN bits
    .tl_a_mask      (bios_s_a_mask),             // (XLEN/8) bits
    .tl_a_data      (bios_s_a_data),             // XLEN bits

    // TileLink D Channel
    .tl_d_valid     (bios_s_d_valid),
    .tl_d_ready     (bios_s_d_ready),
    .tl_d_opcode    (bios_s_d_opcode),           // 3 bits
    .tl_d_param     (bios_s_d_param),            // 2 bits
    .tl_d_size      (bios_s_d_size),             // 3 bits
    .tl_d_source    (bios_s_d_source),           // SID_WIDTH bits
    .tl_d_data      (bios_s_d_data),             // XLEN bits
    .tl_d_corrupt   (bios_s_d_corrupt),          // 1 bit
    .tl_d_denied    (bios_s_d_denied)            // 1 bit
);

// ====================================
// Instantiate Outputs
// ====================================
tl_ul_output #(
    .XLEN       (XLEN),
    .SID_WIDTH  (SID_WIDTH),
    .OUTPUTS    (6)
) out_inst (
    .clk            (clk),
    .reset          (reset),

    .outputs        (leds),

    // TileLink A Channel
    .tl_a_valid     (outputs_s_a_valid),
    .tl_a_ready     (outputs_s_a_ready),
    .tl_a_opcode    (outputs_s_a_opcode),           // 3 bits
    .tl_a_param     (outputs_s_a_param),            // 3 bits
    .tl_a_size      (outputs_s_a_size),             // 3 bits
    .tl_a_source    (outputs_s_a_source),           // SID_WIDTH bits
    .tl_a_address   (outputs_s_a_address),          // XLEN bits
    .tl_a_mask      (outputs_s_a_mask),             // (XLEN/8) bits
    .tl_a_data      (outputs_s_a_data),             // XLEN bits

    // TileLink D Channel
    .tl_d_valid     (outputs_s_d_valid),
    .tl_d_ready     (outputs_s_d_ready),
    .tl_d_opcode    (outputs_s_d_opcode),           // 3 bits
    .tl_d_param     (outputs_s_d_param),            // 2 bits
    .tl_d_size      (outputs_s_d_size),             // 3 bits
    .tl_d_source    (outputs_s_d_source),           // SID_WIDTH bits
    .tl_d_data      (outputs_s_d_data),             // XLEN bits
    .tl_d_corrupt   (outputs_s_d_corrupt),          // 1 bit
    .tl_d_denied    (outputs_s_d_denied)            // 1 bit
);

endmodule
