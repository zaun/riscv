import sys
import re

def parse_opcodes(opcode_file):
    """Parse the opcode file to map addresses to instructions."""
    addr_to_instr = {}
    opcode_pattern = re.compile(r"^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F ]+)\s+(.+)$")
    try:
        with open(opcode_file, "r") as f:
            for line in f:
                match = opcode_pattern.match(line)
                if match:
                    address = int(match.group(1), 16)
                    instruction = match.group(3).strip()
                    addr_to_instr[address] = instruction
    except FileNotFoundError:
        print(f"Error: Opcode file {opcode_file} not found.")
    except Exception as e:
        print(f"Error: {e}")
    return addr_to_instr

def bin_to_sv_mem(bin_file, sv_file, opcode_file=None, memory_name="mock_memory"):
    """Convert binary to SystemVerilog memory with optional opcode comments."""
    addr_to_instr = {}
    if opcode_file:
        addr_to_instr = parse_opcodes(opcode_file)

    try:
        with open(bin_file, "rb") as f:
            binary_data = f.read()

        with open(sv_file, "w") as f:
            for addr, byte in enumerate(binary_data):
                comment = ""
                if addr in addr_to_instr:
                    comment = f" // {addr_to_instr[addr]}"
                f.write(f"{memory_name}.memory['h{addr:04X}] = 8'h{byte:02X};{comment}\n")

        print(f"SystemVerilog memory initialization written to {sv_file}")
    except FileNotFoundError:
        print(f"Error: File {bin_file} not found.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python bin_to_sv_mem.py <input_bin_file> <output_sv_file> [input_opcode_file] -m <memory_name>")
    else:
        bin_file = None
        sv_file = None
        opcode_file = None
        memory_name = "mock_mem"

        # Parse arguments
        args = sys.argv[1:]
        if "-m" in args:
            m_index = args.index("-m")
            if m_index + 1 < len(args):
                memory_name = args[m_index + 1]
                args = args[:m_index] + args[m_index + 2:]
            else:
                print("Error: Missing value for -m option.")
                sys.exit(1)

        if len(args) == 2:
            bin_file = args[0]
            sv_file = args[1]
        elif len(args) == 3:
            bin_file = args[0]
            sv_file = args[1]
            opcode_file = args[2]
        else:
            print("Usage: python bin_to_sv_mem.py <input_bin_file> <output_sv_file> [input_opcode_file] -m <memory_name>")
            sys.exit(1)

        bin_to_sv_mem(bin_file, sv_file, opcode_file, memory_name)
