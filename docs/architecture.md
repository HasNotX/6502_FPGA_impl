# System Architecture

## Overview

The NES-on-FPGA design is a hardware implementation of the original Nintendo Entertainment System, written in Verilog and targeting the Altera DE10-Standard board (Cyclone V FPGA). The system is organized into three main clock domains and five major subsystems.

## High-Level Block Diagram

```
                    ┌─────────────────────────────────────────────────────────────┐
                    │                     nes_top.v                              │
                    │                                                           │
  ┌──────────┐     │  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐  │
  │ 50 MHz   │─────│─▶│ vga_pll     │───▶│ clk_25mhz    │───▶│ Clock Gen     │  │
  │ Crystal  │     │  └─────────────┘    │ (PLL)        │    │ (nes_clock_   │  │
  └──────────┘     │                     │              │    │  generator)   │  │
                   │                     └──────────────┘    │               │  │
                   │                                         │ cpu_ce(~1.79MHz)│  │
                   │                                         │ ppu_ce(~5.37MHz)│  │
                   │                                         └───────┬───────┘  │
                   │                                                 │         │
                   │          ┌──────────────────────────────────────┘         │
                   │          ▼                              ▼                  │
                   │  ┌──────────────┐            ┌──────────────────┐         │
                   │  │ MOS 6502 CPU │            │ Video Subsystem  │         │
                   │  │ (cpu_fsm +   │◄──────────▶│  (PPU + VGA)     │         │
                   │  │  cpu_decoder)│   Memory   │                  │         │
                   │  └──────┬───────┘     Bus    │ ppu_core         │         │
                   │         │                    │ ppu_bg_render    │         │
                   │         │                    │ ppu_sprite_eval  │         │
                   │         │                    │ ppu_sprite_render│         │
                   │         │                    │ ppu_timing_gen   │         │
                   │         │                    └────────┬─────────┘         │
                   │         │                             │                   │
                   │         ▼                             ▼                   │
                   │  ┌─────────────────────────────────────────────┐         │
                   │  │          Memory & I/O Bus Arbiter           │         │
                   │  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌────────────┐ │         │
                   │  │  │Work  │ │PRG   │ │CHR   │ │ PPU VRAM/  │ │         │
                   │  │  │RAM   │ │ROM   │ │ROM   │ │ Palette    │ │         │
                   │  │  └──────┘ └──────┘ └──────┘ └────────────┘ │         │
                   │  └─────────────────────────────────────────────┘         │
                   │                                                           │
                   │  ┌──────────┐  ┌────────────┐  ┌──────────────────┐     │
                   │  │APU/Audio │  │Controller  │  │ OAM DMA          │     │
                   │  │(APU.v +  │  │(nes_       │  │ (oam_dma.v)      │     │
                   │  │SoundDrv) │  │ controller)│  │                  │     │
                   │  └──────────┘  └────────────┘  └──────────────────┘     │
                   └─────────────────────────────────────────────────────────────┘
```

## Clock Domains

The system uses a cascaded clocking scheme:

| Clock | Frequency | Source | Used By |
|-------|-----------|--------|---------|
| `CLOCK_50` | 50 MHz | Board crystal | PLL reference, I2C config |
| `clk_25mhz` | 25.175 MHz | PLL (`vga_pll.v`) | All logic, VGA pixel clock |
| `ppu_ce` | ~5.37 MHz | Fractional accumulator | PPU dot clock (3x CPU) |
| `cpu_ce` | ~1.79 MHz | Divided from ppu_ce (1:3) | CPU core clock enable |

### Clock Generation (`nes_clock_generator.v`)

The clock generator uses a 32-bit fractional phase accumulator to derive the PPU clock from 25.175 MHz:

```verilog
localparam PPU_INC = 32'd916029601;
{ppu_ce, ppu_acc} <= {1'b0, ppu_acc} + {1'b0, PPU_INC};
```

The CPU clock is generated as a hard-locked 1:3 divider from the PPU clock, matching the NTSC standard ratio.

## Data Flow

1. **CPU Fetch**: CPU addresses PRG ROM ($8000-$FFFF) or Work RAM ($0000-$1FFF) to read instructions/data
2. **PPU Rendering**: PPU reads CHR ROM for pattern data, writes pixel color indices to the scanline buffer
3. **VGA Output**: VGA sync generator reads from the ping-pong buffer (completed scanline) and outputs via DAC
4. **Audio**: APU generates digital samples → SoundDriver → WM8731 codec via I2C
5. **DMA**: OAM DMA steals the bus from CPU to transfer sprite data to PPU OAM

## Memory Map

```
$0000 - $1FFF:  Work RAM (2KB + mirrors)
$2000 - $3FFF:  PPU Registers & VRAM (mirrored every 8 bytes)
$4000 - $4017:  APU & I/O Registers
$4014:          OAM DMA
$4016:          Controller 1
$8000 - $FFFF:  PRG ROM (32KB)
```

## Interrupts

- **NMI**: Generated by PPU at start of VBlank (vertical blanking interval)
- **IRQ**: Generated by APU frame sequencer or DMC (DPCM sample finished)
- **Reset**: Board reset or SW[9] toggle
