`timescale 1ns / 1ps
`default_nettype none

`define BAUD_RATE 115200 // The slower this is the larger the VCD file is
`define CLK_FREQ_MHZ 100 // The slower this is the larger the VCD file is
`define DEBUG            // Turn on debugging ports
// `define LOG_UART
// `define LOG_FIFO

`include "src/tl_ul_uart.sv"
`include "test/zz_uart_baud_monitor.sv"

`ifndef XLEN
`define XLEN 32
`endif

`include "src/log.sv"

module tl_ul_uart_tb;
`include "test/test_macros.sv"

// ====================================
// Parameters
// ====================================
parameter XLEN = `XLEN;
parameter SID_WIDTH = 2;      // Source ID length for TileLink

// ====================================
// Clock and Reset
// ====================================
reg clk;
reg reset;

// Clock Generation: 100MHz Clock (10ns period)
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// ====================================
// TileLink A Channel
// ====================================
reg                     tl_a_valid;
wire                    tl_a_ready;
reg [2:0]               tl_a_opcode;
reg [2:0]               tl_a_param;
reg [2:0]               tl_a_size;
reg [SID_WIDTH-1:0]     tl_a_source;
reg [XLEN-1:0]          tl_a_address;
reg [XLEN/8-1:0]        tl_a_mask;
reg [XLEN-1:0]          tl_a_data;

// ====================================
// TileLink D Channel
// ====================================
wire                    tl_d_valid;
reg                     tl_d_ready;
wire [2:0]              tl_d_opcode;
wire [1:0]              tl_d_param;
wire [2:0]              tl_d_size;
wire [SID_WIDTH-1:0]    tl_d_source;
wire [XLEN-1:0]         tl_d_data;
wire                    tl_d_corrupt;
wire                    tl_d_denied;

// ====================================
// UART
// ====================================
wire                    uart_tx;
reg                     uart_rx;
wire                    uart_irq;

// ====================================
// Instantiate UART
// ====================================
tl_ul_uart #(
    .XLEN(XLEN),
    .SID_WIDTH(SID_WIDTH),
    .CLK_FREQ_MHZ(`CLK_FREQ_MHZ)
) uart (
    .clk         (clk),
    .reset       (reset),

    // TileLink A Channel
    .tl_a_valid  (tl_a_valid),
    .tl_a_ready  (tl_a_ready),
    .tl_a_opcode (tl_a_opcode),
    .tl_a_param  (tl_a_param),
    .tl_a_size   (tl_a_size),
    .tl_a_source (tl_a_source),
    .tl_a_address(tl_a_address),
    .tl_a_mask   (tl_a_mask),
    .tl_a_data   (tl_a_data),

    // TileLink D Channel
    .tl_d_valid  (tl_d_valid),
    .tl_d_ready  (tl_d_ready),
    .tl_d_opcode (tl_d_opcode),
    .tl_d_param  (tl_d_param),
    .tl_d_size   (tl_d_size),
    .tl_d_source (tl_d_source),
    .tl_d_data   (tl_d_data),
    .tl_d_corrupt(tl_d_corrupt),
    .tl_d_denied (tl_d_denied),

    // UART
    .rx          (uart_rx),
    .tx          (uart_tx),
    .irq         (uart_irq)
);

// ====================================
// Testbench Tasks
// ====================================

// Task to perform a write operation directly via TileLink A and D channels
task WriteData(
    input [XLEN-1:0]   address,
    input [2:0]        size,
    input [XLEN/8-1:0] mask,
    input [XLEN-1:0]   value
);
    reg [SID_WIDTH-1:0] source_id;
    reg [2:0]           opcode;
    reg [2:0]           param;
    integer             wait_cycles;

    begin
        // Initialize request signals
        source_id = 2'b01; // Example Source ID
        opcode = 3'b000;   // PUT_FULL_DATA_OPCODE
        param = 3'b000;    // No additional parameters

        @(posedge clk);
        // Drive TileLink A channel signals
        tl_a_valid = 1'b1;
        tl_a_opcode = opcode;
        tl_a_param  = param;
        tl_a_size   = size;
        tl_a_source = source_id;
        tl_a_address= address;
        tl_a_mask   = mask;
        tl_a_data   = value;

        `ifdef LOG_UART `LOG("testbench", ("WriteData: Sending WRITE request - Addr: 0x%h, Size: %0d, Mask: 0x%h, Data: 0x%h", address, size, mask, value)); `endif

        // Wait for tl_a_ready
        wait_cycles = 0;
        while (!tl_a_ready && wait_cycles < 100) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (!tl_a_ready) begin
            $display("\033[91mERROR: WriteData timeout waiting for tl_a_ready\033[0m");
            $stop;
        end
        `ifdef LOG_UART `LOG("testbench", ("Channel A is ready")); `endif

        // Handshake complete, deassert tl_a_valid
        @(posedge clk);
        tl_a_valid = 1'b0;

        // Wait for D channel response
        wait_cycles = 0;
        while (!tl_d_valid && wait_cycles < 100) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end
        `ifdef LOG_UART `LOG("testbench", ("Channel D is Valid")); `endif

        if (!tl_d_valid) begin
            $display("\033[91mERROR: WriteData timeout waiting for tl_d_valid\033[0m");
            $stop;
        end

        // Verify the response
        if (tl_d_denied ==1'b1) begin
            $display("\033[91mERROR: WriteData tl_d_denied\033[0m");
            $stop;
        end
        if (tl_d_corrupt == 1'b1) begin
            $display("\033[91mERROR: WriteData tl_d_corrupt\033[0m");
            $stop;
        end
        if (tl_d_opcode != 3'b000) begin
            $display("\033[91mERROR: WriteData tl_d_opcode\033[0m");
            $stop;
        end

        // Assert tl_d_ready to acknowledge reception
        tl_d_ready = 1'b1;

        @(posedge clk);
        tl_d_ready = 1'b0;

        // Deassert tl_d_ready after response is captured
        @(posedge clk);
    end
endtask

// Task to perform a read operation directly via TileLink A and D channels
reg [XLEN-1:0] last_read;
task ReadData(
    input [XLEN-1:0]   address,
    input [2:0]        size
);
    reg [SID_WIDTH-1:0] source_id;
    reg [2:0]           opcode;
    reg [2:0]           param;
    integer             wait_cycles;

    begin
        // Initialize request signals
        source_id = 2'b10; // Example Source ID
        opcode = 3'b100;   // GET_OPCODE
        param = 3'b000;    // No additional parameters

        @(posedge clk);
        // Drive TileLink A channel signals
        tl_a_valid = 1'b1;
        tl_a_opcode = opcode;
        tl_a_param  = param;
        tl_a_size   = size;
        tl_a_source = source_id;
        tl_a_address= address;
        tl_a_mask   = {(XLEN/8){1'b0}}; // No mask for read
        tl_a_data   = {XLEN{1'b0}};     // No data for read

        `ifdef LOG_UART `LOG("testbench", ("ReadData: Sending READ request - Addr: 0x%h, Size: %0d", address, size)); `endif

        // Wait for tl_a_ready
        wait_cycles = 0;
        while (!tl_a_ready && wait_cycles < 100) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (!tl_a_ready) begin
            $display("\033[91mERROR: ReadData timeout waiting for tl_a_ready\033[0m");
            $stop;
        end

        // Handshake complete, deassert tl_a_valid
        @(posedge clk);
        tl_a_valid = 1'b0;

        // Wait for D channel response
        wait_cycles = 0;
        while (!tl_d_valid && wait_cycles < 1000) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (!tl_d_valid) begin
            $display("\033[91mERROR: ReadData timeout waiting for tl_d_valid\033[0m");
            $stop;
        end

        // Verify the response
        if (tl_d_denied ==1'b1) begin
            $display("\033[91mERROR: ReadData tl_d_denied\033[0m");
            $stop;
        end
        if (tl_d_corrupt == 1'b1) begin
            $display("\033[91mERROR: ReadData tl_d_corrupt\033[0m");
            $stop;
        end
        if (tl_d_opcode != 3'b010) begin
            $display("\033[91mERROR: ReadData tl_d_opcode\033[0m");
            $stop;
        end

        last_read <= tl_d_data;

        // Assert tl_d_ready to acknowledge reception
        tl_d_ready = 1'b1;

        @(posedge clk);
        tl_d_ready = 1'b0;

        // Deassert tl_d_ready after response is captured
        @(posedge clk);
    end
endtask

task SendByte(
    input [7:0] data,
    int baud_rate
);
integer i;
integer cycles_per_bit;
begin
    // Calculate CYCLES_PER_BIT based on CLK_FREQ_MHZ and baud_rate
    cycles_per_bit = (`CLK_FREQ_MHZ * 1000000) / baud_rate;
    
    // Send Start Bit (Low)
    uart_rx = 1'b0;
    repeat (cycles_per_bit) @(posedge clk);
    
    // Send Data Bits (LSB first)
    for (i = 0; i < 8; i = i + 1) begin
        uart_rx = data[i];
        repeat (cycles_per_bit) @(posedge clk);
    end
    
    // Send Stop Bit (High)
    uart_rx = 1'b1;
    repeat (cycles_per_bit) @(posedge clk);
end
endtask

// ====================================
// UART Decoder
// ====================================
reg       rx_ready;
reg [7:0] rx_byte;
uart_baud_monitor #(
    .CLK_FREQ_MHZ(`CLK_FREQ_MHZ),
    .BAUD_RATE(`BAUD_RATE),
    .OVERSAMPLE(16)
) my_monitor (
    .clk        (clk),
    .reset      (reset),
    .uart_tx    (uart_tx),
    .out_ready  (rx_ready),
    .out_byte   (rx_byte)
);

// ====================================
// Test Sequence
// ====================================
initial begin
    $dumpfile("tl_ul_uart_tb.vcd");
    $dumpvars(0, tl_ul_uart_tb);

    test = 0;

    // Initialize TileLink A and D channel signals
    tl_a_valid = 1'b0;
    tl_a_opcode = 3'b000;
    tl_a_param  = 3'b000;
    tl_a_size   = 3'b000;
    tl_a_source = {SID_WIDTH{1'b0}};
    tl_a_address= {XLEN{1'b0}};
    tl_a_mask   = {(XLEN/8){1'b0}};
    tl_a_data   = {XLEN{1'b0}};
    tl_d_ready = 1'b0;

    uart_rx = 1'b1; // Idle high

    // ====================================
    // Apply Reset
    // ====================================
    reset = 1;
    #10; // Hold reset for 10ns
    @(posedge clk);
    reset = 0;
    @(posedge clk);
    wait(~rx_ready);

    // ====================================
    // Test Single Byte Send
    // ====================================
    `TEST("tl_ul_uart", "Single Byte Send (0x41)");
    @(posedge clk);
    wait(~rx_ready);

    WriteData('h08, 3'b000, 4'b0001, 'h41); // Queue the letter 0x41 'A' 01000001
    wait(rx_ready);
    `EXPECT("Should recieve 'A'", rx_byte, 'h41);
    wait(~rx_ready);

    // ====================================
    // Test Single Byte Send
    // ====================================
    `TEST("tl_ul_uart", "Single Byte Send (0x42)");
    @(posedge clk);
    wait(~rx_ready);

    WriteData('h08, 3'b000, 4'b0001, 'h42); // Queue the letter 0x42 'B' 01000010
    wait(rx_ready);
    `EXPECT("Should recieve 'B'", rx_byte, 'h42);
    wait(~rx_ready);

    // ====================================
    // Test Multi Byte Send
    // ====================================
    `TEST("tl_ul_uart", "Multi Byte Send (0x48, 0x45, 0x4C, 0x4C, 0x4F)");
    @(posedge clk);
    wait(~rx_ready);

    WriteData('h08, 3'b000, 4'b0001, 'h48); // Queue the letter 0x48 'H'
    WriteData('h08, 3'b000, 4'b0001, 'h45); // Queue the letter 0x45 'E'
    WriteData('h08, 3'b000, 4'b0001, 'h4C); // Queue the letter 0x4C 'L'
    WriteData('h08, 3'b000, 4'b0001, 'h4C); // Queue the letter 0x4C 'L'
    WriteData('h08, 3'b000, 4'b0001, 'h4F); // Queue the letter 0x4F 'O'

    wait(rx_ready);
    `EXPECT("Should recieve 'H'", rx_byte, 'h48);
    wait(~rx_ready);
    wait(rx_ready);
    `EXPECT("Should recieve 'E'", rx_byte, 'h45);
    wait(~rx_ready);
    wait(rx_ready);
    `EXPECT("Should recieve 'L'", rx_byte, 'h4C);
    wait(~rx_ready);
    wait(rx_ready);
    `EXPECT("Should recieve 'L'", rx_byte, 'h4C);
    wait(~rx_ready);
    wait(rx_ready);
    `EXPECT("Should recieve 'O'", rx_byte, 'h4F);

    // ====================================
    // Test Single Byte Recieve
    // ====================================
    `TEST("tl_ul_uart", "Read Single Byte");
    @(posedge clk);
    SendByte(8'h41, 115200); // Send 'A' (0x41)
    `EXPECT("UART IRQ should be high before read", uart_irq, 1'b1);
    ReadData(32'h08, 3'b000); // Read a byte from RX buffer
    `EXPECT("UART IRQ should be low after read", uart_irq, 1'b0);
    `EXPECT("Read byte from RX buffer 'A'", last_read, 'h41);

    // ====================================
    // Test Multi Byte Recieve
    // ====================================
    `TEST("tl_ul_uart", "Read Single Byte");
    @(posedge clk);
    SendByte(8'h48, 115200); // Send 'H' (0x48)
    SendByte(8'h45, 115200); // Send 'E' (0x45)
    SendByte(8'h4C, 115200); // Send 'L' (0x4C)
    SendByte(8'h4C, 115200); // Send 'L' (0x4C)
    SendByte(8'h4F, 115200); // Send 'O' (0x4F)
    `EXPECT("UART IRQ should be high before read", uart_irq, 1'b1);
    ReadData(32'h08, 3'b000);
    `EXPECT("UART IRQ should still be high after 1st read", uart_irq, 1'b1);
    `EXPECT("Read byte from RX buffer 'H'", last_read, 'h48);
    ReadData(32'h08, 3'b000);
    `EXPECT("Read byte from RX buffer 'E'", last_read, 'h45);
    ReadData(32'h08, 3'b000);
    `EXPECT("Read byte from RX buffer 'L'", last_read, 'h4C);
    ReadData(32'h08, 3'b000);
    `EXPECT("Read byte from RX buffer 'L'", last_read, 'h4C);
    ReadData(32'h08, 3'b000);
    `EXPECT("UART IRQ should still be high after last read", uart_irq, 1'b0);
    `EXPECT("Read byte from RX buffer 'O'", last_read, 'h4F);

    // ====================================
    // Finish Testbench
    // ====================================
    @(posedge clk);
    `FINISH;
end

endmodule
