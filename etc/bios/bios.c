#include <stdbool.h>
#include <stdint.h>
#include <string.h>

// System memory is 0x0000_0000 to 0x0000_FFFF
// Bios memory is 0x8000_0000 to 0x0000_00FF
// Output memory is 0x0002_0000 to 0x0000_0010
// UART memory is 0x0001_0000 to 0x0000_0010
// CPU boots to 0x8000_0000

#define CLOCK_MHZ      27
#define MEMORY_ADDRESS 0x00000F00
#define OUTPUT_ADDRESS 0x80000000
#define UART_ADDRESS   0xC0000000

void delay(uint32_t ms) {
    volatile uint32_t count;
    while(ms > 0) {
        for(count = 0; count < 2; count++) {
            __asm__("nop");
        }
        ms--;
    }
}

int main() {
    volatile uint8_t *mem = (volatile uint8_t *)(MEMORY_ADDRESS);
    // volatile uint8_t *output = (volatile uint8_t *)(OUTPUT_ADDRESS);
    *mem = 0;
    // *output = 0;

    while(1) {
        *mem = *mem + 1;
        // *output = *output + 1;

        delay(1);
    }
}
