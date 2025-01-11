`default_nettype none
`timescale 1ns / 1ps

module cpu_regfile_tb;

    // Parameters for XLEN
    localparam XLEN_32 = 32;
    localparam XLEN_64 = 64;

    // -----------------------------
    // 32-bit Register File Signals
    // -----------------------------
    // Inputs
    logic clk_32;
    logic reset_32;
    logic [4:0] rs1_addr32;
    logic [4:0] rs2_addr32;
    logic [4:0] rd_addr32;
    logic [XLEN_32-1:0] rd_data32;
    logic rd_write_en32;

    // Outputs
    logic [XLEN_32-1:0] rs1_data32;
    logic [XLEN_32-1:0] rs2_data32;

    // -----------------------------
    // 64-bit Register File Signals
    // -----------------------------
    // Inputs
    logic clk_64;
    logic reset_64;
    logic [4:0] rs1_addr64;
    logic [4:0] rs2_addr64;
    logic [4:0] rd_addr64;
    logic [XLEN_64-1:0] rd_data64;
    logic rd_write_en64;

    // Outputs
    logic [XLEN_64-1:0] rs1_data64;
    logic [XLEN_64-1:0] rs2_data64;

    // Instantiate the 32-bit Register File
    cpu_regfile #(
        .XLEN(XLEN_32)
    ) uut32 (
        .clk        (clk_32),
        .reset      (reset_32),
        .rs1_addr   (rs1_addr32),
        .rs2_addr   (rs2_addr32),
        .rd_addr    (rd_addr32),
        .rd_data    (rd_data32),
        .rd_write_en (rd_write_en32),
        .rs1_data   (rs1_data32),
        .rs2_data   (rs2_data32)
    );

    // Instantiate the 64-bit Register File
    cpu_regfile #(
        .XLEN(XLEN_64)
    ) uut64 (
        .clk        (clk_64),
        .reset      (reset_64),
        .rs1_addr   (rs1_addr64),
        .rs2_addr   (rs2_addr64),
        .rd_addr    (rd_addr64),
        .rd_data    (rd_data64),
        .rd_write_en (rd_write_en64),
        .rs1_data   (rs1_data64),
        .rs2_data   (rs2_data64)
    );

    // Test Counters for 32-bit and 64-bit
    integer testCount32 = 0;
    integer testCountPass32 = 0;
    integer testCountFail32 = 0;

    integer testCount64 = 0;
    integer testCountPass64 = 0;
    integer testCountFail64 = 0;

    // Task to perform a test for 32-bit Register File
    task perform_test32(
        input string desc,
        input [4:0] rd_addr,
        input [XLEN_32-1:0] rd_data,
        input rd_write_en,
        input [4:0] rs1_addr,
        input [4:0] rs2_addr,
        input [XLEN_32-1:0] expected_rs1_data,
        input [XLEN_32-1:0] expected_rs2_data
    );
        begin
            testCount32 = testCount32 + 1;
            $display("\n[32-bit Reg File] Test %0d: %s", testCount32, desc);
            rd_addr32    = rd_addr;
            rd_data32    = rd_data;
            rd_write_en32 = rd_write_en;
            rs1_addr32   = rs1_addr;
            rs2_addr32   = rs2_addr;
            #10; // Wait for write and read

            // Check rs1_data
            if (rs1_data32 === expected_rs1_data) begin
                $display("  == PASS == rs1_data: 0x%h", rs1_data32);
                testCountPass32 = testCountPass32 + 1;
            end else begin
                $display("  == FAIL == rs1_data: Expected 0x%h, Got 0x%h", expected_rs1_data, rs1_data32);
                testCountFail32 = testCountFail32 + 1;
            end

            // Check rs2_data
            if (rs2_data32 === expected_rs2_data) begin
                $display("  == PASS == rs2_data: 0x%h", rs2_data32);
                testCountPass32 = testCountPass32 + 1;
            end else begin
                $display("  == FAIL == rs2_data: Expected 0x%h, Got 0x%h", expected_rs2_data, rs2_data32);
                testCountFail32 = testCountFail32 + 1;
            end
        end
    endtask

    // Task to perform a test for 64-bit Register File
    task perform_test64(
        input string desc,
        input [4:0] rd_addr,
        input [XLEN_64-1:0] rd_data,
        input rd_write_en,
        input [4:0] rs1_addr,
        input [4:0] rs2_addr,
        input [XLEN_64-1:0] expected_rs1_data,
        input [XLEN_64-1:0] expected_rs2_data
    );
        begin
            testCount64 = testCount64 + 1;
            $display("\n[64-bit Reg File] Test %0d: %s", testCount64, desc);
            rd_addr64    = rd_addr;
            rd_data64    = rd_data;
            rd_write_en64 = rd_write_en;
            rs1_addr64   = rs1_addr;
            rs2_addr64   = rs2_addr;
            #10; // Wait for write and read

            // Check rs1_data
            if (rs1_data64 === expected_rs1_data) begin
                $display("  == PASS == rs1_data: 0x%h", rs1_data64);
                testCountPass64 = testCountPass64 + 1;
            end else begin
                $display("  == FAIL == rs1_data: Expected 0x%h, Got 0x%h", expected_rs1_data, rs1_data64);
                testCountFail64 = testCountFail64 + 1;
            end

            // Check rs2_data
            if (rs2_data64 === expected_rs2_data) begin
                $display("  == PASS == rs2_data: 0x%h", rs2_data64);
                testCountPass64 = testCountPass64 + 1;
            end else begin
                $display("  == FAIL == rs2_data: Expected 0x%h, Got 0x%h", expected_rs2_data, rs2_data64);
                testCountFail64 = testCountFail64 + 1;
            end
        end
    endtask

    // Clock generation for 32-bit Register File
    initial begin
        clk_32 = 0;
        forever #5 clk_32 = ~clk_32; // 100MHz clock
    end

    // Clock generation for 64-bit Register File
    initial begin
        clk_64 = 0;
        forever #5 clk_64 = ~clk_64; // 100MHz clock
    end

    initial begin
        $dumpfile("cpu_regfile_tb.vcd");
        $dumpvars(0, cpu_regfile_tb);

        // Initialize Inputs for 32-bit Register File
        reset_32      = 1;
        rd_addr32     = 5'd0;
        rd_data32     = {XLEN_32{1'b0}};
        rd_write_en32 = 1'b0;
        rs1_addr32    = 5'd0;
        rs2_addr32    = 5'd0;

        // Initialize Inputs for 64-bit Register File
        reset_64      = 1;
        rd_addr64     = 5'd0;
        rd_data64     = {XLEN_64{1'b0}};
        rd_write_en64 = 1'b0;
        rs1_addr64    = 5'd0;
        rs2_addr64    = 5'd0;

        #10;
        reset_32 = 0;
        reset_64 = 0;

        // Wait for a positive clock edge to ensure reset has been processed
        @(posedge clk_32);
        @(posedge clk_64);

        // -------------------
        // Write and Read Operations
        // -------------------

        // Test 1: Write to x1 and read from x1, x2
        perform_test32("Write x1=0x12345678 and read x1, x2",
                      5'd1, 32'h12345678, 1'b1, // Write to x1
                      5'd1, 5'd2,               // Read from x1 and x2
                      32'h12345678, 32'h00000000); // Expected x1=0x12345678, x2=0

        perform_test64("Write x1=0x123456789ABCDEF0 and read x1, x2",
                      5'd1, 64'h123456789ABCDEF0, 1'b1, // Write to x1
                      5'd1, 5'd2,                     // Read from x1 and x2
                      64'h123456789ABCDEF0, 64'h0000000000000000); // Expected x1=..., x2=0

        // Test 2: Attempt to write to x0 and verify it remains zero
        perform_test32("Attempt to write x0=0xDEADBEEF (should remain 0) and read x0, x1",
                      5'd0, 32'hDEADBEEF, 1'b1, // Write to x0
                      5'd0, 5'd1,               // Read from x0 and x1
                      32'h00000000, 32'h12345678); // Expected x0=0, x1=0x12345678

        perform_test64("Attempt to write x0=0xDEADBEEFDEADBEEF (should remain 0) and read x0, x1",
                      5'd0, 64'hDEADBEEFDEADBEEF, 1'b1, // Write to x0
                      5'd0, 5'd1,                     // Read from x0 and x1
                      64'h0000000000000000, 64'h123456789ABCDEF0); // Expected x0=0, x1=...

        // Test 3: Write to x2 and read from x1, x2
        perform_test32("Write x2=0xFFFFFFFF and read x1, x2",
                      5'd2, 32'hFFFFFFFF, 1'b1, // Write to x2
                      5'd1, 5'd2,               // Read from x1 and x2
                      32'h12345678, 32'hFFFFFFFF); // Expected x1=0x12345678, x2=0xFFFFFFFF

        perform_test64("Write x2=0xFFFFFFFFFFFFFFFF and read x1, x2",
                      5'd2, 64'hFFFFFFFFFFFFFFFF, 1'b1, // Write to x2
                      5'd1, 5'd2,                     // Read from x1 and x2
                      64'h123456789ABCDEF0, 64'hFFFFFFFFFFFFFFFF); // Expected x1=..., x2=...

        // Test 4: Write to x3 and x4, then read them
        perform_test32("Write x3=0x00000000 and read x3, x4",
                      5'd3, 32'h00000000, 1'b1, // Write to x3
                      5'd3, 5'd4,               // Read from x3 and x4
                      32'h00000000, 32'h00000000); // Expected x3=0, x4=0

        perform_test64("Write x3=0x0000000000000000 and read x3, x4",
                      5'd3, 64'h0000000000000000, 1'b1, // Write to x3
                      5'd3, 5'd4,                     // Read from x3 and x4
                      64'h0000000000000000, 64'h0000000000000000); // Expected x3=0, x4=0

        perform_test32("Write x4=0xAAAAAAAA and read x1, x4",
                      5'd4, 32'hAAAAAAAA, 1'b1, // Write to x4
                      5'd1, 5'd4,               // Read from x1 and x4
                      32'h12345678, 32'hAAAAAAAA); // Expected x1=..., x4=0xAAAAAAAA

        perform_test64("Write x4=0xAAAAAAAAAAAAAAAA and read x1, x4",
                      5'd4, 64'hAAAAAAAAAAAAAAAA, 1'b1, // Write to x4
                      5'd1, 5'd4,                     // Read from x1 and x4
                      64'h123456789ABCDEF0, 64'hAAAAAAAAAAAAAAAA); // Expected x1=..., x4=...

        // Test 5: Reset the Register Files and verify all registers are zero except x0
        reset_32 = 1;
        reset_64 = 1;
        #10;
        reset_32 = 0;
        reset_64 = 0;

        // Wait for a positive clock edge to ensure reset has been processed
        @(posedge clk_32);
        @(posedge clk_64);

        // After reset, read x0, x1, x2, x3, x4
        perform_test32("After reset: read x0, x1, x2",
                      5'd0, 32'h00000000, 1'b0, // No write
                      5'd0, 5'd1,               // Read from x0 and x1
                      32'h00000000, 32'h00000000); // Expected x0=0, x1=0

        perform_test64("After reset: read x0, x1, x2",
                      5'd0, 64'h0000000000000000, 1'b0, // No write
                      5'd0, 5'd1,                     // Read from x0 and x1
                      64'h0000000000000000, 64'h0000000000000000); // Expected x0=0, x1=0

        perform_test32("After reset: read x2, x3",
                      5'd0, 32'h00000000, 1'b0, // No write
                      5'd2, 5'd3,               // Read from x2 and x3
                      32'h00000000, 32'h00000000); // Expected x2=0, x3=0

        perform_test64("After reset: read x2, x3",
                      5'd0, 64'h0000000000000000, 1'b0, // No write
                      5'd2, 5'd3,                     // Read from x2 and x3
                      64'h0000000000000000, 64'h0000000000000000); // Expected x2=0, x3=0

        perform_test32("After reset: read x4",
                      5'd0, 32'h00000000, 1'b0, // No write
                      5'd4, 5'd0,               // Read from x4 and x0
                      32'h00000000, 32'h00000000); // Expected x4=0, x0=0

        perform_test64("After reset: read x4",
                      5'd0, 64'h0000000000000000, 1'b0, // No write
                      5'd4, 5'd0,                     // Read from x4 and x0
                      64'h0000000000000000, 64'h0000000000000000); // Expected x4=0, x0=0

        // -------------------
        // Additional Tests
        // -------------------

        // Test 6: Write multiple registers and read them
        perform_test32("Write x5=0x55555555 and x6=0xAAAAAAAA and read x5, x6",
                      5'd5, 32'h55555555, 1'b1, // Write to x5
                      5'd5, 5'd6,               // Read from x5 and x6
                      32'h55555555, 32'h00000000); // Expected x5=0x55555555, x6=0

        perform_test64("Write x5=0x5555555555555555 and x6=0xAAAAAAAAAAAAAAAA and read x5, x6",
                      5'd5, 64'h5555555555555555, 1'b1, // Write to x5
                      5'd5, 5'd6,                     // Read from x5 and x6
                      64'h5555555555555555, 64'h0000000000000000); // Expected x5=..., x6=0

        perform_test32("Write x6=0xAAAAAAAA and read x5, x6",
                      5'd6, 32'hAAAAAAAA, 1'b1, // Write to x6
                      5'd5, 5'd6,               // Read from x5 and x6
                      32'h55555555, 32'hAAAAAAAA); // Expected x5=0x55555555, x6=0xAAAAAAAA

        perform_test64("Write x6=0xAAAAAAAAAAAAAAAA and read x5, x6",
                      5'd6, 64'hAAAAAAAAAAAAAAAA, 1'b1, // Write to x6
                      5'd5, 5'd6,                     // Read from x5 and x6
                      64'h5555555555555555, 64'hAAAAAAAAAAAAAAAA); // Expected x5=..., x6=...

        // Test 7: Attempt to write to multiple registers in succession
        perform_test32("Write x7=0x0 and read x7, x8",
                      5'd7, 32'h00000000, 1'b1, // Write to x7
                      5'd7, 5'd8,               // Read from x7 and x8
                      32'h00000000, 32'h00000000); // Expected x7=0, x8=0

        perform_test64("Write x7=0x0000000000000000 and read x7, x8",
                      5'd7, 64'h0000000000000000, 1'b1, // Write to x7
                      5'd7, 5'd8,                     // Read from x7 and x8
                      64'h0000000000000000, 64'h0000000000000000); // Expected x7=0, x8=0

        perform_test32("Write x8=0xFFFFFFFF and read x7, x8",
                      5'd8, 32'hFFFFFFFF, 1'b1, // Write to x8
                      5'd7, 5'd8,               // Read from x7 and x8
                      32'h00000000, 32'hFFFFFFFF); // Expected x7=0, x8=0xFFFFFFFF

        perform_test64("Write x8=0xFFFFFFFFFFFFFFFF and read x7, x8",
                      5'd8, 64'hFFFFFFFFFFFFFFFF, 1'b1, // Write to x8
                      5'd7, 5'd8,                     // Read from x7 and x8
                      64'h0000000000000000, 64'hFFFFFFFFFFFFFFFF); // Expected x7=0, x8=0xFFFFFFFFFFFFFFFF

        // -------------------
        // Finish the simulation
        // -------------------
        #10;
        $display("\n===========================");
        $display("[32-bit Reg File] Total Tests Run      : %0d", testCount32);
        $display("[32-bit Reg File] Total Asserts Passed : %0d", testCountPass32);
        $display("[32-bit Reg File] Total Asserts Failed : %0d", testCountFail32);
        $display("[64-bit Reg File] Total Tests Run      : %0d", testCount64);
        $display("[64-bit Reg File] Total Asserts Passed : %0d", testCountPass64);
        $display("[64-bit Reg File] Total Asserts Failed : %0d", testCountFail64);
        $display("===========================\n");
        $finish;
    end

endmodule
