#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#ifdef SUPPORT_ZICSR
// Tell GCC no to include function prologue and epilogue code
void trap() __attribute__((noreturn, naked));
#endif

int main(uintptr_t baseAddress) {
    #ifdef SUPPORT_ZICSR
    uintptr_t trap_address = (uintptr_t)trap;
    __asm__ volatile("csrw mtvec, %0" :: "r"(trap_address));
    #endif

    // 64-bit aligned address (8 bytes aligned)
    volatile int64_t *locationA = (volatile int64_t *)(baseAddress + 0xFFD0);
    volatile int64_t *locationB = (volatile int64_t *)(baseAddress + 0xFFD8);

    // 32-bit aligned addresses (4 bytes aligned)
    volatile int32_t *locationC = (volatile int32_t *)(baseAddress + 0xFFE0);
    volatile int32_t *locationD = (volatile int32_t *)(baseAddress + 0xFFE4);

    // 16-bit aligned addresses (2 bytes aligned)
    volatile int16_t *locationE = (volatile int16_t *)(baseAddress + 0xFFE8);
    volatile int16_t *locationF = (volatile int16_t *)(baseAddress + 0xFFEA);
    volatile int16_t *locationG = (volatile int16_t *)(baseAddress + 0xFFEC);
    volatile int16_t *locationH = (volatile int16_t *)(baseAddress + 0xFFEE);

    // 8-bit aligned addresses (1 byte aligned)
    volatile int8_t *locationI = (volatile int8_t *)(baseAddress + 0xFFF0);
    volatile int8_t *locationJ = (volatile int8_t *)(baseAddress + 0xFFF1);
    volatile int8_t *locationK = (volatile int8_t *)(baseAddress + 0xFFF2);
    volatile int8_t *locationL = (volatile int8_t *)(baseAddress + 0xFFF3);
    volatile int8_t *locationM = (volatile int8_t *)(baseAddress + 0xFFF4);
    volatile int8_t *locationN = (volatile int8_t *)(baseAddress + 0xFFF5);
    volatile int8_t *locationO = (volatile int8_t *)(baseAddress + 0xFFF6);
    volatile int8_t *locationP = (volatile int8_t *)(baseAddress + 0xFFF7);

    // Writing values to test memory alignments
    *locationA = 0x1122334455667788;  // 64-bit aligned write
    *locationB = 0xFFEEDDCCBBAA9988;  // 64-bit aligned write
    *locationC = 0x11223344;          // 32-bit aligned write
    *locationD = 0xFFEEDDCC;          // Another 32-bit aligned write
    *locationE = 0xFFEE;              // 16-bit aligned write (High)
    *locationF = 0xDDCC;              // 16-bit aligned write (Mid-High)
    *locationG = 0xBBAA;              // 16-bit aligned write (Mid-Low)
    *locationH = 0x1234;              // 16-bit aligned write (Low)
    *locationI = 0xFE;                // 8-bit aligned write (1st byte)
    *locationJ = 0xDC;                // 8-bit aligned write (2nd byte)
    *locationK = 0xBA;                // 8-bit aligned write (3rd byte)
    *locationL = 0x98;                // 8-bit aligned write (4th byte)
    *locationM = 0x76;                // 8-bit aligned write (5th byte)
    *locationN = 0x54;                // 8-bit aligned write (6th byte)
    *locationO = 0x32;                // 8-bit aligned write (7th byte)
    *locationP = 0x10;                // 8-bit aligned write (8th byte)

    volatile int16_t *resultA = (volatile int16_t *)(baseAddress + 0xFFF8);
    volatile int16_t *resultB = (volatile int16_t *)(baseAddress + 0xFFFA);
    volatile int16_t *resultC = (volatile int16_t *)(baseAddress + 0xFFFC);
    volatile int16_t *resultD = (volatile int16_t *)(baseAddress + 0xFFFE);
    *resultA = 800 + 50;
    *resultB = 200 - 75;
    *resultC = -(*resultA);
    *resultD = -(*resultB);

    return 0;
}

#ifdef SUPPORT_ZICSR
void trap() {
    __asm__ volatile("mret");
    __builtin_unreachable();
}
#endif
