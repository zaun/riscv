`timescale 1ns/1ps
`default_nettype none

`include "src/log.sv"

module uart_baud_monitor #(
    parameter real CLK_FREQ_MHZ  = 100.0,    // System clock frequency in MHz
    parameter int  BAUD_RATE     = 51200,    // Baud rate (e.g., 51200 or 115200)
    parameter int  OVERSAMPLE    = 16        // Oversampling factor (not used in this implementation)
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       uart_tx,    // TX line to decode
    output reg        out_ready,  // Pulses high for 1 clock when a full byte is decoded
    output reg [7:0]  out_byte    // Decoded byte
);

// --------------------------------------------------------
// Compute Cycles per Bit
// --------------------------------------------------------
localparam real CLK_PERIOD_NS   = 1000.0 / CLK_FREQ_MHZ;    // e.g., 10ns for 100MHz
localparam real BAUD_PERIOD_NS  = 1_000_000_000.0 / BAUD_RATE; // e.g., ~19531.25ns for 51200 baud
localparam int  CYCLES_PER_BIT  = $rtoi(BAUD_PERIOD_NS / CLK_PERIOD_NS + 0.5); // Rounded to nearest integer

// --------------------------------------------------------
// State Definitions
// --------------------------------------------------------
typedef enum logic [1:0] {
    IDLE,
    START,
    DATA,
    STOP
} state_t;

state_t state;

// Registers to hold sampled data
reg [7:0] shift_reg;
reg [2:0] bit_idx;

// Counter to track bit timing
integer counter;

// Previous uart_tx value for edge detection
reg uart_tx_prev;

// --------------------------------------------------------
// State Machine Implementation
// --------------------------------------------------------
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state         <= IDLE;
        out_ready     <= 1'b0;
        out_byte      <= 8'h00;
        shift_reg     <= 8'h00;
        bit_idx       <= 3'd0;
        counter       <= 0;
        uart_tx_prev  <= 1'b1; // Idle state is high
    end else begin
        // Capture previous uart_tx for edge detection
        uart_tx_prev <= uart_tx;

        // Default outputs
        out_ready <= 1'b0;

        case (state)
            //---------------------------------------------------
            // IDLE: Wait for start bit (falling edge)
            //---------------------------------------------------
            IDLE: begin
                if (uart_tx_prev == 1'b1 && uart_tx == 1'b0) begin
                    state   <= START;
                    counter <= (CYCLES_PER_BIT >> 1); // Half bit period
                    `ifdef LOG_UART
                        `LOG("uart_baud_monitor", ("Start bit detected, transitioning to START state"));
                    `endif
                end
            end

            //---------------------------------------------------
            // START: Wait for half bit period to sample first data bit
            //---------------------------------------------------
            START: begin
                if (counter == 0) begin
                    state   <= DATA;
                    bit_idx <= 3'd0;
                    counter <= CYCLES_PER_BIT; // Full bit period
                    `ifdef LOG_UART
                        `LOG("uart_baud_monitor", ("Half bit period elapsed, transitioning to DATA state"));
                    `endif
                end else begin
                    counter <= counter - 1;
                end
            end

            //---------------------------------------------------
            // DATA: Sample each data bit at bit period intervals
            //---------------------------------------------------
            DATA: begin
                if (counter == 0) begin
                    // Sample the current bit
                    shift_reg[bit_idx] <= uart_tx;
                    `ifdef LOG_UART
                        `LOG("uart_baud_monitor", ("Data bit %0d sampled: %b", bit_idx, uart_tx));
                    `endif

                    // Increment bit index
                    bit_idx <= bit_idx + 1;

                    if (bit_idx + 1 == 8) begin
                        state   <= STOP;
                        counter <= CYCLES_PER_BIT; // Wait for stop bit
                        `ifdef LOG_UART
                            `LOG("uart_baud_monitor", ("All data bits sampled, transitioning to STOP state"));
                        `endif
                    end else begin
                        counter <= CYCLES_PER_BIT; // Next bit period
                    end
                end else begin
                    counter <= counter - 1;
                end
            end

            //---------------------------------------------------
            // STOP: Wait for stop bit period and then output the byte
            //---------------------------------------------------
            STOP: begin
                if (counter == 0) begin
                    out_byte  <= shift_reg;
                    out_ready <= 1'b1;
                    `ifdef LOG_UART
                        `LOG("uart_baud_monitor", ("Stop bit period elapsed, byte received: b%08b 0x%02h ('%c')", shift_reg, shift_reg, shift_reg));
                    `endif
                    state <= IDLE;
                end else begin
                    counter <= counter - 1;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
