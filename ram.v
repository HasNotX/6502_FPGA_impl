// =============================================================================
// ram_fpga.v  —  Quartus / Intel FPGA BRAM wrapper
//
// This module infers a true single-port M10K (Cyclone) or MLAB BRAM block.
// It uses SYNCHRONOUS reads with "read-during-write = new data" (write-first)
// which Quartus maps cleanly to M10K primitives.
//
// IMPORTANT — read latency:
//   Registered read means data_out is valid ONE cycle after addr is presented.
//   The FSM's _WAIT states already compensate for this.  Every state that
//   samples data_in has a paired _WAIT state before it, providing exactly
//   one cycle of address setup before the data is captured.
//
// If your target device is Cyclone IV/V/10:
//   Quartus will infer this as an M10K block.  No IP core needed.
//   Just add this file to your project and set:
//     Assignments → Settings → Compiler Settings → Advanced Settings (Synthesis)
//     → "Auto RAM Recognition" = ON  (it is ON by default).
//
// If your target is MAX 10:
//   Same flow — MAX 10 also has M10K blocks.
//
// Initialisation for Klaus Dörmann test:
//   Option A (recommended): use Quartus In-System Memory Content Editor or
//     the mif_to_hex.py script below to produce a .mif file and set
//     INIT_FILE = "6502_functional_test.mif" in the parameter.
//   Option B: $readmemh in simulation only — does NOT initialise BRAM
//     in hardware. Use a .mif file for hardware init.
// =============================================================================

module ram #(
    parameter INIT_FILE = ""    // Set to .mif filename for hardware init
                                // e.g. "6502_functional_test.mif"
) (
    input            clk,
    input  [15:0]    addr,
    input  [7:0]     data_in,
    input            write_en,
    output reg [7:0] data_out   // registered — valid one cycle after addr
);

// 64 KB inferred BRAM
// Quartus recognises this pattern as M10K "Simple Dual Port" or "Single Port"
reg [7:0] mem [0:65535];

// Optional .mif initialisation (synthesis + simulation)
// Quartus uses INIT_FILE parameter; for simulation you can also
// call $readmemh in the testbench after elaboration.
generate
    if (INIT_FILE != "") begin
        initial $readmemh(INIT_FILE, mem);
    end
endgenerate

always @(posedge clk) begin
    if (write_en) begin
        mem[addr]  <= data_in;
        data_out   <= data_in;   // write-through so FSM sees written data immediately
    end else begin
        data_out <= mem[addr];   // registered read — 1-cycle latency
    end
end

endmodule