`default_nettype none
`timescale 1ns / 1ps

`ifndef XLEN
`define XLEN 32
`endif

`include "src/cpu_csr.sv"


module cpu_csr_tb;

    // Parameters
    localparam XLEN      = `XLEN;
    localparam NMI_COUNT = 4;
    localparam IRQ_COUNT = 4;

    // Inputs (driven by testbench)
    logic                clk;
    logic                reset;

    // CSR Register Interface
    logic [11:0]         reg_addr;
    logic                reg_write_en;
    logic [XLEN-1:0]     reg_wdata;
    logic [XLEN-1:0]     reg_rdata;

    // CSR Operation Interface
    logic                op_valid;
    logic                op_ready;
    logic [2:0]          op_control;
    logic [11:0]         op_addr;
    logic [XLEN-1:0]     op_operand;
    logic [4:0]          op_imm;
    logic [XLEN-1:0]     op_rdata;
    logic                op_done;

    // Exposed Registers
    logic [XLEN-1:0]     mtvec;
    logic [XLEN-1:0]     mepc;
    logic [XLEN-1:0]     mcause;

    // Output Signals
    logic                interrupt_pending;

    // Interrupt Request Lines
    logic [IRQ_COUNT-1:0] irq;
    logic [NMI_COUNT-1:0] nmi;

    // DUT (Device Under Test) Instantiation
    cpu_csr #(
        .XLEN(XLEN),
        .NMI_COUNT(NMI_COUNT),
        .IRQ_COUNT(IRQ_COUNT),
        .MTVEC_RESET_VAL(0)
    ) uut (
        .clk                (clk),
        .reset              (reset),

        // CSR Register Interface
        .reg_addr           (reg_addr),
        .reg_write_en       (reg_write_en),
        .reg_wdata          (reg_wdata),
        .reg_rdata          (reg_rdata),

        // CSR Operation Interface
        .op_valid           (op_valid),   // Operation valid
        .op_ready           (op_ready),   // Operation ready
        .op_control         (op_control), // CSR operation control signals
        .op_addr            (op_addr),    // CSR address for Operation Interface
        .op_operand         (op_operand), // Operand for CSR operations
        .op_imm             (op_imm),     // Immediate for CSR operations
        .op_rdata           (op_rdata),   // Read data from Operation Interface
        .op_done            (op_done),    // Operation done signal

        // Exposed Registers
        .mtvec              (mtvec),
        .mepc               (mepc),
        .mcause             (mcause),

        // Output Signals
        .interrupt_pending  (interrupt_pending),

        // Interrupt Request Lines
        .irq                (irq),
        .nmi                (nmi)
    );

    //-----------------------------------------------------
    // Test Counters
    //-----------------------------------------------------
    integer testCount      = 0;
    integer testCountPass  = 0;
    integer testCountFail  = 0;

    `define TEST(desc) \
        testCount = testCount + 1; \
        $display("\n[CSR] Test %0d: %s", testCount, desc);

    `define EXPECT(desc, actual, expected) \
        if (actual === expected) begin \
            $display("  == PASS == %s", desc); \
            testCountPass = testCountPass + 1; \
        end else begin \
            $display("  == FAIL == %s (Expected: 0x%h, Got: 0x%h)", desc, expected, actual); \
            testCountFail = testCountFail + 1; \
        end

    `define FINISH \
        begin \
            $display("\n===================================="); \
            $display("Total Tests Run:    %0d", testCount); \
            $display("Tests Passed:       %0d", testCountPass); \
            $display("Tests Failed:       %0d", testCountFail); \
            if (testCountFail > 0) begin \
                $display("== Some tests FAILED. ==============\n"); \
                $stop; \
            end else begin \
                $display("== All tests PASSED successfully. ==\n"); \
                $finish; \
            end \
        end

    //-----------------------------------------------------
    // Clock Generation
    //-----------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    //-----------------------------------------------------
    // Updated csr_operation Task Without op_done
    //-----------------------------------------------------
    task csr_operation;
        input [2:0]          ctrl;
        input [11:0]         csr_addr;
        input [XLEN-1:0]     op;
        input [4:0]          imm_val;
        output [XLEN-1:0]    old_value;
    begin
        wait (op_ready == 1'b1);

        // Apply operation signals
        op_control = ctrl;
        op_addr    = csr_addr;
        op_operand = op;
        op_imm     = imm_val;
        op_valid   = 1'b1;

        wait (op_done == 1'b1);

        // Capture old_value BEFORE the operation is applied
        old_value = op_rdata;

        // De-assert operation signals and return to Register Interface Mode
        op_valid   = 1'b0;
        op_control = 3'b000;
        op_addr    = 12'h000;
        op_operand = {XLEN{1'b0}};
        op_imm     = 5'b00000;
        @(posedge clk); // Ensure signals are de-asserted
    end
    endtask

    //-----------------------------------------------------
    // Helper Tasks for Register Interface Mode
    //-----------------------------------------------------
    task reg_write;
        input [11:0] csr_addr;
        input [XLEN-1:0] data;
    begin
        // Apply write signals
        reg_addr     = csr_addr;
        reg_wdata    = data;
        reg_write_en = 1'b1;
        @(posedge clk);
        reg_write_en = 1'b0;
        @(posedge clk);
    end
    endtask

    task reg_read;
        input [11:0] csr_addr;
        output [XLEN-1:0] data;
    begin
        // Apply read signals
        reg_addr = csr_addr;
        @(posedge clk);
        data = reg_rdata;
    end
    endtask

    //-----------------------------------------------------
    // Test Variables
    //-----------------------------------------------------
    logic [XLEN-1:0] initial_cycle;
    logic [XLEN-1:0] new_cycle;
    logic [XLEN-1:0] initial_cycle_high;
    logic [XLEN-1:0] new_cycle_high;
    logic [XLEN-1:0] old_val;

    //-----------------------------------------------------
    // Test Sequence
    //-----------------------------------------------------
    initial begin
        $dumpfile("cpu_csr_tb.vcd");
        $dumpvars(0, cpu_csr_tb);

        // Initialize Inputs
        reset        = 1;

        // Initialize Register Interface Signals
        reg_addr     = 12'h000;
        reg_write_en = 1'b0;
        reg_wdata    = {XLEN{1'b0}};

        // Initialize Operation Interface Signals
        op_valid     = 1'b0;
        op_control   = 3'b000;
        op_operand   = {XLEN{1'b0}};
        op_imm       = 5'b00000;
        op_addr      = 12'h000;

        // Initialize Interrupt Lines
        irq          = {IRQ_COUNT{1'b0}};
        nmi          = {NMI_COUNT{1'b0}};

        // De-assert reset after two clock cycles
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);

        //-------------------------------------------------
        // Test 1: Write and read mtvec via Register Interface
        //-------------------------------------------------
        `TEST("Write and read mtvec externally")
        reg_write(`CSR_MTVEC, 32'h12345678);
        // Read back mtvec
        reg_read(`CSR_MTVEC, initial_cycle);
        `EXPECT("mtvec=0x12345678", initial_cycle, 32'h12345678);

        //-------------------------------------------------
        // Test 2: Write and read mepc via Register Interface
        //-------------------------------------------------
        `TEST("Write and read mepc externally")
        reg_write(`CSR_MEPC, 32'h87654321);
        // Read back mepc
        reg_read(`CSR_MEPC, initial_cycle);
        `EXPECT("mepc=0x87654321", initial_cycle, 32'h87654321);

        //-------------------------------------------------
        // Test 3: Write and read mstatus via Register Interface with masking
        //-------------------------------------------------
        `TEST("Write and read mstatus externally with masking")
        reg_write(`CSR_MSTATUS, 32'hFFFF_FFFF);
        // Read back mstatus
        reg_read(`CSR_MSTATUS, initial_cycle);
        `EXPECT("mstatus=0x0000000B", initial_cycle, 32'h0000000B);

        //-------------------------------------------------
        // Test 4: Write and read mie via Register Interface
        //-------------------------------------------------
        `TEST("Write and read mie externally")
        reg_write(`CSR_MIE, 32'h000000FF);
        // Read back mie
        reg_read(`CSR_MIE, initial_cycle);
        `EXPECT("mie=0x000000FF", initial_cycle, 32'h000000FF);

        //-------------------------------------------------
        // Test 5: Write and read mcause via Register Interface
        //-------------------------------------------------
        `TEST("Write and read mcause externally")
        reg_write(`CSR_MCAUSE, 32'h000000AA);
        // Read back mcause
        reg_read(`CSR_MCAUSE, initial_cycle);
        `EXPECT("mcause=0x000000AA", initial_cycle, 32'h000000AA);

        //-------------------------------------------------
        // Test 6: Attempt to write to read-only mvendorid
        //-------------------------------------------------
        `TEST("Attempt to write to read-only mvendorid")
        reg_write(`CSR_MVENDORID, 32'hDEAD_BEEF);
        // Read back mvendorid
        reg_read(`CSR_MVENDORID, initial_cycle);
        `EXPECT("mvendorid=0x4A5A5256", initial_cycle, 32'h4A5A5256);

        //-------------------------------------------------
        // Test 7: Attempt to write to read-only marchid
        //-------------------------------------------------
        `TEST("Attempt to write to read-only marchid")
        reg_write(`CSR_MARCHID, 32'hBAAD_F00D);
        // Read back marchid
        reg_read(`CSR_MARCHID, initial_cycle);
        `EXPECT("marchid=0x00000000", initial_cycle, 32'h00000000);

        //-------------------------------------------------
        // Test 8: CSRRW - Read and write mtvec via Operation Interface
        //-------------------------------------------------
        `TEST("CSRRW: Read and write mtvec via CSR instruction")
        csr_operation(`CSR_RW, `CSR_MTVEC, 32'hAAAA_AAAA, 5'b0, old_val);
        `EXPECT("old mtvec=0x12345678", old_val, 32'h12345678);
        // Read back mtvec via Register Interface
        reg_read(`CSR_MTVEC, initial_cycle);
        `EXPECT("new mtvec=0xAAAA_AAAA", initial_cycle, 32'hAAAA_AAAA);

        //-------------------------------------------------
        // Test 9: CSRRS - Read and set bits in mie via Operation Interface
        //-------------------------------------------------
        `TEST("CSRRS: Read and set bits in mie via CSR instruction")
        csr_operation(`CSR_RS, `CSR_MIE, 32'h0000000F, 5'b0, old_val); // Set lower 4 bits
        `EXPECT("old mie=0x000000FF", old_val, 32'h000000FF);
        // Read back mie via Register Interface
        reg_read(`CSR_MIE, initial_cycle);
        `EXPECT("new mie=0x000000FF", initial_cycle, 32'h000000FF); // No change since lower 4 bits already set

        //-------------------------------------------------
        // Test 10: CSRRC - Read and clear bits in mie via Operation Interface
        //-------------------------------------------------
        `TEST("CSRRC: Read and clear bits in mie via CSR")
        csr_operation(`CSR_RC, `CSR_MIE, 32'h0000000F, 5'b0, old_val); // Clear lower 4 bits
        `EXPECT("old mie=0x000000FF", old_val, 32'h000000FF);
        // Read back mie via Register Interface
        reg_read(`CSR_MIE, initial_cycle);
        `EXPECT("new mie=0x000000F0", initial_cycle, 32'h000000F0);

        //-------------------------------------------------
        // Test 11: CSRRWI - Read and write immediate to mepc via Operation Interface
        //-------------------------------------------------
        `TEST("CSRRWI: Read and write immediate to mepc")
        csr_operation(`CSR_RWI, `CSR_MEPC, 32'h0, 5'b11111, old_val);
        `EXPECT("old mepc=0x87654321", old_val, 32'h87654321);
        // Read back mepc via Register Interface
        reg_read(`CSR_MEPC, initial_cycle);
        `EXPECT("new mepc=0x0000001F", initial_cycle, 32'h0000001F);

        //-------------------------------------------------
        // Test 12: CSRRSI - Read and clear bit1 in mstatus via Operation Interface
        //-------------------------------------------------
        `TEST("CSRRCI: Read and clear bit1 in mstatus")
        csr_operation(`CSR_RCI, `CSR_MSTATUS, 32'h0, 5'b00010, old_val); // Clear bit1
        `EXPECT("old mstatus=0x0000000B", old_val, 32'h0000000B); // Initial value
        // Read back mstatus via Register Interface
        reg_read(`CSR_MSTATUS, initial_cycle);
        `EXPECT("new mstatus=0x00000009 (bit 1 cleared)", initial_cycle, 32'h00000009);

        //-------------------------------------------------
        // Test 13: CSRRSI - Read and set bit1 in mstatus via Operation Interface
        //-------------------------------------------------
        `TEST("CSRRSI: Read and set bit1 in mstatus")
        csr_operation(`CSR_RSI, `CSR_MSTATUS, 32'h0, 5'b00010, old_val); // Set bit1
        `EXPECT("old mstatus=0x00000009", old_val, 32'h00000009); // Value after clearing bit 1
        // Read back mstatus via Register Interface
        reg_read(`CSR_MSTATUS, initial_cycle);
        `EXPECT("new mstatus=0x0000000B (bit 1 set)", initial_cycle, 32'h0000000B);

        //-------------------------------------------------
        // Test 14: Interrupt Pending (IRQ) with enabled MIE and active IRQ
        //-------------------------------------------------
        `TEST("Interrupt Pending (IRQ) with enabled MIE, active IRQ")
        // Enable MIE by setting mstatus[3] = 1
        reg_write(`CSR_MSTATUS, 32'h00000008);
        // Read back mstatus
        reg_read(`CSR_MSTATUS, initial_cycle);
        `EXPECT("mstatus[3]=1", initial_cycle[3], 1'b1);

        // Enable IRQ0 - IRQ3 by setting mie[0] = 1
        reg_write(`CSR_MIE, 32'h0000000F);
        // Read back mie
        reg_read(`CSR_MIE, initial_cycle);
        `EXPECT("mie[0]=1", initial_cycle[0], 1'b1);
        `EXPECT("mie[1]=1", initial_cycle[1], 1'b1);
        `EXPECT("mie[2]=1", initial_cycle[2], 1'b1);
        `EXPECT("mie[3]=1", initial_cycle[3], 1'b1);

        // Activate IRQ0
        @(posedge clk);
        irq = 4'b0001;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (IRQ0 on)", interrupt_pending, 1'b1);

        // Read mip register and verify IRQ0 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[0]=1 (IRQ0)", initial_cycle[0], 1'b1);

        // Deactivate IRQ0
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ0 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ0 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[0]=0 (IRQ0)", initial_cycle[0], 1'b0);

        // Activate IRQ1
        @(posedge clk);
        irq = 4'b0010;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (IRQ1 on)", interrupt_pending, 1'b1);

        // Read mip register and verify IRQ1 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[1]=1 (IRQ1)", initial_cycle[1], 1'b1);

        // Deactivate IRQ1
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ1 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ1 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[1]=0 (IRQ1)", initial_cycle[1], 1'b0);

        // Activate IRQ2
        @(posedge clk);
        irq = 4'b0100;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (IRQ2 on)", interrupt_pending, 1'b1);

        // Read mip register and verify IRQ2 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[2]=1 (IRQ2)", initial_cycle[2], 1'b1);

        // Deactivate IRQ2
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ2 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ2 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[2]=0 (IRQ2)", initial_cycle[2], 1'b0);

        // Activate IRQ3
        @(posedge clk);
        irq = 4'b1000;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (IRQ3 on)", interrupt_pending, 1'b1);

        // Read mip register and verify IRQ3 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[3]=1 (IRQ3)", initial_cycle[3], 1'b1);

        // Deactivate IRQ3
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ3 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ3 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[3]=0 (IRQ3)", initial_cycle[3], 1'b0);

        //-------------------------------------------------
        // Test 15: Interrupt Pending respects MIE disable
        //-------------------------------------------------
        `TEST("Interrupt Pending (IRQ) with enabled MIE bit in mstatus enabled\n               and disabled mie register bit for IRQ2")
        // Enable MIE by setting mstatus[3] = 1
        reg_write(`CSR_MSTATUS, 32'h00000008);
        // Read back mstatus
        reg_read(`CSR_MSTATUS, initial_cycle);
        `EXPECT("mstatus[3]=1", initial_cycle[3], 1'b1);

        // Enable IRQ0, IRQ1, IRQ3
        reg_write(`CSR_MIE, 32'h0000000B);
        // Read back mie
        reg_read(`CSR_MIE, initial_cycle);
        `EXPECT("mie[0]=1", initial_cycle[0], 1'b1);
        `EXPECT("mie[1]=1", initial_cycle[1], 1'b1);
        `EXPECT("mie[2]=0", initial_cycle[2], 1'b0);
        `EXPECT("mie[3]=1", initial_cycle[3], 1'b1);

        // Activate IRQ0
        @(posedge clk);
        irq = 4'b0001;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (IRQ0 on)", interrupt_pending, 1'b1);

        // Read mip register and verify IRQ0 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[0]=1 (IRQ0)", initial_cycle[0], 1'b1);

        // Deactivate IRQ0
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ0 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ0 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[0]=0 (IRQ0)", initial_cycle[0], 1'b0);

        // Activate IRQ1
        @(posedge clk);
        irq = 4'b0010;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (IRQ1 on)", interrupt_pending, 1'b1);

        // Read mip register and verify IRQ1 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[1]=1 (IRQ1)", initial_cycle[1], 1'b1);

        // Deactivate IRQ1
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ1 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ1 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[1]=0 (IRQ1)", initial_cycle[1], 1'b0);

        // Activate IRQ2
        @(posedge clk);
        irq = 4'b0100;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ2 on, mie register bit off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ2 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[2]=1 (IRQ2)", initial_cycle[2], 1'b1);

        // Deactivate IRQ2
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ2 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ2 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[2]=0 (IRQ2)", initial_cycle[2], 1'b0);

        // Activate IRQ3
        @(posedge clk);
        irq = 4'b1000;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (IRQ3 on)", interrupt_pending, 1'b1);

        // Read mip register and verify IRQ3 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[3]=1 (IRQ3)", initial_cycle[3], 1'b1);

        // Deactivate IRQ3
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ3 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ3 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[3]=0 (IRQ3)", initial_cycle[3], 1'b0);

        //-------------------------------------------------
        // Test 16: Interrupt Pending respects MIE disable
        //-------------------------------------------------
        `TEST("Interrupt Pending (IRQ) with enabled MIE bit in mstatus disabled")
        // Enable MIE by setting mstatus[3] = 0
        reg_write(`CSR_MSTATUS, 32'h00000006);
        // Read back mstatus
        reg_read(`CSR_MSTATUS, initial_cycle);
        `EXPECT("mstatus[3]=0", initial_cycle[3], 1'b0);

        // Enable IRQ0 - IRQ3
        reg_write(`CSR_MIE, 32'h0000000F);
        // Read back mie
        reg_read(`CSR_MIE, initial_cycle);
        `EXPECT("mie[0]=1", initial_cycle[0], 1'b1);
        `EXPECT("mie[1]=1", initial_cycle[1], 1'b1);
        `EXPECT("mie[2]=0", initial_cycle[2], 1'b1);
        `EXPECT("mie[3]=1", initial_cycle[3], 1'b1);

        // Activate IRQ0
        @(posedge clk);
        irq = 4'b0001;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ0 on, mstatus mie bit off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ0 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[0]=1 (IRQ0)", initial_cycle[0], 1'b1);

        // Deactivate IRQ0
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ0 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ0 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[0]=0 (IRQ0)", initial_cycle[0], 1'b0);

        // Activate IRQ1
        @(posedge clk);
        irq = 4'b0010;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ1 on, mstatus mie bit off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ1 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[1]=1 (IRQ1)", initial_cycle[1], 1'b1);

        // Deactivate IRQ1
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ1 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ1 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[1]=0 (IRQ1)", initial_cycle[1], 1'b0);

        // Activate IRQ2
        @(posedge clk);
        irq = 4'b0100;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ2 on, mstatus mie bit off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ2 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[2]=1 (IRQ2)", initial_cycle[2], 1'b1);

        // Deactivate IRQ2
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ2 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ2 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[2]=0 (IRQ2)", initial_cycle[2], 1'b0);

        // Activate IRQ3
        @(posedge clk);
        irq = 4'b1000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ3 on, mstatus mie bit off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ3 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[3]=1 (IRQ3)", initial_cycle[3], 1'b1);

        // Deactivate IRQ3
        @(posedge clk);
        irq = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (IRQ3 off)", interrupt_pending, 1'b0);

        // Read mip register and verify IRQ3 is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[3]=0 (IRQ3)", initial_cycle[3], 1'b0);

        //-------------------------------------------------
        // Test 17: Interrupt Pending with enabled MIE and active NMI
        //-------------------------------------------------
        `TEST("Interrupt Pending (NMI) with enabled MIE, active IRQ")
        // Enable MIE by setting mstatus[3] = 1
        reg_write(`CSR_MSTATUS, 32'h00000008);
        // Read back mstatus
        reg_read(`CSR_MSTATUS, initial_cycle);
        `EXPECT("mstatus[3]=1", initial_cycle[3], 1'b1);

        // Enable IRQ0 - IRQ3 by setting mie[0] = 1
        reg_write(`CSR_MIE, 32'h000000F0);
        // Read back mie
        reg_read(`CSR_MIE, initial_cycle);
        `EXPECT("mie[4]=1", initial_cycle[4], 1'b1);
        `EXPECT("mie[5]=1", initial_cycle[5], 1'b1);
        `EXPECT("mie[6]=1", initial_cycle[6], 1'b1);
        `EXPECT("mie[7]=1", initial_cycle[7], 1'b1);

        // Trigger NMI0
        @(posedge clk);
        nmi = 4'b0001;
        @(posedge clk);
        nmi = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (NMI0 triggered)", interrupt_pending, 1'b1);

        // Read mip register and verify NMI is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[4]=1 (NMI0)", initial_cycle[4], 1'b1);

        // Clear the mip[4] bit
        reg_write(`CSR_MIP, 32'h00000010);
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (NMI0 cleared)", interrupt_pending, 1'b0);

        // Read mip register and verify NMI is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[4]=0 (NMI0)", initial_cycle[4], 1'b0);

        // Trigger NMI1
        @(posedge clk);
        nmi = 4'b0010;
        @(posedge clk);
        nmi = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (NMI1 triggered)", interrupt_pending, 1'b1);

        // Read mip register and verify NMI is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[5]=1 (NMI1)", initial_cycle[5], 1'b1);

        // Clear the mip[5] bit
        reg_write(`CSR_MIP, 32'h00000020);
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (NMI1 cleared)", interrupt_pending, 1'b0);

        // Read mip register and verify NMI is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[4]=0 (NMI1)", initial_cycle[5], 1'b0);

        // Trigger NMI2
        @(posedge clk);
        nmi = 4'b0100;
        @(posedge clk);
        nmi = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (NMI2 triggered)", interrupt_pending, 1'b1);

        // Read mip register and verify NMI is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[6]=1 (NMI2)", initial_cycle[6], 1'b1);

        // Clear the mip[6] bit
        reg_write(`CSR_MIP, 32'h00000040);
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (NMI2 cleared)", interrupt_pending, 1'b0);

        // Read mip register and verify NMI is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[6]=0 (NMI2)", initial_cycle[6], 1'b0);

        // Trigger NMI3
        @(posedge clk);
        nmi = 4'b1000;
        @(posedge clk);
        nmi = 4'b0000;
        @(posedge clk);
        `EXPECT("interrupt_pending=1 (NMI3 triggered)", interrupt_pending, 1'b1);

        // Read mip register and verify NMI is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[7]=1 (NMI3)", initial_cycle[7], 1'b1);

        // Clear the mip[6] bit
        reg_write(`CSR_MIP, 32'h00000080);
        @(posedge clk);
        `EXPECT("interrupt_pending=0 (NMI3 cleared)", interrupt_pending, 1'b0);

        // Read mip register and verify NMI is reflected
        reg_read(`CSR_MIP, initial_cycle);
        `EXPECT("mip[7]=0 (NMI3)", initial_cycle[7], 1'b0);


        //-------------------------------------------------
        // Test 18: Cycle Counter increments correctly
        //-------------------------------------------------
        `TEST("Cycle Counter increments correctly")
        // Read initial mcounter value
        reg_read(`CSR_MCYCLE, initial_cycle);
        // Wait exactly 4 full clock cycles
        repeat(4) @(posedge clk);
        // Read updated mcounter value
        reg_read(`CSR_MCYCLE, new_cycle);
        // Verify increment
        `EXPECT("cycle_counter +5 (including reg_read delay)", new_cycle, initial_cycle + 5);

        //-------------------------------------------------
        // Test 19: Cycle Counter High increments correctly
        //-------------------------------------------------
        `TEST("Cycle Counter High increments correctly")
        // Read initial mcounter high
        reg_read(`CSR_MCYCLEH, initial_cycle_high);
        // Wait 10 clock cycles
        repeat(10) @(posedge clk);
        // Read new mcounter high
        reg_read(`CSR_MCYCLEH, new_cycle_high);
        `EXPECT("cycle_counter_high unchanged", new_cycle_high, initial_cycle_high);

        //-------------------------------------------------
        // Test 20: Read mvendorid correctly
        //-------------------------------------------------
        `TEST("Read mvendorid correctly")
        reg_read(`CSR_MVENDORID, initial_cycle);
        `EXPECT("mvendorid=0x4A5A5256", initial_cycle, 32'h4A5A5256);

        //-------------------------------------------------
        // Test 21: Read marchid correctly
        //-------------------------------------------------
        `TEST("Read marchid correctly")
        reg_read(`CSR_MARCHID, initial_cycle);
        `EXPECT("marchid=0x00000000", initial_cycle, 32'h00000000);


        //-------------------------------------------------
        // Test 22: Read mcause, write to mtvec, then read mtvec and mcause to verify
        //-------------------------------------------------
        `TEST("Read mcause, write to mtvec, then read mtvec and mcause to verify")
        
        // Step 1: Read mcause
        reg_read(`CSR_MCAUSE, initial_cycle);
        `EXPECT("mcause read correctly (should be 0x000000AA)", initial_cycle, 32'h000000AA);

        // Step 2: Write to mtvec via Register Interface
        reg_write(`CSR_MTVEC, 32'hDEADBEEF);
        
        // Step 3: Read back mtvec
        reg_read(`CSR_MTVEC, new_cycle);
        `EXPECT("mtvec updated to 0xDEADBEEF", new_cycle, 32'hDEADBEEF);

        // Step 4: Read mcause again to ensure it remains unchanged
        reg_read(`CSR_MCAUSE, new_cycle);
        `EXPECT("mcause remains unchanged (should be 0x000000AA)", new_cycle, 32'h000000AA);


        //-------------------------------------------------
        // Finish Testbench
        //-------------------------------------------------
        `FINISH;
    end

endmodule
