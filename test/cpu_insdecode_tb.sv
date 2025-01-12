`default_nettype none
`timescale 1ns / 1ps

`include "src/cpu_insdecode.sv"

module cpu_insdecode_tb;

    // Testbench Signals
    logic [31:0] instr;
    logic [6:0]  opcode;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [6:0]  funct7;
    logic [31:0] imm;

    logic [6:0]  opcode64;
    logic [4:0]  rd64;
    logic [2:0]  funct364;
    logic [4:0]  rs164;
    logic [4:0]  rs264;
    logic [6:0]  funct764;
    logic [63:0] imm64;

    // Control Signals
    logic        is_mem;
    logic        is_op_imm;
    logic        is_op;
    logic        is_lui;
    logic        is_auipc;
    logic        is_branch;
    logic        is_jal;
    logic        is_jalr;
    `ifdef SUPPORT_ZICSR
    logic        is_system;
    `endif
    `ifdef SUPPORT_ZIFENCEI
    logic        is_fence;
    `endif
    `ifdef SUPPORT_M
    logic        is_mul_div;
    `endif
    `ifdef SUPPORT_F
    logic        is_fpu;
    `endif

    logic        is_mem64;
    logic        is_op_imm64;
    logic        is_op64;
    logic        is_lui64;
    logic        is_auipc64;
    logic        is_branch64;
    logic        is_jal64;
    logic        is_jalr64;
    `ifdef SUPPORT_ZICSR
    logic        is_system64;
    `endif
    `ifdef SUPPORT_ZIFENCEI
    logic        is_fence64;
    `endif
    `ifdef SUPPORT_M
    logic        is_mul_div64;
    `endif
    `ifdef SUPPORT_F
    logic        is_fpu64;
    `endif

    // Instantiate the Instruction Decoder
    cpu_insdecode uut32 (
        .instr    (instr),
        .opcode   (opcode),
        .rd       (rd),
        .funct3   (funct3),
        .rs1      (rs1),
        .rs2      (rs2),
        .funct7   (funct7),
        .imm      (imm),
        .is_mem   (is_mem),
        .is_op_imm(is_op_imm),
        .is_op    (is_op),
        .is_lui   (is_lui),
        .is_auipc (is_auipc),
        .is_branch(is_branch),
        .is_jal   (is_jal),
        .is_jalr  (is_jalr)
        `ifdef SUPPORT_ZICSR
        ,
        .is_system(is_system)
        `endif
        `ifdef SUPPORT_ZIFENCEI
        ,
        .is_fence (is_fence)
        `endif
        `ifdef SUPPORT_M
        ,
        .is_mul_div(is_mul_div)
        `endif
        `ifdef SUPPORT_F
        ,
        .is_fpu (is_fpu)
        `endif
    );

    // Instantiate the 64bit Instruction Decoder
    cpu_insdecode #(.XLEN(64)) uut64 (
        .instr    (instr),
        .opcode   (opcode64),
        .rd       (rd64),
        .funct3   (funct364),
        .rs1      (rs164),
        .rs2      (rs264),
        .funct7   (funct764),
        .imm      (imm64),
        .is_mem   (is_mem64),
        .is_op_imm(is_op_imm64),
        .is_op    (is_op64),
        .is_lui   (is_lui64),
        .is_auipc (is_auipc64),
        .is_branch(is_branch64),
        .is_jal   (is_jal64),
        .is_jalr  (is_jalr64)
        `ifdef SUPPORT_ZICSR
        ,
        .is_system(is_system64)
        `endif
        `ifdef SUPPORT_ZIFENCEI
        ,
        .is_fence (is_fence64)
        `endif
        `ifdef SUPPORT_M
        ,
        .is_mul_div(is_mul_div64)
        `endif
        `ifdef SUPPORT_F
        ,
        .is_fpu (is_fpu64)
        `endif
    );

    // Test Counters
    integer testCount = 0;
    integer testCountPass = 0;
    integer testCountFail = 0;

    // Test Macros
    `define EXPECT(desc, a, b) \
        if (a === b) begin \
            $display("  == PASS == %s (Value: 0x%h)", desc, a); \
            testCountPass = testCountPass + 1; \
        end else begin \
            $display("  == FAIL == %s (Expected: 0x%h, Got: 0x%h)", desc, b, a); \
            testCountFail = testCountFail + 1; \
        end

    // R-Type Test Macro
    // Checks: opcode, rd, funct3, rs1, rs2, funct7, is_op=1, all others=0, imm=0
    `define TEST_R(desc, instr_val, opcode_val, rd_val, funct3_val, rs1_val, rs2_val, funct7_val) \
        testCount = testCount + 1; \
        $display("\n[cpu_insdecode] Test %0d: %s", testCount, desc); \
        instr = instr_val; \
        #10; \
        `EXPECT("Opcode", opcode, opcode_val); \
        `EXPECT("rd", rd, rd_val); \
        `EXPECT("funct3", funct3, funct3_val); \
        `EXPECT("rs1", rs1, rs1_val); \
        `EXPECT("rs2", rs2, rs2_val); \
        `EXPECT("funct7", funct7, funct7_val); \
        `EXPECT("is_op should be 1", is_op, 1'b1); \
        `EXPECT("is_mem should be 0", is_mem, 1'b0); \
        `EXPECT("is_op_imm should be 0", is_op_imm, 1'b0); \
        `EXPECT("is_lui should be 0", is_lui, 1'b0); \
        `EXPECT("is_auipc should be 0", is_auipc, 1'b0); \
        `EXPECT("is_branch should be 0", is_branch, 1'b0); \
        `EXPECT("is_jal should be 0", is_jal, 1'b0); \
        `EXPECT("is_jalr should be 0", is_jalr, 1'b0); \
        `EXPECT("imm (32bit) should be 0", imm, 32'b0); \
        `EXPECT("imm (64bit) should be 0", imm64, 64'b0);

    // I-Type Test Macro
    // Checks: opcode, rd, funct3, rs1, imm, is_op_imm or is_mem or is_jalr (only one set), no rs2/funct7 check
    `define TEST_I(desc, instr_val, opcode_val, rd_val, funct3_val, rs1_val, is_op_imm_val, is_mem_val, is_jalr_val, imm_val, imm64_val) \
        testCount = testCount + 1; \
        $display("\n[cpu_insdecode] Test %0d: %s", testCount, desc); \
        instr = instr_val; \
        #10; \
        `EXPECT("Opcode", opcode, opcode_val); \
        `EXPECT("rd", rd, rd_val); \
        `EXPECT("funct3", funct3, funct3_val); \
        `EXPECT("rs1", rs1, rs1_val); \
        /* No rs2 or funct7 expected for I-type. They are irrelevant. */ \
        `EXPECT("is_op_imm", is_op_imm, is_op_imm_val); \
        `EXPECT("is_mem", is_mem, is_mem_val); \
        `EXPECT("is_jalr", is_jalr, is_jalr_val); \
        `EXPECT("is_op should be 0", is_op, 1'b0); \
        `EXPECT("is_lui should be 0", is_lui, 1'b0); \
        `EXPECT("is_auipc should be 0", is_auipc, 1'b0); \
        `EXPECT("is_branch should be 0", is_branch, 1'b0); \
        `EXPECT("is_jal should be 0", is_jal, 1'b0); \
        `EXPECT("32bit Immediate", imm, imm_val); \
        `EXPECT("64bit Immediate", imm64, imm64_val);

    // RV64-Specific I-Type Test Macro
    `define TEST_RV64_I(desc, instr_val, opcode_val, rd_val, funct3_val, rs1_val, is_op_imm_val, is_mem_val, is_jalr_val, imm_val, imm64_val) \
        testCount = testCount + 1; \
        $display("\n[cpu_insdecode] Test %0d: %s (RV64)", testCount, desc); \
        instr = instr_val; \
        #10; \
        `EXPECT("Opcode", opcode64, opcode_val); \
        `EXPECT("rd", rd64, rd_val); \
        `EXPECT("funct3", funct364, funct3_val); \
        `EXPECT("rs1", rs164, rs1_val); \
        `EXPECT("is_op_imm", is_op_imm64, is_op_imm_val); \
        `EXPECT("ismem", is_mem64, is_mem_val); \
        `EXPECT("is_jalr", is_jalr64, is_jalr_val); \
        `EXPECT("is_op64 should be 0", is_op64, 1'b0); \
        `EXPECT("is_lui64 should be 0", is_lui64, 1'b0); \
        `EXPECT("is_auipc64 should be 0", is_auipc64, 1'b0); \
        `EXPECT("is_branch64 should be 0", is_branch64, 1'b0); \
        `EXPECT("is_jal64 should be 0", is_jal64, 1'b0); \
        `EXPECT("is_jalr64 should be 0", is_jalr64, 1'b0); \
        `EXPECT("imm (32bit)", imm64[31:0], imm_val); \
        `EXPECT("imm (64bit)", imm64, imm64_val);

    // S-Type Test Macro
    // Checks: opcode, rs1, rs2, funct3, imm, is_mem=1, no rd/funct7 relevant
    `define TEST_S(desc, instr_val, opcode_val, funct3_val, rs1_val, rs2_val, imm_val, imm64_val) \
        testCount = testCount + 1; \
        $display("\n[cpu_insdecode] Test %0d: %s", testCount, desc); \
        instr = instr_val; \
        #10; \
        `EXPECT("Opcode", opcode, opcode_val); \
        `EXPECT("funct3", funct3, funct3_val); \
        `EXPECT("rs1", rs1, rs1_val); \
        `EXPECT("rs2", rs2, rs2_val); \
        /* rd, funct7 irrelevant for S-type */ \
        `EXPECT("is_mem should be 1", is_mem, 1'b1); \
        `EXPECT("is_op should be 0", is_op, 1'b0); \
        `EXPECT("is_op_imm should be 0", is_op_imm, 1'b0); \
        `EXPECT("is_lui should be 0", is_lui, 1'b0); \
        `EXPECT("is_auipc should be 0", is_auipc, 1'b0); \
        `EXPECT("is_branch should be 0", is_branch, 1'b0); \
        `EXPECT("is_jal should be 0", is_jal, 1'b0); \
        `EXPECT("is_jalr should be 0", is_jalr, 1'b0); \
        `EXPECT("32bit Immediate", imm, imm_val); \
        `EXPECT("64bit Immediate", imm64, imm64_val);

    // B-Type Test Macro
    // Checks: opcode, rs1, rs2, funct3, imm, is_branch=1, no rd/funct7 relevant
    `define TEST_B(desc, instr_val, opcode_val, funct3_val, rs1_val, rs2_val, imm_val, imm64_val) \
        testCount = testCount + 1; \
        $display("\n[cpu_insdecode] Test %0d: %s", testCount, desc); \
        instr = instr_val; \
        #10; \
        `EXPECT("Opcode", opcode, opcode_val); \
        `EXPECT("funct3", funct3, funct3_val); \
        `EXPECT("rs1", rs1, rs1_val); \
        `EXPECT("rs2", rs2, rs2_val); \
        `EXPECT("is_branch should be 1", is_branch, 1'b1); \
        `EXPECT("is_mem should be 0", is_mem, 1'b0); \
        `EXPECT("is_op should be 0", is_op, 1'b0); \
        `EXPECT("is_op_imm should be 0", is_op_imm, 1'b0); \
        `EXPECT("is_lui should be 0", is_lui, 1'b0); \
        `EXPECT("is_auipc should be 0", is_auipc, 1'b0); \
        `EXPECT("is_jal should be 0", is_jal, 1'b0); \
        `EXPECT("is_jalr should be 0", is_jalr, 1'b0); \
        `EXPECT("32bit Immediate", imm, imm_val); \
        `EXPECT("64bit Immediate", imm64, imm64_val);

    // U-Type Test Macro
    // Checks: opcode, rd, imm, is_lui or is_auipc=1, no rs1/rs2/funct3/funct7 relevant
    `define TEST_U(desc, instr_val, opcode_val, rd_val, is_lui_val, is_auipc_val, imm_val, imm64_val) \
        testCount = testCount + 1; \
        $display("\n[cpu_insdecode] Test %0d: %s", testCount, desc); \
        instr = instr_val; \
        #10; \
        `EXPECT("Opcode", opcode, opcode_val); \
        `EXPECT("rd", rd, rd_val); \
        `EXPECT("is_lui", is_lui, is_lui_val); \
        `EXPECT("is_auipc", is_auipc, is_auipc_val); \
        `EXPECT("is_op should be 0", is_op, 1'b0); \
        `EXPECT("is_op_imm should be 0", is_op_imm, 1'b0); \
        `EXPECT("is_mem should be 0", is_mem, 1'b0); \
        `EXPECT("is_branch should be 0", is_branch, 1'b0); \
        `EXPECT("is_jal should be 0", is_jal, 1'b0); \
        `EXPECT("is_jalr should be 0", is_jalr, 1'b0); \
        `EXPECT("imm (32bit)", imm, imm_val); \
        `EXPECT("imm (64bit)", imm64, imm64_val);

    // J-Type Test Macro
    // Checks: opcode, rd, imm, is_jal=1, no rs1/rs2/funct3/funct7 relevant
    `define TEST_J(desc, instr_val, opcode_val, rd_val, imm_val, imm64_val) \
        testCount = testCount + 1; \
        $display("\n[cpu_insdecode] Test %0d: %s", testCount, desc); \
        instr = instr_val; \
        #10; \
        `EXPECT("Opcode", opcode, opcode_val); \
        `EXPECT("rd", rd, rd_val); \
        `EXPECT("is_jal should be 1", is_jal, 1'b1); \
        `EXPECT("is_lui should be 0", is_lui, 1'b0); \
        `EXPECT("is_auipc should be 0", is_auipc, 1'b0); \
        `EXPECT("is_mem should be 0", is_mem, 1'b0); \
        `EXPECT("is_branch should be 0", is_branch, 1'b0); \
        `EXPECT("is_op should be 0", is_op, 1'b0); \
        `EXPECT("is_op_imm should be 0", is_op_imm, 1'b0); \
        `EXPECT("is_jalr should be 0", is_jalr, 1'b0); \
        `EXPECT("imm (32bit)", imm, imm_val); \
        `EXPECT("imm (64bit)", imm64, imm64_val);
    
    `define FINISH \
        $display("\nTests Run:    %d", testCount); \
        $display("Cases Passed: %d", testCountPass); \
        $display("Cases Failed: %d", testCountFail); \
        if (testCountFail > 0) begin \
            $display("Stopping simulation due to failed tests."); \
            $stop; \
        end else begin \
            $display("All tests passed successfully."); \
            $finish; \
        end


    initial begin
        $dumpfile("cpu_insdecode_tb.vcd");
        $dumpvars(0, cpu_insdecode_tb);

        // Initialize Inputs
        instr = 32'h0000_0000;

        #10;

        //////////////////////////////////////////////////////////////
        // R-Type Instructions
        //////////////////////////////////////////////////////////////

        `TEST_R("Decode (ADD x3, x1, x2) instruction",
            ({7'b0000000, 5'b00010, 5'b00001, 3'b000, 5'd3, 7'b0110011}),
            7'b0110011, 5'd3, 3'b000, 5'b00001, 5'b00010, 7'b0000000)

        `TEST_R("Decode (SUB x4, x1, x2) instruction",
            ({7'b0100000, 5'b00010, 5'b00001, 3'b000, 5'd4, 7'b0110011}),
            7'b0110011, 5'd4, 3'b000, 5'b00001, 5'b00010, 7'b0100000)

        `TEST_R("Decode (SLL x5, x1, x2) instruction",
            ({7'b0000000, 5'b00010, 5'b00001, 3'b001, 5'd5, 7'b0110011}),
            7'b0110011, 5'd5, 3'b001, 5'b00001, 5'b00010, 7'b0000000)

        `TEST_R("Decode (SLT x6, x1, x2) instruction",
            ({7'b0000000, 5'b00010, 5'b00001, 3'b010, 5'd6, 7'b0110011}),
            7'b0110011, 5'd6, 3'b010, 5'b00001, 5'b00010, 7'b0000000)

        `TEST_R("Decode (SLTU x7, x1, x2) instruction",
            ({7'b0000000, 5'b00010, 5'b00001, 3'b011, 5'b00111, 7'b0110011}),
            7'b0110011, 5'b00111, 3'b011, 5'b00001, 5'b00010, 7'b0000000)

        `TEST_R("Decode (XOR x8, x1, x2) instruction",
            ({7'b0000000, 5'b00010, 5'b00001, 3'b100, 5'b01000, 7'b0110011}),
            7'b0110011, 5'b01000, 3'b100, 5'b00001, 5'b00010, 7'b0000000)

        `TEST_R("Decode (SRL x9, x1, x2) instruction",
            ({7'b0000000, 5'b00010, 5'b00001, 3'b101, 5'b01001, 7'b0110011}),
            7'b0110011, 5'b01001, 3'b101, 5'b00001, 5'b00010, 7'b0000000)

        `TEST_R("Decode (SRA x10, x1, x2) instruction",
            ({7'b0100000, 5'b00010, 5'b00001, 3'b101, 5'd10, 7'b0110011}),
            7'b0110011, 5'd10, 3'b101, 5'b00001, 5'b00010, 7'b0100000)

        `TEST_R("Decode (OR x11, x1, x2) instruction",
            ({7'b0000000, 5'b00010, 5'b00001, 3'b110, 5'd11, 7'b0110011}),
            7'b0110011, 5'd11, 3'b110, 5'b00001, 5'b00010, 7'b0000000)

        `TEST_R("Decode (AND x12, x1, x2) instruction",
            ({7'b0000000, 5'b00010, 5'b00001, 3'b111, 5'd12, 7'b0110011}),
            7'b0110011, 5'd12, 3'b111, 5'b00001, 5'b00010, 7'b0000000)

        `TEST_R("Decode ADDW x1, x2, x3 instruction",
            {7'b0000000, 5'd3, 5'b00010, 3'b000, 5'b00001, 7'b0111011},
            7'b0111011, 5'b00001, 3'b000, 5'b00010, 5'd3, 7'b0000000)

        `TEST_R("Decode SUBW x4, x5, x6 instruction",
            {7'b0100000, 5'd6, 5'd5, 3'b000, 5'd4, 7'b0111011},
            7'b0111011, 5'd4, 3'b000, 5'd5, 5'd6, 7'b0100000)

        `TEST_R("Decode SLLW x7, x8, x9 instruction",
            {7'b0000000, 5'b01001, 5'b01000, 3'b001, 5'b00111, 7'b0111011},
            7'b0111011, 5'b00111, 3'b001, 5'b01000, 5'b01001, 7'b0000000)

        `TEST_R("Decode SRLW x10, x11, x12 instruction",
            {7'b0000000, 5'd12, 5'd11, 3'b101, 5'd10, 7'b0111011},
            7'b0111011, 5'd10, 3'b101, 5'd11, 5'd12, 7'b0000000)

        `TEST_R("Decode SRAW x13, x14, x15 instruction",
            {7'b0100000, 5'b01111, 5'b01110, 3'b101, 5'b01101, 7'b0111011},
            7'b0111011, 5'b01101, 3'b101, 5'd14, 5'd15, 7'b0100000)

        `TEST_R("Decode (ADD x0, x0, x0) instruction (NOP)",
            ({7'b0000000, 5'b00000, 5'b00000, 3'b000, 5'b00000, 7'b0110011}),
            7'b0110011, 5'b00000, 3'b000, 5'b00000, 5'b00000, 7'b0000000)


        //////////////////////////////////////////////////////////////
        // I-Type Instructions
        //////////////////////////////////////////////////////////////

        `TEST_I("Decode ADDI x13, x1, 5 instruction",
            {12'd5, 5'b00001, 3'b000, 5'b01101, 7'b0010011},
            7'b0010011, 5'b01101, 3'b000, 5'b00001, 1'b1, 1'b0, 1'b0, 32'd5, 64'd5)

        `TEST_I("Decode ADDI x0, x0, 0 instruction (NOP)",
            {12'd0, 5'b00000, 3'b000, 5'b00000, 7'b0010011},
            7'b0010011, 5'b00000, 3'b000, 5'b00000, 1'b1, 1'b0, 1'b0, 32'd0, 64'd0)

        `TEST_I("Decode ADDI x1, x0, 2047 (max immediate)",
            {12'h7FF, 5'b00000, 3'b000, 5'b00001, 7'b0010011},
            7'b0010011, 5'b00001, 3'b000, 5'b00000, 1'b1, 1'b0, 1'b0, 32'd2047, 64'd2047)

        `TEST_I("Decode ADDI x1, x0, -2048 (min immediate)",
            {12'h800, 5'b00000, 3'b000, 5'b00001, 7'b0010011},
            7'b0010011, 5'b00001, 3'b000, 5'b00000, 1'b1, 1'b0, 1'b0, 32'hFFFFF800, 64'hFFFFFFFFFFFFF800)

        `TEST_I("Decode SLTI x14, x1, -3 instruction",
            {12'b111111111101, 5'b00001, 3'b010, 5'd14, 7'b0010011},
            7'b0010011, 5'd14, 3'b010, 5'b00001, 1'b1, 1'b0, 1'b0, 32'hFFFFFFFD, 64'hFFFFFFFFFFFFFFFD)

        `TEST_I("Decode XORI x15, x1, 255 instruction",
            {12'h0FF, 5'b00001, 3'b100, 5'd15, 7'b0010011},
            7'b0010011, 5'd15, 3'b100, 5'b00001, 1'b1, 1'b0, 1'b0, 32'd255, 64'd255)

        `TEST_I("Decode ORI x16, x1, 26 instruction",
            {12'h01A, 5'b00001, 3'b110, 5'd16, 7'b0010011},
            7'b0010011, 5'd16, 3'b110, 5'b00001, 1'b1, 1'b0, 1'b0, 32'd26, 64'd26)

        `TEST_I("Decode ANDI x17, x1, 15 instruction",
            {12'h00F, 5'b00001, 3'b111, 5'd17, 7'b0010011},
            7'b0010011, 5'd17, 3'b111, 5'b00001, 1'b1, 1'b0, 1'b0, 32'd15, 64'd15)

        `TEST_I("Decode SLLI x18, x1, 3 instruction",
            {7'b0000000, 5'd3, 5'b00001, 3'b001, 5'd18, 7'b0010011},
            7'b0010011, 5'd18, 3'b001, 5'b00001, 1'b1, 1'b0, 1'b0, 32'd3, 64'd3)

        `TEST_I("Decode SRLI x19, x1, 4 instruction",
            {7'b0000000, 5'd4, 5'b00001, 3'b101, 5'd19, 7'b0010011},
            7'b0010011, 5'd19, 3'b101, 5'b00001, 1'b1, 1'b0, 1'b0, 32'd4, 64'd4)

        `TEST_I("Decode SRAI x20, x1, 5 instruction",
            {7'b0100000, 5'd5, 5'b00001, 3'b101, 5'd20, 7'b0010011},
            7'b0010011, 5'd20, 3'b101, 5'b00001, 1'b1, 1'b0, 1'b0, 32'd5, 64'd5)

        `TEST_I("Decode LB x21, -8(x1) instruction",
            {12'b111111111000, 5'b00001, 3'b000, 5'd21, 7'b0000011},
            7'b0000011, 5'd21, 3'b000, 5'b00001, 1'b0, 1'b1, 1'b0, 32'hFFFFFFF8, 64'hFFFFFFFFFFFFFFF8)

        `TEST_I("Decode LH x22, 16(x1) instruction",
            {12'd16, 5'b00001, 3'b001, 5'd22, 7'b0000011},
            7'b0000011, 5'd22, 3'b001, 5'b00001, 1'b0, 1'b1, 1'b0, 32'd16, 64'd16)

        `TEST_I("Decode LW x23, 32(x1) instruction",
            {12'd32, 5'b00001, 3'b010, 5'd23, 7'b0000011},
            7'b0000011, 5'd23, 3'b010, 5'b00001, 1'b0, 1'b1, 1'b0, 32'd32, 64'd32)

        `TEST_I("Decode LBU x24, 8(x1) instruction",
            {12'd8, 5'b00001, 3'b100, 5'd24, 7'b0000011},
            7'b0000011, 5'd24, 3'b100, 5'b00001, 1'b0, 1'b1, 1'b0, 32'd8, 64'd8)

        `TEST_I("Decode LHU x25, 24(x1) instruction",
            {12'd24, 5'b00001, 3'b101, 5'd25, 7'b0000011},
            7'b0000011, 5'd25, 3'b101, 5'b00001, 1'b0, 1'b1, 1'b0, 32'd24, 64'd24)

        `TEST_I("Decode JALR x1, x2, -20 instruction",
            {12'hFEC, 5'b00010, 3'b000, 5'b00001, 7'b1100111},
            7'b1100111, 5'b00001, 3'b000, 5'b00010, 1'b0, 1'b0, 1'b1, 32'hFFFFFFEC, 64'hFFFFFFFFFFFFFFEC)

        `TEST_RV64_I("Decode ADDIW x1, x2, 10 instruction",
            {12'd10, 5'b00010, 3'b000, 5'b00001, 7'b0011011},
            7'b0011011, 5'b00001, 3'b000, 5'b00010, 1'b1, 1'b0, 1'b0, 32'h0000000A, 64'h000000000000000A)

        `TEST_RV64_I("Decode SLLIW x3, x4, 3 instruction",
            {7'b0000000, 5'd3, 5'd4, 3'b001, 5'd3, 7'b0011011},
            7'b0011011, 5'd3, 3'b001, 5'd4, 1'b1, 1'b0, 1'b0, 32'h00000003, 64'h0000000000000003)

        `TEST_RV64_I("Decode SRLIW x5, x6, 4 instruction",
            {7'b0000000, 5'd4, 5'd6, 3'b101, 5'd5, 7'b0011011},
            7'b0011011, 5'd5, 3'b101, 5'd6, 1'b1, 1'b0, 1'b0, 32'h00000004, 64'h0000000000000004)

        `TEST_RV64_I("Decode SRAIW x7, x8, 5 instruction",
            {7'b0100000, 5'd5, 5'b01000, 3'b101, 5'b00111, 7'b0011011},
            7'b0011011, 5'b00111, 3'b101, 5'b01000, 1'b1, 1'b0, 1'b0, 32'h00000005, 64'h0000000000000005)

        `TEST_RV64_I("Decode LWU x1, 8(x2) instruction",
            {12'd8, 5'b00010, 3'b110, 5'b00001, 7'b0000011},
            7'b0000011, 5'b00001, 3'b110, 5'b00010, 1'b0, 1'b1, 1'b0, 32'd8, 64'd8)

        `TEST_RV64_I("Decode LD x3, -16(x4) instruction",
            {12'hFF0, 5'd4, 3'b011, 5'd3, 7'b0000011},
            7'b0000011, 5'd3, 3'b011, 5'd4, 1'b0, 1'b1, 1'b0, 32'hFFFFFFF0, 64'hFFFFFFFFFFFFFFF0)


        //////////////////////////////////////////////////////////////
        // I-Type Instructions (STORE)
        //////////////////////////////////////////////////////////////
        `TEST_S("Decode SB x1, -4(x1) instruction",
            {7'b1111111, 5'b00001, 5'b00001, 3'b000, 5'b11100, 7'b0100011},
            7'b0100011, 3'b000, 5'b00001, 5'b00001, 32'hFFFFFFFC, 64'hFFFFFFFFFFFFFFFC)

        `TEST_S("Decode SH x2, 20(x1) instruction",
            {7'b0000000, 5'b00010, 5'b00001, 3'b001, 5'b10100, 7'b0100011},
            7'b0100011, 3'b001, 5'b00001, 5'b00010, 32'd20, 64'd20)

        `TEST_S("Decode SW x3, 28(x1) instruction",
            {1'b0, 6'b000000, 5'd3, 5'b00001, 3'b010, 5'b11100, 7'b0100011},
            7'b0100011, 3'b010, 5'b00001, 5'd3, 32'd28, 64'd28)

        `TEST_S("Decode SD x5, 32(x6) instruction",
            {7'b0000001, 5'b00101, 5'b00110, 3'b011, 5'b00000, 7'b0100011},
            7'b0100011, 3'b011, 5'd6, 5'd5, 32'd32, 64'd32)

        `TEST_S("Decode SW x0, 0(x0) instruction",
            {7'b0000000, 5'b00000, 5'b00000, 3'b010, 5'b00000, 7'b0100011},
            7'b0100011, 3'b010, 5'b00000, 5'b00000, 32'd0, 64'd0)

        `TEST_S("Decode SW x0, -2048(x0) instruction",
            {7'b1000000, 5'b00000, 5'b00000, 3'b010, 5'b00000, 7'b0100011},
            7'b0100011, 3'b010, 5'b00000, 5'b00000, 32'hFFFFF800, 64'hFFFFFFFFFFFFF800)

        `TEST_S("Decode SW x0, 2047(x0) instruction",
            {7'b0111111, 5'b00000, 5'b00000, 3'b010, 5'b11111, 7'b0100011},
            7'b0100011, 3'b010, 5'b00000, 5'b00000, 32'd2047, 64'd2047)


        //////////////////////////////////////////////////////////////
        // B-Type Instructions
        //////////////////////////////////////////////////////////////
        `TEST_B("Decode BNE x3, x4, -12 instruction",
            {1'b1, 6'b111111, 5'b00100, 5'b00011, 3'b001, 4'b1010, 1'b1, 7'b1100011},
            7'b1100011, 3'b001, 5'd3, 5'd4, 32'hFFFFFFF4, 64'hFFFFFFFFFFFFFFF4)

        `TEST_B("Decode BLT x5, x6, 8 instruction",
            {1'b0, 6'b000000, 5'b00110, 5'b00101, 3'b100, 4'b0100, 1'b0, 7'b1100011},
            7'b1100011, 3'b100, 5'd5, 5'd6, 32'd8, 64'd8)

        `TEST_B("Decode BGE x7, x8, -16 instruction",
            {1'b1, 6'b111111, 5'b01000, 5'b00111, 3'b101, 4'b1000, 1'b1, 7'b1100011},
            7'b1100011, 3'b101, 5'b00111, 5'b01000, 32'hFFFFFFF0, 64'hFFFFFFFFFFFFFFF0)

        `TEST_B("Decode BLTU x9, x10, 12 instruction",
            {1'b0, 6'b000000, 5'b01010, 5'b01001, 3'b110, 4'b0110, 1'b0, 7'b1100011},
            7'b1100011, 3'b110, 5'b01001, 5'd10, 32'd12, 64'd12)

        `TEST_B("Decode BGEU x11, x12, -20 instruction",
            {1'b1, 6'b111111, 5'b01100, 5'b01011, 3'b111, 4'b0110, 1'b1, 7'b1100011},
            7'b1100011, 3'b111, 5'd11, 5'd12, 32'hFFFFFFEC, 64'hFFFFFFFFFFFFFFEC)

        `TEST_B("Decode BEQ x1, x2, -12 instruction",
            {1'b1, 6'b111111, 5'b00010, 5'b00001, 3'b000, 4'b1010, 1'b1, 7'b1100011},
            7'b1100011, 3'b000, 5'b00001, 5'b00010, 32'hFFFFFFF4, 64'hFFFFFFFFFFFFFFF4)

        `TEST_B("Decode BEQ x0, x0, 0 instruction (infinite loop)",
            {1'b0, 6'b000000, 5'b00000, 5'b00000, 3'b000, 4'b0000, 1'b0, 7'b1100011},
            7'b1100011, 3'b000, 5'b00000, 5'b00000, 32'd0, 64'd0)

        `TEST_B("Decode BEQ x0, x0, 4092 instruction",
            {1'b0, 6'b111111, 5'b00000, 5'b00000, 3'b000, 4'b1110, 1'b1, 7'b1100011},
            7'b1100011, 3'b000, 5'b00000, 5'b00000, 32'd4092, 64'd4092)

        `TEST_B("Decode BEQ x0, x0, -4092 instruction",
            {1'b1, 6'b000000, 5'b00000, 5'b00000, 3'b000, 4'b0010, 1'b0, 7'b1100011},
            7'b1100011, 3'b000, 5'b00000, 5'b00000, 32'hFFFFF004, 64'hFFFFFFFFFFFFF004)


        //////////////////////////////////////////////////////////////
        // U-Type Instructions
        //////////////////////////////////////////////////////////////
        `TEST_U("Decode LUI x13, 0xABC000 instruction",
            {20'hABC, 5'b01101, 7'b0110111},
            7'b0110111, 5'b01101, 1'b1, 1'b0, {20'hABC, 12'd0}, 64'h0000000000ABC000)

        `TEST_U("Decode AUIPC x14, 0x123000 instruction",
            {20'h123, 5'd14, 7'b0010111},
            7'b0010111, 5'd14, 1'b0, 1'b1, {20'h123, 12'd0}, 64'h0000000000123000)

        `TEST_U("Decode LUI x0, 0 instruction",
            {20'd0, 5'b00000, 7'b0110111},
            7'b0110111, 5'b00000, 1'b1, 1'b0, 32'd0, 64'd0)

        `TEST_U("Decode AUIPC x0, 0 instruction",
            {20'd0, 5'b00000, 7'b0010111},
            7'b0010111, 5'b00000, 1'b0, 1'b1, 32'd0, 64'd0)

        `TEST_U("Decode LUI x31, 0xFFFFF00000 instruction",
            {20'hFFFFF, 5'd31, 7'b0110111},
            7'b0110111, 5'd31, 1'b1, 1'b0, 32'hFFFFF000, 64'hFFFFFFFFFFFFF000)

        `TEST_U("Decode AUIPC x31, 0xFFFFF00000 instruction",
            {20'b11111111111111111111, 5'b11111, 7'b0010111},
            7'b0010111, 5'd31, 1'b0, 1'b1, 32'hFFFFF000, 64'hFFFFFFFFFFFFF000)


        //////////////////////////////////////////////////////////////
        // J-Type Instructions
        //////////////////////////////////////////////////////////////
        `TEST_J("Decode JAL x15, 100 instruction",
            {1'b0, 10'd50, 1'b0, 8'd0, 5'd15, 7'b1101111},
            7'b1101111, 5'd15, 32'd100, 64'd100)

        `TEST_J("Decode JAL x0, 0 instruction",
            {1'b0, 8'b00000000, 1'b0, 10'b0000000000, 5'b00000, 7'b1101111},
            7'b1101111, 5'b00000, 32'd0, 64'd0)

        `TEST_J("Decode JAL x31, 0xFFFFF00000 instruction",
            {1'b1, 8'b00000000, 1'b0, 10'b0000000000, 5'b11111, 7'b1101111},
            7'b1101111, 5'd31, 32'hFFF00000, 64'hFFFFFFFFFFF00000)

        //////////////////////////////////////////////////////////////
        // System Instructions (if SUPPORT_ZICSR)
        //////////////////////////////////////////////////////////////
        `ifdef SUPPORT_ZICSR
        `TEST_I("Decode ECALL instruction",
            {12'd0, 5'b00000, 3'b000, 5'b00000, 7'b1110011},
            7'b1110011, 5'b00000, 3'b000, 5'b00000, 1'b0, 1'b0, 1'b0, 32'd0, 64'd0)

        `TEST_I("Decode EBREAK instruction",
            {12'd1, 5'b00000, 3'b000, 5'b00000, 7'b1110011},
            7'b1110011, 5'b00000, 3'b000, 5'b00000, 1'b0, 1'b0, 1'b0, 32'd1, 64'd1)
        `endif


        //////////////////////////////////////////////////////////////
        // FENCE Instructions (if SUPPORT_ZIFENCEI)
        //////////////////////////////////////////////////////////////
        `ifdef SUPPORT_ZIFENCEI
        `TEST_I("Decode FENCE instruction",
            {12'd0, 5'b00000, 3'b000, 5'b00000, 7'b0001111},
            7'b0001111, 5'b00000, 3'b000, 5'b00000, 1'b0, 1'b0, 1'b0, 32'd0, 64'd0)

        `TEST_I("Decode FENCE.I instruction",
            {12'd1, 5'b00000, 3'b001, 5'b00000, 7'b0001111},
            7'b0001111, 5'b00000, 3'b001, 5'b00000, 1'b0, 1'b0, 1'b0, 32'd1, 64'd1)
        `endif

        //////////////////////////////////////////////////////////////
        // M-Type Instructions (if SUPPORT_M)
        //////////////////////////////////////////////////////////////
        `ifdef SUPPORT_M

        `TEST_R("Decode MUL x1, x2, x3 instruction",
            {7'b0000001, 5'd3, 5'b00010, 3'b000, 5'b00001, 7'b0110011},
            7'b0110011, 5'b00001, 3'b000, 5'b00010, 5'd3, 7'b0000001)

        `TEST_R("Decode MULH x4, x5, x6 instruction",
            {7'b0000001, 5'd6, 5'd5, 3'b001, 5'd4, 7'b0110011},
            7'b0110011, 5'd4, 3'b001, 5'd5, 5'd6, 7'b0000001)

        `TEST_R("Decode MULHSU x7, x8, x9 instruction",
            {7'b0000001, 5'b01001, 5'b01000, 3'b010, 5'b00111, 7'b0110011},
            7'b0110011, 5'b00111, 3'b010, 5'b01000, 5'b01001, 7'b0000001)

        `TEST_R("Decode MULHU x10, x11, x12 instruction",
            {7'b0000001, 5'd12, 5'd11, 3'b011, 5'd10, 7'b0110011},
            7'b0110011, 5'd10, 3'b011, 5'd11, 5'd12, 7'b0000001)

        `TEST_R("Decode DIV x13, x14, x15 instruction",
            {7'b0000001, 5'd15, 5'd14, 3'b100, 5'b01101, 7'b0110011},
            7'b0110011, 5'b01101, 3'b100, 5'd14, 5'd15, 7'b0000001)

        `TEST_R("Decode DIVU x16, x17, x18 instruction",
            {7'b0000001, 5'b10010, 5'b10001, 3'b101, 5'b10000, 7'b0110011},
            7'b0110011, 5'd16, 3'b101, 5'd17, 5'd18, 7'b0000001)

        `TEST_R("Decode REM x19, x20, x21 instruction",
            {7'b0000001, 5'd21, 5'd20, 3'b110, 5'd19, 7'b0110011},
            7'b0110011, 5'd19, 3'b110, 5'd20, 5'd21, 7'b0000001)

        `TEST_R("Decode REMU x22, x23, x24 instruction",
            {7'b0000001, 5'd24, 5'd23, 3'b111, 5'd22, 7'b0110011},
            7'b0110011, 5'd22, 3'b111, 5'd23, 5'd24, 7'b0000001)

        `endif

        //////////////////////////////////////////////////////////////
        // Finalizing Testbench
        //////////////////////////////////////////////////////////////

        `FINISH;
    end

endmodule
