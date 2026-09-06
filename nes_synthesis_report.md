# NES FPGA Implementation Synthesis & Timing Report

## 1. Synthesis Overview
The NES (Nintendo Entertainment System) core was synthesized targeting an **Altera Cyclone V (5CSXFC6D6F31C6)**—the SoC typically found on the DE10 board—to evaluate hardware cost and maximum clock frequency (Fmax) for classic console emulation. The design leverages on-chip block memory for the PRG and CHR ROMs and utilizes a PLL to derive the system's 25 MHz primary clock from the base 50 MHz oscillator.

## 2. Resource Utilization Summary
The synthesis results demonstrate a very efficient and lightweight footprint on the Cyclone V FPGA. Due to the block-based architecture of the console's memory map, Quartus optimally inferred dedicated Block RAMs for the cartridge ROM and work RAM arrays, while keeping logic utilization incredibly low:
*   **ALMs (Logic)**: 3,081 / 41,910 (7.3%)
*   **Registers (FFs)**: 4,199
*   **DSP Blocks**: 0 / 112 (0%)
    *   *The NES architecture predates heavy DSP usage, relying entirely on LUT-based integer arithmetic.*
*   **Block Memory Bits**: 370,944 / 5,662,720 (6.5%)
*   **RAM Blocks**: 47 / 553 (8.5%)
    *   *Directly maps to the `prg_rom`, `chr_rom`, and `work_ram` memory blocks.*
*   **PLLs**: 1 / 15 (6.6%)
    *   *Used to generate the 25 MHz core system clock (`divclk`).*

## 3. Timing & Performance (Fmax)
*   **Target Clock Periods**: 20.00 ns (50 MHz Input) & 40.00 ns (25 MHz System)
*   **Achieved Fmax**: **~50.84 MHz** on the 25 MHz System Clock (`divclk`) (Worst Setup Slack: +20.051 ns)
*   **Achieved Fmax**: **~203.5 MHz** on the 50 MHz Input Clock (`CLOCK_50`) (Worst Setup Slack: +15.086 ns)

Operating on a 25 MHz system clock (which is divided down internally for the 1.79 MHz 6502 CPU and 5.37 MHz PPU), the design possesses a massive **+20 ns timing margin**. This demonstrates that the NES core is easily capable of meeting real-time 60 FPS rendering and audio generation requirements on this silicon without breaking a sweat.

## 4. Critical Path Analysis
**Path Description:**
The real-world Quartus timing report indicates the critical path restricts the main system clock (`divclk`) to a theoretical maximum of ~50.84 MHz. This path is heavily dominated by the combinatorial logic routing across the shared memory-mapped I/O multiplexer (`cpu_data_in` mapping to the PPU, APU, Controller, and Work RAM). 

The path originates at the CPU's program counter / address generation registers (`MOS_6502_CPU`) and traverses the memory decoders in `nes_top.v` before terminating at the CPU's data-in capture registers. This deep combinatorial depth is typical for a single-cycle shared memory bus in retro console architectures.

**Proposed Optimizations:**
To theoretically push the Fmax beyond 50 MHz (which is strictly unnecessary for an NES, but useful from an FPGA design perspective), the memory decoding broadcast could be optimized:
1. **Pipelined Memory Bus**: Insert a pipeline stage between the address decoders (`ppu_cs`, `apu_cs`, `ctrl_cs`) and the actual data multiplexer. This would grant the routing fabric a full clock cycle to resolve the chip selects before merging the data.
2. **Address Decoding Simplification**: The APU/PPU address decoding (e.g., `sys_address >= 16'h4000`) requires a large 16-bit comparator tree. Masking out unused address bits or using Block RAM-based lookup tables for memory-map address decoding would slash the logic levels on the critical path.
