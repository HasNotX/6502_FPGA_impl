/*
 * File: ppu_timing_generator_tb.v
 * Description: Verification testbench for the NTSC timing generator.
 * Simulates the 25.175 MHz master clock and the fractional 5.37 MHz ppu_ce.
 */

`timescale 1ns/1ps

module ppu_timing_generator_tb;

    reg clk;
    reg reset;
    reg ppu_ce;
    reg frame_sync_reset;

    wire [8:0] ppu_x;
    wire [8:0] ppu_y;
    wire visible;
    wire hblank;
    wire vblank;

    ppu_timing_generator uut (
        .clk(clk),
        .reset(reset),
        .ppu_ce(ppu_ce),
        .frame_sync_reset(frame_sync_reset),
        .ppu_x(ppu_x),
        .ppu_y(ppu_y),
        .visible(visible),
        .hblank(hblank),
        .vblank(vblank)
    );

    // 25.175 MHz Clock Generation (~39.72 ns period)
    always #19.86 clk = ~clk;

    // Fractional Accumulator (Mocking nes_clock_generator.v)
    reg [31:0] ppu_acc;
    localparam PPU_INC = 32'd916029601;

    always @(posedge clk) begin
        if (reset) begin
            ppu_acc <= 32'd0;
            ppu_ce  <= 1'b0;
        end else begin
            {ppu_ce, ppu_acc} <= {1'b0, ppu_acc} + {1'b0, PPU_INC};
        end
    end

    initial begin
        $dumpfile("ppu_timing.vcd");
        $dumpvars(0, ppu_timing_generator_tb);

        clk = 0;
        reset = 1;
        frame_sync_reset = 0;

        #100;
        @(posedge clk);
        reset <= 0;

        $display("Starting Simulation. Waiting for NTSC Frame Rollover...");
        
        // Wait for the exact NTSC frame boundary (341 * 262 dots)
        wait (ppu_y == 9'd261 && ppu_x == 9'd340);
        
        // Wait until the clock enable fires to trigger the actual rollover
        wait (ppu_ce == 1'b1);
        @(posedge clk);
        #1; // Small delay to allow non-blocking outputs to stabilize in simulation
        
        // Verify Rollover
        if (ppu_y == 9'd0 && ppu_x == 9'd0) begin
            $display("[PASS] Frame rollover verified at 341x262.");
        end else begin
            $display("[FAIL] Frame rollover incorrect. x=%d, y=%d", ppu_x, ppu_y);
        end

        // Verify Frame Sync Injection
        #5000;
        @(posedge clk);
        frame_sync_reset <= 1'b1; // Non-blocking assignment avoids simulation race conditions
        
        @(posedge clk);
        frame_sync_reset <= 1'b0;
        
        @(posedge clk);
        #1;
        if (ppu_y == 9'd241 && ppu_x == 9'd0) begin
            $display("[PASS] frame_sync_reset correctly forced VBLANK alignment.");
        end else begin
            $display("[FAIL] frame_sync_reset alignment failed. x=%d, y=%d", ppu_x, ppu_y);
        end

        #1000;
        $display("Simulation Complete.");
        $finish;
    end

endmodule