///////////////////////////////////////////////////////////////////////////////////////////////////
// ALU Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module cpu_bmu
 * @brief Performs bit manipulation logic.
 *
 * The BMU module executes bit manipulation operations based on the
 * `control` signal. It is designed to support riscv m instructions.
 */

`default_nettype none
`timescale 1ns / 1ps

// -----------------------------
// BMU Operation Encoding
// -----------------------------
`define BMU_CLZ       6'b000000 // 0  Count Leading Zeros
`define BMU_CTZ       6'b000001 // 1  Count Trailing Zeros
`define BMU_CPOP      6'b000010 // 2  Count Population (Set Bits)
`define BMU_ANDN      6'b000011 // 3  AND with NOT
`define BMU_ORN       6'b000100 // 4  OR with NOT
`define BMU_XNOR      6'b000101 // 5  XOR with NOT
`define BMU_SLO       6'b000110 // 6  Set Lowest-order Zero
`define BMU_SRO       6'b000111 // 7  Set Highest-order One
`define BMU_ROL       6'b001000 // 8  Rotate Left
`define BMU_ROR       6'b001001 // 9  Rotate Right
`define BMU_REV8      6'b001010 // 10 Byte Reversal
`define BMU_SHFL      6'b001011 // 11 Bit Shuffle
`define BMU_UNSHFL    6'b001100 // 12 Bit Unshuffle
`define BMU_BEXT      6'b001101 // 13 Bit Extract
`define BMU_BDEP      6'b001110 // 14 Bit Deposit
`define BMU_BCOMP     6'b001111 // 15 Bit Compress
`define BMU_BSET      6'b010000 // 16 Bit Set
`define BMU_BCLR      6'b010001 // 17 Bit Clear
`define BMU_BINV      6'b010010 // 18 Bit Invert
`define BMU_REV16     6'b010011 // 19 16-bit Reversal
`define BMU_REV32     6'b010100 // 20 32-bit Reversal
`define BMU_PACKB     6'b010101 // 21 Pack Bytes
`define BMU_PACKH     6'b010110 // 22 Pack Half-Words
`define BMU_PACKW     6'b010111 // 23 Pack Words
`define BMU_UNPACKB   6'b011000 // 24 Unpack Bytes
`define BMU_UNPACKH   6'b011001 // 25 Unpack Half-Words
`define BMU_UNPACKW   6'b011010 // 26 Unpack Words
`define BMU_BSHIFT    6'b011011 // 27 Bitwise Shift
`define BMU_BUNSHIFT  6'b011100 // 28 Bitwise Unshift
`define BMU_CLMUL     6'b011101 // 29 Carry-less Multiplication
`define BMU_CLMULH    6'b011110 // 30 Carry-less Multiplication High
`define BMU_CLMULR    6'b011111 // 31 Carry-less Multiplication Reverse
`define BMU_MAX       6'b100000 // 32 Max
`define BMU_MAXU      6'b100001 // 33 Max Unsigned
`define BMU_MIN       6'b100010 // 34 Min
`define BMU_MINU      6'b100011 // 35 Min Unsigned
`define BMU_SH1ADD    6'b100100 // 37 Shift-Left 1 and Add
`define BMU_SH2ADD    6'b100101 // 38 Shift-Left 2 and Add
`define BMU_SH3ADD    6'b100110 // 39 Shift-Left 3 and Add
`define BMU_XPERM16   6'b100111 // 40 Extended Permute 16
`define BMU_XPERM32   6'b101000 // 41 Extended Permute 32
`define BMU_XPERM4    6'b101001 // 42 Extended Permute 4
`define BMU_XPERM8    6'b101010 // 43 Extended Permute 8
`define BMU_ZEXTH32   6'b101011 // 44 Zero-Extend Halfword 32
`define BMU_ZEXTH64   6'b101100 // 45 Zero-Extend Halfword 64
`define BMU_ADD_UW    6'b101101 // 46 Add Unsigned Word
`define BMU_SH1ADD_UW 6'b101110 // 47 Shift-Left 1 and Add Unsigned Word
`define BMU_SH2ADD_UW 6'b101111 // 48 Shift-Left 2 and Add Unsigned Word
`define BMU_SH3ADD_UW 6'b110000 // 49 Shift-Left 3 and Add Unsigned Word
`define BMU_SEXTB     6'b110001 // 50 Byte Sign extend
`define BMU_SEXTH     6'b110010 // 50 Half-Word Sign extend
`define BMU_ORCB      6'b110011 // 51 Bitware OR-combine, byte granule
`define BMU_SLLIUW    6'b110100 // 52 Shift left unsigned word (Immediate)
`define BMU_GREV      6'b110101 // 53 Generalized Bit REversal Immediate

module cpu_bmu #(
    parameter XLEN = 32
) (
    input  logic [XLEN-1:0] operand_a,
    input  logic [XLEN-1:0] operand_b,
    input  logic [5:0]      control,
    output logic [XLEN-1:0] result
);

// -----------------------------
// Shift Bits Calculation
// -----------------------------
localparam SHIFT_BITS = $clog2(XLEN); // 5 for XLEN=32, 6 for XLEN=64

// -----------------------------
// Internal Signals for Signed Comparisons
// -----------------------------
logic signed [XLEN-1:0] operand_a_signed;
assign operand_a_signed = operand_a;

logic signed [XLEN-1:0] operand_b_signed;
assign operand_b_signed = operand_b;

// -----------------------------
// Helper functions
// -----------------------------
logic [XLEN-1:0] temp_operand;  // Bit counting register

function automatic [XLEN-1:0] shuffle(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] temp_result;
    begin
        temp_result = {XLEN{1'b0}};
        for (i = 0; i < XLEN/2; i = i + 1) begin
            temp_result[2*i+:1]   = data[i+:1];
            temp_result[2*i+1+:1] = data[i+XLEN/2+:1];
        end
        shuffle = temp_result;
    end
endfunction

function automatic [XLEN-1:0] unshuffle(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] result;
    begin
        result = {XLEN{1'b0}};
        for (i = 0; i < XLEN/2; i = i + 1) begin
            result[i]         = data[2*i];
            result[i+XLEN/2] = data[2*i+1];
        end
        unshuffle = result;
    end
endfunction

// Bit Deposit: Deposits bits from src into dest according to mask
function automatic [XLEN-1:0] bdep(input [XLEN-1:0] src, input [XLEN-1:0] mask);
    integer i;
    begin
        bdep = 0;
        for (i = 0; i < XLEN; i = i + 1) begin
            if (mask[i])
                bdep[i] = src[i];
        end
    end
endfunction

// Bit Compress: Compresses bits from data according to mask
function automatic [XLEN-1:0] bcomp(input [XLEN-1:0] data, input [XLEN-1:0] mask);
    integer i, j;
    begin
        bcomp = 0;
        j = 0;
        for (i = 0; i < XLEN; i = i + 1) begin
            if (mask[i]) begin
                bcomp[j] = data[i];
                j = j + 1;
            end
        end
    end
endfunction

// 8-bit Reversal
function automatic [XLEN-1:0] rev8(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] temp_result;
    begin
        temp_result = {XLEN{1'b0}};
        for (i = 0; i < XLEN/8; i = i + 1) begin
            temp_result[i*8 +: 8] = {data[i*8 + 4 +: 4], data[i*8 +: 4]};
        end
        rev8 = temp_result;
    end
endfunction

// 16-bit Reversal
function automatic [XLEN-1:0] rev16(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] temp_result;
    begin
        temp_result = {XLEN{1'b0}};
        for (i = 0; i < XLEN/16; i = i + 1) begin
            temp_result[i*16 +: 16] = {data[i*16 + 8 +: 8], data[i*16 +: 8]};
        end
        rev16 = temp_result;
    end
endfunction


// 32-bit Reversal
function automatic [XLEN-1:0] rev32(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] temp_result;
    begin
        temp_result = {XLEN{1'b0}};
        for (i = 0; i < XLEN/32; i = i + 1) begin
            temp_result[i*32 +: 32] = {data[i*32 + 16 +: 16], data[i*32 +: 16]};
        end
        rev32 = temp_result;
    end
endfunction

// Pack Bytes
function automatic [XLEN-1:0] packb(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] result;
    begin
        result = 0;
        for (i = 0; i < XLEN/8; i = i + 1) begin
            result[i] = |data[8*i +: 8];
        end
        packb = result;
    end
endfunction

// Unpack Bytes
function automatic [XLEN-1:0] unpackb(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] result;
    begin
        result = 0;
        for (i = 0; i < XLEN/8; i = i + 1) begin
            result[8*i +: 8] = {8{data[i]}};
        end
        unpackb = result;
    end
endfunction

// Pack Half-Words
function automatic [XLEN-1:0] packh(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] result;
    begin
        result = 0;
        for (i = 0; i < XLEN/16; i = i + 1) begin
            result[i] = |data[16*i +: 16];
        end
        packh = result;
    end
endfunction

// Unpack Half-Words
function automatic [XLEN-1:0] unpackh(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] result;
    begin
        result = 0;
        for (i = 0; i < XLEN/16; i = i + 1) begin
            result[16*i +: 16] = {16{data[i]}};
        end
        unpackh = result;
    end
endfunction

// Pack Words
function automatic [XLEN-1:0] packw(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] result;
    begin
        result = 0;
        for (i = 0; i < XLEN/32; i = i + 1) begin
            result[i] = |data[32*i +: 32];
        end
        packw = result;
    end
endfunction

// Unpack Words
function automatic [XLEN-1:0] unpackw(input [XLEN-1:0] data);
    integer i;
    reg [XLEN-1:0] result;
    begin
        result = 0;
        for (i = 0; i < XLEN/32; i = i + 1) begin
            result[32*i +: 32] = {32{data[i]}};
        end
        unpackw = result;
    end
endfunction

// XPERM4: Crossbar Permutation for 4-bit elements
function automatic [XLEN-1:0] xperm4(input [XLEN-1:0] data_a, input [XLEN-1:0] data_b);
    integer i;
    reg [XLEN-1:0] temp_result;
    begin
        temp_result = {XLEN{1'b0}};
        for (i = 0; i < XLEN/4; i = i + 1) begin
            // Extract 4-bit index
            logic [3:0] index;
            index = data_b[4*i +:4];
            
            if (index < (XLEN/4)) begin
                temp_result[4*i +:4] = data_a[4*index +:4];
            end else begin
                temp_result[4*i +:4] = 4'b0000;
            end
        end
        xperm4 = temp_result;
    end
endfunction

// XPERM8: Crossbar Permutation for 8-bit elements
function automatic [XLEN-1:0] xperm8(input [XLEN-1:0] data_a, input [XLEN-1:0] data_b);
    integer i;
    reg [XLEN-1:0] temp_result;
    begin
        temp_result = {XLEN{1'b0}};
        for (i = 0; i < XLEN/8; i = i + 1) begin
            // Extract 8-bit index
            logic [7:0] index;
            index = data_b[8*i +:8];
            
            if (index < (XLEN/8)) begin
                temp_result[8*i +:8] = data_a[8*index +:8];
            end else begin
                temp_result[8*i +:8] = 8'b00000000;
            end
        end
        xperm8 = temp_result;
    end
endfunction

// XPERM16: Crossbar Permutation for 16-bit elements
function automatic [XLEN-1:0] xperm16(input [XLEN-1:0] data_a, input [XLEN-1:0] data_b);
    integer i;
    reg [XLEN-1:0] temp_result;
    begin
        temp_result = {XLEN{1'b0}};
        for (i = 0; i < XLEN/16; i = i + 1) begin
            // Extract 16-bit index
            logic [15:0] index;
            index = data_b[16*i +:16];
            
            if (index < (XLEN/16)) begin
                temp_result[16*i +:16] = data_a[16*index +:16];
            end else begin
                temp_result[16*i +:16] = 16'b0000000000000000;
            end
        end
        xperm16 = temp_result;
    end
endfunction

// XPERM32: Crossbar Permutation for 32-bit elements
function automatic [XLEN-1:0] xperm32(input [XLEN-1:0] data_a, input [XLEN-1:0] data_b);
    integer i;
    reg [XLEN-1:0] temp_result;
    begin
        temp_result = {XLEN{1'b0}};
        for (i = 0; i < XLEN/32; i = i + 1) begin
            // Extract 32-bit index
            logic [31:0] index;
            index = data_b[32*i +:32];
            
            if (index < (XLEN/32)) begin
                temp_result[32*i +:32] = data_a[32*index +:32];
            end else begin
                temp_result[32*i +:32] = 32'b00000000000000000000000000000000;
            end
        end
        xperm32 = temp_result;
    end
endfunction

always_comb begin
    result = {XLEN{1'b0}};

    case (control)
        `BMU_CPOP:      result = $countones(operand_a);                // Count Population (Set Bits)
        `BMU_ANDN:      result = operand_a & ~operand_b;               // AND with NOT
        `BMU_ORN:       result = operand_a | ~operand_b;               // OR with NOT
        `BMU_XNOR:      result = ~(operand_a ^ operand_b);             // XOR with NOT
        `BMU_SLO:       result = operand_a | (~operand_a & (operand_a + 1)); // Set Lowest-order Zero
        `BMU_SRO:       result = operand_a & (~operand_a + 1);         // Set Highest-order One
        `BMU_ROL:       result = (operand_a << operand_b[SHIFT_BITS-1:0]) | (operand_a >> (XLEN - operand_b[SHIFT_BITS-1:0])); // Rotate Left
        `BMU_ROR:       result = (operand_a >> operand_b[SHIFT_BITS-1:0]) | (operand_a << (XLEN - operand_b[SHIFT_BITS-1:0])); // Rotate Right
        `BMU_REV8:      result = rev8(operand_a);                      // 8-bit Reversal
        `BMU_REV16:     result = rev16(operand_a);                     // 16-bit Reversal
        `BMU_REV32:     result = rev32(operand_a);                     // 32-bit Reversal
        `BMU_PACKB:     result = packb(operand_a);                     // Pack Bytes
        `BMU_PACKH:     result = packh(operand_a);                     // Pack Half-Words
        `BMU_PACKW:     result = packw(operand_a);                     // Pack Words
        `BMU_UNPACKB:   result = unpackb(operand_a);                   // Unpack Bytes
        `BMU_UNPACKH:   result = unpackh(operand_a);                   // Unpack Half-Words
        `BMU_UNPACKW:   result = unpackw(operand_a);                   // Unpack Words
        `BMU_SHFL:      result = shuffle(operand_a);                   // Shuffle
        `BMU_UNSHFL:    result = unshuffle(operand_a);                 // Unshuffle
        `BMU_BDEP:      result = bdep(operand_a, operand_b);           // Bit Deposit: Deposits bits from src into dest according to mask
        `BMU_BCOMP:     result = bcomp(operand_a, operand_b);          // Bit Compress: Compresses bits from data according to mask
        `BMU_BSET:      result = operand_a | (1 << operand_b[4:0]);    // Bit Set: Sets a specific bit
        `BMU_BCLR:      result = operand_a & ~(1 << operand_b[4:0]);   // Bit Clear: Clears a specific bit
        `BMU_BINV:      result = operand_a ^ (1 << operand_b[4:0]);    // Bit Invert: Inverts a specific bit
        `BMU_BEXT:      result = (operand_a >> operand_b[4:0]) & ((1 << operand_b[9:5]) - 1); // Bit Extract: Extracts a contiguous set of bits from a source word
        `BMU_ZEXTH32:   result = {operand_a, 16'b0};                   // Zero-Extend Halfword 32
        `BMU_ZEXTH64:   result = {operand_a, 32'b0};                   // Zero-Extend Halfword 64
        `BMU_ADD_UW:    result = operand_a + operand_b;                // Add Unsigned Word
        `BMU_SH1ADD_UW: result = (operand_a << 1) + operand_b;         // Shift-Left 1 and Add Unsigned Word
        `BMU_SH2ADD_UW: result = (operand_a << 2) + operand_b;         // Shift-Left 2 and Add Unsigned Word
        `BMU_SH3ADD_UW: result = (operand_a << 3) + operand_b;         // Shift-Left 3 and Add Unsigned Word
        `BMU_MAX:       result = (operand_a_signed > operand_b_signed) ? operand_a : operand_b; // Max: Compare two operands and select the maximum
        `BMU_MAXU:      result = (operand_a > operand_b) ? operand_a : operand_b;               // Max Unsigned
        `BMU_MIN:       result = (operand_a_signed < operand_b_signed) ? operand_a : operand_b; // Min: Compare two operands and select the minimum
        `BMU_MINU:      result = (operand_a < operand_b) ? operand_a : operand_b;               // Min Unsigned
        `BMU_SH1ADD:    result = (operand_a_signed << 1) + operand_b_signed;  // Shift-Left 1 and Add
        `BMU_SH2ADD:    result = (operand_a_signed << 2) + operand_b_signed;  // Shift-Left 2 and Add
        `BMU_SH3ADD:    result = (operand_a_signed << 3) + operand_b_signed;  // Shift-Left 3 and Add
        `BMU_XPERM4:    result = xperm4(operand_a, operand_b);
        `BMU_XPERM8:    result = xperm8(operand_a, operand_b);
        `BMU_XPERM16:   result = xperm16(operand_a, operand_b);
        `BMU_XPERM32:   result = xperm32(operand_a, operand_b);
        `BMU_SEXTB:     result = {{(XLEN-8){operand_a[7]}}, operand_a[7:0]};
        `BMU_SEXTH:     result = {{(XLEN-16){operand_a[15]}}, operand_a[15:0]};
        `BMU_GREV: begin //Generalized Bit REversal Immediate
            logic [XLEN-1:0] temp_bits;
            integer i;
            integer count;

            temp_bits = 0;
            count = 0;

            // First Pass: Collect bits to reverse
            for (i = 0; i < XLEN; i = i + 1) begin
                if (operand_b[i]) begin
                    temp_bits[count] = operand_a[i];
                    count = count + 1;
                end
            end

            // Second Pass: Assign reversed bits back
            count = count - 1; // Adjust counter for reverse indexing
            for (i = 0; i < XLEN; i = i + 1) begin
                if (operand_b[i]) begin
                    result[i] = temp_bits[count];
                    count = count - 1;
                end else begin
                    result[i] = operand_a[i];
                end
            end
        end
        `BMU_SLLIUW: begin // Shift left unsigned word (Immediate)
            // Extract the least-significant word (32 bits)
            logic [31:0] lsw;
            logic [XLEN-1:0] zero_extended;
            
            // Zero-extend LSW to XLEN bits
            lsw = operand_a[31:0];
            if (XLEN > 32) begin
                zero_extended = { {(XLEN-32){1'b0}}, lsw };
            end else begin
                zero_extended = lsw;
            end
            
            // Shift left by the immediate (operand_b[4:0])
            result = zero_extended << operand_b[4:0];
        end
        `BMU_ORCB: begin
            for (integer i = 0; i < XLEN/8; i = i + 1) begin
                // Perform a reduction OR on each byte
                if (|operand_a[8*i +:8]) begin
                    result[8*i +:8] = 8'hFF; // Set byte to all ones
                end else begin
                    result[8*i +:8] = 8'h00; // Set byte to all zeros
                end
            end
        end
        `BMU_CLZ: begin  // Count leading zeros
            temp_operand = operand_a;
            result = 0;

            if (temp_operand[(XLEN-1):(XLEN/2)] == 0) begin
                result = result + XLEN/2;
                temp_operand = temp_operand[(XLEN/2-1):0];
            end
            if (temp_operand[(XLEN/2-1):(XLEN/4)] == 0) begin
                result = result + XLEN/4;
                temp_operand = temp_operand[(XLEN/4-1):0];
            end
            if (temp_operand[(XLEN/4-1):(XLEN/8)] == 0) begin
                result = result + XLEN/8;
                temp_operand = temp_operand[(XLEN/8-1):0];
            end
            if (temp_operand[(XLEN/8-1):(XLEN/16)] == 0) begin
                result = result + XLEN/16;
                temp_operand = temp_operand[(XLEN/16-1):0];
            end
            if (temp_operand[(XLEN/16-1):(XLEN/32)] == 0) begin
                result = result + XLEN/32;
                temp_operand = temp_operand[(XLEN/32-1):0];
            end
            if (XLEN >= 64) begin
                if (temp_operand[(XLEN/32-1):(XLEN/64)] == 0) begin
                    result = result + XLEN/64;
                    temp_operand = temp_operand[(XLEN/64-1):0];
                end
            end
            if (temp_operand[1] == 0) begin
                result = result + 1;
            end
            if (temp_operand[0] == 0) begin
                result = result + 1;
            end
        end
        `BMU_CTZ: begin  // Count trailing zeros
            temp_operand = operand_a;
            result = 0;

            if (temp_operand[(XLEN/2)-1:0] == 0) begin
                result = result + XLEN/2;
                temp_operand = temp_operand[(XLEN-1):(XLEN/2)];
            end
            if (temp_operand[(XLEN/4)-1:0] == 0) begin
                result = result + XLEN/4;
                temp_operand = temp_operand[(XLEN/2)-1:(XLEN/4)];
            end
            if (temp_operand[(XLEN/8)-1:0] == 0) begin
                result = result + XLEN/8;
                temp_operand = temp_operand[(XLEN/4)-1:(XLEN/8)];
            end
            if (temp_operand[(XLEN/16)-1:0] == 0) begin
                result = result + XLEN/16;
                temp_operand = temp_operand[(XLEN/8)-1:(XLEN/16)];
            end
            if (XLEN >= 64) begin
                if (temp_operand[(XLEN/32)-1:0] == 0) begin
                    result = result + XLEN/32;
                    temp_operand = temp_operand[(XLEN/16)-1:(XLEN/32)];
                end
            end
            if (temp_operand[1:0] == 0) begin
                result = result + 2;
                temp_operand = temp_operand[1:0];
            end
            if (temp_operand[0] == 0) begin
                result = result + 1;
            end
        end
        `BMU_BSHIFT: begin
            // Bitwise Shift: Shift bits left or right based on operand_b[5]
            if (operand_b[5]) begin
                result = operand_a << operand_b[4:0]; // Shift Left
            end else begin
                result = operand_a >> operand_b[4:0]; // Shift Right
            end
        end
        `BMU_BUNSHIFT: begin
            // Bitwise Unshift: Complementary to BSHIFT
            if (operand_b[5]) begin
                result = operand_a >> operand_b[4:0]; // Shift Right
            end else begin
                result = operand_a << operand_b[4:0]; // Shift Left
            end
        end
        `BMU_CLMUL: begin
            // Carry-less Multiplication
            // Example implementation using polynomial multiplication
            // Note: This is a simplified version and may need optimization
            logic [XLEN-1:0] mul_result;
            mul_result = 0;
            for (integer i = 0; i < XLEN; i++) begin
                if (operand_b[i])
                    mul_result ^= operand_a << i;
            end
            result = mul_result;
        end
        `BMU_CLMULH: begin
            // Carry-less Multiplication High Part
            logic [2*XLEN-1:0] mul_result;
            mul_result = 0;
            for (integer i = 0; i < XLEN; i++) begin
                if (operand_b[i])
                    mul_result ^= operand_a << i;
            end
            result = mul_result[2*XLEN-1:XLEN];
        end
        `BMU_CLMULR: begin
            // Carry-less Multiplication Reverse
            logic [XLEN-1:0] reversed_a, reversed_b, mul_result;
            // Reverse the bits of operand_a and operand_b
            for (integer i = 0; i < XLEN; i++) begin
                reversed_a[i] = operand_a[XLEN-1-i];
                reversed_b[i] = operand_b[XLEN-1-i];
            end
            mul_result = 0;
            for (integer i = 0; i < XLEN; i++) begin
                if (reversed_b[i])
                    mul_result ^= reversed_a << i;
            end
            // Reverse the result back
            result = 0;
            for (integer i = 0; i < XLEN; i++) begin
                result[i] = mul_result[XLEN-1-i];
            end
        end
        default:   result = {XLEN{1'b0}};
    endcase
end

endmodule
