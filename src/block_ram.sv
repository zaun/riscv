`ifndef __BLOCK_RAM__
`define __BLOCK_RAM__
///////////////////////////////////////////////////////////////////////////////////////////////////
// block_ram Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module block_ram
 * @brief Asynchronous Reset Block RAM Module with Configurable Size and Width.
 *
 * The `block_ram` module implements a synchronous block RAM with separate read and write ports.
 * It is parameterized to support various memory sizes and data widths, making it versatile for
 * different applications such as data storage, buffering, and register files in digital designs.
 *
 * **Parameters:**
 * - `SIZE` (default: 1024): Specifies the total size of the memory in bytes. This parameter
 *                            determines the depth of the memory array.
 * - `WIDTH` (default: 8): Defines the width of each memory word in bits. Common widths include
 *                            8, 16, 32, 64, etc.
 *
 * **Interface:**
 * 
 * **Ports:**
 * - `clk` (`input`): Clock signal for synchronous operations.
 * - `reset` (`input`): Asynchronous reset signal. When asserted, the `read_data` output is
 *                      cleared to zero immediately, regardless of the clock.
 * 
 * - `write_en` (`input`): Write enable signal. When high, the module writes `write_data` to the
 *                         memory location specified by `write_address` on the rising edge of
 *                         `clk`.
 * - `write_address` (`input`): Address for the write operation. The width is determined by the
 *                              `SIZE` and `WIDTH` parameters to ensure proper addressing.
 * - `write_data` (`input` [WIDTH-1:0]): Data to be written to the memory.
 * 
 * - `read_address` (`input`): Address for the read operation. The width is determined by the
 *                             `SIZE` and `WIDTH` parameters to ensure proper addressing.
 * - `read_data` (`output` reg [WIDTH-1:0]): Data read from the memory at the specified
 *                                           `read_address`.
 * 
 * **Behavior:**
 * - **Write Operation:**
 *   - On the rising edge of `clk`, if `write_en` is asserted, `write_data` is written to the
 *     memory location specified by `write_address`.
 *   - The write operation is synchronous with the clock.
 * 
 * - **Read Operation:**
 *   - On the rising edge of `clk`, the data stored at `read_address` is read and presented on
 *     the `read_data` output.
 *   - If `reset` is asserted **asynchronously**, `read_data` is cleared to zero regardless of
 *     the `read_address`.
 * 
 * **Implementation Details:**
 * - **Memory Array:**
 *   - The memory is implemented using a Verilog `reg` array with a depth determined by the `SIZE`
 *     and `WIDTH` parameters.
 *   - **Depth Calculation:** The depth of the memory array is calculated using
 *                            `$clog2(SIZE/(WIDTH/8))`, which determines the number of address bits
 *                            required. This calculation results in a memory depth of
 *                            `2^ceil(log2(SIZE/(WIDTH/8)))`. Consequently, the actual memory depth
 *                            may **exceed** `SIZE/(WIDTH/8)` if `SIZE/(WIDTH/8)` is not a power of
 *                            two.
 *   - The `(* ram_style = "block" *)` synthesis directive suggests that the implementation should
 *     utilize block RAM resources on the target FPGA or ASIC for optimal performance and resource
 *     usage.
 * 
 * - **Address Calculation:**
 *   - The width of the `write_address` and `read_address` ports is calculated as
 *     `$clog2(SIZE/(WIDTH/8))`. This ensures that all memory locations can be uniquely addressed
 *     within the power-of-two depth determined by the memory array declaration.
 *   - **Example:** If `SIZE` is 1024 bytes and `WIDTH` is 8 bits, `SIZE/(WIDTH/8)` equals 1024.
 *                  Then, `$clog2(1024)` yields 10 bits for the address width, providing a memory
 *                  depth of 1024 entries.
 *   - **Note:** If `SIZE/(WIDTH/8)` is not a power of two, the memory depth becomes the next
 *               higher power of two, potentially leading to unused memory locations.
 * 
 * - **Asynchronous Reset:**
 *   - The `reset` signal asynchronously clears the `read_data` output to ensure immediate response
 *     to reset conditions, independent of the clock signal.
 * 
 * **Usage Notes:**
 * - **Parameter Configuration:**
 *   - Ensure that the `SIZE` parameter is a multiple of `WIDTH/8` to maintain proper byte
 *     alignment and to prevent address overflow.
 *   - Choose `WIDTH` based on the data width requirements of your application. Common
 *     configurations include 8, 16, 32, and 64 bits.
 * 
 * - **Memory Depth Consideration:**
 *   - Be aware that the memory depth is determined by `$clog2(SIZE/(WIDTH/8))`, resulting in a
 *     depth of `2^ceil(log2(SIZE/(WIDTH/8)))`. If `SIZE/(WIDTH/8)` is not a power of two, the
 *     memory will have additional unused locations. Plan your address mapping accordingly to
 *     avoid unintended behavior.
 * 
 * - **Timing Considerations:**
 *   - Both read and write operations are synchronous and occur on the rising edge of the `clk`
 *     signal.
 *   - Ensure that the clock frequency meets the timing requirements of your system to prevent
 *     metastability and data corruption.
 * 
 * - **Synthesis Directives:**
 *   - The `(* ram_style = "block" *)` attribute guides synthesis tools to implement the memory
 *     using block RAM resources. Ensure that your target FPGA or ASIC supports block RAM and
 *     that the synthesis tool respects this directive.
 * 
 * - **Initialization:**
 *   - Upon asynchronous reset, the `read_data` output is cleared to zero. Ensure that the
 *     memory contents are initialized as required for your application, either through reset
 *     logic or external initialization.
 * 
 * **Assertions:**
 * - The module includes `ASSERT` statements to enforce the following constraints during
 *   simulation:
 *   - `WIDTH` must be at least 8 bits.
 *   - `WIDTH` must be divisible by 8 to ensure byte alignment.
 *   - `SIZE` must be a multiple of `WIDTH/8` to ensure proper byte alignment.
 * 
 * **Example Instantiation:**
 * ```verilog
 * block_ram #(
 *     .SIZE(2048),   // 2048 bytes
 *     .WIDTH(32)     // 32-bit wide words
 * ) my_block_ram (
 *     .clk(clk),
 *     .reset(reset),
 *     .write_en(write_enable),
 *     .write_address(write_addr),
 *     .write_data(write_data),
 *     .read_address(read_addr),
 *     .read_data(read_data)
 * );
 * ```
 */

`timescale 1ns / 1ps
`default_nettype none

`include "log.sv"

module block_ram #(
    parameter int SIZE  = 1024,
    parameter int WIDTH = 8
) (
	input  wire         						clk,
	input  wire         						reset,
	input  wire         						write_en,
	input  wire [$clog2(SIZE/(WIDTH/8)) - 1:0]  write_address,
	input  wire [WIDTH-1:0]   					write_data,
	input  wire [$clog2(SIZE/(WIDTH/8)) - 1:0]  read_address,
	output reg  [WIDTH-1:0]   					read_data
);

initial begin
    `ASSERT((WIDTH >= 8), "WIDTH must be at least 8 bits.");
    `ASSERT((WIDTH % 8 == 0), "WIDTH must be divisible by 8 to ensure byte alignment.");
    `ASSERT((SIZE % (WIDTH / 8) == 0), "SIZE must be a multiple of WIDTH/8 to ensure proper byte alignment.");
end

(* ram_style = "block" *)
reg [WIDTH-1:0] memory[(SIZE/(WIDTH/8)) - 1:0];

always @(posedge clk or posedge reset) begin
	if (reset) begin
		read_data <= 0;
	end else begin
		read_data <= memory[read_address];
	end
end

always @(posedge clk) begin
	if (write_en) begin
		memory[write_address] <= write_data;
	end
end
endmodule

`endif // __BLOCK_RAM__
