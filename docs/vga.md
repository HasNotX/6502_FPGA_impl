# VGA Output Pipeline

## Overview

The VGA subsystem converts the NES's 256x240 internal resolution to standard 640x480@60Hz VGA output with 2x integer scaling and pillarboxing.

## Module Hierarchy

```
video_subsystem_top
└── nes_vga_core
    ├── vga_sync_generator       (640×480@60Hz timing)
    ├── nes_coordinate_mapper    (Coordinate scaling + mapping)
    ├── ping_pong_line_buffer    (Domain-crossing scanline buffer)
    └── nes_palette_lut          (6-bit color → 30-bit RGB)
```

## VGA Sync Generator (`vga_sync_generator.v`)

Generates standard 640x480@60Hz VGA timing at 25.175 MHz pixel clock:

| Horizontal | Pixels | Vertical | Lines |
|------------|--------|----------|-------|
| Visible | 640 | Visible | 480 |
| Front porch | 16 | Front porch | 10 |
| Sync pulse | 96 | Sync pulse | 2 |
| Back porch | 48 | Back porch | 33 |
| **Total** | **800** | **Total** | **525** |

## Coordinate Mapping (`nes_coordinate_mapper.v`)

The NES 256x240 resolution is scaled 2x to 512x480 and centered horizontally with 64-pixel pillarboxing on each side:

```verilog
localparam H_OFFSET = 10'd64;   // (640 - (256 * 2)) / 2
localparam V_OFFSET = 10'd0;    // (480 - (240 * 2)) / 2
```

NES coordinates are derived by subtracting offsets and downshifting:
```verilog
assign nes_x = ((pixel_x - H_OFFSET + TEST_OFFSET) >> 1);
assign nes_y = ((pixel_y - V_OFFSET) >> 1);
```

## Ping-Pong Line Buffer (`ping_pong_line_buffer.v`)

A dual-buffer system prevents screen tearing by isolating the PPU rendering domain from the VGA display domain:

- Two 256-entry × 5-bit SRAM buffers (`buffer_a`, `buffer_b`)
- PPU writes to one buffer during scanline rendering
- VGA reads from the other buffer (the completed scanline)
- Buffers swap every scanline based on `ppu_y[0]`

```
PPU writes to buffer A ─────────────────▶ VGA reads from buffer B
       (even scanlines)                          (even scanlines)

PPU writes to buffer B ─────────────────▶ VGA reads from buffer A
       (odd scanlines)                           (odd scanlines)
```

## NES Palette LUT (`nes_palette_lut.v`)

A 64-entry lookup table converts NES 6-bit color codes (from the PPU palette RAM) to 30-bit RGB values (10 bits per channel for the DE10-Lite DAC).

The NES color palette consists of 4 rows of 16 colors:
- **Row 0 ($00-$0F)**: Dark colors
- **Row 1 ($10-$1F)**: Medium/standard colors
- **Row 2 ($20-$2F)**: Light colors
- **Row 3 ($30-$3F)**: Pale/bright colors

Each entry maps to 8-bit R, G, B values (from the standard NTSC palette) scaled to 10-bit by left-shifting 2 positions.

## Pixel Data Path

```
PPU Dot Clock Domain (5.37 MHz)
  ┌─────────────────────────────────────────┐
  │ ppu_bg_render ──▶ ppu_sprite_render    │
  │        │                   │            │
  │        ▼                   ▼            │
  │    Pixel Multiplexer (bg vs sprite)     │
  │              │                          │
  │              ▼                          │
  │       5-bit color index                 │
  └──────────────┬──────────────────────────┘
                 │
                 ▼
    Ping-Pong Buffer (domain crossing)
                 │
                 ▼
VGA Domain (25.175 MHz)
  ┌──────────────┬──────────────────────────┐
  │              ▼                          │
  │    Palette LUT (6-bit → 30-bit RGB)    │
  │              │                          │
  │              ▼                          │
  │    VGA DAC (R/G/B each 8-bit)          │
  └─────────────────────────────────────────┘
```
