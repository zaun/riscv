///////////////////////////////////////////////////////////////////////////////////////////////////
// tl_ul_uart Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module tl_ul_uart
 * @brief UART Interface with TileLink Uncached Lightweight (TL-UL) Support, 16-Byte FIFOs, and IRQ
 *        Handling
 *
 * The `tl_ul_uart` module implements a Universal Asynchronous Receiver/Transmitter (UART)
 * interfaced via the TileLink Uncached Lightweight (TL-UL) protocol. It features separate
 * 16-byte FIFOs for transmission (TX) and reception (RX), configurable baud rates, parity
 * settings, and interrupt request (IRQ) capabilities to notify the system of incoming data.
 *
 * **Parameters:**
 * - `XLEN` (integer, default: 32): Defines the data width for the TileLink interface.
 * - `SID_WIDTH` (integer, default: 2): Specifies the Source ID width for TileLink transactions.
 * - `CLK_FREQ_MHZ` (real, default: 100.0): Sets the system clock frequency in MHz, used for
 *   accurate baud rate generation.
 *
 * **Ports:**
 * - **Clock and Reset:**
 *   - `clk` (input wire): System clock signal.
 *   - `reset` (input wire): Asynchronous reset signal.
 *
 * - **TileLink A Channel:**
 *   - `tl_a_valid` (input wire): Indicates a valid TileLink A channel request.
 *   - `tl_a_ready` (output reg): Indicates readiness to accept a TileLink A channel request.
 *   - `tl_a_opcode` (input wire [2:0]): Opcode specifying the type of TileLink A channel request.
 *   - `tl_a_param` (input wire [2:0]): Parameter associated with the TileLink A channel request.
 *   - `tl_a_size` (input wire [2:0]): Size (in bytes) of the TileLink A channel request.
 *   - `tl_a_source` (input wire [SID_WIDTH-1:0]): Source ID for the TileLink A channel request.
 *   - `tl_a_address` (input wire [XLEN-1:0]): Address for the TileLink A channel request.
 *   - `tl_a_mask` (input wire [XLEN/8-1:0]): Byte mask for the TileLink A channel request.
 *   - `tl_a_data` (input wire [XLEN-1:0]): Data payload for the TileLink A channel request.
 *
 * - **TileLink D Channel:**
 *   - `tl_d_valid` (output reg): Indicates a valid TileLink D channel response.
 *   - `tl_d_ready` (input wire): Indicates readiness to accept a TileLink D channel response.
 *   - `tl_d_opcode` (output reg [2:0]): Opcode specifying the type of TileLink D channel response.
 *   - `tl_d_param` (output reg [1:0]): Parameter associated with the TileLink D channel response.
 *   - `tl_d_size` (output reg [2:0]): Size (in bytes) of the TileLink D channel response.
 *   - `tl_d_source` (output reg [SID_WIDTH-1:0]): Source ID for the TileLink D channel response.
 *   - `tl_d_data` (output reg [XLEN-1:0]): Data payload for the TileLink D channel response.
 *   - `tl_d_corrupt` (output reg): Indicates if the TileLink D channel response contains corrupt
 *                                  data.
 *   - `tl_d_denied` (output reg): Indicates if the TileLink D channel response is denied.
 *
 * - **UART Interface:**
 *   - `rx` (input wire): UART receive line.
 *   - `tx` (output wire): UART transmit line.
 *   - `irq` (output wire): Interrupt Request signal, asserted when new data is received.
 *
 * **Address Map:**
 * - `0x00`: **Status Register** (8 bits, Read/Write)
 *   - **Read Operation:**
 *     - **Bit 0**: TX FIFO Empty Status
 *       - `1`: Transmit FIFO is empty.
 *       - `0`: Transmit FIFO is not empty.
 *     - **Bit 1**: TX FIFO Full Status
 *       - `1`: Transmit FIFO is full.
 *       - `0`: Transmit FIFO is not full.
 *     - **Bit 2**: RX FIFO Empty Status
 *       - `1`: Receive FIFO is empty.
 *       - `0`: Receive FIFO is not empty.
 *     - **Bit 3**: RX FIFO Full Status
 *       - `1`: Receive FIFO is full.
 *       - `0`: Receive FIFO is not full.
 *     - **Bit 4**: IRQ Status
 *       - `1`: IRQ is pending (new data received).
 *       - `0`: No IRQ pending.
 *     - **Bits 7:5**: Reserved (read as `0`).
 *   - **Write Operation:**
 *     - Ignores data sent, clears the IRQ bit in the Status Register.
 *
 * - `0x04`: **Configuration Register** (8 bits, Read/Write)
 *   - **Bits [2:0]**: Baud Rate Settings
 *     - `000`: 230400 baud
 *     - `001`: 115200 baud (default)
 *     - `010`: 57600 baud
 *     - `011`: 28800 baud
 *     - `100`: 9600 baud
 *     - `101`: 4800 baud
 *     - `110`: 1200 baud
 *     - `111`: 300 baud
 *   - **Bits [4:3]**: Parity Settings
 *     - `00`: No parity
 *     - `01`: Even parity
 *     - `10`: Odd parity
 *     - `11`: Reserved
 *   - **Bit 5**: IRQ Enable
 *     - `1`: IRQ enabled (default)
 *     - `0`: IRQ disabled
 *   - **Bits 7:6**: Reserved (read as `0`).
 *
 * - `0x08`: **Data Register** (8 bits, Read/Write)
 *   - **Write Operation:**
 *     - Accepts byte-sized (`8-bit`) writes only.
 *     - Writing a byte enqueues it into the Transmit FIFO for transmission.
 *     - If the Transmit FIFO is full, the write operation is denied, and an error response is
 *       generated.
 *     - Writes with byte masks other than single-byte writes are denied with an error response.
 *   - **Read Operation:**
 *     - Accepts byte-sized (`8-bit`) reads only.
 *     - **When RX FIFO is not empty:**
 *       - Reading retrieves a byte from the Receive FIFO.
 *     - **When RX FIFO is empty:**
 *       - Reading returns zero data without generating an error response.
 *
 * **Operational Overview:**
 * - **TileLink Interface Handling:**
 *   - The module listens for TileLink A channel requests and processes them based on the address
 *     and operation type (read/write).
 *   - Responses are provided on the TileLink D channel, including data reads and acknowledgment
 *     of writes.
 *   - Error responses (`TL_D_ACCESS_ACK_ERROR`) are generated for invalid operations, such as
 *     unsupported addresses, incorrect data sizes, or FIFO overflows.
 *
 * - **UART Transmission:**
 *   - Data to be transmitted is written to the **Data Register** (`0x08`), which enqueues the
 *     byte into the Transmit FIFO.
 *   - The UART transmitter state machine handles sending start bits, data bits, and stop bits
 *     based on the configured baud rate.
 *   - If the Transmit FIFO is full, further write attempts are denied until space becomes
 *     available.
 *
 * - **UART Reception:**
 *   - Incoming serial data is received on the `rx` line and processed by the UART receiver state
 *     machine.
 *   - Received bytes are enqueued into the Receive FIFO.
 *   - Upon receiving new data, if IRQs are enabled, the `irq` signal is asserted to notify the
 *     system.
 *   - Data can be read from the **Data Register** (`0x08`). If the Receive FIFO is empty, read
 *     attempts return zero data without generating an error response.
 *
 * - **Interrupt Handling:**
 *   - **IRQ Assertion:**
 *     - The `irq` output is asserted when new data is received and enqueued into the Receive FIFO.
 *     - This occurs only if IRQs are enabled via the Configuration Register.
 *   - **IRQ Clearing:**
 *     - Writing to the **Status Register** (`0x00`) clears the IRQ status.
 *       - **Write Operation:**
 *         - Ignores the data written but clears Bit [4] of the Status Register.
 *       - **Effect:**
 *         - De-asserts the `irq` signal until new data is received.
 *
 * - **Baud Rate Configuration:**
 *   - The baud rate is configurable via the **Configuration Register** (`0x04`), allowing
 *     selection among various standard baud rates.
 *   - The baud rate generator calculates the number of clock cycles per bit based on the system
 *     clock frequency (`CLK_FREQ_MHZ`) and the selected baud rate.
 *
 * **FIFO Management:**
 * - **Transmit FIFO (TX FIFO):**
 *   - 16-byte deep FIFO for managing outgoing data.
 *   - Monitored via Status Register bits to indicate full or not full status.
 *   - Ensures smooth data transmission without data loss, provided the system handles FIFO full
 *     conditions appropriately.
 *
 * - **Receive FIFO (RX FIFO):**
 *   - 16-byte deep FIFO for managing incoming data.
 *   - Monitored via Status Register bits to indicate empty or not empty status.
 *   - Ensures reliable data reception, provided the system reads data promptly to prevent FIFO
 *     overflows.
 *
 * **Error Handling:**
 * - **Read Errors:**
 *   - **Previously:** Attempting to read from the **Data Register** (`0x08`) when the Receive FIFO is empty
 *     resulted in an error response (`TL_D_ACCESS_ACK_ERROR`).
 *   - **Current Behavior:** Reading from `0x08` when the Receive FIFO is empty returns zero data without
 *     generating an error response.
 *
 * - **Write Errors:**
 *   - Attempting to write to the **Data Register** (`0x08`) when the Transmit FIFO is full results
 *     in an error response.
 *   - Writes with data sizes other than byte-sized writes to `0x08` or writes to unsupported
 *     addresses result in an error response.
 *
 * **Usage Guidelines:**
 * - **Initialization:**
 *   - Connect the `clk` and `reset` signals appropriately.
 *   - Set the `CLK_FREQ_MHZ` parameter to match the system's clock frequency for accurate baud
 *     rate generation.
 *
 * - **TileLink Transactions:**
 *   - **Read Operations:**
 *     - Read from `0x00` to obtain the current Status Register.
 *     - Read from `0x04` to obtain the current Configuration Register.
 *     - Read from `0x08` to retrieve received data from the Receive FIFO. If the RX FIFO is empty,
 *       zero data is returned without an error.
 *   - **Write Operations:**
 *     - Write to `0x04` to configure baud rate, parity, and IRQ settings.
 *     - Write to `0x08` to send data via the UART.
 *     - Write to `0x00` to clear the IRQ status by ignoring the written data and resetting Bit [4].
 *
 * - **Data Transmission and Reception:**
 *   - **Sending Data:**
 *     - Write byte-sized data to the **Data Register** (`0x08`). The data is enqueued into the
 *       Transmit FIFO and sent serially over the `tx` line.
 *     - Monitor the Status Register to ensure the Transmit FIFO is not full before writing.
 *   - **Receiving Data:**
 *     - Data received on the `rx` line is enqueued into the Receive FIFO.
 *     - An IRQ is asserted if enabled, signaling that data is available.
 *     - Read byte-sized data from the **Data Register** (`0x08`) to retrieve received bytes.
 *     - If the Receive FIFO is empty, reading from `0x08` returns zero data without an error.
 *
 * **Notes:**
 * - **Flow Control:**
 *   - The module does not implement hardware flow control (e.g., RTS/CTS). Ensure that the system
 *     manages FIFO statuses to prevent data loss.
 * - **Parity and Error Checking:**
 *   - Parity settings are configurable via the Configuration Register. Ensure parity is correctly
 *     configured to match the communicating device.
 * - **Baud Rate Accuracy:**
 *   - Accurate baud rate generation depends on the precision of the `CLK_FREQ_MHZ` parameter and
 *     the system clock stability.
 * - **IRQ Handling:**
 *   - Properly handle IRQs by clearing the IRQ status after servicing the interrupt to ensure
 *     subsequent interrupts are correctly generated.
 * - **Extensibility:**
 *   - The module can be extended to support additional features such as flow control, multiple
 *     parity options, or larger FIFOs based on system requirements.
 *
 * **TODO:**
 * - Implement Parity bits.
 * - Move to an external FIFO module.
 * - Add a config option and logic to support XON/XOFF software flow control.
 * - Add a config option and logic to support echoing.
 *
 */


`timescale 1ns / 1ps
`default_nettype none
    
`include "src/log.sv"

module tl_ul_uart #(
    parameter int XLEN = 32,
    parameter int SID_WIDTH = 2,
    parameter real CLK_FREQ_MHZ = 100.0 // System clock frequency in MHz
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
    output reg                  tl_d_denied,

    // UART Interface
    input  wire                 rx, // UART Receive line
    output wire                 tx, // UART Transmit line
    output wire                 irq // IRQ output
);

// Local Parameters for TileLink Opcodes
localparam [2:0] TL_D_ACCESS_ACK              = 3'b000;  // Acknowledge access (no data)
localparam [2:0] TL_D_ACCESS_ACK_DATA         = 3'b010;  // Acknowledge access with data
localparam [2:0] TL_D_ACCESS_ACK_DATA_CORRUPT = 3'b101;  // Access with corrupt data
localparam [2:0] TL_D_ACCESS_ACK_ERROR        = 3'b111;  // Acknowledge access with an error

// Local Parameters for TileLink Access
localparam [2:0] PUT_FULL_DATA_OPCODE = 3'b000;
localparam [2:0] GET_OPCODE           = 3'b100;

// Local Parameters for Register Addresses
localparam STATUS_ADDRESS = 32'h00;
localparam CONFIG_ADDRESS = 32'h04;
localparam DATA_ADDRESS   = 32'h08;

// State Definitions
typedef enum logic [1:0] {
    IDLE,
    PROCESS,
    RESPOND,
    RESPOND_WAIT
} state_t;
state_t state;

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

// FIFO Parameters
localparam FIFO_DEPTH = 16;
localparam FIFO_ADDR_WIDTH = 4; // 16 entries

// Transmit FIFO
reg [7:0] tx_fifo [0:FIFO_DEPTH-1];
reg [FIFO_ADDR_WIDTH:0] tx_fifo_wr_ptr;
reg [FIFO_ADDR_WIDTH:0] tx_fifo_rd_ptr;
wire tx_fifo_full;
wire tx_fifo_empty;

assign tx_fifo_full = (tx_fifo_wr_ptr[FIFO_ADDR_WIDTH-1:0] == tx_fifo_rd_ptr[FIFO_ADDR_WIDTH-1:0]) && 
                      (tx_fifo_wr_ptr[FIFO_ADDR_WIDTH] != tx_fifo_rd_ptr[FIFO_ADDR_WIDTH]);
assign tx_fifo_empty = (tx_fifo_wr_ptr == tx_fifo_rd_ptr);

// Receive FIFO
reg [7:0] rx_fifo [0:FIFO_DEPTH-1];
reg [FIFO_ADDR_WIDTH:0] rx_fifo_wr_ptr;
reg [FIFO_ADDR_WIDTH:0] rx_fifo_rd_ptr;
wire rx_fifo_full = (rx_fifo_wr_ptr[FIFO_ADDR_WIDTH-1:0] == rx_fifo_rd_ptr[FIFO_ADDR_WIDTH-1:0]) && 
                    (rx_fifo_wr_ptr[FIFO_ADDR_WIDTH] != rx_fifo_rd_ptr[FIFO_ADDR_WIDTH]);
wire rx_fifo_empty = (rx_fifo_wr_ptr == rx_fifo_rd_ptr);

// Status Register Bits
// [0] - TX FIFO Empty Status
//       - 1: TX FIFO is Empty
//       - 0: TX FIFO is Not Empty
// [1] - TX FIFO Full Status
//       - 1: TX FIFO is Full
//       - 0: TX FIFO is Not Full
// [2] - RX FIFO Empty Status
//       - 1: RX FIFO is Empty
//       - 0: RX FIFO is Not Empty
// [3] - RX FIFO Full Status
//       - 1: RX FIFO is Full
//       - 0: RX FIFO is Not Full
// [4] - IRQ Status
//       - 1: IRQ Pending (new data received)
//       - 0: No IRQ
// [7:5] - Reserved
reg [7:0] status_reg;

// Config Register Bits
// [2:0] - Baud Rate Settings
//       - 000: 230400 baud
//       - 001: 115200 baud (default)
//       - 010: 57600 baud
//       - 011: 28800 baud
//       - 100: 9600 baud
//       - 101: 4800 baud
//       - 110: 1200 baud
//       - 111: 300 baud
// [4:3] - Parity Settings (Reserved)
//       - 00: None (default)
//       - 01: Even
//       - 10: Odd
//       - 11: None
// [5]   - IRQ Enabled
//       - 0: IRQ Disabled
//       - 1: IRQ Enabled (default)
// [7:6] - Reserved
reg [7:0] config_reg;

// IRQ Handling
assign irq = config_reg[5] & status_reg[4]; // Drive the IRQ line directly from the status register

// Utility function for WSTRB
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

// ------------- Baud Rate Generator -------------
// Compute CYCLES_PER_BIT for each baud rate based on CLK_FREQ_MHZ
localparam integer CYCLES_230400 = (CLK_FREQ_MHZ * 1000000) / 230400;  // ≈ 868 for 100MHz
localparam integer CYCLES_115200 = (CLK_FREQ_MHZ * 1000000) / 115200;  // ≈ 1736 for 100MHz
localparam integer CYCLES_57600  = (CLK_FREQ_MHZ * 1000000) / 57600;   // ≈ 3472 for 100MHz
localparam integer CYCLES_28800  = (CLK_FREQ_MHZ * 1000000) / 28800;   // ≈ 10416 for 100MHz
localparam integer CYCLES_9600   = (CLK_FREQ_MHZ * 1000000) / 9600;    // ≈ 868 for 100MHz
localparam integer CYCLES_4800   = (CLK_FREQ_MHZ * 1000000) / 4800;    // ≈ 1736 for 100MHz
localparam integer CYCLES_1200   = (CLK_FREQ_MHZ * 1000000) / 1200;    // ≈ 3472 for 100MHz
localparam integer CYCLES_300    = (CLK_FREQ_MHZ * 1000000) / 300;     // ≈ 10416 for 100MHz

// Register to hold current cycles per bit based on baud rate
reg [18:0] cycles_per_bit_reg; // baud reate cycle ounter

// Update cycles_per_bit_reg based on config_reg[2:0]
always @(posedge clk or posedge reset) begin
    if (reset) begin
        cycles_per_bit_reg <= CYCLES_115200;
    end else begin
        case (config_reg[2:0])
            3'b000 : cycles_per_bit_reg <= CYCLES_230400;
            3'b001 : cycles_per_bit_reg <= CYCLES_115200;
            3'b010 : cycles_per_bit_reg <= CYCLES_57600;
            3'b011 : cycles_per_bit_reg <= CYCLES_28800;
            3'b100 : cycles_per_bit_reg <= CYCLES_9600;
            3'b101 : cycles_per_bit_reg <= CYCLES_4800;
            3'b110 : cycles_per_bit_reg <= CYCLES_1200;
            3'b111 : cycles_per_bit_reg <= CYCLES_300;
            default: cycles_per_bit_reg <= CYCLES_115200;
        endcase
    end
end

// Baud rate generator using cycles_per_bit_reg
reg [13:0] baud_counter;
reg baud_tick;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        baud_counter <= 0;
        baud_tick    <= 0;
    end else begin
        if (baud_counter == cycles_per_bit_reg) begin
            baud_counter <= 0;
            baud_tick    <= 1;
        end else begin
            baud_counter <= baud_counter + 1;
            baud_tick    <= 0;
        end
    end
end

// ------------- UART Transmitter Logic -------------
typedef enum logic [2:0] {
    TX_IDLE,
    TX_DATA,
    TX_STOP
} tx_state_t;

tx_state_t tx_state_reg;
reg [3:0] tx_bit_cnt; // 0 to 7 for data bits
reg [7:0] tx_shift_reg;
reg       tx_serial;

// Signals to manage synchronized start bit
reg want_start_bit;      // Flag to indicate readiness to start

assign tx = tx_serial;

// Transmitter State Machine
always @(posedge clk or posedge reset) begin
    if (reset) begin
        tx_state_reg     <= TX_IDLE;
        tx_bit_cnt       <= 0;
        tx_serial        <= 1'b1;  // Idle state is high
        want_start_bit   <= 1'b0;
        `ifdef LOG_UART
            `LOG("uart", ("TX_IDLE state initialized"));
        `endif
    end else begin
        // Handle state transitions on baud_tick
        if (baud_tick) begin
            case (tx_state_reg)
                //---------------------------------------------------
                // TX_IDLE: Check if there's data to dequeue
                //---------------------------------------------------
                TX_IDLE: begin
                    if (!tx_fifo_empty) begin
                        tx_shift_reg   <= tx_fifo[tx_fifo_rd_ptr[FIFO_ADDR_WIDTH-1:0]];
                        tx_fifo_rd_ptr <= tx_fifo_rd_ptr + 1;
                        tx_serial    <= 1'b0;  // Start bit
                        tx_bit_cnt   <= 0;
                        tx_state_reg   <= TX_DATA;
                        `ifdef LOG_UART `LOG("uart", ("Dequeued FIFO[%0d]: %h, transitioning to TX_DATA", tx_fifo_rd_ptr, tx_fifo[tx_fifo_rd_ptr[FIFO_ADDR_WIDTH-1:0]])); `endif
                    end
                end

                //---------------------------------------------------
                // TX_DATA: Send bits [0..7]
                //---------------------------------------------------
                TX_DATA: begin
                    tx_serial  <= tx_shift_reg[tx_bit_cnt];
                    `ifdef LOG_UART
                        `LOG("uart", ("TX_DATA, sending bit %0d: %b", tx_bit_cnt, tx_shift_reg[tx_bit_cnt]));
                    `endif
                    tx_bit_cnt <= tx_bit_cnt + 1;

                    if (tx_bit_cnt == 7) begin
                        tx_state_reg <= TX_STOP;
                        `ifdef LOG_UART
                            `LOG("uart", ("Transition to TX_STOP"));
                        `endif
                    end
                end

                //---------------------------------------------------
                // TX_STOP: Drive stop bit high
                //---------------------------------------------------
                TX_STOP: begin
                    tx_serial    <= 1'b1; // Stop bit
                    tx_state_reg <= TX_IDLE;
                    `ifdef LOG_UART
                        `LOG("uart", ("Transition to TX_IDLE, sending stop bit"));
                    `endif
                end

                //---------------------------------------------------
                // Default Case
                //---------------------------------------------------
                default: begin
                    tx_state_reg <= TX_IDLE;
                    tx_serial    <= 1'b1;
                    `ifdef LOG_UART
                        `LOG("uart", ("Defaulting to TX_IDLE"));
                    `endif
                end
            endcase
        end
    end
end

// ------------- UART Receiver Logic with Enhanced Sampling -------------
typedef enum logic [1:0] {
    RX_IDLE,
    RX_START,
    RX_DATA,
    RX_STOP
} rx_state_t;

// Registers for Receive State Machine
rx_state_t rx_state_reg;
reg [3:0] rx_bit_cnt;       // Bit counter for data bits
reg [7:0] rx_shift_reg;     // Shift register to store received bits

// Initialize Receive State Machine
always @(posedge clk or posedge reset) begin
    if (reset) begin
        rx_state_reg  <= RX_IDLE;
        rx_bit_cnt    <= 0;
        rx_shift_reg  <= 0;
        status_reg[4] <= 1'b0; // Clear IRQ
        `ifdef LOG_UART
            `LOG("uart", ("Receiver reset to RX_IDLE"));
        `endif
    end else begin
        case (rx_state_reg)
            RX_IDLE: begin
                if (rx == 1'b0) begin // Start bit detected
                    rx_state_reg <= RX_START;
                    `ifdef LOG_UART
                        `LOG("uart", ("Start bit detected, transitioning to RX_START"));
                    `endif
                end
            end

            RX_START: begin
                if (baud_tick) begin
                    // Move to data sampling
                    rx_state_reg <= RX_DATA;
                    rx_bit_cnt   <= 0;
                    rx_shift_reg <= 0;
                    `ifdef LOG_UART
                        `LOG("uart", ("Half baud period passed, transitioning to RX_DATA"));
                    `endif
                end
            end

            RX_DATA: begin
                if (baud_tick) begin
                    // Sample the current data bit
                    rx_shift_reg[rx_bit_cnt] <= rx;
                    `ifdef LOG_UART
                        `LOG("uart", ("Data bit %0d sampled: %b", rx_bit_cnt, rx));
                    `endif
                    rx_bit_cnt <= rx_bit_cnt + 1;

                    if (rx_bit_cnt == 7) begin
                        // All data bits received, transition to RX_STOP
                        rx_state_reg <= RX_STOP;
                        `ifdef LOG_UART
                            `LOG("uart", ("All data bits sampled, transitioning to RX_STOP"));
                        `endif
                    end
                end
            end

            RX_STOP: begin
                if (baud_tick) begin
                    if (rx == 1'b1 && !rx_fifo_full) begin
                        // Valid stop bit and RX FIFO not full
                        rx_fifo[rx_fifo_wr_ptr[FIFO_ADDR_WIDTH-1:0]] <= rx_shift_reg;
                        rx_fifo_wr_ptr <= rx_fifo_wr_ptr + 1;
                        status_reg[4]  <= 1'b1; // Set IRQ
                        `ifdef LOG_UART
                            `LOG("uart", ("Stop bit received, data enqueued to RX FIFO: %h, IRQ set", rx_shift_reg));
                        `endif
                    end else begin
                        // Stop bit error or RX FIFO full
                        `ifdef LOG_UART
                            `LOG("uart", ("Stop bit error or RX FIFO full"));
                        `endif
                    end
                    // Transition back to RX_IDLE
                    rx_state_reg <= RX_IDLE;
                    `ifdef LOG_UART
                        `LOG("uart", ("Transitioning back to RX_IDLE"));
                    `endif
                end
            end

            default: begin
                rx_state_reg <= RX_IDLE;
                `ifdef LOG_UART
                    `LOG("uart", ("Defaulting to RX_IDLE"));
                `endif
            end
        endcase
    end
end

// ------------- Handle TileLink + IRQ in same always block -------------
always @(posedge clk or posedge reset) begin
    if (reset) begin
        // Reset all registers
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

        // Reset FIFOs
        tx_fifo_wr_ptr <= 0;
        tx_fifo_rd_ptr <= 0;
        rx_fifo_wr_ptr <= 0;
        rx_fifo_rd_ptr <= 0;

        // Registers Register
        status_reg     <= 8'b0000_0000;
        config_reg     <= 8'b0010_0001; // IRQ Enabled, 115200 Baud

        `ifdef LOG_UART
            `LOG("uart", ("Reset complete"));
        `endif
    end else begin
        // Update Status Register bits [0:2]
        // TX FIFO Status
        status_reg[0] <= tx_fifo_empty;
        status_reg[1] <= tx_fifo_full;

        // RX FIFO Status
        status_reg[2] <= rx_fifo_empty;
        status_reg[3] <= rx_fifo_full;

        // Zero out reserved bits
        status_reg[7:5] <= 3'b000;
        config_reg[7:6] <= 2'b00;

        // TileLink handshake signals
        tl_a_ready <= (state == IDLE);
        tl_d_valid <= (state == RESPOND);

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
                    state <= PROCESS;

                    `ifdef LOG_UART
                        `LOG("uart", ("Captured request - Address: %0h, Read: %0b, Size: %0d, Data: %0h", tl_a_address, req_read, tl_a_size, req_wdata));
                    `endif
                end
            end

            PROCESS: begin
                // Initialize response flags
                resp_param   <= 2'b00;
                resp_source  <= req_source;

                // Handle Read vs Write
                if (req_read) begin
                    // ---------- READ ----------
                    case (req_address)
                        STATUS_ADDRESS: begin
                            if (req_size == 3'b000) begin
                                `ifdef LOG_UART `LOG("uart", ("Processing Read from STATUS_ADDRESS")); `endif
                                resp_data   <= {{(XLEN-8){1'b0}}, status_reg};
                                resp_opcode <= TL_D_ACCESS_ACK_DATA;
                            end else begin
                                resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                                `ifdef LOG_UART
                                    `LOG("uart", ("Read from STATUS_ADDRESS denied due to invalid size: %b", req_size));
                                `endif
                            end
                        end
                        CONFIG_ADDRESS: begin
                            if (req_size == 3'b000) begin
                                `ifdef LOG_UART `LOG("uart", ("Processing Read from CONFIG_ADDRESS")); `endif
                                resp_data   <= {{(XLEN-8){1'b0}}, config_reg};
                                resp_opcode <= TL_D_ACCESS_ACK_DATA;
                            end else begin
                                resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                                `ifdef LOG_UART
                                    `LOG("uart", ("Read from STATUS_ADDRESS denied due to invalid size: %b", req_size));
                                `endif
                            end
                        end
                        DATA_ADDRESS: begin
                            if (req_size == 3'b000) begin
                                if (!rx_fifo_empty) begin
                                    `ifdef LOG_UART `LOG("uart", ("Read byte from DATA_ADDRESS: %h", rx_fifo[rx_fifo_rd_ptr[FIFO_ADDR_WIDTH-1:0]])); `endif
                                    resp_data  <= {{(XLEN-8){1'b0}}, rx_fifo[rx_fifo_rd_ptr[FIFO_ADDR_WIDTH-1:0]]};
                                    resp_opcode <= TL_D_ACCESS_ACK_DATA;
                                    rx_fifo_rd_ptr <= rx_fifo_rd_ptr + 1;

                                    // If RX FIFO becomes empty => clear IRQ
                                    if (rx_fifo_rd_ptr + 1 == rx_fifo_wr_ptr) begin
                                        status_reg[4] <= 1'b0;
                                        `ifdef LOG_UART `LOG("uart", ("RX_FIFO is now empty, IRQ cleared")); `endif
                                    end
                                end else begin
                                    resp_data   <= {XLEN{1'b0}};
                                    resp_denied <= 1'b0;
                                    resp_opcode <= TL_D_ACCESS_ACK_DATA;
                                    `ifdef LOG_UART `LOG("uart", ("Attempted Read from empty RX_FIFO, respond without ERROR")); `endif
                                end
                            end else begin
                                resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                                `ifdef LOG_UART `LOG("uart", ("Read from RX_FIFO denied due to invalid size: %b", req_size)); `endif
                            end
                        end
                        default: begin
                            resp_data   <= {XLEN{1'b0}};
                            resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                            resp_denied <= 1'b1;
                            resp_param  <= 2'b10; // Error param
                            `ifdef LOG_UART
                                `LOG("uart", ("Invalid Read Address: %h, respond with ERROR", req_address));
                            `endif
                        end
                    endcase
                end else begin
                    // ---------- WRITE ----------
                    case (req_address)
                        STATUS_ADDRESS: begin
                            if (req_size == 3'b000) begin
                                if (count_wstrb_bits(req_wstrb) == 1) begin
                                    `ifdef LOG_UART
                                        `LOG("uart", ("Processing Write to STATUS_ADDRESS, Data: %h", req_wdata));
                                    `endif
                                    // Ignore teh content, just clear the IRQ bit in the status_reg
                                    status_reg[4] <= 1'b0;
                                    resp_data   <= {XLEN{1'b0}};
                                    resp_opcode <= TL_D_ACCESS_ACK;
                                end else begin
                                    resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                    `ifdef LOG_UART
                                        `LOG("uart", ("Write to STATUS_ADDRESS denied due to invalid mask"));
                                    `endif
                                end
                            end else begin
                                resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                                `ifdef LOG_UART
                                    `LOG("uart", ("Write to STATUS_ADDRESS denied due to invalid size: %b", req_size));
                                `endif
                            end
                        end

                        CONFIG_ADDRESS: begin
                            if (req_size == 3'b000) begin
                                if (count_wstrb_bits(req_wstrb) == 1) begin
                                    `ifdef LOG_UART
                                        `LOG("uart", ("Processing Write to CONFIG_ADDRESS, Data: %h", req_wdata));
                                    `endif

                                    config_reg  <= req_wdata[7:0];
                                    resp_data   <= {XLEN{1'b0}};
                                    resp_opcode <= TL_D_ACCESS_ACK;
                                end else begin
                                    resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                    `ifdef LOG_UART
                                        `LOG("uart", ("Write to CONFIG_ADDRESS denied due to invalid mask"));
                                    `endif
                                end
                            end else begin
                                resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                                `ifdef LOG_UART
                                    `LOG("uart", ("Write to CONFIG_ADDRESS denied due to invalid size: %b", req_size));
                                `endif
                            end
                        end

                        DATA_ADDRESS: begin
                            // Only accept byte writes
                            if (req_size == 3'b000) begin
                                if (count_wstrb_bits(req_wstrb) == 1) begin
                                    if (!tx_fifo_full) begin
                                        `ifdef LOG_UART
                                            `LOG("uart", ("Byte enqueued to TX_FIFO: %h", req_wdata[7:0]));
                                        `endif
                                        tx_fifo[tx_fifo_wr_ptr[FIFO_ADDR_WIDTH-1:0]] <= req_wdata[7:0];
                                        tx_fifo_wr_ptr <= tx_fifo_wr_ptr + 1;
                                        resp_opcode <= TL_D_ACCESS_ACK;
                                        resp_data   <= {XLEN{1'b0}};
                                    end else begin
                                        resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                        resp_denied <= 1'b1;
                                        resp_param  <= 2'b10; // Error param
                                        `ifdef LOG_UART
                                            `LOG("uart", ("TX_FIFO is full, write denied"));
                                        `endif
                                    end
                                end else begin
                                    resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                    resp_denied <= 1'b1;
                                    resp_param  <= 2'b10; // Error param
                                    `ifdef LOG_UART
                                        `LOG("uart", ("Write to DATA_ADDRESS denied due to invalid mask"));
                                    `endif
                                end
                            end else begin
                                resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                                resp_denied <= 1'b1;
                                resp_param  <= 2'b10; // Error param
                                `ifdef LOG_UART
                                    `LOG("uart", ("Write to DATA_ADDRESS denied due to invalid size: %b", req_size));
                                `endif
                            end
                        end

                        default: begin
                            resp_opcode <= TL_D_ACCESS_ACK_ERROR;
                            resp_denied <= 1'b1;
                            resp_param  <= 2'b10; // Error param
                            `ifdef LOG_UART
                                `LOG("uart", ("Invalid Write Address: %h, responding with ERROR", req_address));
                            `endif
                        end
                    endcase
                end
                state <= RESPOND;
            end

            RESPOND: begin
                // Assign response signals
                tl_d_opcode  <= resp_opcode;
                tl_d_param   <= resp_param;
                tl_d_size    <= req_size;
                tl_d_source  <= resp_source;
                tl_d_data    <= resp_data;
                tl_d_corrupt <= resp_corrupt;
                tl_d_denied  <= resp_denied;

                `ifdef LOG_UART
                    `LOG("uart", ("Prepared response - Opcode: %0b, Data: %0h, Denied: %0b, Corrupt: %0b",
                                  resp_opcode, resp_data, resp_denied, resp_corrupt));
                `endif

                state <= RESPOND_WAIT;
            end

            RESPOND_WAIT: begin
                if (tl_d_ready) begin
                    // Handshake done, reset response signals
                    tl_d_opcode  <= 3'b000;
                    tl_d_param   <= 2'b00;
                    tl_d_size    <= 3'b000;
                    tl_d_source  <= {SID_WIDTH{1'b0}};
                    tl_d_data    <= {XLEN{1'b0}};
                    tl_d_corrupt <= 1'b0;
                    tl_d_denied  <= 1'b0;
                    resp_denied  <= 1'b0;
                    resp_corrupt <= 1'b0;
                    state        <= IDLE;
                end else begin
                    // Remain in RESPOND_WAIT until tl_d_ready is asserted
                    state <= RESPOND_WAIT;
                end
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end
end

endmodule
