#!/usr/bin/env python3
import sys
import os

def split_ines(filepath):
    if not os.path.isfile(filepath):
        print("Error: File not found.")
        return

    with open(filepath, "rb") as f:
        header = f.read(16)
        
        if header[0:4] != b"NES\x1A":
            print("Error: Invalid iNES header.")
            return
            
        prg_banks = header[4]
        chr_banks = header[5]
        
        prg_size = prg_banks * 16384
        chr_size = chr_banks * 8192
        
        print("iNES ROM Detected")
        print(f"PRG-ROM Size: {prg_size} bytes ({prg_banks} banks)")
        print(f"CHR-ROM Size: {chr_size} bytes ({chr_banks} banks)")
        
        prg_data = f.read(prg_size)
        chr_data = f.read(chr_size)
        
        with open("prg_rom.hex", "w") as prg_out:
            for byte in prg_data:
                prg_out.write(f"{byte:02X}\n")
                
        if chr_size > 0:
            with open("chr_rom.hex", "w") as chr_out:
                for byte in chr_data:
                    chr_out.write(f"{byte:02X}\n")
                    
        print("Successfully extracted prg_rom.hex and chr_rom.hex")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python ines_splitter.py <rom_file.nes>")
    else:
        split_ines(sys.argv[1])