test_cpu_alu:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu_alu.vvp -s cpu_alu_tb test/cpu_alu_tb.sv
	vvp -N graph/cpu_alu.vvp
	mv ./cpu_alu_tb.vcd ./graph/cpu_alu_32.vcd

	iverilog -g2012 -DXLEN=64 -o graph/cpu_alu.vvp -s cpu_alu_tb test/cpu_alu_tb.sv
	vvp -N graph/cpu_alu.vvp
	mv ./cpu_alu_tb.vcd ./graph/cpu_alu_64.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_alu.vvp

test_cpu_mdu:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu_mdu.vvp -s cpu_mdu_tb test/cpu_mdu_tb.sv
	vvp -N graph/cpu_mdu.vvp
	mv ./cpu_mdu_tb.vcd ./graph/cpu_mdu_32.vcd

	iverilog -g2012 -DXLEN=64 -o graph/cpu_mdu.vvp -s cpu_mdu_tb test/cpu_mdu_tb.sv
	vvp -N graph/cpu_mdu.vvp
	mv ./cpu_mdu_tb.vcd ./graph/cpu_mdu_64.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_mdu.vvp

test_cpu_bmu:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu_bmu.vvp -s cpu_bmu_tb test/cpu_bmu_tb.sv
	vvp -N graph/cpu_bmu.vvp
	mv ./cpu_bmu_tb.vcd ./graph/cpu_bmu_32.vcd

	iverilog -g2012 -DXLEN=64 -o graph/cpu_bmu.vvp -s cpu_bmu_tb test/cpu_bmu_tb.sv
	vvp -N graph/cpu_bmu.vvp
	mv ./cpu_bmu_tb.vcd ./graph/cpu_bmu_64.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_bmu.vvp

test_cpu_csr:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu_csr.vvp -s cpu_csr_tb test/cpu_csr_tb.sv
	vvp -N graph/cpu_csr.vvp
	mv ./cpu_csr_tb.vcd ./graph/cpu_csr_32.vcd

	iverilog -g2012 -DXLEN=64 -o graph/cpu_csr.vvp -s cpu_csr_tb test/cpu_csr_tb.sv
	vvp -N graph/cpu_csr.vvp
	mv ./cpu_csr_tb.vcd ./graph/cpu_csr_64.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_csr.vvp

test_cpu_regfile:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu_regfile.vvp -s cpu_regfile_tb test/cpu_regfile_tb.sv
	vvp -N graph/cpu_regfile.vvp
	mv ./cpu_regfile_tb.vcd ./graph/cpu_regfile_32.vcd

	iverilog -g2012 -DXLEN=64 -o graph/cpu_regfile.vvp -s cpu_regfile_tb test/cpu_regfile_tb.sv
	vvp -N graph/cpu_regfile.vvp
	mv ./cpu_regfile_tb.vcd ./graph/cpu_regfile_64.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_regfile.vvp

test_cpu_insdecode:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu_insdecode.vvp -s cpu_insdecode_tb test/cpu_insdecode_tb.sv
	vvp -N graph/cpu_insdecode.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode_32.vcd

	# Second Run: With SUPPORT_ZICSR defined
	iverilog -g2012 -DSUPPORT_ZICSR -o graph/cpu_insdecode_csr.vvp -s cpu_insdecode_tb test/cpu_insdecode_tb.sv
	vvp -N graph/cpu_insdecode_csr.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode_32_csr.vcd

	# Fourth Run: With SUPPORT_M defined
	iverilog -g2012 -DSUPPORT_M -o graph/cpu_insdecode_m.vvp -s cpu_insdecode_tb test/cpu_insdecode_tb.sv
	vvp -N graph/cpu_insdecode_m.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode_32_m.vcd

	iverilog -g2012 -DXLEN=64 -o graph/cpu_insdecode.vvp -s cpu_insdecode_tb test/cpu_insdecode_tb.sv
	vvp -N graph/cpu_insdecode.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode_64.vcd

	# Second Run: With SUPPORT_ZICSR defined
	iverilog -g2012 -DXLEN=64 -DSUPPORT_ZICSR -o graph/cpu_insdecode_csr.vvp -s cpu_insdecode_tb test/cpu_insdecode_tb.sv
	vvp -N graph/cpu_insdecode_csr.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode_64_csr.vcd

	# Fourth Run: With SUPPORT_M defined
	iverilog -g2012 -DXLEN=64 -DSUPPORT_M -o graph/cpu_insdecode_m.vvp -s cpu_insdecode_tb test/cpu_insdecode_tb.sv
	vvp -N graph/cpu_insdecode_m.vvp
	mv ./cpu_insdecode_tb.vcd ./graph/cpu_insdecode_64_m.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/cpu_insdecode_tb.vvp graph/cpu_insdecode_m.vvp graph/cpu_insdecode_csr.vvp graph/cpu_insdecode_fence.vvp

test_cpu:
	mkdir -p ./graph

	iverilog -g2012 -o graph/cpu.vvp -s cpu_tb  test/cpu_tb.sv
	vvp -N graph/cpu.vvp
	mv ./cpu_tb.vcd ./graph/cpu_32.vcd

	iverilog -g2012 -DSUPPORT_M -o graph/cpu.vvp -s cpu_tb  test/cpu_tb.sv
	vvp -N graph/cpu.vvp
	mv ./cpu_tb.vcd ./graph/cpu_32_m.vcd

	iverilog -g2012 -DSUPPORT_B -o graph/cpu.vvp -s cpu_tb  test/cpu_tb.sv
	vvp -N graph/cpu.vvp
	mv ./cpu_tb.vcd ./graph/cpu_32_b.vcd

	iverilog -g2012 -DXLEN=64 -o graph/cpu.vvp -s cpu_tb  test/cpu_tb.sv
	vvp -N graph/cpu.vvp
	mv ./cpu_tb.vcd ./graph/cpu_64.vcd

	iverilog -g2012 -DXLEN=64 -DSUPPORT_M -o graph/cpu.vvp -s cpu_tb  test/cpu_tb.sv
	vvp -N graph/cpu.vvp
	mv ./cpu_tb.vcd ./graph/cpu_64_m.vcd

	iverilog -g2012 -DXLEN=64 -DSUPPORT_B -o graph/cpu.vvp -s cpu_tb  test/cpu_tb.sv
	vvp -N graph/cpu.vvp
	mv ./cpu_tb.vcd ./graph/cpu_64_b.vcd

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
	mv ./tl_switch_tb.vcd ./graph/tl_switch_32.vcd

	iverilog -g2012 -DXLEN=64 -o graph/tl_switch.vvp -s tl_switch_tb test/tl_switch_tb.sv
	vvp -N graph/tl_switch.vvp
	mv ./tl_switch_tb.vcd ./graph/tl_switch_63.vcd

	# Clean Up: Remove intermediate .vvp files
	rm -f graph/tl_switch.vvp
