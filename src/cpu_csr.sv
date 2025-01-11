`default_nettype none

///////////////////////////////////////////////////////////////////////////////
// CSR File Module with Edge-Triggered NMI Handling
///////////////////////////////////////////////////////////////////////////////
/**
 * @module cpu_csr
 * @brief Implements the Control and Status Registers (CSRs) for handling
 * privileged operations, including support for edge-triggered Non-Maskable Interrupts (NMIs).
 *
 * This module manages essential CSRs required for exception and interrupt
 * handling, such as `mstatus`, `mie`, `mip`, `mtvec`, `mepc`, and `mcause`.
 * It supports parameterized Non-Maskable Interrupts (NMIs) by integrating them
 * into the `mip` register based on the `NMI_COUNT` parameter.
 *
 * Features:
 * - Parameterized support for NMIs via `NMI_COUNT`.
 * - Parameterized support for standard IRQs via `IRQ_COUNT`.
 * - Handles CSR reads and writes with appropriate masking.
 * - Detects rising edges on NMI inputs to handle edge-triggered NMIs.
 * - Updates `mip` based on `irq` and edge-detected `nmi` inputs.
 * - `mip` is read-only and cannot be modified via CSR writes.
 * - Supports CSR instructions by handling operations like CSRRW, CSRRS, etc.
 *
 * @param XLEN            Data width (default: 32)
 * @param NMI_COUNT       Number of Non-Maskable Interrupts (default: 4)
 * @param IRQ_COUNT       Number of standard Interrupt Requests (default: 4)
 * @param MTVEC_RESET_VAL Reset value for `mtvec` register (default: 0)
 * @param MHARTID_VAL     Reset value for `mheartid` register (default: 0)
 *
 * Developers should ensure that `XLEN` is sufficiently large to accommodate
 * both standard interrupts and NMIs. Additionally, proper prioritization and
 * handling mechanisms should be implemented to manage NMIs effectively.
 */
 
// CSR Address Definitions
//*****************************
// Machine-Level CSRs (M-mode)
//*****************************
// Vendor, Architecture, and Implementation IDs
`define CSR_MVENDORID    12'hF11 // Vendor ID
`define CSR_MARCHID      12'hF12 // Architecture ID
// `define CSR_MIMPID       12'hF13 // Implementation ID
`define CSR_MHARTID      12'hF14 // Hardware Thread ID

// Status and Control Registers
`define CSR_MSTATUS      12'h300 // Machine Status Register
`define CSR_MISA         12'h301 // ISA and Extensions Register
// `define CSR_MEDELEG      12'h302 // Machine Exception Delegation Register
// `define CSR_MIDELEG      12'h303 // Machine Interrupt Delegation Register
`define CSR_MIE          12'h304 // Machine Interrupt Enable Register
`define CSR_MTVEC        12'h305 // Machine Trap-Vector Base Address Register
// `define CSR_MCOUNTEREN  =12'h306 // Machine Counter Enable Register

// Scratch and Exception Handling
`define CSR_MSCRATCH     12'h340 // Machine Scratch Register
`define CSR_MEPC         12'h341 // Machine Exception Program Counter
`define CSR_MCAUSE       12'h342 // Machine Trap Cause
`define CSR_MTVAL        12'h343 // Machine Trap Value
`define CSR_MIP          12'h344 // Machine Interrupt Pending Register

// Performance Counters
`define CSR_MCYCLE       12'hB00 // Machine Cycle Counter
// `define CSR_MINSTRET     12'hB02 // Machine Instructions Retired Counter
`define CSR_MCYCLEH      12'hB80 // Machine Cycle Counter High
// `define CSR_MINSTRETH    12'hB82 // Machine Instructions Retired Counter High
// `define CSR_MCOUNTINHIBIT  12'h320 // Machine Counter/Timer Inhibit Register

//*****************************
// Supervisor-Level CSRs (S-mode)
//*****************************
// Status and Control Registers
// `define CSR_SSTATUS      12'h100 // Supervisor Status Register
// `define CSR_SDELEG       12'h102 // Supervisor Exception Delegation Register
// `define CSR_SIDELEG      12'h103 // Supervisor Interrupt Delegation Register
// `define CSR_SIE          12'h104 // Supervisor Interrupt Enable Register
// `define CSR_STVEC        12'h105 // Supervisor Trap-Vector Base Address Register
// `define CSR_SCOUNTEREN   12'h106 // Supervisor Counter Enable Register

// Scratch and Exception Handling
// `define CSR_SSCRATCH     12'h140 // Supervisor Scratch Register
// `define CSR_SEPC         12'h141 // Supervisor Exception Program Counter
// `define CSR_SCAUSE       12'h142 // Supervisor Trap Cause
// `define CSR_STVAL        12'h143 // Supervisor Trap Value
// `define CSR_SIP          12'h144 // Supervisor Interrupt Pending Register

// Address Translation and Protection
// `define CSR_SATP         12'h180 // Supervisor Address Translation and Protection
// `define CSR_SFENCE_VMA   12'h500 // Supervisor Virtual Memory Management Fence
// `define CSR_SPTBR        12'h180 // Supervisor Page Table Base Register (Alias of SATP)

//*****************************
// User-Level CSRs (U-mode)
//*****************************
// Status and Control Registers
// `define CSR_USTATUS      12'h000 // User Status Register
// `define CSR_UIE          12'h004 // User Interrupt Enable Register
// `define CSR_UTVEC        12'h005 // User Trap-Vector Base Address Register

// Scratch and Exception Handling
// `define CSR_USCRATCH     12'h040 // User Scratch Register
// `define CSR_UEPC         12'h041 // User Exception Program Counter
// `define CSR_UCAUSE       12'h042 // User Trap Cause
// `define CSR_UTVAL        12'h043 // User Trap Value
// `define CSR_UIP          12'h044 // User Interrupt Pending Register

//*****************************
// Floating-Point CSRs (F/D Extensions)
//*****************************
// `define CSR_FFLAGS       12'h001 // Floating-Point Flags
// `define CSR_FRM          12'h002 // Floating-Point Rounding Mode
// `define CSR_FCSR         12'h003 // Floating-Point Control and Status Register

//*****************************
// Custom and Implementation-Defined CSRs
//*****************************
// Reserved for custom CSRs: 0xC00 to 0xCFF
// Example custom CSR definitions:
// `define CSR_CUSTOM_0   12'hC00;
// ...
// `define CSR_CUSTOM_FF  12'hCFF;

// CSR Operation Controls
`define CSR_RW    3'b000 // 0 Atomic Read/Write CSR
`define CSR_RS    3'b001 // 1 Atomic Read and Set CSR
`define CSR_RC    3'b010 // 2 Atomic Read and Clear CSR
`define CSR_RWI   3'b011 // 3 Immediate Read/Write CSR
`define CSR_RSI   3'b100 // 4 Immediate Read and Set CSR
`define CSR_RCI   3'b101 // 5 Immediate Read and Clear CSR

`ifdef SUPPORT_M
`define HAS_M 1
`else
`define HAS_M 0
`endif

// Unsupported extentions 
`define HAS_A 0 
`define HAS_B 0
`define HAS_C 0 
`define HAS_D 0 
`define HAS_E 0 
`define HAS_F 0 
`define HAS_G 0 
`define HAS_H 0 
`define HAS_I 0 
`define HAS_N 0
`define HAS_P 0
`define HAS_Q 0
`define HAS_S 0
`define HAS_U 0
`define HAS_V 0
`define HAS_X 0

module cpu_csr #(
    parameter XLEN = 32,                                // Data width: 32 bits
    parameter NMI_COUNT = 4,                            // Number of NMIs (must satisfy XLEN > IRQ_COUNT + NMI_COUNT)
    parameter IRQ_COUNT = 4,                            // Number of standard IRQs (must satisfy XLEN > IRQ_COUNT + NMI_COUNT)
    parameter MTVEC_RESET_VAL = {XLEN{1'b0}},           // Reset value for mtvec_reg (default: 0)
    parameter MHARTID_VAL = {XLEN{1'b0}}                // Reset value for mhartid_reg (default: 0)
) (
    input  logic                    clk,                // Shared Clock
    input  logic                    reset,              // Shared Reset

    // CSR Register Interface
    input  logic [11:0]             reg_addr,           // CSR address for Register Interface
    input  logic                    reg_write_en,       // Write enable for Register Interface
    input  logic [XLEN-1:0]         reg_wdata,          // Write data for Register Interface
    output logic [XLEN-1:0]         reg_rdata,          // Read data from Register Interface

    // CSR Operation Interface
    input  logic                    op_valid,           // Operation valid
    output logic                    op_ready,           // Operation ready
    input  logic [2:0]              op_control,         // CSR operation control signals
    input  logic [11:0]             op_addr,            // CSR address for Operation Interface
    input  logic [XLEN-1:0]         op_operand,         // Operand for CSR operations
    input  logic [4:0]              op_imm,             // Immediate for CSR operations
    output logic [XLEN-1:0]         op_rdata,           // Read data from Operation Interface
    output logic                    op_done,            // Operation done signal

    // Exposed Registers
    output logic [XLEN-1:0]         mtvec,              // 
    output logic [XLEN-1:0]         mepc,               // 
    output logic [XLEN-1:0]         mcause,             // 

    // Output Signals
    output logic                    interrupt_pending,  // 

    // Interrupt Request Lines
    input  logic [IRQ_COUNT-1:0]    irq,                // Standard IRQs
    input  logic [NMI_COUNT-1:0]    nmi                 // Non-Maskable IRQs (Edge-Triggered)
);  

    // -------------------------------------------------------------------------
    // Parameter Validation
    // -------------------------------------------------------------------------
    initial begin
        if (XLEN <= (IRQ_COUNT + NMI_COUNT)) begin
            $error("Parameter Error: XLEN (%0d) must be greater than IRQ_COUNT (%0d) + NMI_COUNT (%0d)", 
                    XLEN, IRQ_COUNT, NMI_COUNT);
            $finish;
        end
    end

    // -------------------------------------------------------------------------
    // Define Bit Positions for NMIs within mip
    // -------------------------------------------------------------------------
    localparam NMI_BITS_WIDTH  = NMI_COUNT;
    localparam IRQ_BITS_WIDTH  = IRQ_COUNT;
    localparam IRQ_BITS_START  = 0;
    localparam NMI_BITS_START  = IRQ_BITS_WIDTH; // Starting bit for NMIs

    // -------------------------------------------------------------------------
    // Define masks for writable bits
    // -------------------------------------------------------------------------
    // 1) MIP_WRITE_MASK covers only NMI bits (write-1-to-clear)
    localparam MIP_WRITE_MASK     = ((1 << NMI_BITS_WIDTH) - 1) << NMI_BITS_START;
    // 2) MSTATUS_WRITE_MASK allows writing specific bits (e.g., MIE, etc.)
    localparam MSTATUS_WRITE_MASK = (1 << 3) | (1 << 1) | (1 << 0); 

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    logic [(XLEN*2)-1:0] cycle_counter;
    logic [XLEN-1:0]     marchid_reg;
    logic [XLEN-1:0]     mhartid_reg;
    logic [XLEN-1:0]     misa_reg;
    logic [XLEN-1:0]     mstatus_reg;
    logic [XLEN-1:0]     mie_reg;
    logic [XLEN-1:0]     mip_reg;
    logic [XLEN-1:0]     mtvec_reg;
    logic [XLEN-1:0]     mtval_reg;
    logic [XLEN-1:0]     mepc_reg;
    logic [XLEN-1:0]     mcause_reg;
    logic [XLEN-1:0]     mscratch_reg;

    // -------------------------------------------------------------------------
    // Edge Detection for NMIs
    // -------------------------------------------------------------------------
    logic [NMI_COUNT-1:0] nmi_prev;
    logic [NMI_COUNT-1:0] nmi_edge;

    // -------------------------------------------------------------------------
    // Generate Edge Detection for each NMI signal
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NMI_COUNT; i = i + 1) begin : nmi_edge_detect
            always_ff @(posedge clk or posedge reset) begin
                if (reset) begin
                    nmi_prev[i] <= 1'b0;
                    nmi_edge[i] <= 1'b0;
                end else begin
                    nmi_edge[i] <= nmi[i] & ~nmi_prev[i];
                    nmi_prev[i] <= nmi[i];
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Assign Exposed Outputs
    // -------------------------------------------------------------------------
    assign mtvec  = mtvec_reg;
    assign mepc   = mepc_reg;
    assign mcause = mcause_reg;

    // -------------------------------------------------------------------------
    // Interrupt pending logic
    // -------------------------------------------------------------------------
    assign interrupt_pending = ((mip_reg & mie_reg) != 0) && mstatus_reg[3];

    logic op_busy;

    // -------------------------------------------------------------------------
    // Cycle Counter Increment
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_counter <= {2*XLEN{1'b0}};
        end else begin
            cycle_counter <= cycle_counter + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Combine Standard IRQs and Edge-Detected NMIs into mip
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            mip_reg <= {XLEN{1'b0}};
        end else begin
            mip_reg[IRQ_BITS_START +: IRQ_BITS_WIDTH] <= irq;
            mip_reg[NMI_BITS_START +: NMI_BITS_WIDTH] <= mip_reg[NMI_BITS_START +: NMI_BITS_WIDTH] | nmi_edge;
        end
    end

    // -------------------------------------------------------------------------
    // Read Logic
    // -------------------------------------------------------------------------
    // Register Interface Read
    always_comb begin
        case (reg_addr)
            `CSR_MVENDORID : reg_rdata = (XLEN == 32) ? 32'h4A5A5256 : 64'h000000004A5A5256;
            `CSR_MARCHID   : reg_rdata = marchid_reg;
            `CSR_MHARTID   : reg_rdata = mhartid_reg;
            `CSR_MISA      : reg_rdata = misa_reg;
            `CSR_MSTATUS   : reg_rdata = mstatus_reg;
            `CSR_MIE       : reg_rdata = mie_reg;
            `CSR_MTVEC     : reg_rdata = mtvec_reg;
            `CSR_MTVAL     : reg_rdata = mtval_reg;
            `CSR_MEPC      : reg_rdata = mepc_reg;
            `CSR_MCAUSE    : reg_rdata = mcause_reg;
            `CSR_MIP       : reg_rdata = mip_reg;
            `CSR_MCYCLE    : reg_rdata = cycle_counter[XLEN-1:0];
            `CSR_MCYCLEH   : reg_rdata = cycle_counter[(XLEN*2)-1:XLEN];
            `CSR_MSCRATCH  : reg_rdata = mscratch_reg;
            default        : reg_rdata = {XLEN{1'b0}};
        endcase
    end

    // Operation Interface Read
    always_comb begin
        if (op_ready && op_valid && ~op_busy && ~op_done) begin
            // Grab the current value before any operation request
            case (op_addr)
                `CSR_MSTATUS  : op_rdata = mstatus_reg;
                `CSR_MARCHID  : op_rdata = marchid_reg;
                `CSR_MHARTID  : op_rdata = mhartid_reg;
                `CSR_MISA     : op_rdata = misa_reg;
                `CSR_MIE      : op_rdata = mie_reg;
                `CSR_MTVEC    : op_rdata = mtvec_reg;
                `CSR_MTVAL    : reg_rdata = mtval_reg;
                `CSR_MEPC     : op_rdata = mepc_reg;
                `CSR_MCAUSE   : op_rdata = mcause_reg;
                `CSR_MCYCLE   : op_rdata = cycle_counter[XLEN-1:0];
                `CSR_MCYCLEH  : op_rdata = cycle_counter[(XLEN*2)-1:XLEN];
                `CSR_MSCRATCH : op_rdata = mscratch_reg;
                default       : op_rdata = {XLEN{1'b0}};
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Write Logic with Priority to Operation Interface
    // -------------------------------------------------------------------------
    // Handle Operation Writes
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize all registers
            mie_reg     <= {XLEN{1'b0}};
            mip_reg     <= {XLEN{1'b0}};
            mtvec_reg   <= MTVEC_RESET_VAL;
            mtval_reg   <= {XLEN{1'b0}};
            mepc_reg    <= {XLEN{1'b0}};
            mcause_reg  <= {XLEN{1'b0}};
            mstatus_reg <= { {(XLEN-4){1'b0}}, 4'hB };
            mhartid_reg <= MHARTID_VAL;
            marchid_reg <= {{(XLEN-32){1'b0}}, 32'h0} |
                           ((XLEN == 32) ? 2'b00 : 
                           (XLEN == 64) ? 2'b01 : 
                           (XLEN == 128) ? 2'b10 : 2'b11) |
                           ((`HAS_M) ? 3'b100 : 3'b000) |
                           ((`HAS_B) ? 4'b1000 : 4'b0000);
            cycle_counter <= {2*XLEN{1'b0}};

            misa_reg <= {(XLEN){1'b0}} |
                        // Base ISA width
                        ((XLEN == 32)  ? 32'h4000_0000 : 
                         (XLEN == 64)  ? 64'h4000_0000_0000_0000 : 
                         (XLEN == 128) ? 128'hC0000000000000000000000000000000 : 2'b00) |
                        // Extensions
                        ((`HAS_A) ? (1 << 0) : 0) |  // Atomic
                        ((`HAS_B) ? (1 << 1) : 0) |  // Bit-Manipulation
                        ((`HAS_C) ? (1 << 2) : 0) |  // Compressed
                        ((`HAS_D) ? (1 << 3) : 0) |  // Double-precision Floating-Point
                        ((`HAS_E) ? (1 << 4) : 0) |  // Reduced ("Embedded")
                        ((`HAS_F) ? (1 << 5) : 0) |  // Single-precision Floating-Point
                        ((`HAS_G) ? (1 << 6) : 0) |  // General
                        ((`HAS_H) ? (1 << 7) : 0) |  // Hypervisor
                        ((`HAS_I) ? (1 << 8) : 0) |  // Base Integer ISA
                        ((`HAS_M) ? (1 << 12) : 0) | // Integer Multiply/Divide
                        ((`HAS_N) ? (1 << 13) : 0) | // User-level interrupts
                        ((`HAS_P) ? (1 << 15) : 0) | // Packed-SIMD
                        ((`HAS_Q) ? (1 << 16) : 0) | // Quad-precision Floating-Point
                        ((`HAS_S) ? (1 << 18) : 0) | // Supervisor mode
                        ((`HAS_U) ? (1 << 20) : 0) | // User mode
                        ((`HAS_V) ? (1 << 21) : 0) | // Vector
                        ((`HAS_X) ? (1 << 23) : 0);  // Non-standard extensions

            // ready for operation request
            op_ready = 1'b1;
            op_busy  = 1'b0;
            op_done  = 1'b0;
        end else begin
            // Handle Operation Interface Writes
            if (op_valid && op_busy) begin
                // Let the write settle
                op_busy <= 1'b0;
                op_done <= 1'b1;
            end else if (op_valid && ~op_busy) begin
                op_busy <= 1'b1;
                
                case (op_control)
                    `CSR_RW: begin // Atomic Read/Write CSR
                        `ifdef LOG_CSR $display("[CSR Module]        Time %0t: Operation Interface: CSR_RW: %00h, %00h", $time, op_addr, op_operand); `endif
                        case (op_addr)
                            `CSR_MSTATUS : mstatus_reg  <= (op_operand & MSTATUS_WRITE_MASK) | (mstatus_reg & ~MSTATUS_WRITE_MASK);
                            `CSR_MIE     : mie_reg      <= op_operand;
                            `CSR_MTVEC   : mtvec_reg    <= op_operand;
                            `CSR_MTVAL   : mtval_reg    <= op_operand;
                            `CSR_MEPC    : mepc_reg     <= op_operand;
                            `CSR_MCAUSE  : mcause_reg   <= op_operand;
                            `CSR_MSCRATCH: mscratch_reg <= op_operand;
                            `CSR_MCYCLE  : cycle_counter[XLEN-1:0] <= op_operand;
                            `CSR_MCYCLEH : cycle_counter[(XLEN*2)-1:XLEN] <= op_operand;
                            default      : ; // No action for other addresses
                        endcase
                    end
                    `CSR_RS: begin // Atomic Read and Set CSR
                        if (op_control != 0) begin
                            `ifdef LOG_CSR $display("[CSR Module]        Time %0t: Operation Interface: CSR_RS: %00h, %00h", $time, op_addr, op_operand); `endif
                            case (op_addr)
                                `CSR_MSTATUS : mstatus_reg  <= (mstatus_reg | (op_operand & MSTATUS_WRITE_MASK)) | (mstatus_reg & ~MSTATUS_WRITE_MASK);
                                `CSR_MIE     : mie_reg      <= mie_reg | op_operand;
                                `CSR_MTVEC   : mtvec_reg    <= mtvec_reg | op_operand;
                                `CSR_MTVAL   : mtval_reg    <= mtval_reg | op_operand;
                                `CSR_MEPC    : mepc_reg     <= mepc_reg | op_operand;
                                `CSR_MCAUSE  : mcause_reg   <= mcause_reg | op_operand;
                                `CSR_MSCRATCH: mscratch_reg <= mscratch_reg | op_operand;
                                `CSR_MCYCLE  : cycle_counter[XLEN-1:0] <= cycle_counter[XLEN-1:0] | op_operand;
                                `CSR_MCYCLEH : cycle_counter[(XLEN*2)-1:XLEN] <= cycle_counter[(XLEN*2)-1:XLEN] | op_operand;
                                default      : ; // No action for other addresses
                            endcase
                        end
                    end
                    `CSR_RC: begin // Atomic Read and Clear CSR
                        if (op_control != 0) begin
                            case (op_addr)
                                `CSR_MSTATUS : mstatus_reg  <= (mstatus_reg & ~op_operand) | (mstatus_reg & ~MSTATUS_WRITE_MASK);
                                `CSR_MIE     : mie_reg      <= mie_reg & ~op_operand;
                                `CSR_MTVEC   : mtvec_reg    <= mtvec_reg & ~op_operand;
                                `CSR_MTVAL   : mtval_reg    <= mtval_reg & ~op_operand;
                                `CSR_MEPC    : mepc_reg     <= mepc_reg & ~op_operand;
                                `CSR_MCAUSE  : mcause_reg   <= mcause_reg & ~op_operand;
                                `CSR_MSCRATCH: mscratch_reg <= mscratch_reg & ~op_operand;
                                `CSR_MCYCLE  : cycle_counter[XLEN-1:0] <= cycle_counter[XLEN-1:0] & ~op_operand;
                                `CSR_MCYCLEH : cycle_counter[(XLEN*2)-1:XLEN] <= cycle_counter[(XLEN*2)-1:XLEN] & ~op_operand;
                                default      : ; // No action for other addresses
                            endcase
                        end
                    end
                    `CSR_RWI: begin // Immediate Read/Write CSR
                        logic [XLEN-1:0] imm_extended;
                        imm_extended = { {(XLEN-5){1'b0}}, op_imm };
                        case (op_addr)
                            `CSR_MSTATUS : mstatus_reg  <= (imm_extended & MSTATUS_WRITE_MASK) | (mstatus_reg & ~MSTATUS_WRITE_MASK);
                            `CSR_MIE     : mie_reg      <= imm_extended;
                            `CSR_MTVEC   : mtvec_reg    <= imm_extended;
                            `CSR_MTVAL   : mtval_reg    <= imm_extended;
                            `CSR_MEPC    : mepc_reg     <= imm_extended;
                            `CSR_MCAUSE  : mcause_reg   <= imm_extended;
                            `CSR_MSCRATCH: mscratch_reg <= imm_extended;
                            `CSR_MCYCLE  : cycle_counter[XLEN-1:0] <= imm_extended;
                            `CSR_MCYCLEH : cycle_counter[(XLEN*2)-1:XLEN] <= imm_extended;
                            default      : ; // No action for other addresses
                        endcase
                    end
                    `CSR_RSI: begin // Immediate Read and Set CSR
                        if (op_imm != 0) begin
                            logic [XLEN-1:0] imm_extended;
                            imm_extended = { {(XLEN-5){1'b0}}, op_imm };
                            case (op_addr)
                                `CSR_MSTATUS : mstatus_reg  <= (mstatus_reg | (imm_extended & MSTATUS_WRITE_MASK)) | (mstatus_reg & ~MSTATUS_WRITE_MASK);
                                `CSR_MIE     : mie_reg      <= mie_reg | imm_extended;
                                `CSR_MTVEC   : mtvec_reg    <= mtvec_reg | imm_extended;
                                `CSR_MTVAL   : mtval_reg    <= mtval_reg | imm_extended;
                                `CSR_MEPC    : mepc_reg     <= mepc_reg | imm_extended;
                                `CSR_MCAUSE  : mcause_reg   <= mcause_reg | imm_extended;
                                `CSR_MSCRATCH: mscratch_reg <= mscratch_reg | imm_extended;
                                `CSR_MCYCLE  : cycle_counter[XLEN-1:0] <= cycle_counter[XLEN-1:0] | imm_extended;
                                `CSR_MCYCLEH : cycle_counter[(XLEN*2)-1:XLEN] <= cycle_counter[(XLEN*2)-1:XLEN] | imm_extended;
                                default      : ; // No action for other addresses
                            endcase
                        end
                    end
                    `CSR_RCI: begin // Immediate Read and Clear CSR
                        if (op_imm != 0) begin
                            logic [XLEN-1:0] imm_extended;
                            imm_extended = { {(XLEN-5){1'b0}}, op_imm };
                            case (op_addr)
                                `CSR_MSTATUS : mstatus_reg  <= (mstatus_reg & ~imm_extended) | (mstatus_reg & ~MSTATUS_WRITE_MASK);
                                `CSR_MIE     : mie_reg      <= mie_reg & ~imm_extended;
                                `CSR_MTVEC   : mtvec_reg    <= mtvec_reg & ~imm_extended;
                                `CSR_MTVAL   : mtval_reg    <= mtval_reg & ~imm_extended;
                                `CSR_MEPC    : mepc_reg     <= mepc_reg & ~imm_extended;
                                `CSR_MCAUSE  : mcause_reg   <= mcause_reg & ~imm_extended;
                                `CSR_MSCRATCH: mscratch_reg <= mscratch_reg & ~imm_extended;
                                `CSR_MCYCLE  : cycle_counter[XLEN-1:0] <= cycle_counter[XLEN-1:0] & ~imm_extended;
                                `CSR_MCYCLEH : cycle_counter[(XLEN*2)-1:XLEN] <= cycle_counter[(XLEN*2)-1:XLEN] & ~imm_extended;
                                default      : ; // No action for other addresses
                            endcase
                        end
                    end
                    default: ; // No CSR operation
                endcase
            end
            
            if (!reg_write_en && !op_valid) begin
                // no register or operation request is on-going
                op_busy <= 1'b0;
                op_done <= 1'b0;
                op_ready <= 1'b1;
            end

            // Handle Register Interface Writes only if Operation Interface is not writing
            if (reg_write_en && !(op_valid && op_ready)) begin
                op_ready <= 1'b0;
                case (reg_addr)
                    `CSR_MSTATUS : begin
                        mstatus_reg <= (reg_wdata & MSTATUS_WRITE_MASK) | (mstatus_reg & ~MSTATUS_WRITE_MASK);
                        `ifdef LOG_CSR $display("[CSR Module] [Register Write] mstatus_reg updated to 0x%h", mstatus_reg); `endif
                    end
                    `CSR_MIP : begin
                        // "Write 1 to clear" only in NMI bits
                        logic [XLEN-1:0] nmi_clears;
                        nmi_clears = reg_wdata & MIP_WRITE_MASK;
                        // Clear the specified NMI bits
                        mip_reg[NMI_BITS_START +: NMI_BITS_WIDTH] <= mip_reg[NMI_BITS_START +: NMI_BITS_WIDTH] & ~nmi_clears[NMI_BITS_START +: NMI_BITS_WIDTH];
                        // IRQ bits remain unaffected
                        `ifdef LOG_CSR $display("[CSR Module]        [Register Write] mip_reg[NMI_BITS] updated to 0x%h", mip_reg[NMI_BITS_START +: NMI_BITS_WIDTH]); `endif
                    end
                    `CSR_MTVEC   : begin
                        mtvec_reg <= reg_wdata;
                        `ifdef LOG_CSR $display("[CSR Module]        [Register Write] mtvec_reg updated to 0x%h", reg_wdata); `endif
                    end
                    `CSR_MTVAL   : begin
                        mtval_reg <= reg_wdata;
                        `ifdef LOG_CSR $display("[CSR Module]        [Register Write] mtval_reg updated to 0x%h", reg_wdata); `endif
                    end
                    `CSR_MIE     : begin
                        mie_reg <= reg_wdata;
                        `ifdef LOG_CSR $display("[CSR Module]        [Register Write] mie_reg updated to 0x%h", reg_wdata); `endif
                    end
                    `CSR_MEPC    : begin
                        mepc_reg <= reg_wdata;
                        `ifdef LOG_CSR $display("[CSR Module]        [Register Write] mepc_reg updated to 0x%h", reg_wdata); `endif
                    end
                    `CSR_MCAUSE  : begin
                        mcause_reg <= reg_wdata;
                        `ifdef LOG_CSR $display("[CSR Module]        [Register Write] mcause_reg updated to 0x%h", reg_wdata); `endif
                    end
                    `CSR_MSCRATCH: begin
                        mscratch_reg <= reg_wdata;
                        `ifdef LOG_CSR $display("[CSR Module]        [Register Write] mscratch_reg updated to 0x%h", reg_wdata); `endif
                    end
                    default      : begin
                        `ifdef LOG_CSR $display("[CSR Module]        [Register Write] No action for CSR address 0x%h", reg_wdata); `endif
                    end
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Debugging: Display CSR states and NMI edges
    // -------------------------------------------------------------------------
    `ifdef LOG_CLOCKED
    always @(posedge clk) begin
        // Register Interface Read
        if (reg_write_en) begin
            $display("[CSR Module]        Time %0t: [Register Write] addr=0x%h, data=0x%h", 
                     $time, reg_addr, reg_wdata);
        end

        // Operation Interface Read/Write
        if (op_valid && op_ready) begin
            $display("[CSR Module]        Time %0t: [Operation] control=0x%h, addr=0x%h, operand=0x%h, imm=0x%h", 
                     $time, op_control, op_addr, op_operand, op_imm);
        end

        // Display current CSR states and NMI edges
        $display("[CSR Module]        Time %0t: mstatus=0x%08h, mie=0x%08h, mip=0x%08h, interrupt_pending=%b", 
                 $time, mstatus_reg, mie_reg, mip_reg, interrupt_pending);
        $display("[CSR Module]        Time %0t: nmi=%b, nmi_prev=%b, nmi_edge=%b",
                 $time, nmi, nmi_prev, nmi_edge);
    end
    `endif

endmodule
