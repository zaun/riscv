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

# Modify ARCH and DEFINES if SUPPORT_BSUPPORT_ZICSR is set
ifeq ($(SUPPORT_ZICSR), 1)
	ARCH := $(ARCH)_zicsr
    DEFINES += -DSUPPORT_ZICSR
endif


##
# Board
##

all: bios out.fs

# Compile a C program in riscv asm
bios: etc/main.c
	echo $(ARCH)
	riscv64-unknown-elf-gcc $(DEFINES) -c -fPIC -march=$(ARCH) -mabi=$(ABI) -nostartfiles -nostdlib -o etc/bios/start.o etc/bios/start.S
	riscv64-unknown-elf-gcc $(DEFINES) -c -fPIC -march=$(ARCH) -mabi=$(ABI) -nostartfiles -nostdlib -o etc/bios/bios.o etc/bios/bios.c
	riscv64-unknown-elf-ld -m $(MACHINE) -o etc/bios/program.o etc/bios/start.o etc/bios/bios.o
	riscv64-unknown-elf-objcopy -O binary etc/bios/program.o etc/bios/bios.bin
	riscv64-unknown-elf-objdump -D -b binary -m riscv:$(RV) -M numeric etc/bios/bios.bin > etc/bios/bios.opcodes
	hexdump -v -e '1/1 "%02x\n"' etc/bios/bios.bin | \
	awk 'BEGIN {desired=255} {print; count++} END {for(i=count+1;i<=desired;i++) print "00"}' > etc/bios/bios.hex
	rm etc/bios/*.o


# Synthesis
synthesis.json: src/soc.sv
	yosys -p "read_verilog -sv src/soc.sv; synth_gowin -top top -json synthesis.json"

# Place and Route
bitstream.json: synthesis.json
	nextpnr-himbaechel -q --json synthesis.json --write bitstream.json --device ${DEVICE} --vopt family=${FAMILY} --vopt cst=etc/boards/${BOARD}.cst

# Generate Bitstream
out.fs: bitstream.json
	gowin_pack -d ${FAMILY} -o out.fs bitstream.json

clean:
	rm etc/bios/bios.hex
	rm etc/bios/bios.bin
	rm etc/bios/bios.opcodes
	rm out.fs

# Program Board
load: out.fs
	openFPGALoader -b ${BOARD} out.fs -f

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
	python etc/scripts/bin_to_sv_mem.py etc/program.bin etc/program.sv etc/program.opcodes -m mock_mem
	rm etc/*.o etc/program.bin etc/program.opcodes

	iverilog -g2012 $(DEFINES) -o graph/cpu_runner.vvp -s cpu_runner etc/run.sv
	vvp -N graph/cpu_runner.vvp
	mv ./cpu_runner.vcd ./graph/cpu_runner.vcd
	rm -f graph/cpu_runner.vvp

run_soc: bios
	iverilog -g2012 $(DEFINES) -o graph/soc_runner.vvp -s soc_runner etc/runsoc.sv
	vvp -N graph/soc_runner.vvp
	mv ./soc_runner.vcd ./graph/soc_runner.vcd
	rm -f graph/soc_runner.vvp

test_cpu_alu:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu_alu.vvp -s cpu_alu_tb test/cpu_alu_tb.sv
	vvp -N graph/cpu_alu.vvp
	mv ./cpu_alu_tb.vcd ./graph/cpu_alu.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_alu.vvp

test_cpu_mdu:
	iverilog -g2012 -o graph/cpu_mdu.vvp -s cpu_mdu_tb test/cpu_mdu_tb.sv
	vvp -N graph/cpu_mdu.vvp
	mv ./cpu_alu_tb.vcd ./graph/cpu_mdu.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_mdu.vvp -N graph/cpu_mdu.vvp


test_cpu_bmu:
	iverilog -g2012 -o graph/cpu_bmu.vvp -s cpu_bmu_tb test/cpu_bmu_tb.sv
	vvp -N graph/cpu_bmu.vvp
	mv ./cpu_bmu_tb.vcd ./graph/cpu_bmu.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_bmu.vvp

test_cpu_csr:
	iverilog -g2012 -o graph/cpu_csr.vvp -s cpu_csr_tb test/cpu_csr_tb.sv
	vvp -N graph/cpu_csr.vvp
	mv ./cpu_csr_tb.vcd ./graph/cpu_csr.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_csr.vvp

test_cpu_regfile:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu_regfile.vvp -s cpu_regfile_tb \
		test/cpu_regfile_tb.sv src/cpu_regfile.sv
	vvp -N graph/cpu_regfile.vvp
	mv ./cpu_regfile_tb.vcd ./graph/cpu_regfile.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_regfile.vvp

test_cpu_insdecode:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu_insdecode.vvp -s cpu_insdecode_tb \
		test/cpu_insdecode_tb.sv src/cpu_insdecode.sv
	vvp -N graph/cpu_insdecode.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode.vcd

	# Second Run: With SUPPORT_ZICSR defined
	iverilog -g2012 -DSUPPORT_ZICSR -o graph/cpu_insdecode_csr.vvp -s cpu_insdecode_tb \
		test/cpu_insdecode_tb.sv src/cpu_insdecode.sv
	vvp -N graph/cpu_insdecode_csr.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode_csr.vcd

	# Third Run: With SUPPORT_ZIFENCEI defined
	iverilog -g2012 -DSUPPORT_ZIFENCEI -o graph/cpu_insdecode_fence.vvp -s cpu_insdecode_tb \
		test/cpu_insdecode_tb.sv src/cpu_insdecode.sv
	vvp -N graph/cpu_insdecode_fence.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode_fence.vcd

	# Fourth Run: With SUPPORT_M defined
	iverilog -g2012 -DSUPPORT_M -o graph/cpu_insdecode_m.vvp -s cpu_insdecode_tb \
		test/cpu_insdecode_tb.sv src/cpu_insdecode.sv
	vvp -N graph/cpu_insdecode_m.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode_m.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_insdecode_tb.vvp -N graph/cpu_insdecode_m.vvp -N graph/cpu_insdecode_csr.vvp -N graph/cpu_insdecode_fence.vvp

test_cpu:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu.vvp -s cpu_tb \
		test/cpu_tb.sv src/cpu.sv
	vvp -N graph/cpu.vvp
	mv ./cpu_tb.vcd ./graph/cpu.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu.vvp

test_tl_interface:
	mkdir -p ./graph

	iverilog -g2012 -o graph/tl_interface_32.vvp -s tl_interface_tb test/tl_interface_tb.sv
	vvp -N graph/tl_interface_32.vvp
	mv ./tl_interface_tb.vcd ./graph/tl_interface_32.vcd

	iverilog -g2012 -DXLEN=64 -o graph/tl_interface_64.vvp -s tl_interface_tb test/tl_interface_tb.sv
	vvp -N graph/tl_interface_64.vvp
	mv ./tl_interface_tb.vcd ./graph/tl_interface_64.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/tl_interface_32.vvp graph/tl_interface_64.vvp

test_tl_memory:
	mkdir -p ./graph

	iverilog -g2012 -o graph/tl_memory_32.vvp -s tl_memory_tb test/tl_memory_tb.sv
	vvp -N graph/tl_memory_32.vvp
	mv ./tl_memory_tb.vcd ./graph/tl_memory_32.vcd

	iverilog -g2012 -DXLEN=64 -o graph/tl_memory_64.vvp -s tl_memory_tb test/tl_memory_tb.sv
	vvp -N graph/tl_memory_64.vvp
	mv ./tl_memory_tb.vcd ./graph/tl_memory_64.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/tl_memory_32.vvp graph/tl_memory_64.vvp

test_tl_ul_uart:
	mkdir -p ./graph

	iverilog -g2012 -o graph/tl_ul_uart_32.vvp -s tl_ul_uart_tb test/tl_ul_uart_tb.sv
	vvp -N graph/tl_ul_uart_32.vvp
	mv ./tl_ul_uart_tb.vcd ./graph/tl_ul_uart_32.vcd

	iverilog -g2012 -DXLEN=64 -o graph/tl_ul_uart_64.vvp -s tl_ul_uart_tb test/tl_ul_uart_tb.sv
	vvp -N graph/tl_ul_uart_64.vvp
	mv ./tl_ul_uart_tb.vcd ./graph/tl_ul_uart_64.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/tl_ul_uart_32.vvp graph/tl_ul_uart_64.vvp

test_tl_switch:
	mkdir -p ./graph

	iverilog -g2012 -o graph/tl_switch.vvp -s tl_switch_tb test/tl_switch_tb.sv
	vvp -N graph/tl_switch.vvp
	mv ./tl_switch_tb.vcd ./graph/tl_switch.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/tl_switch.vvp

clean:
	rm -f synthesis.json
	rm -f bitstream.json
	rm -f out.fs

.PHONY: load
.INTERMEDIATE: synthesis.json bitstream.json
