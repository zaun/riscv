#include <stdbool.h>
#include <stdint.h>
#include <string.h>

// Tell GCC no to include function prologue and epilogue code
void trap() __attribute__((noreturn, naked));

// Define the base address of the UART
#define UART_BASE_ADDR 0x00010000

// Register Offsets
#define UART_STATUS_REG   0x00
#define UART_CONFIG_REG   0x04
#define UART_DATA_REG     0x08

// Status Register Bits
#define UART_TX_FIFO_EMPTY_BIT  0
#define UART_TX_FIFO_FULL_BIT   1
#define UART_RX_FIFO_EMPTY_BIT  2
#define UART_IRQ_PENDING_BIT    4

// Memory-mapped I/O addresses
#define UART_STATUS_ADDR   ((volatile uint8_t *)(UART_BASE_ADDR + UART_STATUS_REG))
#define UART_CONFIG_ADDR   ((volatile uint8_t *)(UART_BASE_ADDR + UART_CONFIG_REG))
#define UART_DATA_ADDR     ((volatile uint8_t *)(UART_BASE_ADDR + UART_DATA_REG))

/**
 * @brief Checks if the UART Transmit FIFO is full.
 *
 * @return true if TX FIFO is full, false otherwise.
 */
static inline bool uart_is_tx_full(void) {
    return ((*UART_STATUS_ADDR) & (1 << UART_TX_FIFO_FULL_BIT)) != 0;
}

/**
 * @brief Checks if the UART Transmit FIFO is empty.
 *
 * @return true if TX FIFO is full, false otherwise.
 */
static inline bool uart_is_tx_emptyl(void) {
    return ((*UART_STATUS_ADDR) & (1 << UART_TX_FIFO_EMPTY_BIT)) != 0;
}

/**
 * @brief Checks if the UART Receive FIFO is empty.
 *
 * @return true if RX FIFO is empty, false otherwise.
 */
static inline bool uart_is_rx_empty(void) {
    return ((*UART_STATUS_ADDR) & (1 << UART_RX_FIFO_EMPTY_BIT)) != 0;
}

/**
 * @brief Sends a single byte via UART.
 *
 * This function writes a byte to the UART Send Register. It waits until the
 * Transmit FIFO is not full before writing. If the FIFO remains full after
 * a timeout period, the function returns an error.
 *
 * @param byte The byte to send.
 * @return 0 on success, -1 on failure (FIFO full).
 */
int uart_send(char byte) {
    // Wait until TX FIFO is not full
    while (uart_is_tx_full()) { }

    // Write the byte to the Send Register
    *UART_DATA_ADDR = (uint8_t)byte;

    return 0; // Success
}

/**
 * @brief Sends a null-terminated string via UART.
 *
 * This function iterates through each character in the input string and sends it via UART
 * using the uart_send function. If the UART transmit FIFO is full for any character,
 * the function returns an error.
 *
 * @param str Pointer to the null-terminated string to send.
 * @return 0 on success, -1 on failure (if any uart_send call fails).
 */
int uart_send_string(const char *str) {
    // Iterate through each character until the null terminator is reached
    while (*str != '\0') {
        // Send the current character
        if (uart_send(*str) != 0) {
            // If uart_send fails, return an error
            return -1;
        }
        // Move to the next character in the string
        str++;
    }
    // All characters sent successfully
    return 0;
}

/**
 * @brief Reads a single byte from UART.
 *
 * This function reads a byte from the UART Receive Register. It waits until the
 * Receive FIFO is not empty before reading. If the FIFO remains empty after
 * a timeout period, the function returns an error.
 *
 * @param byte Pointer to store the received byte.
 * @return 0 on success, -1 on failure (FIFO empty).
 */
int uart_read(char *byte) {
    // Wait until RX FIFO is not empty
    while (uart_is_rx_empty()) {
        // Implement a timeout or other error handling as needed
        // For simplicity, we'll return an error if FIFO is empty
        return -1; // Failure: RX FIFO is empty
    }

    // Read the byte from the Receive Register
    *byte = (char)(*UART_DATA_ADDR);

    return 0; // Success
}

/**
 * @brief Clears the UART IRQ.
 *
 * This function clears the IRQ by writing '1' to bit [4] of the Status Register.
 */
void uart_clear_irq(void) {
    // Define a volatile pointer to the Status Register
    volatile uint8_t *status_reg = UART_STATUS_ADDR;

    // Write '1' to bit [4] to clear the IRQ
    *status_reg = (1 << UART_IRQ_PENDING_BIT);
}

int done = 0;

int main(uintptr_t baseAddress) {
    uintptr_t trap_address = (uintptr_t)trap;
    __asm__ volatile("csrw mtvec, %0" :: "r"(trap_address));

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

    // uart_send('A');
    // uart_send('\n');
    // uart_send_string("Hello world from the UART\n");


    // Wait until TX FIFO is not full
    // while (!uart_is_tx_emptyl()) { }

    return 0;
}

void trap() {
    __asm__ volatile("mret");
    __builtin_unreachable();
}

