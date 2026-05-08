# Picture Processing Unit (PPU)

## Overview

A cycle-accurate implementation of the Ricoh 2C02 PPU, the graphics processor used in the NES. The PPU generates 256x240 pixel NTSC video at ~60 frames per second.

## Module Hierarchy

```
video_subsystem_top
├── nes_vga_core              (VGA sync + coordinate mapping)
├── ppu_timing_generator      (NTSC timing: 341 dots × 262 lines)
└── ppu_core
    ├── ppu_bg_render         (Background tile rendering pipeline)
    ├── ppu_sprite_eval       (Sprite evaluation / secondary OAM)
    ├── ppu_sprite_render     (Sprite rendering + priority)
    ├── ppu_registers         (Internal PPU register file)
    ├── vram_2k               (2KB nametable VRAM)
    ├── palette_ram           (32-byte palette RAM)
    ├── oam_ram               (256-byte sprite OAM)
    └── sec_oam_ram           (32-byte secondary OAM)
```

## NTSC Timing (`ppu_timing_generator.v`)

The timing generator produces the standard NES PPU dot clock cycle:

| Parameter | Value |
|-----------|-------|
| Dots per scanline | 341 |
| Visible dots | 256 |
| HBlank dots | 85 (dots 256-340) |
| Scanlines per frame | 262 |
| Visible scanlines | 240 |
| VBlank lines | ~20 (lines 241-260) |

A frame-sync reset mechanism synchronizes the PPU timing to VGA VBlank, preventing drift between the 60.09 Hz NTSC rate and 60.00 Hz VGA rate.

## Internal Registers

The PPU exposes six registers mapped to CPU address space $2000-$2007 (mirrored through $3FFF):

| CPU Address | Register | Access | Description |
|-------------|----------|--------|-------------|
| $2000 | PPUCTRL | Write | NMI enable, sprite size, pattern table addresses, VRAM increment |
| $2001 | PPUMASK | Write | Color emphasis, sprite/background enable, left-clip |
| $2002 | PPUSTATUS | Read | VBlank flag, Sprite-0 hit, sprite overflow |
| $2003 | OAMADDR | Write | OAM read/write address |
| $2004 | OAMDATA | Read/Write | OAM data port (auto-incrementing) |
| $2005 | PPUSCROLL | Write | Fine X/Y scroll (two-write latch) |
| $2006 | PPUADDR | Write | VRAM address (two-write latch) |
| $2007 | PPUDATA | Read/Write | VRAM data port (post-increment) |

### Register Details

**PPUCTRL ($2000)**:
- Bit 7: NMI enable (VBlank NMI)
- Bit 6: PPU master/slave (unused)
- Bit 5: Sprite size (0=8x8, 1=8x16)
- Bit 4: Background pattern table address (0=$0000, 1=$1000)
- Bit 3: Sprite pattern table address (0=$0000, 1=$1000)
- Bit 2: VRAM address increment (0=+1, 1=+32)
- Bits 1-0: Base nametable address (0-3)

**PPUSTATUS ($2002)**:
- Bit 7: VBlank flag (cleared on read)
- Bit 6: Sprite-0 hit flag
- Bit 5: Sprite overflow flag
- Bits 4-0: Open bus (reads as 0)

### Scroll Register ($2005) and VRAM Address ($2006)

Both use a two-write latch mechanism (`w` flag) shared between them. The internal 15-bit VRAM address register `v` tracks the current PPU memory access location:

```
v: yyy NN YYYYY XXXXX
   ││  ││ │││││ └──── coarse X scroll (5 bits)
   ││  ││ └──────────── coarse Y scroll (5 bits)
   ││  │└────────────── nametable select Y (1 bit)
   ││  └─────────────── nametable select X (1 bit)
   │└────────────────── fine Y scroll (3 bits)
   └─────────────────── unused (1 bit) 
```

The `t` register holds the temporary (latched) address, and `fine_x` holds the 3-bit fine horizontal scroll offset.

## Background Rendering (`ppu_bg_render.v`)

### 8-Tick Staggered Pipeline

The background renderer fetches tile data using an 8-tick pipeline that absorbs 2-cycle BRAM latency:

| Tick (ppu_x[2:0]) | Action |
|-------|--------|
| 0 | Request nametable byte from VRAM |
| 1 | Wait (BRAM latency) |
| 2 | Latch nametable byte, request attribute byte |
| 3 | Wait (BRAM latency) |
| 4 | Latch attribute byte, request pattern table low byte |
| 5 | Wait (BRAM latency) |
| 6 | Latch pattern low byte, request pattern high byte |
| 7 | Wait (BRAM latency) |

### Shift Register Pipeline

16-bit shift registers hold the pattern and attribute data for pixel output:

- `shift_pat_lo[15:0]` - Low bit of pattern data (8 tiles of 2 pixels each)
- `shift_pat_hi[15:0]` - High bit of pattern data
- `shift_attr_lo[15:0]` - Low attribute bit (replicated across 8-pixel tile)
- `shift_attr_hi[15:0]` - High attribute bit

Shift registers load on tick 0 and shift 1 bit per dot clock. The fine X scroll selects which bit position to output:

```verilog
wire [3:0] bit_sel = 4'd15 - fine_x_scroll;
wire pat_bit_0  = shift_pat_lo[bit_sel];
wire pat_bit_1  = shift_pat_hi[bit_sel];
wire attr_bit_0 = shift_attr_lo[bit_sel];
wire attr_bit_1 = shift_attr_hi[bit_sel];
```

### Pixel Color Index

The final 4-bit pixel index is constructed as:
```
pixel_color_idx = {attr_bit_1, attr_bit_0, pat_bit_1, pat_bit_0}
```

A value of `4'b0000` selects the universal background color (palette entry 0). The leftmost 8 pixels can be clipped via PPUMASK[1].

## Sprite Evaluation (`ppu_sprite_eval.v`)

The sprite evaluation unit operates during dots 65-256 to scan the primary OAM (256 bytes, 64 sprites × 4 bytes each) and copy up to 8 visible sprites to secondary OAM (32 bytes).

### Phase 1: Clear (Dots 1-64)
Secondary OAM is cleared to $FF on even dots.

### Phase 2: Evaluation (Dots 65-256)
- **Odd dots**: Request sprite data from primary OAM at address `{n, b}` (n=sprite index, b=byte offset)
- **Even dots**: Evaluate or copy data

The evaluation checks if a sprite is in-range for the current scanline:
```verilog
wire [8:0] diff = ppu_y - oam_data;
wire is_in_range = (diff >= 9'd0) && (diff < sprite_height);
```

When a sprite is in-range, its 4 bytes (Y, tile index, attributes, X) are copied to secondary OAM. If 8 sprites are already found, the overflow flag is set.

## Sprite Rendering (`ppu_sprite_render.v`)

Sprite rendering operates during dots 257-320 (the sprite fetch window):

- Fetches up to 8 sprite tiles from secondary OAM
- For each sprite, fetches pattern data from CHR ROM (8 bytes per tile)
- During visible dots, evaluates which sprite has priority at each pixel:

```verilog
for (i = 7; i >= 0; i = i - 1) begin
    adjusted_x = {1'b0, sprite_x[i]} + 9'd1;
    if (ppu_x >= adjusted_x && ppu_x < (adjusted_x + 9'd8)) begin
        // Check pixel bits, apply horizontal flip
        // Higher-indexed sprite has lower priority
    end
end
```

### Sprite-0 Hit Detection

A flag is raised when sprite 0 has a non-transparent pixel overlapping a non-transparent background pixel (used for split-scroll effects):

```verilog
assign sprite_0_hit_pulse = rendering_enabled && sprite_0_active && is_sprite_0 &&
                            bg_is_opaque && sp_is_opaque && (ppu_x < 9'd256);
```

## Pixel Multiplexer

At the video_subsystem_top level, background and sprite pixels are combined:

| Condition | Output |
|-----------|--------|
| Both transparent | Universal background (5'h00) |
| BG transparent, sprite opaque | Sprite pixel with sprite flag |
| Sprite transparent, BG opaque | BG pixel with BG flag |
| Both opaque | Sprite wins if priority flag=0, else BG |

The 5th bit (`1'b1` for sprites, `1'b0` for background) selects the upper half of the palette.
