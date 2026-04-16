# NES on Altera DE10-Lite

An FPGA implementation of the Nintendo Entertainment System (NES) running on the Altera DE10-Lite development board (Cyclone V FPGA).

## Overview

This project implements a fully functional NES system in Verilog, targeting the Altera DE10-Lite board. It consists of three main subsystems:

- **MOS 6502 CPU** - Full implementation of the NES CPU
- **Picture Processing Unit (PPU)** - NES graphics processor
- **VGA Output** - Converts NES video to standard VGA

## Hardware Target

- **Board**: Altera DE10-Lite
- **FPGA**: Cyclone V (5CSXFC6D6F31C6)
- **Input Clock**: 50 MHz
- **Output**: VGA (640x480)

## Project Structure

```
nes/
├── cpu/                          # CPU Subsystem
│   ├── MOS_6502_CPU.v           # Main CPU core
│   ├── cpu_fsm.v                # Instruction execution FSM
│   └── cpu_decoder.v            # Opcode decoder
│
├── video_subsystem/             # Video/GPU Subsystem
│   ├── vga/
│   │   ├── vga_sync_generator.v
│   │   └── nes_vga_core.v
│   ├── ppu/
│   │   ├── ppu_core.v          # Ricoh 2C02 PPU core
│   │   ├── ppu_bg_render.v     # Background rendering
│   │   └── ppu_sprite_eval.v   # Sprite evaluation
│   └── memory/
│       ├── vram.v              # 2KB Video RAM
│       └── palette_ram.v        # 32-byte Palette RAM
│
├── nes_clock_generator.v        # CPU/PPU clock generation
├── ram.v                        # CPU RAM (64KB)
└── nes.qsf                      # Quartus project file
```

## CPU (MOS 6502)

The CPU implementation includes:

- **FSM-based execution** - Multi-cycle instruction execution
- **Instruction decoder** - Supports LDA, ADC, AND instructions
- **Addressing modes** - Immediate, Zero Page, Absolute, Indexed, Indirect
- **ALU operations** - Addition, subtraction, bitwise AND

### Supported Instructions

| Opcode | Instruction | Addressing Mode |
|--------|-------------|-----------------|
| 0xA9   | LDA         | Immediate       |
| 0xA5   | LDA         | Zero Page       |
| 0xAD   | LDA         | Absolute        |
| 0xB5   | LDA         | Zero Page,X     |
| 0xBD   | LDA         | Absolute,X      |
| 0xB9   | LDA         | Absolute,Y      |
| 0xA1   | LDA         | (Indirect,X)   |
| 0xB1   | LDA         | (Indirect),Y   |
| 0x69   | ADC         | Immediate       |
| ...    | (more)      | Various         |

## PPU (Picture Processing Unit)

The PPU mimics the Ricoh 2C02 with:

- **Internal registers** - PPUCTRL, PPUMASK, PPUSTATUS, PPUSCROLL, PPUADDR, PPUDATA
- **2KB VRAM** - Nametable storage
- **32-byte Palette RAM** - Color palette
- **256-byte OAM** - Object Attribute Memory for sprites

### Background Rendering

- 8-cycle tile fetch pipeline
- Nametable, attribute, and pattern table fetches
- 16-bit shift registers for pixel output

## Clock Generation

Uses fractional phase accumulators to generate accurate NES timings:

- **CPU Clock**: ~1.79 MHz (NTSC standard)
- **PPU Clock**: ~5.37 MHz (3x CPU clock)

## Building the Project

1. Open `nes.qpf` in Quartus Prime
2. Compile the design
3. Program the DE10-Lite board via USB-Blaster

## I/O Connections

| Signal | Description |
|--------|-------------|
| CLOCK_50 | 50 MHz input clock |
| KEY[3:0] | Push buttons |
| SW[9:0] | Slide switches |
| VGA_R[7:0] | Red output |
| VGA_G[7:0] | Green output |
| VGA_B[7:0] | Blue output |
| VGA_HS | Horizontal sync |
| VGA_VS | Vertical sync |
| LEDR[9:0] | LED indicators |
| HEX[5:0] | 7-segment displays |

## License

This project is for educational purposes.