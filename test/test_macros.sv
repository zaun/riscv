// ====================================
// Testbench Control Signals
// ====================================
integer testCount = 0;
integer testPass = 0;
integer testFail = 0;
integer addr;
reg test;

// ====================================
// Testbench Macros
// ====================================
`define EXPECT(desc, actual, expected) \
    if ((actual) === (expected)) begin \
        $display("  == PASS == %s (Value: 0x%0h)", desc, actual); \
        testPass = testPass + 1; \
    end else begin \
        $display("  == \033[91mFAIL\033[0m == %s (Expected: 0x%0h, Got: 0x%0h)", desc, expected, actual); \
        testFail = testFail + 1; \
    end

`define TEST(name, desc) \
    test = ~test; \
    testCount = testCount + 1; \
    $display("\n[%0s] Test %0d: %s", name, testCount, desc);

`define FINISH \
    begin \
        test = ~test; \
        repeat (10000) @(posedge clk); \
        $display("\n+---=[ %00d bits ]=------------------+", `XLEN); \
        $display("|                                  |"); \
        $display("|  Total Tests Run:           %03d  |", testCount); \
        $display("|  Eexpects Passed:           %03d  |", testPass); \
        $display("|  Eexpects Failed:           %03d  |", testFail); \
        $display("|                                  |"); \
        if (testFail > 0) begin \
            $display("|  Some tests \033[91mFAILED\033[0m!              |"); \
            $display("|                                  |"); \
            $display("+----------------------------------+\n"); \
            $stop; \
        end else begin \
            $display("|  All tests PASSED successfully!  |"); \
            $display("|                                  |"); \
            $display("+----------------------------------+\n"); \
            $finish; \
        end \
    end


`define DISPLAY_MEM_RANGE_ARRAY(MEM, START_ADDR, END_ADDR) \
    for (addr = START_ADDR; addr <= END_ADDR; addr = addr + 16) begin \
        reg [7:0] bytes [0:15]; \
        integer i; \
        for (i = 0; i < 16; i = i + 1) begin \
            bytes[i] = MEM.memory[addr + i]; \
        end \
        $display("%04h : %02h %02h %02h %02h | %02h %02h %02h %02h | %02h %02h %02h %02h | %02h %02h %02h %02h", \
                 addr, bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], \
                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]); \
    end
