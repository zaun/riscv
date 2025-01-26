///////////////////////////////////////////////////////////////////////////////////////////////////
// rv_cpu Module
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * @module rv_cpu
 * @brief A RISC-V RV32/64I CPU Core with Optional Extensions.
 *
 * The `rv_cpu` module implements a non-pipelined RISC-V CPU core supporting the RV32/64I base
 * integer instruction set. It includes optional support for several extensions, including Zicsr
 * (Control and Status Registers), M (Multiplication and Division), B (Bit Manipulation), and 
 * F (Floating-Point Unit).
 *
 * Pipeline Structure (single instruction per cycle):
 * - STATE_IF:   Fetches the next instruction from memory using the PC.
 * - STATE_ID:   Decodes the fetched instruction and extracts control signals.
 * - STATE_EX:   Performs ALU operations, handles branches, jumps, and
 *               interacts with the MDU (if enabled) for multiplication and
 *               division.
 * - STATE_MEM:  Manages load/store operations through the TileLink Uncached
 *               Lightweight (TL-UL) memory interface, handling data sizes and
 *               alignment checks.
 * - STATE_WB:   Writes results back to the register file, updates the PC based
 *               on branch/jump decisions, and handles CSR operations (if Zicsr
 *               is enabled).
 * - STATE_TRAP: Manages exceptions and interrupts by updating relevant CSRs
 *               and redirecting execution to trap vectors.
 *
 * Key Features:
 * - Instruction Support: Executes RV32/64I instructions, including 
 *                        arithmetic, logical, load/store, branch, and control
 *                        transfer instructions.
 * - Memory Interface: Communicates with memory using the TileLink TL-UL 
 *   protocol, supporting read/write operations with proper alignment and data 
 *   sizing.
 * - Interrupt and Exception Handling: Detects and manages interrupts and 
 *   exceptions, updating CSRs such as `mstatus`, `mie`, `mtvec`, `mepc`, and 
 *   `mcause`.
 * - Halt Detection: Recognizes self-jump instructions (e.g., `jal x0, 0`) 
 *   to halt execution.
 *
 * Optional Extensions:
 * - SUPPORT_ZICSR: Enables access to Control and Status Registers for
 *                  managing exceptions and interrupts.
 * - SUPPORT_B: Adds bit manupulation operations via the BMU.
 * - SUPPORT_M: Adds multiplication and division operations via the MDU.
 *
 * Development Considerations:
 * - Simplicity: Focusing on clear state transitions without optimizations
 *   like actual pipelining or hazard detection.
 * - Synchronization: Ensures proper synchronization between CPU state 
 *   transitions and interactions with auxiliary modules (ALU, RegFile, MDU, 
 *   Memory Interface, CSR).
 * - Parameterization: Supports different data widths (`XLEN`), start 
 *   addresses, and configurable numbers of NMIs and IRQs, ensuring flexibility
 *   across various system configurations.
 * - Robustness: Incorporates error handling for undefined instructions, 
 *   unaligned memory accesses, and interrupt prioritization, transitioning to 
 *   safe states (`STATE_TRAP` or `STATE_RESET`) when necessary.
 *
 * Limitations:
 * - Non-Pipelined: Implements a sequential instruction flow without true 
 *   pipelining, limiting performance.
 * - Hazard Detection: Lacks mechanisms for hazard detection or resolution, 
 *   making it unsuitable for high-throughput applications.
 *
 * Usage:
 * - Integration: Can be integrated into larger systems requiring a simple 
 *   RISC-V core with optional extensions. Ensure that the memory interface 
 *   adheres to the TL-UL protocol and that optional extension parameters 
 *   (`SUPPORT_ZICSR`, `SUPPORT_B`, `SUPPORT_M`) are configured as 
 *   needed.
 * - Simulation: Ideal for educational simulations and testing scenarios 
 *   where a clear, step-by-step instruction flow is beneficial. Utilize the 
 *   debug outputs (`dbg_halt`, `dbg_pc`, `dbg_x1`, `dbg_x2`, 
 *   `dbg_x3`) for monitoring CPU state during simulations.
 *
 * @note The CPU's design emphasizes clarity and over performance and
 *       completeness. It serves as a foundational model for understanding
 *       RISC-V CPU architecture and operation.
 */

`timescale 1ns / 1ps
`default_nettype none

`include "src/instructions.sv"
`include "src/cpu_alu.sv"
`include "src/cpu_insdecode.sv"
`include "src/tl_interface.sv"
`include "src/cpu_regfile.sv"
`ifdef SUPPORT_ZICSR
`include "src/cpu_csr.sv"
`endif
`ifdef SUPPORT_M
`include "src/cpu_mdu.sv"
`endif
`ifdef SUPPORT_B
`include "src/cpu_bmu.sv"
`endif

module rv_cpu #(
    parameter MHARTID_VAL     = 32'h0000_0000,  // The Hardware ID for the CPU
    parameter XLEN            = 32,             // Data width: 32 bits
    parameter SID_WIDTH       = 8,              // Source ID Width
    parameter START_ADDRESS   = 32'h8000_0000,  // Default start address
    parameter MTVEC_RESET_VAL = 32'h8000_0000,  // Default mtvec address
    parameter NMI_COUNT       = 1,              // Number of NMIs (must satisfy XLEN > IRQ_COUNT + NMI_COUNT)
    parameter IRQ_COUNT       = 1               // Number of standard IRQs (must satisfy XLEN > IRQ_COUNT + NMI_COUNT)
) (
    input wire                  clk,
    input wire                  reset,

    `ifdef SUPPORT_ZICSR
    input wire                  external_irq, // Interrupt Request Lines
    input wire                  external_nmi, // Non-Maskable Interrupt
    `endif

    // TileLink TL-UL Interface signals
    // A Channel (Requests)
    output wire                 tl_a_valid,
    input  wire                 tl_a_ready,
    output wire [2:0]           tl_a_opcode,
    output wire [2:0]           tl_a_param,
    output wire [2:0]           tl_a_size,
    output wire [SID_WIDTH-1:0] tl_a_source,
    output wire [XLEN-1:0]      tl_a_address,
    output wire [XLEN/8-1:0]    tl_a_mask,
    output wire [XLEN-1:0]      tl_a_data,

    // D Channel (Responses)
    input  wire                  tl_d_valid,
    output wire                  tl_d_ready,
    input  wire [2:0]            tl_d_opcode,
    input  wire [1:0]            tl_d_param,
    input  wire [2:0]            tl_d_size,
    input  wire [SID_WIDTH-1:0]  tl_d_source,
    input  wire [XLEN-1:0]       tl_d_data,
    input  wire                  tl_d_corrupt,
    input  wire                  tl_d_denied,

    // Signals
    output wire                  trap,
    output wire [5:0]            test

    `ifdef DEBUG
    // Debug output
    ,output wire                 dbg_halt
    ,output wire [XLEN-1:0]      dbg_pc
    ,output wire [XLEN-1:0]      dbg_x1
    ,output wire [XLEN-1:0]      dbg_x2
    ,output wire [XLEN-1:0]      dbg_x3
    `endif
);

localparam WSTRB_WIDTH = XLEN / 8; // Number of bytes for mem write mask

// State Definitions
typedef enum logic [3:0] {
    STATE_RESET = 4'b0000,  // CPU is rest eithe by the user or some fault
    STATE_IF    = 4'b0001,  // Instruction Fetch
    STATE_ID    = 4'b0010,  // Instruction Decode
    STATE_EX    = 4'b0011,  // Execute
    STATE_MEM   = 4'b0100,  // Memory Access
    STATE_WB    = 4'b0101,  // Write Back
    STATE_TRAP  = 4'b0111   // Trap Handling
    `ifdef SUPPORT_M
    ,STATE_MUL_DIV   // Multiplication and Division Operations
    `endif
} cpu_state_t;
cpu_state_t state;
initial state = STATE_RESET;

typedef enum logic [1:0] {
    ALU,
    BMU,
    MDU
} cpu_work_unit_t;
cpu_work_unit_t work_unit;

// Trap cause
typedef enum logic [3:0] {
    TRAP_UNKNOWN,       // Default, unknown cause
    TRAP_UNSUPPORTED,   // XLEN not supported
    TRAP_HALT,          // Self jump detected
    TRAP_INSTRUCTION,   // Unknow insstruction encountered
    TRAP_EBREAK,        // EBreak instruction
    TRAP_ECALL,         // ECall instruction
    TRAP_INTERRUPT,     // Interrupt
    TRAP_I_MISALIGNED,  // Misaligned instruction memory access
    TRAP_L_MISALIGNED,  // Misaligned load memory access
    TRAP_S_MISALIGNED   // Misaligned store memory access
} trap_cause_t;
trap_cause_t trap_cause;

// Internal Registers and Signals
logic [XLEN-1:0] pc;
logic [31:0]     instr;
logic            halt;
logic [5:0]      test_cpu_reg;
logic            trap_reg;
logic            if_wait;  // instruction loading,
logic            mem_wait; // memory loading

assign trap = trap_reg;
assign test = state;

// Instruction Decoder Signals
logic [6:0]      opcode;
logic [4:0]      rd;
logic [2:0]      funct3;
logic [4:0]      rs1;
logic [4:0]      rs2;
logic [6:0]      funct7;
logic [11:0]     funct12;
logic [XLEN-1:0] imm;
// Control Signals
logic            is_mem, is_op_imm, is_op;
logic            is_lui, is_auipc, is_branch, is_jal, is_jalr;
logic            is_system;
`ifdef SUPPORT_M
logic            is_mul_div;
`endif

// Instantiate Instruction Decoder
cpu_insdecode #(.XLEN(XLEN)) instr_decoder_inst (
    .instr    (instr),
    .opcode   (opcode),
    .rd       (rd),
    .funct3   (funct3),
    .rs1      (rs1),
    .rs2      (rs2),
    .funct7   (funct7),
    .funct12  (funct12),
    .imm      (imm),
    .is_mem   (is_mem),
    .is_op_imm(is_op_imm),
    .is_op    (is_op),
    .is_lui   (is_lui),
    .is_auipc (is_auipc),
    .is_branch(is_branch),
    .is_jal   (is_jal),
    .is_jalr  (is_jalr),
    .is_system(is_system)
    `ifdef SUPPORT_M
    ,.is_mul_div(is_mul_div)
    `endif
);

// Register File Signals
logic [4:0]      rs1_addr, rs2_addr, rd_addr;
logic [XLEN-1:0] rs1_data, rs2_data;
logic [XLEN-1:0] rd_data;
logic            rd_write_en;

`ifdef DEBUG
logic [XLEN-1:0] dbg_rf_x1, dbg_rf_x2, dbg_rf_x3;
`endif

// Instantiate Register File
cpu_regfile #(.XLEN(XLEN)) reg_file_inst (
    .clk        (clk),
    .reset      (reset),
    .rs1_addr   (rs1_addr),
    .rs2_addr   (rs2_addr),
    .rd_addr    (rd_addr),
    .rd_data    (rd_data),
    .rd_write_en(rd_write_en),
    .rs1_data   (rs1_data),
    .rs2_data   (rs2_data)

    `ifdef DEBUG
    ,.dbg_x1     (dbg_rf_x1)
    ,.dbg_x2     (dbg_rf_x2)
    ,.dbg_x3     (dbg_rf_x3)
    `endif
);

`ifdef DEBUG
assign dbg_x1   = dbg_rf_x1;
assign dbg_x2   = dbg_rf_x2;
assign dbg_x3   = dbg_rf_x3;
assign dbg_pc   = pc;
assign dbg_halt = halt;
`endif

// ALU Signals
logic [XLEN-1:0] alu_operand_a, alu_operand_b;
logic [3:0]      alu_control;
logic [XLEN-1:0] alu_result;
logic            alu_zero;
logic            alu_less_than;
logic            alu_unsigned_less_than;

// Instantiate ALU
cpu_alu #(.XLEN(XLEN)) alu_inst (
    .operand_a          (alu_operand_a),
    .operand_b          (alu_operand_b),
    .control            (alu_control),
    .result             (alu_result),
    .zero               (alu_zero),
    .less_than          (alu_less_than),
    .unsigned_less_than (alu_unsigned_less_than)
);

`ifdef SUPPORT_B
// BMU Signals
logic [XLEN-1:0] bmu_operand_a, bmu_operand_b;
logic [3:0]      bmu_control;
logic [XLEN-1:0] bmu_result;

cpu_alu #(.XLEN(XLEN)) bmu_inst (
    .operand_a          (bmu_operand_a),
    .operand_b          (bmu_operand_b),
    .control            (bmu_control),
    .result             (bmu_result)
);
`endif

`ifdef SUPPORT_M
// MDU Signals
logic [XLEN-1:0] mdu_operand_a, mdu_operand_b;
logic [2:0]      mdu_control;
logic [XLEN-1:0] mdu_result;
logic            mdu_start;
logic            mdu_ready;

// Instantiate MDU
cpu_mdu #(.XLEN(XLEN)) mdu_inst (
    .clk                (clk),
    .reset              (reset),
    .operand_a          (mdu_operand_a),
    .operand_b          (mdu_operand_b),
    .control            (mdu_control),
    .start              (mdu_start),
    .result             (mdu_result),
    .ready              (mdu_ready)
);
`endif

// Memory Interface Signals
logic                   mem_ready;
logic [XLEN-1:0]        mem_address;
logic [XLEN-1:0]        mem_wdata;
logic [XLEN/8-1:0]      mem_wstrb;
logic [2:0]             mem_size;   // Byte, Halfword, Word
logic                   mem_read;
logic                   mem_ack;
logic [XLEN-1:0]        mem_rdata;
logic                   mem_valid;
logic                   mem_denied;
logic                   mem_corrupt;


// Instantiate Memory Interface
tl_interface #(
    .XLEN(XLEN),
    .SID_WIDTH(SID_WIDTH)
) mem_if_inst (
    .clk         (clk),
    .reset       (reset),

    // CPU Side
    .cpu_ready   (mem_ready),
    .cpu_address (mem_address),
    .cpu_wdata   (mem_wdata),
    .cpu_wstrb   (mem_wstrb),
    .cpu_size    (mem_size),
    .cpu_read    (mem_read),
    .cpu_ack     (mem_ack),
    .cpu_rdata   (mem_rdata),
    .cpu_denied  (mem_denied),
    .cpu_corrupt (mem_corrupt),
    .cpu_valid   (mem_valid),

    // TileLink TL-UL Interface signals
    .tl_a_valid  (tl_a_valid),
    .tl_a_ready  (tl_a_ready),
    .tl_a_opcode (tl_a_opcode),
    .tl_a_param  (tl_a_param),
    .tl_a_size   (tl_a_size),
    .tl_a_source (tl_a_source),
    .tl_a_address(tl_a_address),
    .tl_a_mask   (tl_a_mask),
    .tl_a_data   (tl_a_data),

    .tl_d_valid  (tl_d_valid),
    .tl_d_ready  (tl_d_ready),
    .tl_d_opcode (tl_d_opcode),
    .tl_d_param  (tl_d_param),
    .tl_d_size   (tl_d_size),
    .tl_d_source (tl_d_source),
    .tl_d_data   (tl_d_data),
    .tl_d_corrupt(tl_d_corrupt),
    .tl_d_denied (tl_d_denied)
);

`ifdef SUPPORT_ZICSR
// CSR Module Signals
logic [XLEN-1:0] csr_reg_rdata;
logic            csr_reg_write_en;
logic [11:0]     csr_reg_addr;
logic [XLEN-1:0] csr_reg_wdata;

logic            csr_op_valid;
logic            csr_op_ready;
logic            csr_op_done;
logic [XLEN-1:0] csr_op_rdata;
logic [11:0]     csr_op_addr;    // CSR operation address
logic [2:0]      csr_op_control; // CSR operation control signal
logic [XLEN-1:0] csr_op_operand; // Operand for CSR operations
logic [4:0]      csr_op_imm;     // Immediate for CSR operations

logic [XLEN-1:0] csr_mtvec;      // Machine Trap-Vector Base-Address Register
logic [XLEN-1:0] csr_mepc;       // Machine Exception Program Counter
logic [XLEN-1:0] csr_mcause;     // Machine Cause Register

// Interrupt CSRs
logic            interrupt_pending;

typedef enum logic [1:0] {
    STORE_PC,
    STORE_CAUSE,
    CONTINUE
} cpu_trap_state_t;
cpu_state_t trap_state;

// Instantiate CSR Module
cpu_csr #(
    .XLEN(XLEN),
    .NMI_COUNT(NMI_COUNT),
    .IRQ_COUNT(IRQ_COUNT),
    .MHARTID_VAL(MHARTID_VAL),
    .MTVEC_RESET_VAL(MTVEC_RESET_VAL)
) cpu_csr_inst (
    .clk         (clk),
    .reset       (reset),

    // CSR Register Interface
    .reg_addr    (csr_reg_addr),     // CSR address for Register Interface
    .reg_write_en(csr_reg_write_en), // Write enable for Register Interface
    .reg_wdata   (csr_reg_wdata),    // Write data for Register Interface
    .reg_rdata   (csr_reg_rdata),    // Read data from Register Interface

    // CSR Operation Interface
    .op_valid    (csr_op_valid),     // Operation valid
    .op_ready    (csr_op_ready),     // Operation ready
    .op_control  (csr_op_control),   // CSR operation control signals
    .op_addr     (csr_op_addr),      // CSR address for Operation Interface
    .op_operand  (csr_op_operand),   // Operand for CSR operations
    .op_imm      (csr_op_imm),       // Immediate for CSR operations
    .op_rdata    (csr_op_rdata),     // Read data from Operation Interface
    .op_done     (csr_op_done),      // Operation done signal

    // Exposed Registers
    .mtvec       (csr_mtvec),        // Exposed for STATE_TRAP logic
    .mepc        (csr_mepc),         // Exposed for INST_MRET logic
    .mcause      (csr_mcause),       // Exposed for STATE_TRAP logic

    // Output Signals
    .interrupt_pending(interrupt_pending),

    // Interrupt Request Lines
    .irq         (external_irq),     // Standard IRQs
    .nmi         (external_nmi)      // Non-Maskable IRQs (Edge-Triggered)
);
`endif

// Exception Handling Signals
logic [XLEN-1:0] trap_vector;

// CPU State Machine
always_ff @(posedge clk) begin
    if (reset) begin
        state               <= STATE_IF;
        pc                  <= START_ADDRESS;
        trap_cause          <= TRAP_UNKNOWN;
        trap_reg            <= 1'b0;
        rd_write_en         <= 1'b0;
        mem_ready           <= 1'b0;
        halt                <= 1'b0;
        if_wait             <= 1'b0;
        mem_wait            <= 1'b0;
        test_cpu_reg        <= 6'b100000;
        `ifdef SUPPORT_M
        mdu_start           <= 1'b0;
        `endif
        `ifdef SUPPORT_ZICSR
        csr_reg_write_en    <= 1'b0;
        csr_op_valid        <= 1'b0;
        trap_state          <= STORE_PC;
        `endif
        `ifdef LOG_CPU `LOG("rv_cpu", ("Reset, PC=0x%0h", START_ADDRESS)); `endif
    end else if (halt) begin
    end else begin
        case (state)
            STATE_RESET: begin
                state               <= STATE_IF;
                pc                  <= START_ADDRESS;
                trap_cause          <= TRAP_UNKNOWN;
                trap_reg            <= 1'b0;
                rd_write_en         <= 1'b0;
                mem_ready           <= 1'b0;
                halt                <= 1'b0;
                if_wait             <= 1'b0;
                mem_wait            <= 1'b0;
                test_cpu_reg        <= 6'b100000;
                `ifdef SUPPORT_M
                mdu_start           <= 1'b0;
                `endif
                `ifdef SUPPORT_ZICSR
                csr_reg_write_en    <= 1'b0;
                csr_op_valid        <= 1'b0;
                trap_state          <= STORE_PC;
                `endif
                `ifdef LOG_CPU `LOG("rv_cpu", ("/RESET/, PC=0x%0h", START_ADDRESS)); `endif
            end

            STATE_IF: begin
                if (halt == 1'b1) begin
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_IF/ HALT detected")); `endif
                    // HALT caught
                    // trap_cause  <= TRAP_HALT;
                    // state       <= STATE_TRAP;
                    // test_cpu_reg    <= 6'b101010;
                end else if (~mem_valid && ~mem_ready && ~if_wait) begin
                    if (pc[1:0] != 2'b00) begin
                        // PC is misaligned
                        `ifdef LOG_CPU `ERROR("rv_cpu", ("/STATE_IF/ Misaligned PC")); `endif
                        trap_cause  <= TRAP_I_MISALIGNED;
                        state       <= STATE_TRAP;
                    end else begin
                        test_cpu_reg    <= 6'b000001;
                        // Fetch instruction
                        rd_write_en      <= 1'b0; // Regfile Write enabled
                        trap_cause       <= TRAP_UNKNOWN;
                        mem_ready        <= 1'b1;
                        mem_address      <= pc;
                        mem_wdata        <= {XLEN{1'b0}};
                        mem_wstrb        <= {8{1'b0}};
                        mem_read         <= 1'b1;
                        mem_size         <= 3'b010; // Word size
                        if_wait          <= 1'b1;
                        `ifdef SUPPORT_ZICSR
                        csr_reg_write_en <= 1'b0; // CSR Register Write enabled
                        `endif
                        `ifdef LOG_CPU $display("\n===\n"); `endif
                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_IF/ Fetching instruction from PC=0x%0h", pc)); `endif
                    end
                end else if (mem_ready && mem_ack) begin
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_IF/ Fetching instruction acknowledged")); `endif
                    test_cpu_reg    <= 6'b000010; // Stuck here
                    mem_ready       <= 1'b0; // Deassert after acknowledgment
                end else if (mem_valid) begin
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_IF/ Fetched instruction from mem_address=0x%0h INS=%31b (0x%00h)", mem_address, mem_rdata[31:0], mem_rdata[31:0])); `endif
                    // Fetched instruction
                    test_cpu_reg    <= 6'b000100;
                    instr           <= mem_rdata[31:0]; // Instructions are 32 bits
                    if_wait         <= 1'b0;
                    state           <= STATE_ID;
                end
            end

            STATE_ID: begin
                `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_ID/ Instruction decoded")); `endif
                // Decode Instruction
                rs1_addr    <= rs1;
                rs2_addr    <= rs2;
                rd_write_en <= 1'b0;
                state       <= STATE_EX;
            end

            STATE_EX: begin
                // test_cpu_reg    <= 6'b001000;
                `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute opcode=%7b, funct3=%3b, funct7=%7b rd=%5b, rs1=%5b, imm=0x%0h", opcode, funct3, funct7, rd, rs1, imm)); `endif
                alu_operand_a <= rs1_data;
                alu_operand_b <= is_op_imm ? imm : rs2_data;
                alu_control  <= `ALU_ADD;

                `ifdef SUPPORT_B ////////////////////////////////////////////////////
                bmu_operand_a <= rs1_data;
                bmu_operand_b <= is_op_imm ? imm : rs2_data;
                bmu_control  <= `ALU_ADD;
                `endif // SUPPORT_B /////////////////////////////////////////////////

                `ifdef SUPPORT_M ////////////////////////////////////////////////////
                mdu_operand_a <= rs1_data;
                mdu_operand_b <= is_op_imm ? imm : rs2_data;
                mdu_control  <= `MDU_MUL;

                if (is_mul_div) begin
                    // Handle Multiplication and Division Instructions
                    // Set up ALU control for multiplication/division
                    mdu_operand_a <= rs1_data;
                    mdu_operand_b <= rs2_data;
                    rd_addr       <= rd;
                    rd_write_en   <= (rd != 5'b0);
                    mdu_start <= 1'b1;
                    state         <= STATE_MUL_DIV;
                    case ({opcode, funct7, funct3})
                        `INST_MUL   : begin work_unit <= MDU; mdu_control <= `MDU_MUL; end
                        `INST_MULH  : begin work_unit <= MDU; mdu_control <= `MDU_MULH; end
                        `INST_MULHSU: begin work_unit <= MDU; mdu_control <= `MDU_MULHSU; end
                        `INST_MULHU : begin work_unit <= MDU; mdu_control <= `MDU_MULHU; end
                        `INST_DIV   : begin work_unit <= MDU; mdu_control <= `MDU_DIV; end
                        `INST_DIVU  : begin work_unit <= MDU; mdu_control <= `MDU_DIVU; end
                        `INST_REM   : begin work_unit <= MDU; mdu_control <= `MDU_REM; end
                        `INST_REMU  : begin work_unit <= MDU; mdu_control <= `MDU_REMU; end
                        `INST_DIVW  : if (XLEN >= 64) begin work_unit <= MDU; mdu_control <= `MDU_DIV; end
                        `INST_DIVUW : if (XLEN >= 64) begin work_unit <= MDU; mdu_control <= `MDU_DIVU; end
                        `INST_MULW  : if (XLEN >= 64) begin work_unit <= MDU; mdu_control <= `MDU_MUL; end
                        `INST_REMW  : if (XLEN >= 64) begin work_unit <= MDU; mdu_control <= `MDU_REM; end
                        `INST_REMUW : if (XLEN >= 64) begin work_unit <= MDU; mdu_control <= `MDU_REMU; end
                        default: begin
                            `ifdef LOG_CPU_UNKNOWN_INST `ERROR("rv_cpu", ("/STATE_EX/ Unknow command opcode=%00b funct7=%00b funct3=%00b", opcode, funct7, funct3)); `endif
                            `ifdef LOG_CPU `ERROR("rv_cpu", ("/STATE_EX/ Unknow command opcode=%00b funct7=%00b funct3=%00b", opcode, funct7, funct3)); `endif
                            trap_cause <= TRAP_INSTRUCTION;
                            state      <= STATE_TRAP;
                        end
                    endcase
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute mul/div")); `endif
                end else
                `endif // SUPPORT_M /////////////////////////////////////////////////
                if (is_op_imm || is_op || is_lui || is_auipc || is_branch) begin
                    state     <= STATE_WB;
                    if (is_op) begin
                        case ({opcode, funct7, funct3})
                            `INST_ADD      : begin work_unit <= ALU; alu_control <= `ALU_ADD; end
                            `INST_SUB      : begin work_unit <= ALU; alu_control <= `ALU_SUB; end
                            `INST_SLT      : begin work_unit <= ALU; alu_control <= `ALU_SLT; end
                            `INST_SLTU     : begin work_unit <= ALU; alu_control <= `ALU_SLT; end
                            `INST_XOR      : begin work_unit <= ALU; alu_control <= `ALU_XOR; end
                            `INST_OR       : begin work_unit <= ALU; alu_control <= `ALU_OR; end
                            `INST_AND      : begin work_unit <= ALU; alu_control <= `ALU_AND; end
                            `INST_SLL      : begin work_unit <= ALU; alu_control <= `ALU_SLL; end
                            `INST_SRA      : begin work_unit <= ALU; alu_control <= `ALU_SRA; end
                            `INST_SRL      : begin work_unit <= ALU; alu_control <= `ALU_SRL; end
                            `ifdef SUPPORT_B ////////////////////////////////////////////////////
                            `INST_ANDN     : begin work_unit <= BMU; bmu_control = `BMU_ANDN; end
                            `INST_BCLR     : begin work_unit <= BMU; bmu_control = `BMU_BCLR; end
                            `INST_BEXT     : begin work_unit <= BMU; bmu_control = `BMU_BEXT; end
                            `INST_BINV     : begin work_unit <= BMU; bmu_control = `BMU_BINV; end
                            `INST_BSET     : begin work_unit <= BMU; bmu_control = `BMU_BSET; end
                            `INST_CLMUL    : begin work_unit <= BMU; bmu_control = `BMU_CLMUL; end
                            `INST_CLMULH   : begin work_unit <= BMU; bmu_control = `BMU_CLMULH; end
                            `INST_CLMULR   : begin work_unit <= BMU; bmu_control = `BMU_CLMULR; end
                            `INST_MAX      : begin work_unit <= BMU; bmu_control = `BMU_MAX; end
                            `INST_MAXU     : begin work_unit <= BMU; bmu_control = `BMU_MAXU; end
                            `INST_MIN      : begin work_unit <= BMU; bmu_control = `BMU_MIN; end
                            `INST_MINU     : begin work_unit <= BMU; bmu_control = `BMU_MINU; end
                            `INST_ORN      : begin work_unit <= BMU; bmu_control = `BMU_ORN; end
                            `INST_ROL      : begin work_unit <= BMU; bmu_control = `BMU_ROL; end
                            `INST_ROR      : begin work_unit <= BMU; bmu_control = `BMU_ROR; end
                            `INST_SH1ADD   : begin work_unit <= BMU; bmu_control = `BMU_SH1ADD; end
                            `INST_SH2ADD   : begin work_unit <= BMU; bmu_control = `BMU_SH2ADD; end
                            `INST_SH3ADD   : begin work_unit <= BMU; bmu_control = `BMU_SH3ADD; end
                            `INST_XNOR     : begin work_unit <= BMU; bmu_control = `BMU_XNOR; end
                            `INST_XPERM16  : begin work_unit <= BMU; bmu_control = `BMU_XPERM16; end
                            `INST_XPERM32  : begin work_unit <= BMU; bmu_control = `BMU_XPERM32; end
                            `INST_XPERM4   : begin work_unit <= BMU; bmu_control = `BMU_XPERM4; end
                            `INST_XPERM8   : begin work_unit <= BMU; bmu_control = `BMU_XPERM8; end
                            `INST_ZEXTH32  : begin work_unit <= BMU; bmu_control = `BMU_ZEXTH32; end
                            `INST_ZEXTH64  : begin work_unit <= BMU; bmu_control = `BMU_ZEXTH64; end
                            `INST_ROLW     : if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_ROL; end
                            `INST_RORW     : if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_ROR; end
                            `INST_ADD_UW   : if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_ADD_UW; end
                            `INST_SH1ADD_UW: if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_SH1ADD_UW; end
                            `INST_SH2ADD_UW: if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_SH2ADD_UW; end
                            `INST_SH3ADD_UW: if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_SH3ADD_UW; end
                            `endif // SUPPORT_B /////////////////////////////////////////////////
                            `INST_ADDW     : if (XLEN >= 64) begin work_unit <= ALU; alu_control <= `ALU_ADD; end
                            `INST_SUBW     : if (XLEN >= 64) begin work_unit <= ALU; alu_control <= `ALU_SUB; end
                            `INST_SLLW     : if (XLEN >= 64) begin work_unit <= ALU; alu_control <= `ALU_SLL; end
                            `INST_SRLW     : if (XLEN >= 64) begin work_unit <= ALU; alu_control <= `ALU_SRL; end
                            `INST_SRAW     : if (XLEN >= 64) begin work_unit <= ALU; alu_control <= `ALU_SRA; end
                            default: begin
                                `ifdef LOG_CPU_UNKNOWN_INST `ERROR("rv_cpu", ("/STATE_EX/ Unknow instruction op pc=%00h (%b)", pc, {opcode, funct7, funct3})); `endif
                                `ifdef LOG_CPUT `ERROR("rv_cpu", ("/STATE_EX/ Unknow instruction op pc=%00h (%b)", pc, {opcode, funct7, funct3})); `endif
                                trap_cause <= TRAP_INSTRUCTION;
                                state      <= STATE_TRAP;
                            end
                        endcase
                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute op rs1_data=0x%0h rs2_data=0x%0h", rs1_data, rs2_data)); `endif
                    end else if (is_op_imm) begin
                        alu_operand_b <= (funct3 == 3'b001 || funct3 == 3'b101) ? {27'b0, instr[24:20]} : imm;
                        casex ({opcode, funct3, imm[31:20]})
                            `INST_ADDI   : begin work_unit <= ALU; alu_control <= `ALU_ADD; end
                            `INST_SLLI   : begin work_unit <= ALU; alu_control <= `ALU_SLL; end
                            `INST_SLTI   : begin work_unit <= ALU; alu_control <= `ALU_SLT; end
                            `INST_SLTIU  : begin work_unit <= ALU; alu_control <= `ALU_SLTU; end
                            `INST_XORI   : begin work_unit <= ALU; alu_control <= `ALU_XOR; end
                            `INST_ORI    : begin work_unit <= ALU; alu_control <= `ALU_OR; end
                            `INST_ANDI   : begin work_unit <= ALU; alu_control <= `ALU_AND; end
                            `INST_SRLI   : begin work_unit <= ALU; alu_control <= `ALU_SRL; end
                            `INST_SRAI   : begin work_unit <= ALU; alu_control <= `ALU_SRA; end
                            `ifdef SUPPORT_B ////////////////////////////////////////////////////
                            `INST_BCLRI  : begin work_unit <= BMU; bmu_control = `BMU_BCLR; end
                            `INST_BINVI  : begin work_unit <= BMU; bmu_control = `BMU_BINV; end
                            `INST_BSETI  : begin work_unit <= BMU; bmu_control = `BMU_BSET; end
                            `INST_CLZ    : begin work_unit <= BMU; bmu_control = `BMU_CLZ; end
                            `INST_CPOP   : begin work_unit <= BMU; bmu_control = `BMU_CPOP; end
                            `INST_CTZ    : begin work_unit <= BMU; bmu_control = `BMU_CTZ; end
                            `INST_SEXT_B : begin work_unit <= BMU; bmu_control = `BMU_SEXTB; end
                            `INST_SEXT_H : begin work_unit <= BMU; bmu_control = `BMU_SEXTH; end
                            `INST_SHFLI  : begin work_unit <= BMU; bmu_control = `BMU_SHFL; end
                            `INST_BEXTI  : begin work_unit <= BMU; bmu_control = `BMU_BEXT; end
                            `INST_GREVI  : begin work_unit <= BMU; bmu_control = `BMU_GREV; end
                            `INST_ORCB   : begin work_unit <= BMU; bmu_control = `BMU_ORCB; end
                            `INST_RORI   : begin work_unit <= BMU; bmu_control = `BMU_ROR; end
                            `INST_UNSHFLI: begin work_unit <= BMU; bmu_control = `BMU_UNSHFL; end
                            `INST_CLZW   : if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_CLZ; end
                            `INST_CPOPW  : if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_CPOP; end
                            `INST_CTZW   : if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_CTZ; end
                            `INST_RORIW  : if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_ROR; end
                            `INST_SLLIUW : if (XLEN >= 64) begin work_unit <= BMU; bmu_control = `BMU_SLLIUW; end
                            `endif // SUPPORT_B /////////////////////////////////////////////////
                            `INST_ADDIW  : if (XLEN >= 64) begin work_unit <= ALU; alu_control <= `ALU_ADD; end
                            `INST_SLLIW  : if (XLEN >= 64) begin work_unit <= ALU; alu_control <= `ALU_SLL; end
                            `INST_SRLIW  : if (XLEN >= 64) begin work_unit <= ALU; alu_control <= `ALU_SRL; end
                            `INST_SRAIW  : if (XLEN >= 64) begin work_unit <= ALU; alu_control <= `ALU_SRA; end
                            default: begin
                                `ifdef LOG_CPU_UNKNOWN_INST `ERROR("rv_cpu", ("/STATE_EX/ Unknow instruction op_imm (%b)", {opcode, funct3, imm[31:19]})); `endif
                                `ifdef LOG_CPU `ERROR("rv_cpu", ("/STATE_EX/ Unknow instruction op_imm (%b)", {opcode, funct3, imm[31:19]})); `endif
                                trap_cause <= TRAP_INSTRUCTION;
                                state      <= STATE_TRAP;
                            end
                        endcase
                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute op_imm rs1_data=0x%0h imm=0x%0h", rs1_data, imm)); `endif
                    end else if (is_branch) begin
                        case ({opcode, funct3})
                            `INST_BEQ : begin work_unit <= ALU; alu_control <= `ALU_SUB; end
                            `INST_BNE : begin work_unit <= ALU; alu_control <= `ALU_SUB; end
                            `INST_BLT : begin work_unit <= ALU; alu_control <= `ALU_SLT; end
                            `INST_BLTU: begin work_unit <= ALU; alu_control <= `ALU_SLTU; end
                            `INST_BGE : begin work_unit <= ALU; alu_control <= `ALU_SLT; end
                            `INST_BGEU: begin work_unit <= ALU; alu_control <= `ALU_SLTU; end
                            default: begin
                                `ifdef LOG_CPU_UNKNOWN_INST `ERROR("rv_cpu", ("/STATE_EX/ Unknow instruction branch (%b)", {opcode, opcode, funct3})); `endif
                                `ifdef LOG_CPU `ERROR("rv_cpu", ("/STATE_EX/ Unknow instruction branch (%b)", {opcode, opcode, funct3})); `endif
                                trap_cause <= TRAP_INSTRUCTION;
                                state      <= STATE_TRAP;
                            end
                        endcase
                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute branch")); `endif
                    end else if (is_lui) begin
                        alu_operand_a <= {XLEN{1'b0}};
                        alu_operand_b <= imm;
                        alu_control   <= `ALU_ADD; // ADD
                        work_unit     <= ALU;
                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute lui")); `endif
                    end else if (is_auipc) begin
                        alu_operand_a <= pc;
                        alu_operand_b <= imm;
                        alu_control   <= `ALU_ADD; // ADD
                        work_unit     <= ALU;
                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute auipc")); `endif
                    end
                end else if (is_mem) begin
                    // Memory Address Calculation
                    alu_operand_a <= rs1_data;
                    alu_operand_b <= imm;
                    alu_control   <= `ALU_ADD; // ADD
                    work_unit     <= ALU;
                    state         <= STATE_MEM;
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute Memory request, ALU ADD rs1_data=0x%0h imm=0x%0h", rs1_data, imm)); `endif
                end else if (is_jal || is_jalr) begin
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute jal/jalr")); `endif
                    state         <= STATE_WB;
                end else if (is_system) begin
                    state         <= STATE_WB;

                `ifdef SUPPORT_ZICSR ////////////////////////////////////////////////
                    rd_addr     <= rd;
                    rs1_addr    <= rs1;
                    rd_data     <= csr_op_rdata;
                    csr_op_addr <= imm[11:0];
                `endif

                    casex ({opcode, funct3, funct12})
                        `INST_EBREAK: begin
                            `ifdef LOG_CPU `LOG("rv_cpu", ("INST_EBREAK")); `endif
                            trap_cause <= TRAP_EBREAK;
                            state      <= STATE_TRAP;
                        end
                        `INST_ECALL: begin
                            `ifdef LOG_CPU `LOG("rv_cpu", ("INST_ECALL")); `endif
                            trap_cause <= TRAP_ECALL;
                            state      <= STATE_TRAP;
                        end
                `ifdef SUPPORT_ZICSR ////////////////////////////////////////////////
                        `INST_MRET: begin
                            trap_reg <= 1'b0;
                            pc       <= csr_mepc;
                            `ifdef LOG_CPU `LOG("rv_cpu", ("MRET PC updated to 0x%0h", csr_mepc)); `endif
                            state <= STATE_IF;
                        end
                        `INST_CSRRW: begin
                            `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ INST_CSRRW: csr_op_addr=%00h rs1_data=0x%00h", imm[11:0], rs1_data)); `endif
                            rd_write_en    <= 1'b1;         // Enable writing to the destination register
                            csr_op_control <= `CSR_RW;      // Indicate a CSR read-write operation
                            csr_op_operand <= rs1_data;     // Operand from rs1
                            csr_op_valid   <= 1'b1;         // Indicate that the CSR operation is valid
                        end
                        `INST_CSRRS: begin
                            `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ INST_CSRRS: csr_op_addr=%00h rs1_data=0x%00h", imm[11:0], rs1_data)); `endif
                            rd_write_en    <= 1'b1;         // Enable writing to the destination register
                            csr_op_control <= `CSR_RS;      // CSR read and set operation
                            csr_op_operand <= rs1_data;     // Operand from rs1
                            csr_op_valid   <= 1'b1;         // Indicate that the CSR operation is valid
                        end
                        `INST_CSRRC: begin
                            rd_write_en    <= 1'b1;         // Enable writing to the destination register
                            csr_op_control <= `CSR_RC;      // CSR read and clear operation
                            csr_op_operand <= rs1_data;     // Operand from rs1
                            csr_op_valid   <= 1'b1;         // Indicate that the CSR operation is valid
                        end
                        `INST_CSRRWI: begin
                            csr_op_control <= `CSR_RW;      // CSR read and write operation
                            csr_op_imm     <= rs1;          // Use the rs1 field as the immediate value for the CSR operation
                            csr_op_valid   <= 1'b1;         // Indicate that the CSR operation is valid
                        end
                        `INST_CSRRSI: begin
                            csr_op_control <= `CSR_RS;       // CSR read and set operation
                            csr_op_imm     <= rs1;           // Immediate value from rs1 field for the operation
                            csr_op_valid   <= 1'b1;          // Indicate that the CSR operation is valid
                        end
                        `INST_CSRRCI: begin
                            csr_op_control <= `CSR_RC;       // CSR read and clear operation
                            csr_op_imm     <= rs1;           // Immediate value from rs1 field for the operation
                            csr_op_valid   <= 1'b1;          // Indicate that the CSR operation is valid
                        end
                `endif // SUPPORT_ZICSR /////////////////////////////////////////////
                        default: begin
                            `ifdef LOG_CPU `ERROR("rv_cpu", ("UNKNOWN SYSTEM opcode=%00b funct3=%00b imm[31:19]=%00b", opcode, funct3, imm[31:19])); `endif
                            trap_cause <= TRAP_INSTRUCTION;
                            state      <= STATE_TRAP;
                        end
                    endcase
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_EX/ Execute system")); `endif
                end else begin
                    // Handle Undefined Instructions
                    `ifdef LOG_CPU `ERROR("rv_cpu", ("/STATE_EX/ Execute unknown")); `endif
                    trap_cause <= TRAP_INSTRUCTION;
                    state      <= STATE_TRAP;
                end
            end

            `ifdef SUPPORT_M ////////////////////////////////////////////////////
            STATE_MUL_DIV: begin
                // Wait for multiplication/division to complete
                if (mdu_ready) begin
                    rd_data       <= mdu_result;
                    rd_write_en   <= (rd != 5'b0);
                    mdu_start <= 1'b0;
                    pc            <= pc + 4;
                    state         <= STATE_IF;
                end else begin
                    // Stay in this state until operation is ready
                    // MDU is processing the operation
                end
            end
            `endif // SUPPORT_M /////////////////////////////////////////////////

            STATE_MEM: begin
                // test_cpu_reg    <= 6'b010000;
                // `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ mem_wait=%0b mem_ready=%0b mem_valid=%0b mem_rdata=0x%08h",
                //         mem_wait, mem_ready, mem_valid, mem_rdata)); `endif
                // Memory Access
                if (~mem_valid && ~mem_ready && ~mem_wait) begin
                    // Memory access is being requested
                    mem_ready   <= 1'b1;
                    mem_wait    <= 1'b1;
                    mem_address <= alu_result;
                    // mem_wdata   <= rs2_data;
                    case ({opcode, funct3})
                        `INST_LBU,
                        `INST_LB: begin
                            // No alignment check needed for byte loads
                            mem_read  <= 1'b1;
                            mem_size  <= 3'b000;
                            mem_wstrb <= 8'b0;
                            `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Load LB/LBU from address 0x%0h", alu_result)); `endif
                        end
                        `INST_LHU,
                        `INST_LH: begin
                            // Halfword load: address must be 2-byte aligned
                            if (alu_result[0] != 1'b0) begin
                                trap_cause <= TRAP_L_MISALIGNED;
                                state      <= STATE_TRAP;
                            end else begin
                                mem_read  <= 1'b1;
                                mem_size  <= 3'b001;
                                mem_wstrb <= 8'b0;
                                `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Load LH/LHU from address 0x%0h", alu_result)); `endif
                            end
                        end
                        `INST_LWU,
                        `INST_LW: begin
                            // Word load: address must be 4-byte aligned
                            if (alu_result[1:0] != 2'b00) begin
                                trap_cause <= TRAP_L_MISALIGNED;
                                state      <= STATE_TRAP;
                            end else begin
                                mem_read  <= 1'b1;
                                mem_size  <= 3'b010;
                                mem_wstrb <= 8'b0;
                                `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Load LW/LWU from address 0x%0h", alu_result)); `endif
                            end
                        end
                        `INST_LD: if (XLEN >= 64) begin
                            // Double word load: address must be 8-byte aligned
                            if (alu_result[2:0] != 3'b000) begin
                                trap_cause <= TRAP_L_MISALIGNED;
                                state      <= STATE_TRAP;
                            end else begin
                                mem_read  <= 1'b1;
                                mem_size  <= 3'b011; // Double Word
                                mem_wstrb <= 8'b0;
                                `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Load LD from address 0x%0h", alu_result)); `endif
                            end
                        end
                        `INST_SB: begin
                            mem_read  <= 1'b0;
                            mem_size  <= 3'b000;
                            mem_wdata  <= {{(XLEN-8){1'b0}},rs2_data[7:0]};
                            // Determine the byte lane based on the address
                            if (XLEN == 32) begin
                                mem_wstrb <= 4'b0001 << alu_result[1:0];
                                `ifdef LOG_CPU_CPU `LOG("rv_cpu", ("/STATE_MEM/ Store SB to address 0x%0h rs2_data=%0h mem_wstrb=%00b", alu_result, rs2_data, 4'b0001 << alu_result[1:0])); `endif
                            end else if (XLEN == 64) begin
                                mem_wstrb <= 8'b00000001 << alu_result[2:0];
                            end else if (XLEN == 128) begin
                                mem_wstrb <= 16'b0000000000000001 << alu_result[3:0];
                            end else begin
                                mem_wait   <= 1'b0;
                                mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                trap_cause <= TRAP_UNSUPPORTED;
                                state      <= STATE_TRAP;
                            end
                        end
                        `INST_SH: begin
                            mem_read  <= 1'b0;
                            mem_size  <= 3'b001;
                            mem_wdata  <= {{(XLEN-16){1'b0}},rs2_data[15:0]};
                            // Shift two '1's to the correct halfword lane based on the lower bits of the address
                            if (XLEN == 32) begin
                                case (alu_result[1:0])
                                    2'b00: begin
                                        mem_wstrb <= 4'b0011;
                                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Store SH to address 0x%0h rs2_data=%0h mem_wstrb=%0b", alu_result, rs2_data, 4'b0011)); `endif
                                    end
                                    2'b10: begin;
                                        mem_wstrb <= 4'b1100;
                                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Store SH to address 0x%0h rs2_data=%0h mem_wstrb=%0b", alu_result, rs2_data, 4'b1100)); `endif
                                    end
                                    default: begin
                                        mem_wait   <= 1'b0;
                                        mem_wdata  <= 0;
                                        mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                        trap_cause <= TRAP_S_MISALIGNED;
                                        state      <= STATE_TRAP;
                                    end
                                endcase
                            end else if (XLEN == 64) begin
                                case (alu_result[2:1])
                                    2'b00: mem_wstrb <= 8'b00000011;
                                    2'b01: mem_wstrb <= 8'b00001100;
                                    2'b10: mem_wstrb <= 8'b00110000;
                                    2'b11: mem_wstrb <= 8'b11000000;
                                    default: begin
                                        mem_wait   <= 1'b0;
                                        mem_wdata  <= 0;
                                        mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                        trap_cause <= TRAP_S_MISALIGNED;
                                        state      <= STATE_TRAP;
                                    end
                                endcase
                            end else if (XLEN == 128) begin
                                case (alu_result[3:1])
                                    3'b000: mem_wstrb <= 16'b0000000000000011;
                                    3'b001: mem_wstrb <= 16'b0000000000001100;
                                    3'b010: mem_wstrb <= 16'b0000000000110000;
                                    3'b011: mem_wstrb <= 16'b0000000011000000;
                                    3'b100: mem_wstrb <= 16'b0000001100000000;
                                    3'b101: mem_wstrb <= 16'b0000110000000000;
                                    3'b110: mem_wstrb <= 16'b0011000000000000;
                                    3'b111: mem_wstrb <= 16'b1100000000000000;
                                    default: begin
                                        mem_wait   <= 1'b0;
                                        mem_wdata  <= 0;
                                        mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                        trap_cause <= TRAP_S_MISALIGNED;
                                        state      <= STATE_TRAP;
                                    end
                                endcase
                            end else begin
                                mem_wait    <= 1'b0;
                                mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                trap_cause <= TRAP_UNSUPPORTED;
                                state      <= STATE_TRAP;
                            end
                        end
                        `INST_SW: begin
                            mem_read  <= 1'b0;
                            mem_size  <= 3'b010;
                            mem_wdata  <= {{(XLEN-32){1'b0}},rs2_data[31:0]};
                            // For word stores, ensure word alignment and set write strobe to enable all bytes
                            if (XLEN == 32) begin
                                // Ensure address is word-aligned
                                if (alu_result[1:0] == 2'b00) begin
                                    mem_wstrb <= 4'b1111;
                                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Store SW to address 0x%0h rs2_data=%0h mem_wstrb=%0b", alu_result, rs2_data, 4'b1111)); `endif
                                end else begin
                                    mem_wait   <= 1'b0;
                                    mem_wdata  <= 0;
                                    mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                    trap_cause <= TRAP_S_MISALIGNED;
                                    state      <= STATE_TRAP;
                                end
                            end else if (XLEN == 64) begin
                                // Ensure address is word-aligned (4-byte boundaries)
                                if (alu_result[1:0] == 2'b00) begin
                                    mem_wstrb <= 8'b00001111;
                                end else begin
                                    mem_wait   <= 1'b0;
                                    mem_wdata  <= 0;
                                    mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                    trap_cause <= TRAP_S_MISALIGNED;
                                    state      <= STATE_TRAP;
                                end
                            end else if (XLEN == 128) begin
                                // Ensure address is word-aligned (4-byte boundaries)
                                if (alu_result[1:0] == 2'b00) begin
                                    mem_wstrb <= 16'b0000000000001111;
                                end else begin
                                    mem_wait   <= 1'b0;
                                    mem_wdata  <= 0;
                                    mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                    trap_cause <= TRAP_S_MISALIGNED;
                                    state      <= STATE_TRAP;
                                end
                            end else begin
                                mem_wait   <= 1'b0;
                                mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                trap_cause <= TRAP_UNSUPPORTED;
                                state      <= STATE_TRAP;
                            end
                        end
                        `INST_SD: if (XLEN >= 64) begin
                            mem_read   <= 1'b0;
                            mem_size   <= 3'b011; // Double Word
                            mem_wdata  <= {{(XLEN-64){1'b0}},rs2_data[63:0]};
                            if (XLEN == 64) begin
                                // Ensure address is 8-byte aligned
                                if (alu_result[2:0] == 3'b000) begin
                                    mem_wstrb <= 8'b11111111;
                                    `ifdef LOG_CPU 
                                        `LOG("rv_cpu", ("/STATE_MEM/ Store SD to address 0x%0h rs2_data=%0h mem_wstrb=%0b", 
                                                alu_result, rs2_data, 8'b11111111));
                                    `endif
                                end else begin
                                    mem_wait   <= 1'b0;
                                    mem_wdata  <= 0;
                                    mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                    trap_cause <= TRAP_S_MISALIGNED;
                                    state      <= STATE_TRAP;
                                end
                            end else if (XLEN == 128) begin
                                // Ensure address is 8-byte aligned (for double word)
                                if (alu_result[3:0] == 4'b0000) begin
                                    mem_wstrb <= 16'b1111111111111111;
                                    `ifdef LOG_CPU 
                                        `LOG("rv_cpu", ("/STATE_MEM/ Store SD to address 0x%0h rs2_data=%0h mem_wstrb=%0b", 
                                                alu_result, rs2_data, 16'b1111111111111111));
                                    `endif
                                end else begin
                                    mem_wait   <= 1'b0;
                                    mem_wdata  <= 0;
                                    mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                    trap_cause <= TRAP_S_MISALIGNED;
                                    state      <= STATE_TRAP;
                                end
                            end else begin
                                mem_wait   <= 1'b0;
                                mem_wstrb  <= {(WSTRB_WIDTH){1'b0}};
                                trap_cause <= TRAP_UNSUPPORTED;
                                state      <= STATE_TRAP;
                            end
                        end
                        default: begin
                            mem_wait   <= 1'b0;
                            trap_cause <= TRAP_INSTRUCTION;
                            state      <= STATE_TRAP;
                        end
                    endcase
                end else if (mem_ack && mem_ready) begin
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Store/Load acknowledged")); `endif
                    mem_ready <= 1'b0; // Deassert after acknowledgment
                end else if (mem_valid && mem_read) begin
                    // Memory is ready to be loaded
                    mem_wait  <= 1'b0;
                    pc        <= pc + 4;
                    `ifdef LOG_CPU `LOG("rv_cpu", ("PC updated to 0x%0h", pc + 4)); `endif
                    state     <= STATE_IF;
                    case ({opcode, funct3})
                        `INST_LB: begin
                            rd_addr     <= rd;
                            rd_write_en <= 1'b1;
                            rd_data     <= {{(XLEN-8){mem_rdata[7]}}, mem_rdata[7:0]};
                            `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Received LB Data=0x%0h for rd=%0d", {{(XLEN-8){mem_rdata[7]}}, mem_rdata[7:0]}, rd)); `endif
                        end
                        `INST_LH: begin
                            rd_addr     <= rd;
                            rd_write_en <= 1'b1;
                            rd_data     <= {{(XLEN-16){mem_rdata[15]}}, mem_rdata[15:0]};
                            `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Received LH Data=0x%0h for rd=%0d", {{(XLEN-16){mem_rdata[15]}}, mem_rdata[15:0]}, rd)); `endif
                        end
                        `INST_LW: begin
                            rd_addr     <= rd;
                            rd_write_en <= 1'b1;
                            rd_data     <= {{(XLEN-32){mem_rdata[31]}}, mem_rdata[31:0]};
                            `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Received LW Data=0x%0h for rd=%0d", {{(XLEN-32){mem_rdata[31]}}, mem_rdata[31:0]}, rd)); `endif
                        end
                        `INST_LBU: begin
                            rd_addr     <= rd;
                            rd_write_en <= 1'b1;
                            rd_data     <= {{(XLEN-8){1'b0}}, mem_rdata[7:0]};
                            `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Received LWU Data=0x%0h for rd=%0d", {{(XLEN-8){1'b0}}, mem_rdata[7:0]}, rd)); `endif
                        end
                        `INST_LHU: begin
                            rd_addr     <= rd;
                            rd_write_en <= 1'b1;
                            rd_data     <= {{(XLEN-16){1'b0}}, mem_rdata[15:0]};
                        end
                        `INST_LWU: begin
                            rd_addr     <= rd;
                            rd_write_en <= 1'b1;
                            rd_data     <= {{(XLEN-32){1'b0}}, mem_rdata[31:0]};
                        end
                        `INST_LD: if (XLEN >= 64) begin
                            rd_addr     <= rd;
                            rd_write_en <= 1'b1;
                            rd_data     <= {{(XLEN-64){mem_rdata[63]}}, mem_rdata[63:0]};
                            `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Received LW Data=0x%0h for rd=%0d", mem_rdata[63:0], rd)); `endif
                        end
                        default: begin
                            trap_cause <= TRAP_INSTRUCTION;
                            state      <= STATE_TRAP;
                        end
                    endcase
                end else if (mem_valid && ~mem_read) begin
                    mem_wait  <= 1'b0;
                    if (mem_corrupt) begin
                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Memory is corrupt")); `endif
                    end
                    if (mem_denied) begin
                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Memory is denied")); `endif
                    end
                    // Memory is written
                    pc        <= pc + 4;
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ PC updated to 0x%0h", pc + 4)); `endif
                    `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_MEM/ Write Done")); `endif
                    state     <= STATE_IF;
                end else begin
                    // `ifdef LOG_CPU `WARN("rv_cpu", ("/STATE_MEM/ WTF mem_valid=%00d mem_read=%00d mem_ack=%00d mem_ready=%00d mem_wait=%00d",mem_valid, mem_read, mem_ack, mem_ready, mem_wait)); `endif
                end
            end

            STATE_WB: begin
                // test_cpu_reg    <= 6'b100000;
                `ifdef LOG_CPU `LOG("rv_cpu", ("STATE_WB: is_op_imm=%0b is_op=%0b is_lui=%0b is_auipc=%0b rd=%0d alu_result=0x%0h",
                        is_op_imm, is_op, is_lui, is_auipc, rd, alu_result)); `endif
                // Write Back
                rd_write_en <= 1'b0;
                if (rd != 5'b0 && (is_op_imm || is_op || is_lui || is_auipc)) begin
                    case (work_unit)
                        ALU: begin
                            rd_data <= alu_result;
                            `ifdef LOG_CPU `LOG("rv_cpu", ("STATE_WB Writing ALU 0x%0h to rd=%0d", alu_result, rd)); `endif
                        end
                        `ifdef SUPPORT_B
                        BMU: begin
                            rd_data <= bmu_result;
                            `ifdef LOG_CPU `LOG("rv_cpu", ("STATE_WB Writing BMU 0x%0h to rd=%0d", bmuu_result, rd)); `endif
                        end
                        `endif
                        `ifdef SUPPORT_M
                        MDU: begin
                            rd_data <= mdu_result;
                            `ifdef LOG_CPU `LOG("rv_cpu", ("STATE_WB Writing MDU 0x%0h to rd=%0d", mdu_result, rd)); `endif
                        end
                        `endif
                    endcase
                    rd_addr     <= rd;
                    rd_write_en <= 1'b1;
                end else if (is_jal || is_jalr) begin
                    rd_data     <= pc + 4;
                    rd_addr     <= rd;
                    rd_write_en <= 1'b1;
                    `ifdef LOG_CPU `LOG("rv_cpu", ("STATE_WB JAL/JALR Writing 0x%0h to rd=%0d", pc + 4, rd)); `endif
                end

                // Branch Decision Logic
                if (is_branch) begin
                    logic take_branch;
                    case (funct3)
                        3'b000: take_branch = alu_zero;               // BEQ
                        3'b001: take_branch = ~alu_zero;              // BNE
                        3'b100: take_branch = alu_less_than;          // BLT
                        3'b101: take_branch = ~alu_less_than;         // BGE
                        3'b110: take_branch = alu_unsigned_less_than; // BLTU
                        3'b111: take_branch = ~alu_unsigned_less_than;// BGEU
                        default: take_branch = 1'b0;
                    endcase
                    pc <= take_branch ? pc + imm : pc + 4;
                    `ifdef LOG_CPU `LOG("rv_cpu", ("take_branch is %0d PC updated to 0x%0h", take_branch, (take_branch ? pc + imm : pc + 4))); `endif
                end else if (is_jal) begin
                    if (pc == pc + imm) begin
                        halt <= 1'b1;
                    end 
                    // Move the the next instruction, then move by the imm
                    // The compiler add's -4 to the imm so "jal x0 0" is compiled as "jal x0 -4"
                    // So the addumption is that pc = pc + 4 happens before the jump
                    pc <= pc + imm;
                    `ifdef LOG_CPU `LOG("rv_cpu", ("JAL PC updated to 0x%0h", pc + imm)); `endif
                end else if (is_jalr) begin
                    if (pc == (rs1_data + imm) & ~32'b1) begin
                        halt <= 1'b1;
                    end
                    pc <= (rs1_data + imm) & ~32'b1; // Clear LSB
                    `ifdef LOG_CPU `LOG("rv_cpu", ("JALR PC updated to 0x%0h. rs1_addr=%0d rs1_data=0x%0h imm=0x%0h", (rs1_data + imm) & ~32'b1, rs1_addr, rs1_data, imm)); `endif
                end else if (is_system) begin
                    `ifdef SUPPORT_ZICSR
                    if (csr_op_valid && csr_op_done) begin
                        `ifdef LOG_CPU `LOG("rv_cpu", ("/STATE_WB/ csr_op_rdata=%00b", csr_op_rdata)); `endif
                        // CSR operation finished
                        csr_op_valid <= 1'b0;
                        rd_write_en  <= 1'b0;
                        pc <= pc + 4;
                    end else if (csr_op_valid && ~csr_op_done) begin
                        // Wait for CSR to finish
                    end else if (~csr_op_valid) begin
                        // Not CSR
                        pc <= pc + 4;
                    end
                    `else
                    pc <= pc + 4;
                    `endif
                end else begin
                    pc <= pc + 4;
                    `ifdef LOG_CPU `LOG("rv_cpu", ("PC updated to 0x%0h", pc + 4)); `endif
                end

                // Check for Interrupts
                `ifdef SUPPORT_ZICSR
                if (interrupt_pending) begin
                    trap_cause <= TRAP_INTERRUPT;
                    state      <= STATE_TRAP;
                end else begin
                    state <= STATE_IF;
                end
                `else
                state <= STATE_IF;
                `endif
            end

            STATE_TRAP: begin
                // test_cpu_reg    <= 6'b001111;
                `ifdef LOG_CPU `WARN("rv_cpu", ("/TRAP/")); `endif
                // Handle Exception
                `ifdef SUPPORT_ZICSR
                case(trap_state)
                    STORE_PC: begin
                        csr_reg_addr     <= `CSR_MEPC;
                        csr_reg_wdata    <= pc + 32'h4;
                        csr_reg_write_en <= 1'b1;
                        trap_state       <= STORE_CAUSE;
                    end
                    STORE_CAUSE: begin
                        csr_reg_addr     <= `CSR_MCAUSE;
                        case(trap_cause)
                            TRAP_I_MISALIGNED: csr_reg_wdata <= {XLEN{1'b0}} + 'h0;
                            TRAP_INSTRUCTION:  csr_reg_wdata <= {XLEN{1'b0}} + 'h2;
                            TRAP_EBREAK:       csr_reg_wdata <= {XLEN{1'b0}} + 'h3;
                            TRAP_L_MISALIGNED: csr_reg_wdata <= {XLEN{1'b0}} + 'h5;
                            TRAP_S_MISALIGNED: csr_reg_wdata <= {XLEN{1'b0}} + 'h6;
                            TRAP_ECALL:        csr_reg_wdata <= {XLEN{1'b0}} + 'hB;
                            TRAP_HALT:         csr_reg_wdata <= {XLEN{1'b0}} + 'h100;     // Custom
                            TRAP_INTERRUPT:    csr_reg_wdata <= {1'b1, {(XLEN-1){1'b0}}} + 'h3;
                            TRAP_UNSUPPORTED:  csr_reg_wdata <= {1'b0, {(XLEN-1){1'b1}}}; // Custom
                            TRAP_UNKNOWN:      csr_reg_wdata <= {1'b0, {(XLEN-1){1'b1}}}; // Custom
                            default:           csr_reg_wdata <= {1'b0, {(XLEN-1){1'b1}}}; // Custom
                        endcase
                        csr_reg_write_en <= 1'b1;
                        trap_state       <= CONTINUE;
                    end
                    CONTINUE: begin
                        // Reset for next trap
                        csr_reg_write_en <= 1'b0;
                        trap_state <= STORE_PC;

                        // Set PC to csr_mtvec CSR (trap vector)
                        if (csr_mtvec[1:0] == 2'b00) begin
                            // Direct mode
                            pc    <= csr_mtvec & ~(32'h3);
                            `ifdef LOG_CPU `LOG("rv_cpu", ("TRAP PC updated to 0x%0h", csr_mtvec & ~(32'h3))); `endif
                            state <= STATE_IF;
                        end else if (csr_mtvec[1:0] == 2'b01) begin
                            // Vector mode
                            pc    <= (csr_mtvec & ~(32'h3)) + (csr_mcause << 2);
                            `ifdef LOG_CPU `LOG("rv_cpu", ("TRAP PC updated to 0x%0h", (csr_mtvec & ~(32'h3)) + (csr_mcause << 2))); `endif
                            state <= STATE_IF;
                        end else begin
                            // Unsupported mode, force reset
                            state <= STATE_RESET;
                        end
                    end
                    default: state <= STATE_RESET;
                endcase
                `else
                // If Zicsr not supported, reset the CPU
                trap_reg <= 1'b1;
                state    <= STATE_RESET;
                `endif
            end

            default: begin
                `ifdef LOG_CPU `ERROR("rv_cpu", ("DEFAULT STATE SHOULD NOT HAPPEN")); `endif
                state <= STATE_RESET;
            end
        endcase
    end
end

`ifdef LOG_CPU_CLOCKED
// Debug memory reads
always_ff @(posedge clk) begin
    `LOG("rv_cpu", ("/CLK/ mem_ready=%0d mem_address=%0h mem_read=%0d mem_valid=%0d, mem_rdata=0x%0h mem_wdata=0x%0h", mem_ready, mem_address, mem_read, mem_valid, mem_rdata, mem_wdata));
    `LOG("rv_cpu", ("/CLK/ alu_operand_a=%0h alu_operand_b=%0h alu_result=%0h", alu_operand_a, alu_operand_b, alu_result));
end
`endif

endmodule
