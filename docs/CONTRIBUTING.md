# How to Contribue

Generally this is an open project. If you want to do somehting, do it and submit a pull request. If you want to check before doing open an issue and ask. Items below are a general to do lists of things that should be done but aren't yet. There is not a proirity to any of these, but some require others as a dependancy. This is not an exsausive list, if you want to add a i2c or spi or any other module, go for it.

## Code

All sumbnitted code should be clear, and easy to follow. This project as a whole is meant for learning, not performance and optimization. That said if you want to optimize something or increase preformance of something that still has clear, and easy to follow code, then please do. Learning easy to understand optimized code is more helpful than learning easy to understand unoptimized code.

***For anything new, provide a testbench for it.***

## Testing

Verify all current modules have a working testbench. These are a high priority and are being activly worked on.

- cpu_alu
- cpu_csr
- cpu_insdecode
- cpu_mdu
- cpu_regfile
- cpu
- tl_interface
- tl_memory
- tl_switch
- tl_ul_uart

## Features

### Switch

- Add TileLink-UH support to the tl_switch in a SUPPORT_TL_UH flag. Be suport to the switch still support UL modules connected to it.
- Add TileLink-C support to the tl_switch in a SUPPORT_TL_C flag and should not require the SUPPORT_UH support. So caching should work withe UL or UH switch. Be sure the switch still support non-cache aware modules to it.

### Memory

- Add TileLink-UH support to the tl_memory in a SUPPORT_TL_UH flag.
- Add TileLink-C support to the tl_memory in a SUPPORT_TL_C flag and should not require the SUPPORT_UH support. So caching should work withe UL or UH switch.

### Interface

- Add TileLink-UH support to the tl_interface in a SUPPORT_TL_UH flag.
- Add TileLink-C support to the tl_interface in a SUPPORT_TL_C flag and should not require the SUPPORT_UH support. So caching should work withe UL or UH switch.
- Add a L1 cache for program and a L1 cache for data directly to the tl_interface in a SUPPORT_TL_C flag. The cache should be seamless for any master using the tl_interface.

### Bios

- The bios should be developered to wait for the uart to load a program into memory and execute it.

### CPU

- Add 'b' extension support in a SUPPORT_B flag.
- Add 'f' extension support in a SUPPORT_F flag. This should build out a new FPU module and should build out real synthizable IEEE 754 support.
- Add 'd' extension support in a SUPPORT_D flag updating the FPU to support double-presision. Adding the SUPPORT_D should automatically include the SUPPORT_F flag.

### CSR

- Finish machine level support
- Add System level support
- Add user level support
- Add 4 XLEN timers with interrupt support. User should set the timer value and it should decrement to 0 once every nanosecond. at 0 it should trigger an interrupt. Maybe have a config register to support decrements but clocks, ns, ms, s, etc.
- Add 4 XLEN psudo random number generators that create a new number on read. Writing to the rng sets seed for the next read.

### Video

- Create a basic memory mapped frame buffer with back-buffer that outputs a DVI signal. Should have a config register that holds resolution information and a bit to flip the buffer. Looking to support 720 and below resolutions.
- Add a SUPPORT_RAW flag that adds 24bit RGB outputs for LCD/VGA/others to use.

### Anything

- Add whatever modules or features you would like. Just put things behind a SUPPORT_* flag so its off by default.
