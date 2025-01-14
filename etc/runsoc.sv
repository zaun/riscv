`timescale 1ns / 1ps
`default_nettype none

// `define LOG_UNKNOWN_INST
// `define LOG_CPU
// `define LOG_MEM_INTERFACE
// `define LOG_REG
// `define LOG_BIOS
// `define LOG_MEMORY
`define LOG_MMIO
// `define LOG_CLOCKED
// `define LOG_SWITCH
// `define LOG_UART
// `define LOG_CSR

// Only include the SOC
`include "src/soc.sv"

// Included to see UART output
`include "test/zz_uart_baud_monitor.sv"

module soc_runner;

// ====================================
// Parameters
// ====================================
parameter CLK_FREQ_MHZ  = 27;
parameter BAUD_RATE = 115200;

// ====================================
// Clock and Reset
// ====================================
reg clk;
reg reset;

// Initialize Clock
initial begin
    clk = 0;
    forever #18.5185 clk = ~clk; // 27MHz Clock
end

// ====================================
// Clock Cycle Counter
// ====================================
integer cycle_count;

initial begin
    cycle_count = 0; // Initialize the cycle counter
end

always @(posedge clk) begin
    if (!reset) begin
        cycle_count <= cycle_count + 1;
    end
end

// ====================================
// UART Decoder
// ====================================
reg       rx_ready;
reg [7:0] rx_byte;
uart_baud_monitor #(
    .CLK_FREQ_MHZ(CLK_FREQ_MHZ),
    .BAUD_RATE(BAUD_RATE),
    .OVERSAMPLE(16)
) my_monitor (
    .clk        (clk),
    .reset      (reset),
    .uart_tx    (uart_tx),
    .out_ready  (rx_ready),
    .out_byte   (rx_byte)
);

always_ff @(posedge clk) begin
    if (rx_ready) begin
        $write("%c", rx_byte);
    end
end

// ====================================
// Simulation Sequence
// ====================================
wire       uart_rx;
wire       uart_tx;
wire [5:0] leds;

initial begin
    $dumpfile("soc_runner.vcd");
    $dumpvars(0, soc_runner);

    $display("Loading program...");
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);

    reset = 0;
    $display("Running SOC rv i%00s%00s%00s...",
    `ifdef SUPPORT_M "m" `else "" `endif,
    `ifdef SUPPORT_B "b" `else "" `endif,
    `ifdef SUPPORT_ZICSR "_zicsr" `else "" `endif);

    // Wait for a little bit for things to run
    repeat(100000) @(posedge clk);

    $finish;
end

top #() uut (
    .CLK(clk),           // System Clock
    .BTN_S1(reset),      // Button for reset
    .LED(leds),          // LEDs
    .UART_RX(uart_rx),   // Receive line
    .UART_TX(uart_tx)    // Transmit line
);

endmodule
