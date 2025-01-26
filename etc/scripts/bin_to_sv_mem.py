#!/usr/bin/env python3
import sys
import re
import argparse

def parse_opcodes(opcode_file):
    """Parse the opcode file to map byte addresses to instruction strings."""
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
        sys.exit(1)
    except Exception as e:
        print(f"Error reading {opcode_file}: {e}")
        sys.exit(1)
    return addr_to_instr

def bin_to_sv_mem(bin_file, sv_file, opcode_file=None, memory_name="mock_mem", mem_width=8):
    """
    Convert a binary file into SystemVerilog word-based memory initialization.

    Args:
      bin_file (str): Path to input .bin file
      sv_file (str): Path to output .sv or .txt file
      opcode_file (str): (Optional) Path to a file containing disassembly or instructions
      memory_name (str): Name of the memory instance (e.g. mock_mem)
      mem_width (int): Width of each memory word in bits (8, 16, 32, 64, etc.)

    In the generated output:
      - memory[i] corresponds to one mem_width-bit word.
      - We group every 'mem_width/8' bytes into one assignment.
      - We interpret those bytes in little-endian order.
    """

    # Validate mem_width
    if mem_width % 8 != 0:
        print(f"Error: mem_width ({mem_width}) must be a multiple of 8.")
        sys.exit(1)

    # Number of bytes in one mem_width-wide word
    word_bytes = mem_width // 8

    # If an opcode file is provided, parse it
    addr_to_instr = {}
    if opcode_file:
        addr_to_instr = parse_opcodes(opcode_file)

    # Debugging: Print the mem_width being used
    print(f"Debug: mem_width set to {mem_width} bits ({word_bytes} bytes).")

    try:
        with open(bin_file, "rb") as f_in, open(sv_file, "w") as f_out:
            binary_data = f_in.read()

            # Iterate over the input binary in chunks of 'word_bytes'
            # 'addr' is the starting byte index of each chunk.
            for addr in range(0, len(binary_data), word_bytes):
                chunk = binary_data[addr:addr+word_bytes]

                # Pad the chunk if it's shorter than word_bytes (e.g. last partial word)
                if len(chunk) < word_bytes:
                    print(f"Warning: Incomplete memory word at address 0x{addr:X}, padding with zeros.")
                    chunk = chunk + b'\x00' * (word_bytes - len(chunk))

                # Build the word_value as a little-endian integer
                word_value = 0
                for i, b in enumerate(chunk):
                    word_value |= (b << (8*i))

                # The memory index in "word units":
                mem_index = addr // word_bytes

                # Collect instruction comments for addresses within this chunk
                # (addr .. addr+word_bytes-1)
                comment_parts = []
                for byte_address in range(addr, addr + len(chunk)):
                    if byte_address in addr_to_instr:
                        # e.g. "0x04: addi x1,x2,100"
                        comment_parts.append(f"0x{byte_address:X}: {addr_to_instr[byte_address]}")

                comment = ""
                if comment_parts:
                    joined_instrs = " ; ".join(comment_parts)
                    comment = f" // {joined_instrs}"

                # Determine the number of hex digits based on mem_width
                hex_digits = word_bytes * 2  # 2 hex digits per byte

                # Example line:
                #   mock_mem.memory['h0003] = 32'h44332211; // 0x0: add x1,x2,x3
                f_out.write(
                    f"{memory_name}.block_ram_inst.memory['h{mem_index:04X}] = {mem_width}'h{word_value:0{hex_digits}X};{comment}\n"
                )

        print(f"SystemVerilog memory initialization written to {sv_file}")

    except FileNotFoundError:
        print(f"Error: File {bin_file} not found.")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Convert a binary file into SystemVerilog memory initialization.")
    parser.add_argument("input_bin_file", help="Path to input .bin file")
    parser.add_argument("output_sv_file", help="Path to output .sv or .txt file")
    parser.add_argument("input_opcode_file", nargs='?', default=None, help="(Optional) Path to a file containing disassembly or instructions")
    parser.add_argument("-m", "--memory_name", default="mock_mem", help="Name of the memory instance (default: mock_mem)")
    parser.add_argument("-x", "--mem_width", type=int, default=8, help="Width of each memory word in bits (default: 8)")

    args = parser.parse_args()

    bin_file = args.input_bin_file
    sv_file = args.output_sv_file
    opcode_file = args.input_opcode_file
    memory_name = args.memory_name
    mem_width = args.mem_width

    bin_to_sv_mem(bin_file, sv_file, opcode_file, memory_name, mem_width)

if __name__ == "__main__":
    main()
