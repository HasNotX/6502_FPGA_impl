# Testing & Verification

## Overview

The project includes verification infrastructure at multiple levels: CPU functional testing, PPU timing simulation, and board-level debugging features.

## CPU Functional Test

### Klaus Dörmann 6502 Test Suite

The primary CPU verification is done using Klaus Dörmann's comprehensive 6502 functional test suite. This test exercises nearly every 6502 instruction and addressing mode.

**Files involved:**
- `6502_functional_test.bin` — Original binary
- `klaus_dormann.hex` — Converted hex for Verilog simulation
- `klauss_test_bin_conv.py` — Binary-to-hex converter
- `MOS_6502_CPU_tb.v` — Testbench

### Testbench Architecture

```verilog
module MOS_6502_CPU_tb;
    parameter KLAUS_HEX    = "klaus_dormann.hex";
    parameter SUCCESS_PC   = 16'h3469;    // Success trap address
    parameter MAX_CYCLES   = 100_000_000;
    // ...
    // Loads test into RAM
    initial $readmemh(KLAUS_HEX, dut.mem_inst.mem);
    // Monitors for infinite loop at success address
    // Reports pass/fail with register dump
endmodule
```

### Running the Test

```bash
# Convert binary to hex
python klauss_test_bin_conv.py

# Run in ModelSim/Questa
vsim -do simulation/questa/run.do
```

### Test Output

On success:
```
============================================================
PASS  Klaus functional test PASSED at PC=3469
All tests completed in <N> cycles.
============================================================
```

On failure:
```
============================================================
FAIL  CPU trapped at PC=XXXX  (cycle N)
Registers: A=XX X=XX Y=XX SP=XX SR=XXXXXXXX
Look up $XXXX in Klaus's listing to identify the failing test.
============================================================
```

### Debug Features in Testbench

The testbench includes extensive debug tracing:

- **Progress heartbeat**: Register dump every 5M cycles
- **Early fetch trace**: First 20 instruction fetches
- **BRK push debug**: Stack push details during BRK
- **RTI debug**: Stack pull details during RTI
- **IRQ handler entry**: Logging when IRQ handler at $37AB is entered
- **Focused trace**: Full register state for range $3700-$3800 (near failure point)
- **Stack spy**: All stack-page writes and relevant reads

## PPU Timing Simulation

### PPU Timing Generator Testbench

`ppu_timing_generator_tb.v` verifies the NTSC timing generator produces correct dot/line counts and sync signals.

## PPU Coordinate Trap

A hardware debugging feature in the PPU captures the exact PPU coordinate when the CPU writes to the scroll registers ($2005/$2006) during visible rendering:

```verilog
if ((cpu_addr == 3'd5 || cpu_addr == 3'd6) && ppu_y < 9'd240) begin
    trap_y <= ppu_y;
    trap_x <= ppu_x;
end
```

The captured coordinates are displayed on the 7-segment LEDs for real-time debugging.

## Board-Level Debug Indicators

| Indicator | What It Shows |
|-----------|---------------|
| LEDR[7:0] | PPUMASK register value (which rendering layers are enabled) |
| LEDR[8] | DMA active (OAM DMA in progress) |
| LEDR[9] | PLL locked (clock generation stable) |
| HEX[5:3] | Trap Y coordinate |
| HEX[2:0] | Trap X coordinate |

## Pixel Bus Tracing

The video subsystem includes several debug output wires:

```verilog
output wire [7:0]  dbg_ctrl,         // PPUCTRL value
output wire [7:0]  dbg_mask,         // PPUMASK value
output wire [14:0] dbg_vram_addr,    // Current VRAM address
output wire [7:0]  dbg_palette_00,   // Palette entry 0 (universal background)
output wire [7:0]  dbg_nt_latch,     // Last latched nametable byte
```

## PPU Background Render Debug

The background renderer exposes:
- `dbg_nt_latch` — Last nametable byte fetched
- `active_v_reg` — Current VRAM address register (also `dbg_vram_addr`)
- `fine_x_scroll` — Fine X scroll value

## Telemetry Files

The project includes telemetry data from real hardware runs:

- `simulation_telemetry.txt` — Simulation run data
- `sprite_telemetry.txt` — Sprite rendering debug data
