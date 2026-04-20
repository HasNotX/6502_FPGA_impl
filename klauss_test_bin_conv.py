import os

input_bin  = "6502_functional_test.bin"
output_hex = "klaus_dormann.hex"

with open(input_bin, "rb") as f:
    data = bytearray(f.read())

file_size = len(data)
print(f"File size: {file_size} bytes")

# Strip 2-byte PRG header if present
if file_size == 65538:
    print(f"Stripping 2-byte header: {data[0]:02X} {data[1]:02X}")
    data = data[2:]

# Pad to exactly 64KB
while len(data) < 65536:
    data.append(0xEA)
data = data[:65536]

# Report current vectors
print(f"FFFC={data[0xFFFC]:02X} FFFD={data[0xFFFD]:02X}  (reset, should be 00 04)")
print(f"FFFE={data[0xFFFE]:02X} FFFF={data[0xFFFF]:02X}  (IRQ)")

# Force correct reset vector if wrong
if data[0xFFFC] != 0x00 or data[0xFFFD] != 0x04:
    print("Reset vector wrong — patching to $0400")
    data[0xFFFC] = 0x00
    data[0xFFFD] = 0x04

with open(output_hex, "w") as f:
    for b in data:
        f.write(f"{b:02X}\n")

print(f"Done. {output_hex} written.")