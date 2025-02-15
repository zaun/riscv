# Default values for architecture and defines
XLEN := 32
ARCH := rv32i
ABI := ilp32
MACHINE := elf32lriscv
RV := rv32
DEFINES :=

# Set things up for a 64bit CPU
ifeq ($(XLEN), 64)
	XLEN := 64
	ARCH := rv64i
	ABI := lp64
	RV := rv64
	MACHINE := elf64lriscv
	DEFINES += -DXLEN=64
endif

# Modify ARCH and DEFINES if SUPPORT_M is set
ifeq ($(SUPPORT_M), 1)
	ARCH := $(ARCH)m
    DEFINES += -DSUPPORT_M
endif

# Modify ARCH and DEFINES if SUPPORT_M is set
ifeq ($(SUPPORT_B), 1)
	ARCH := $(ARCH)_zic64b_zicbom_zicbop
    DEFINES += -DSUPPORT_B
endif

# Modify ARCH and DEFINES if SUPPORT_BSUPPORT_ZICSR is set
ifeq ($(SUPPORT_ZICSR), 1)
	ARCH := $(ARCH)_zicsr
    DEFINES += -DSUPPORT_ZICSR
endif

all:
	@echo "################################################################################"
	@echo "#                                                                              #"
	@echo "#                             RISC-V SoC Project                               #"
	@echo "#                                                                              #"
	@echo "################################################################################"
	@echo ""
	@echo "make p_soc ................. Build a SOC with a paralell bus"
	@echo "make tl_soc ................ Build a SOC with a TileLink bus"
	@echo "make load .................. Load the built SoC to the FPGA"
	@echo ""
	@echo "make test .................. Run all testbenches"
	@echo "make run_cpu ............... Simulate the cpu in iverilog"
	@echo "make run_soc ............... Simulate the soc in iverilog"

##
# SOC Build 1
##

p_soc: bios out

# Compile a C program in riscv asm
bios: etc/main.c
	echo $(ARCH)
	riscv64-unknown-elf-gcc $(DEFINES) -c -fPIC -march=$(ARCH) -mabi=$(ABI) -nostartfiles -nostdlib -o etc/bios/start.o etc/bios/start.S
	riscv64-unknown-elf-gcc $(DEFINES) -c -fPIC -march=$(ARCH) -mabi=$(ABI) -nostartfiles -nostdlib -o etc/bios/bios.o etc/bios/bios.c
	riscv64-unknown-elf-ld -m $(MACHINE) -o etc/bios/program.o etc/bios/start.o etc/bios/bios.o
	riscv64-unknown-elf-objcopy -O binary etc/bios/program.o etc/bios/bios.bin
	riscv64-unknown-elf-objdump -D -b binary -m riscv:$(RV) -M numeric etc/bios/bios.bin > etc/bios/bios.opcodes
	hexdump -v -e '1/1 "%02x\n"' etc/bios/bios.bin | \
	awk 'BEGIN {desired=256} {print; count++} END {for(i=count+1;i<=desired;i++) print "00"}' > etc/bios/bios.hex
	rm etc/bios/*.o


# Synthesis
synthesis: src/p_soc.sv
	mkdir -p ./graph
	yosys -D SYNTHESIS -q -p "read_verilog -sv -I src/ src/p_soc.sv; hierarchy -check; check; show -colors 1 -width -signed -stretch -prefix graph/soc -format dot; synth_gowin -top top -noabc9 -json synthesis.json"

stat:
	yosys -D SYNTHESIS -p "read_verilog -sv src/p_soc.sv; hierarchy -check; check; synth_gowin -top top -noabc9; stat -hier"

# Place and Route
bitstream: synthesis
	nextpnr-himbaechel --json synthesis.json --write bitstream.json --device ${DEVICE} --vopt family=${FAMILY} --vopt cst=etc/boards/${BOARD}.cst

# Generate Bitstream
out: bitstream
	gowin_pack -d ${FAMILY} -o out.fs bitstream.json

##
# SOC Build 2
##

tl_soc: bios2 out2

# Compile a C program in riscv asm
bios2: etc/main.c
	echo $(ARCH)
	riscv64-unknown-elf-gcc $(DEFINES) -c -fPIC -march=$(ARCH) -mabi=$(ABI) -nostartfiles -nostdlib -o etc/bios/start.o etc/bios/start.S
	riscv64-unknown-elf-gcc $(DEFINES) -c -fPIC -march=$(ARCH) -mabi=$(ABI) -nostartfiles -nostdlib -o etc/bios/bios.o etc/bios/bios.c
	riscv64-unknown-elf-ld -m $(MACHINE) -o etc/bios/program.o etc/bios/start.o etc/bios/bios.o
	riscv64-unknown-elf-objcopy -O binary etc/bios/program.o etc/bios/bios.bin
	riscv64-unknown-elf-objdump -D -b binary -m riscv:$(RV) -M numeric etc/bios/bios.bin > etc/bios/bios.opcodes
	hexdump -v -e '1/1 "%02x\n"' etc/bios/bios.bin | \
	awk 'BEGIN {desired=256} {print; count++} END {for(i=count+1;i<=desired;i++) print "00"}' > etc/bios/bios.hex
	rm etc/bios/*.o


# Synthesis
synthesis2: src/tl_soc.sv
	mkdir -p ./graph
	yosys -D SYNTHESIS -q -p "read_verilog -sv -I src/ src/tl_soc.sv; hierarchy -check; check; show -colors 1 -width -signed -stretch -prefix graph/soc -format dot; synth_gowin -top top -noabc9 -json synthesis.json"

stat2:
	yosys -D SYNTHESIS -p "read_verilog -sv src/tl_soc.sv; hierarchy -check; check; synth_gowin -top top -noabc9; stat -hier"

# Place and Route
bitstream2: synthesis2
	nextpnr-himbaechel --json synthesis.json --write bitstream.json --device ${DEVICE} --vopt family=${FAMILY} --vopt cst=etc/boards/${BOARD}.cst --placed-svg graph/soc2_place.svg --routed-svg graph/soc2_routed.svg

# Generate Bitstream
out2: bitstream2
	gowin_pack -d ${FAMILY} -o out.fs bitstream.json

##
# Develompent
##

# Create graphs from the dot file
graph:
	dot -Tpng ./graph/soc.dot -O

# Program Board
load:
	openFPGALoader -b ${BOARD} out.fs -f

# Remove temp files
clean:
	rm -f etc/bios/bios.hex
	rm -f etc/bios/bios.bin
	rm -f etc/bios/bios.opcodes
	rm -f out.fs
	rm -f bitstream.json
	rm -f synthesis.json
	rm -rf graph/

##
# Develompent
##

# Compile a C program in riscv asm
asm: etc/main.c
	echo $(ARCH)
	rm -f etc/program.sv
	riscv64-unknown-elf-gcc $(DEFINES) -c -fPIC -march=$(ARCH) -mabi=$(ABI) -nostartfiles -nostdlib -o etc/start.o etc/start.S
	riscv64-unknown-elf-gcc $(DEFINES) -c -fPIC -march=$(ARCH) -mabi=$(ABI) -nostartfiles -nostdlib -o etc/main.o etc/main.c
	riscv64-unknown-elf-ld -m $(MACHINE) -o etc/program.o etc/start.o etc/main.o
	riscv64-unknown-elf-objcopy -O binary etc/program.o etc/program.bin
	riscv64-unknown-elf-objdump -D -b binary -m riscv:$(RV) -M numeric etc/program.bin > etc/program.opcodes

run_cpu: asm
	mkdir -p ./graph

	python etc/scripts/bin_to_sv_mem.py etc/program.bin etc/program.sv etc/program.opcodes -m mock_mem -x 16
	rm etc/*.o etc/program.bin etc/program.opcodes

	iverilog -g2012 -I src/  $(DEFINES) -o graph/cpu_runner.vvp -s cpu_runner etc/run.sv
	vvp -N graph/cpu_runner.vvp
	mv ./cpu_runner.vcd ./graph/cpu_runner.vcd
	rm -f graph/cpu_runner.vvp

run_soc: bios
	mkdir -p ./graph

	iverilog -g2012 -I src/  $(DEFINES) -o graph/soc_runner.vvp -s soc_runner etc/runsoc.sv
	vvp -N graph/soc_runner.vvp
	mv ./soc_runner.vcd ./graph/soc_runner.vcd
	rm -f graph/soc_runner.vvp

##
# Tests
##

include MakefileTests.mk

# Automatically find all test_* targets
TESTS := $(shell grep -E '^[[:space:]]*test_[^:]+:$$' MakefileTests.mk | sed -E 's/^[[:space:]]*//' | cut -d':' -f1 )

test: $(TESTS)

.PHONY: load test $(TESTS)

.INTERMEDIATE: synthesis.json bitstream.json
