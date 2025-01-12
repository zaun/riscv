# RISCV SoC Project

This repository contains the System-on-Chip (SoC) design files implemented in SystemVerilog. The project includes various components such as the CPU, memory, peripherals, and interconnect logic. It aims to provide a modular SoC design for embedded applications that is primarily for learning.

The goals for this project:

1. Learning RISCV, TileLink and related peripherals.
2. Designing in SystemVerilog.

This more or less means the projects aims for clarity over performance and oplimizations where a performance or oplimization change does not allow for straightforward, clearly understandable code. Think collge student, hobbiest or junior level enginer as the target.

If you're interested in participating please check [CONTRIBUTING.md](/docs/CONTRIBUTING.md).

## Project Structure

The repository is organized as follows:

- **`docs`**: Contains all documention and resource files useful to the poject. Items such as PDFs related to RISCV, TileLinks, FPGA, etc. as well as general project files liek this readme.
- **`etc`**: Files used in the project but no directly related the design itself. For example, the runner files for simulations, C code files for programming, etc.
- **`src`**: Contains all the SystemVerilog files for the project.
- **`test`**: Contains all the testbench files for the project.

### Source files

- **`cpu.sv`**: Main CPU module that integrates all CPU submodules.
- **`cpu_alu.sv`**: Arithmetic Logic Unit (ALU) for performing arithmetic and logical operations.
- **`cpu_mdu.sv`**: Multiply-Divide Unit (MDU) for handling multiplication and division instructions.
- **`cpu_regfile.sv`**: Register file for storing CPU registers.
- **`cpu_csr.sv`**: Control and Status Register (CSR) unit for managing system control.
- **`cpu_insdecode.sv`**: Instruction decoder for interpreting and dispatching instructions.
- **`tl_switch.sv`**: TileLink Ultra-Lite (TL-UL) switch for interconnecting components.
- **`tl_interface.sv`**: TL-UL interface logic.
- **`tl_ul_bios.sv`**: BIOS implementation for the SoC.
- **`tl_ul_uart.sv`**: UART module for serial communication.
- **`tl_memory.sv`**: Memory module for managing memory operations.
- **`tl_ul_output.sv`**: Output module for handling SoC output.
- **`soc.sv`**: Top-level SoC module that integrates the CPU, memory, and peripherals.
- **`defines.sv`**: Global definitions and macros used throughout the project.
- **`log.sv`**: Logging module for debug and trace support.

### Core Components

- `cpu.sv`: Connects CPU submodules and implements the core processing logic.
- `cpu_alu.sv`: Provides arithmetic and logic operations.
- `cpu_mdu.sv`: Handles complex multiplication and division operations.
- `cpu_regfile.sv`: Implements register storage with read and write capabilities.
- `cpu_csr.sv`: Manages system control and status.

### Interconnect & Peripherals

- `tl_switch.sv`: Implements a switch for TL-UL protocol communication.
- `tl_interface.sv`: Provides the interface logic for TL-UL communication.
- `tl_ul_uart.sv`: UART module for serial input and output.
- `tl_memory.sv`: Memory interface for the SoC.
- `tl_ul_output.sv`: Handles output signals.

### Utilities

- `defines.sv`: Contains global defines for easier configurability.
- `log.sv`: Provides logging support for debugging.


## Development tools

- [Icarus Verilog](https://github.com/steveicarus/iverilog)
- [Yoys](https://github.com/YosysHQ/yosys)
- [riscv-gnu-toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain)
- [openFPGALoader](https://github.com/trabucayre/openFPGALoader)
- make

### Make Targets

Note: **SUPPORT_M=1** will include 'm' extension support, **SUPPORT_ZICSR=1** will include 'zicsr' extension support, **XLEN=64** will create a 64bit system, default is 32 bit.

#### Simulations

- `make run_cpu`: Simulate a basic CPU running the `etc/main.c` program. This CPU contains the rv_cpu connected to a tl_switch with a single tl_memory connected. After simulation a memory dump is provided and a `graph/cpu_runner.vcd` it produced. *This will recompile the program before simulation*
- `make run_soc`: Simulate a basic SOC running teh `etc/bios/bios.c` program. This SOC has a rv_cpu connected to a tl_switch with a tl_ul_bios, tl_memory, tl_ul_output and tl_ul_uart modules. A `graph/soc_runner.vcd` it produced. *This will recompile the bios before simulation*
- Exmaple: `make run_cpu XLEN=64 SUPPORT_ZICSR=1 SUPPORT_M=1` will simulate a rv64im_zicsr system.

#### FPGA

*NOTE*: Thes default to the Tang Nano 20k as the target FPGA but passing **FPGA=9k** will change the target to the Tang Nano 9k.

- `make`: Will build the `etc/bios` program, an syntisize the `src/soc.sv` module into a out.fs bitstream.
- `make load`: Will load the `out.fs` file on to the FPGA using `openFPGALoader`.
- `make clean`: Will clean up after a build. In general if you cange anything run `make clean` before `make` or `make load`.

#### Testing

Testbenches are all in the `test/` folder and are each setup with a make target `make test_<filename>`. For example `make test_tl_memory` with simulate the `test/test_tl_memory_tb.sv` file and produce a `graph/tl_memory_32.vcd` and a `graph/tl_memory_64.vcd`. In general tests a re-run once for each supported configuration of the module.
