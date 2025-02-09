# RISC-V SoC Project

This repository contains a RISC-V System-on-Chip (SoC) design files implemented in SystemVerilog. The project includes various components such as the CPU, memory, peripherals, and interconnect logic. It aims to provide a modular SoC design for embedded applications that is primarily for learning.

---

## Goals for this Project

1. **Learning RISC-V, TileLink, and related peripherals.**
2. **Designing in SystemVerilog.**

This project prioritizes clarity over performance and optimizations, ensuring straightforward, clearly understandable code. It targets students, hobbyists, and junior-level engineers.

If you're interested in participating, please check the [CONTRIBUTING.md](/docs/CONTRIBUTING.md).

---

## Project Structure

The repository is organized as follows:

- **`docs`**: Contains all documentation and resource files useful to the project, including PDFs related to RISC-V, TileLink, FPGA, and general project files like this `README.md`.
- **`etc`**: Files used in the project but not directly related to the design itself, such as simulation runner files, C code for programming, etc.
- **`src`**: Contains all the SystemVerilog files for the project.
- **`test`**: Contains all testbench files for the project.

---

### Source Files Overview

- **Core Components**:
  - **`tl_cpu.sv`**: Main CPU module integrating all submodules.
  - **`cpu_alu.sv`**: Arithmetic Logic Unit (ALU) for arithmetic and logical operations.
  - **`cpu_mdu.sv`**: Multiply-Divide Unit (MDU) for handling multiplication and division instructions.
  - **`cpu_regfile.sv`**: Register file for storing CPU registers.
  - **`cpu_csr.sv`**: Control and Status Register (CSR) unit for system control.
  - **`cpu_insdecode.sv`**: Instruction decoder for interpreting and dispatching instructions.

- **Interconnect & Peripherals**:
  - **`tl_switch.sv`**: Implements a switch for TL-UL protocol communication.
  - **`tl_interface.sv`**: Provides the interface logic for TL-UL communication.
  - **`tl_ul_uart.sv`**: UART module for serial input and output.
  - **`tl_memory.sv`**: Memory interface for the SoC.
  - **`tl_ul_output.sv`**: Handles output signals.

- **Utilities**:
  - **`instructions.sv`**: Contains global defines for instruction decoding.
  - **`log.sv`**: Provides logging support for debugging.

---

## Development Tools

- [Icarus Verilog 12.0](https://github.com/steveicarus/iverilog)
- [Yosys 0.49](https://github.com/YosysHQ/yosys)
- [graphviz](https://graphviz.org) - brew install graphviz
- [riscv-gnu-toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain)
- [openFPGALoader](https://github.com/trabucayre/openFPGALoader)
- `make`

---

## Make Targets

**Note:** Use the following flags to customize builds:
- **`SUPPORT_M=1`**: Includes the 'M' extension.
- **`SUPPORT_ZICSR=1`**: Includes the 'Zicsr' extension.
- **`XLEN=64`**: Builds a 64-bit system (default is 32-bit).

### Simulations

- `make run_cpu`: Simulates a basic CPU running the `etc/main.c` program. Connects the `tl_cpu.sv` to a `tl_switch` with a single `tl_memory`. Outputs a memory dump and generates a waveform (`graph/cpu_runner.vcd`).
  - *This recompiles the program before simulation.*
- `make run_soc`: Simulates a basic SoC running the `etc/bios/bios.c` program. Connects the `tl_cpu.sv` to a `tl_switch` with `tl_ul_bios`, `tl_memory`, `tl_ul_output`, and `tl_ul_uart`. Outputs a waveform (`graph/soc_runner.vcd`).
  - *This recompiles the BIOS before simulation.*

**Example**:  
`make run_cpu XLEN=64 SUPPORT_ZICSR=1 SUPPORT_M=1` simulates a `rv64im_zicsr` system.

---

### FPGA

**Note:**  
Default target FPGA: **Tang Nano 20k**  
Use `FPGA=9k` to target **Tang Nano 9k**.

- `make`: Builds the `etc/bios` program and synthesizes `src/soc.sv` into a `out.fs` bitstream.
- `make load`: Loads the `out.fs` bitstream onto the FPGA using `openFPGALoader`.
- `make clean`: Cleans up after a build.  
  *Run `make clean` before `make` or `make load` if any changes are made.*

---

### Testing

Testbenches are located in the `test/` folder. Each test has a `make` target:  
`make test_<filename>`.

Example:  
`make test_tl_memory` simulates `test/test_tl_memory_tb.sv`, generating waveforms (`graph/tl_memory_32.vcd` and `graph/tl_memory_64.vcd`) for all supported configurations.

Running `make test` will run all existing `test_*` pargets.

---

## Useful Links

- [RISC-V ISA list of instructions](https://riscv-software-src.github.io/riscv-unified-db/manual/html/isa/20240411/insts/add.html)
- [RISC-V Instruction Decoder](https://luplab.gitlab.io/rvcodecjs)
- [Tang Nano Examples](https://github.com/YosysHQ/apicula/tree/master/examples/himbaechel)

---

## License

RISC-V System on a Chip © 2024-2025 by Justin Zaun is licensed under [Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/).

You are free to:
- **Share**: Copy and redistribute the material in any medium or format.
- **Adapt**: Remix, transform, and build upon the material for any purpose, even commercially.

Under the following terms:
- **Attribution**: You must give appropriate credit, provide a link to the license, and indicate if changes were made.
- **ShareAlike**: If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original.
