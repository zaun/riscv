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
        @(posedge clk); \
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

`define GET_BYTE_FROM_MEM(MEM, WIDTH, IDX) MEM[(IDX) / (WIDTH/8)][ 8 * ((IDX) % (WIDTH/8)) +: 8 ]
`define SET_BYTE_IN_MEM(MEM, WIDTH, IDX, VAL) MEM[(IDX) / (WIDTH/8)][ 8 * ((IDX) % (WIDTH/8)) +: 8 ] = VAL

`define DISPLAY_MEM_RANGE_ARRAY(MEM, WIDTH, START_ADDR, END_ADDR)                   \
    $display("\n\nMemory dump, memory data width: %0d", WIDTH);                     \
    $display("----------------------------------------------------------------");   \
    $display("            0  1  2  3 |  4  5  6  7 |  8  9  A  B |  C  D  E  F");   \
    $display("----------------------------------------------------------------");   \
    for (addr = START_ADDR; addr <= END_ADDR; addr = addr + 16) begin               \ 
        reg [7:0] bytes [0:15];                                                     \
        integer i;                                                                  \
        for (i = 0; i < 16; i = i + 1) begin                                        \
            bytes[i] = MEM.memory[((addr + i) >> $clog2(WIDTH/8))]                  \
                            [ 8*((addr + i) & ((1 << $clog2(WIDTH/8)) - 1)) +: 8 ]; \
        end                                                                         \
        $display("%04h : %02h %02h %02h %02h | %02h %02h %02h %02h | %02h %02h %02h %02h | %02h %02h %02h %02h", \
                addr,                                                               \
                bytes[0], bytes[1], bytes[2], bytes[3],                             \
                bytes[4], bytes[5], bytes[6], bytes[7],                             \
                bytes[8], bytes[9], bytes[10], bytes[11],                           \
                bytes[12], bytes[13], bytes[14], bytes[15]);                        \
    end                                                                             \
    $display("----------------------------------------------------------------");
