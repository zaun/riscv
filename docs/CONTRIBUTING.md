# How to Contribute

This is an open project, and contributions are highly encouraged! If you want to do something, feel free to submit a pull request. If you want to discuss an idea before working on it, open an issue and ask. Below is a general to-do list of things that need to be done but haven't yet. 

Note: There is no strict priority to these items, but some depend on others. This list is not exhaustive—if you want to add a new feature like I2C, SPI, or any other module, go for it!

---

## Code

All submitted code should be **clear and easy to follow**. This project is primarily meant for learning, not optimization or performance. However, if you can optimize or improve performance while keeping the code clear and easy to understand, please do so. Learning optimized, easy-to-understand code is better than learning unoptimized, easy-to-understand code.

***For anything new, provide a testbench.***

---

## Cleanup

### Testing

Verify all current modules have a working testbench. These are high-priority items and are actively being worked on:

- **`cpu_alu`** ✔
- **`cpu_csr`** ✔
- **`cpu_insdecode`** ✔
- **`cpu_mdu`** ✔
- **`cpu_regfile`** ✔
- **`cpu`** ✔
- **`tl_interface`** ✔
- **`tl_memory`** ✔ 
- **`tl_switch`**
- **`tl_ul_uart`** ✔

### src/instructions.sv

The F, D and Q defines are mostly placeholders (copies of the I instruction values) and need to be reviewed and updated to the actual encoding for each instruction.

---

## To Do List

### **Switch**

- Add TileLink-UH support to the `tl_switch` in a `SUPPORT_TL_UH` flag. Ensure the switch still supports UL modules connected to it.
- Add TileLink-C support to the `tl_switch` in a `SUPPORT_TL_C` flag. This should not require the `SUPPORT_TL_UH` flag. The caching mechanism should work with UL or UH switches, while maintaining support for non-cache-aware modules.

---

### **Memory**

- Add TileLink-UH support to the `tl_memory` in a `SUPPORT_TL_UH` flag.
- Add TileLink-C support to the `tl_memory` in a `SUPPORT_TL_C` flag. This should not require the `SUPPORT_TL_UH` flag. The caching mechanism should work with UL or UH switches.

---

### **Interface**

- Add TileLink-UH support to the `tl_interface` in a `SUPPORT_TL_UH` flag.
- Add TileLink-C support to the `tl_interface` in a `SUPPORT_TL_C` flag. This should not require the `SUPPORT_TL_UH` flag. The caching mechanism should work with UL or UH switches.
- Add an L1 cache for both program and data to the `tl_interface` in a `SUPPORT_TL_C` flag. The cache should be seamless for any master using the `tl_interface`.

---

### **Bios**

- Develop the BIOS to wait for the UART to load a program into memory and execute it.

---

### **CPU**

- Add 'B' extension support in a `SUPPORT_B` flag.
- Add 'F' extension support in a `SUPPORT_F` flag. This should include a new FPU module and support for synthesizable IEEE 754 floating-point operations.
- Add 'D' extension support in a `SUPPORT_D` flag. Update the FPU to support double-precision. Enabling the `SUPPORT_D` flag should automatically include the `SUPPORT_F` flag.

---

### **CSR**

- Finish machine-level support.
- Add system-level support.
- Add user-level support.
- Add 4 XLEN timers with interrupt support. Users should set the timer value, and it should decrement to 0 at one decrement per nanosecond. At 0, it should trigger an interrupt. A configuration register should allow decrements based on clocks, ns, ms, s, etc.
- Add 4 XLEN pseudo-random number generators. Writing to the RNG sets the seed for the next read, and reading generates a new random number.

---

### **Video**

- Create a basic memory-mapped frame buffer with a back buffer that outputs a DVI signal. Include a configuration register to store resolution information and a bit to flip the buffer. Support resolutions up to 720p.
- Add a `SUPPORT_RAW` flag to enable 24-bit RGB outputs for LCD, VGA, or other video output systems.

---

### **Anything**

- Add whatever modules or features you would like! Just ensure new features are wrapped in a `SUPPORT_*` flag so they are disabled by default.
