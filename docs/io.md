# I/O Subsystems

## Overview

The I/O subsystem handles controller input, DMA transfers, and board-level I/O (LEDs, 7-segment displays, switches, buttons).

## NES Controller (`nes_controller.v`)

Implements the standard NES joypad interface at CPU address $4016.

### Protocol

1. CPU writes to $4016 with bit 0 = 1 (strobe high) → controller latches button states
2. CPU writes to $4016 with bit 0 = 0 (strobe low) → controller freezes state
3. CPU reads $4016 eight times → shift register outputs one button per read (LSB first)

### Button Mapping

```
Bit 0: A (GPIO button A)
Bit 1: B (GPIO button B)
Bit 2: Select (SW[3])
Bit 3: Start (GPIO button Start)
Bit 4: Up (unused, tied to 0)
Bit 5: Down (unused, tied to 0)
Bit 6: Left (GPIO button Left)
Bit 7: Right (GPIO button Right)
```

### Implementation

```verilog
always @(posedge clk) begin
    if (ctrl_write_pulse) strobe <= cpu_data_in[0];
    if (strobe)           shift_reg <= button_state;
    else if (ctrl_read_pulse) shift_reg <= {1'b0, shift_reg[7:1]};
end
assign cpu_data_out = {7'b0000000, shift_reg[0]};
```

### Button Debouncing

External GPIO buttons are debounced using a 20-bit counter that requires the signal to be stable for ~2^20 clock cycles (~41 ms at 25 MHz):

```verilog
module button_debouncer (
    input  wire clk, button_in,
    output reg  button_out
);
    reg [19:0] counter;
    // Synchronizer + counter-based debounce
    if (sync_1 == button_out) counter <= 0;
    else if (counter == 20'hFFFFF) button_out <= sync_1;
endmodule
```

## OAM DMA (`oam_dma.v`)

The OAM DMA controller transfers 256 bytes of sprite data from system memory to the PPU's Object Attribute Memory (OAM) at $2004.

### Trigger

A CPU write to $4014 triggers the DMA:
```verilog
if (cpu_write_en && cpu_addr_in == 16'h4014) begin
    page <= cpu_data_in;   // Source page (e.g., $02 = $0200-$02FF)
    offset <= 8'd0;
    dma_active <= 1'b1;
    state <= STATE_HALT;
end
```

### DMA States

| State | Description |
|-------|-------------|
| IDLE | Monitoring for $4014 write |
| HALT | Wait for next even CPU cycle (dummy read) |
| READ | Read byte from source address {page, offset} |
| WRITE | Write byte to PPU OAMDATA ($2004), increment offset |

### Bus Arbitration

When DMA is active, the system bus is controlled by the DMA engine:
```verilog
wire [15:0] sys_address  = dma_active ? dma_address  : cpu_address;
wire [7:0]  sys_data_out = dma_active ? dma_data_out : cpu_data_out;
```

The CPU clock enable is gated during DMA:
```verilog
wire effective_cpu_ce = raw_cpu_ce && !dma_active;
```

## Board I/O

### LEDs

| LED | Signal | Description |
|-----|--------|-------------|
| LEDR[7:0] | `ppu_dbg_mask` | PPU mask register value |
| LEDR[8] | `dma_active` | OAM DMA active indicator |
| LEDR[9] | `pll_locked` | PLL lock status |

### 7-Segment Displays

The six 7-segment displays show the PPU trap coordinate — the position where the CPU last wrote to the scroll registers during rendering:

- **HEX5-HEX3**: Trap Y coordinate (9-bit, 3 hex digits)
- **HEX2-HEX0**: Trap X coordinate (9-bit, 3 hex digits)

This is a debugging feature that captures CPU writes to $2005/$2006 during visible scanlines, helping identify raster effect timing issues.

### Switches & Buttons

| Signal | Function |
|--------|----------|
| SW[9] | System reset |
| SW[3] | NES Select button |
| SW[7:3] | Radius control (Assignment project only) |
| KEY[3:0] | Push buttons (active-low, inverted in logic) |
| GPIO buttons | A, B, Start, Left, Right (via pin headers) |
