# NES Memory Map

## Overview

The CPU address space (16-bit, 64KB total) is decoded by combinational logic in `nes_top.v`. The PPU has its own dedicated address space.

## CPU Memory Map

```
$0000 ┌───────────────────────┐
      │  Work RAM (2 KB)      │  work_ram.v (2KB, mirrored every $800)
$07FF │                       │
$0800 ├───────────────────────┤
      │  Work RAM Mirrors     │  (3 × $800 mirrors up to $1FFF)
$1FFF ├───────────────────────┤
$2000 │  PPU Registers        │  Mirrored every 8 bytes through $3FFF
      │  $2000: PPUCTRL       │
      │  $2001: PPUMASK       │
      │  $2002: PPUSTATUS     │
      │  $2003: OAMADDR       │
      │  $2004: OAMDATA       │
      │  $2005: PPUSCROLL     │
      │  $2006: PPUADDR       │
      │  $2007: PPUDATA       │
$3FFF ├───────────────────────┤
$4000 │  APU & I/O Registers  │
      │  $4000-$4013: APU     │  (audio channels & DMC)
      │  $4014: OAM DMA       │  (triggers 256-byte DMA to PPU OAM)
      │  $4015: APU Status    │  (channel status / enable)
      │  $4016: Controller 1  │  (joypad strobe & read)
      │  $4017: Frame Counter │  (APU frame sequencer control)
$401F ├───────────────────────┤
$4020 │  (Unused / Expansion) │  (mapped to 0 in current implementation)
$7FFF ├───────────────────────┤
$8000 │  PRG-ROM (32 KB)      │  prg_rom.v (loaded from prg_rom.hex)
      │                       │
$FFFF └───────────────────────┘
```

### Memory Map Decoding (`nes_top.v`)

```verilog
wire work_ram_cs = (sys_address < 16'h2000);
wire ppu_cs      = (sys_address >= 16'h2000 && sys_address <= 16'h3FFF);
wire apu_cs      = (sys_address >= 16'h4000 && sys_address <= 16'h4017) && 
                   (sys_address != 16'h4014) && (sys_address != 16'h4016);
wire ctrl_cs     = (sys_address == 16'h4016);
wire prg_rom_cs  = (sys_address >= 16'h8000);
```

### Data Bus Arbitration

The CPU data bus is driven by the highest-priority matching decoder:

```verilog
assign cpu_data_in = ppu_cs      ? ppu_data_out :
                     ctrl_cs     ? ctrl_data_out :
                     apu_cs      ? apu_data_out :
                     prg_rom_cs  ? prg_data_out :
                     work_ram_cs ? work_ram_data_out : 8'h00;
```

## PPU Memory Map

The PPU has its own 14-bit address space ($0000-$3FFF):

```
$0000 ┌───────────────────────┐
      │  Pattern Table 0      │  CHR-ROM (8 KB) via chr_rom.v
      │  (4 KB, 256 tiles)    │
$0FFF ├───────────────────────┤
$1000 │  Pattern Table 1      │
      │  (4 KB, 256 tiles)    │
$1FFF ├───────────────────────┤
$2000 │  Nametable 0          │  VRAM (2 KB) via vram_2k
$23BF │                       │
$23C0 │  Attribute Table 0    │
$23FF │                       │
$2400 ├───────────────────────┤
      │  Nametable 1          │  Mirror of NT0 (single-screen)
$27FF ├───────────────────────┤
      │  Nametables 2-3       │  Mirrors of $2000-$27FF
$2FFF ├───────────────────────┤
$3000 │  Mirror of $2000      │  (unused in this implementation)
$3EFF ├───────────────────────┤
$3F00 │  Palette RAM Indexes  │  32 bytes, palette_ram
      │  BG: $3F00-$3F0F     │
      │  Spr: $3F10-$3F1F    │
$3F1F │                       │
$3FFF └───────────────────────┘
```

### Palette Mirroring

The palette RAM implements the NES hardware quirk where sprite palette addresses ending in $00/$04/$08/$0C mirror to the corresponding background palette entries:

```verilog
wire [4:0] mapped_addr = (addr[1:0] == 2'b00) ? {1'b0, addr[3:0]} : addr;
```

## Memory Modules

| Module | Size | Address | Type |
|--------|------|---------|------|
| `work_ram.v` | 2 KB (2048×8) | $0000-$07FF | Synchronous, write-enabled |
| `prg_rom.v` | 32 KB (32768×8) | $8000-$FFFF | Synchronous, initialised from `prg_rom.hex` |
| `chr_rom.v` | 8 KB (8192×8) | PPU $0000-$1FFF | Synchronous, initialised from `chr_rom.hex` |
| `vram_2k` (in ppu_core.v) | 2 KB (2048×8) | PPU $2000-$27FF | Synchronous, write-enabled |
| `palette_ram` (in ppu_core.v) | 32 B (32×8) | PPU $3F00-$3F1F | Synchronous, with DAC read port |
| `oam_ram` (in ppu_core.v) | 256 B (256×8) | PPU OAM | Synchronous, shared CPU/PPU |
| `sec_oam_ram` (in ppu_core.v) | 32 B (32×8) | PPU secondary OAM | Sprite evaluation scratch |

## PRG-ROM Loading

The PRG-ROM is loaded from `prg_rom.hex` using `$readmemh`. This hex file is generated from an iNES ROM file (.nes) using the Python utility:

```bash
python ines_splitter.py mario.nes
```

This extracts PRG-ROM data to `prg_rom.hex` and CHR-ROM data to `chr_rom.hex`.

## Simulation Memory

For simulation purposes, `ram_sim.v` provides a 64KB simulation memory initialized with a NOP sled ($EA), used by the Klaus Dörmann functional test.
