# NES on Altera DE10-Lite

An FPGA implementation of the Nintendo Entertainment System (NES) in Verilog, targeting the Altera DE10-Lite development board (Cyclone V FPGA). This project implements a **full-cycle-accurate NES** including the MOS 6502 CPU, Ricoh 2C02 PPU, APU audio, and VGA output.

## Features

- **MOS 6502 CPU**: Full FSM-based implementation with ~100 supported opcodes, all addressing modes, NMI/IRQ interrupts, and stack operations
- **Ricoh 2C02 PPU**: Cycle-accurate NTSC timing (341×262), background rendering (8-tick pipeline), sprite evaluation (8 sprites/scanline), sprite-0 hit detection
- **VGA Output**: 640×480@60Hz with 2x integer scaling, tear-free ping-pong scanline buffering
- **APU Audio**: 5-channel sound (2× Square, Triangle, Noise, DMC) output via WM8731 codec
- **OAM DMA**: Cycle-accurate sprite DMA controller
- **Controller Input**: NES protocol-compatible joypad interface

## Hardware Target

| Parameter | Value |
|-----------|-------|
| Board | Altera DE10-Lite |
| FPGA | Cyclone V 5CSXFC6D6F31C6 |
| Input Clock | 50 MHz |
| System Clock | 25.175 MHz (via PLL) |
| CPU Speed | ~1.79 MHz |
| PPU Speed | ~5.37 MHz |
| Video Output | VGA 640×480@60Hz |
| Audio Codec | WM8731 (I2C + I2S) |

## Quick Start

```bash
# 1. Prepare a ROM
python ines_splitter.py mario.nes

# 2. Open in Quartus Prime
#    File → Open Project → nes.qpf → Start Compilation

# 3. Program the board via USB-Blaster
```

## Project Structure

```
nes/
├── nes_top.v                  # System top-level (bus arbiter, I/O, all subsystems)
├── MOS_6502_CPU.v             # CPU wrapper + address generation
├── cpu_fsm.v                  # 6502 execution FSM (58+ states)
├── cpu_decoder.v              # Opcode decoder (~100 instructions)
├── nes_clock_generator.v      # Fractional accumulator clock gen
│
├── video_subsystem/
│   ├── video_subsystem_top.v  # Video integration (PPU + VGA + pixel mux)
│   ├── ppu/ppu_core.v         # PPU core (registers, OAM, VRAM, sprite logic)
│   ├── ppu/ppu_bg_render.v    # Background rendering pipeline
│   ├── ppu/ppu_sprite_eval.v  # Sprite evaluation engine
│   ├── ppu/ppu_sprite_render.v# Sprite rendering + priority
│   ├── ppu/ppu_timing_generator.v # NTSC timing generator
│   ├── vga/nes_vga_core.v     # VGA sync + coordinate mapper
│   ├── vga/vga_sync_generator.v  # 640×480@60Hz timing
│   ├── vga/nes_pallete_lut.v  # 64-entry NES-to-RGB color LUT
│   └── ping_pong_line_buffer.v   # Tear-free scanline buffer
│
├── APU.v / nes_apu.v          # NES APU (5-channel audio)
├── SoundDriver.v              # WM8731 I2S audio driver
├── I2C_AV_Config.v            # I2C configuration controller
├── I2C_Controller.v           # I2C bus protocol engine
│
├── memory/
│   ├── work_ram.v             # 2KB CPU work RAM
│   ├── prg_rom.v              # 32KB program ROM (from prg_rom.hex)
│   └── chr_rom.v              # 8KB character ROM (from chr_rom.hex)
│
├── nes_controller.v           # $4016 joypad interface
├── oam_dma.v                  # OAM DMA controller
├── deboucer.v                 # Button debouncer
│
├── ines_splitter.py           # ROM → prg_rom.hex / chr_rom.hex converter
├── klauss_test_bin_conv.py    # 6502 test binary converter
├── MOS_6502_CPU_tb.v          # CPU testbench (Klaus Dörmann suite)
│
├── nes.qpf / nes.qsf          # Quartus Prime project files
└── docs/                      # Detailed documentation
```

## Documentation

Detailed documentation is available in the `docs/` directory:

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | System block diagram, clock domains, data flow, memory map |
| [CPU (6502)](docs/cpu.md) | FSM states, opcode decoder, addressing modes, ALU, interrupts |
| [PPU (Video)](docs/ppu.md) | NTSC timing, background pipeline, sprite eval/render, registers |
| [VGA Output](docs/vga.md) | Sync generation, 2x scaling, ping-pong buffer, color LUT |
| [APU (Audio)](docs/apu.md) | Square/Triangle/Noise/DMC channels, frame sequencer, mixing |
| [Memory Map](docs/memory_map.md) | CPU and PPU address spaces, module descriptions |
| [I/O & DMA](docs/io.md) | Controller protocol, OAM DMA, board I/O, debouncing |
| [Building](docs/building.md) | Quartus build, ROM preparation, programming, simulation |
| [Testing](docs/testing.md) | 6502 functional test, PPU timing, debug features |

## I/O Connections

| Signal | Description |
|--------|-------------|
| CLOCK_50 | 50 MHz input clock |
| KEY[3:0] | Push buttons |
| SW[9] | System reset |
| SW[3] | NES Select button |
| GPIO buttons | A, B, Start, Left, Right |
| VGA_R/G/B[7:0] | VGA analog outputs |
| VGA_HS/VS | VGA sync signals |
| AUD_MCLK/LRCK/SCK/SDIN | Audio codec interface |
| LEDR[9:0] | Status indicators |
| HEX[5:0] | 7-segment debug displays |

## License

The APU modules (`APU.v`, `SoundDriver.v`) are Copyright (c) 2012-2013 Ludvig Strigeus, GPL Licensed.  
The I2C controller is Copyright (c) 2012 Terasic Technologies Inc.  
All other code is for educational purposes.
