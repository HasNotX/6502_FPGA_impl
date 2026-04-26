/*
 * File: ppu_timing_generator.v
 * Description: Cycle-accurate NTSC timing generator for the Ricoh 2C02 PPU.
 * Operates in the 25.175 MHz clock domain but advances strictly on ppu_ce
 * to maintain the 5.369 MHz NTSC phase.
 */

`timescale 1ns/1ps

module ppu_timing_generator (
    input  wire       clk,
    input  wire       reset,
    input  wire       ppu_ce,
    input  wire       frame_sync_reset, // From VGA domain to prevent 60.00Hz vs 60.09Hz drift

    output reg  [8:0] ppu_x,            // 0 to 340
    output reg  [8:0] ppu_y,            // 0 to 261
    output wire       visible,
    output wire       hblank,
    output wire       vblank
);

    // NTSC PPU Constants
    localparam DOTS_PER_LINE   = 9'd341;
    localparam LINES_PER_FRAME = 9'd262;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ppu_x <= 9'd0;
            ppu_y <= 9'd0;
        end else if (frame_sync_reset) begin
            // Synchronize to VGA VBlank. Force PPU into the start of its own VBlank.
            ppu_x <= 9'd0;
            ppu_y <= 9'd241;
        end else if (ppu_ce) begin
            if (ppu_x == DOTS_PER_LINE - 1) begin
                ppu_x <= 9'd0;
                if (ppu_y == LINES_PER_FRAME - 1) begin
                    ppu_y <= 9'd0;
                end else begin
                    ppu_y <= ppu_y + 9'd1;
                end
            end else begin
                ppu_x <= ppu_x + 9'd1;
            end
        end
    end

    // Decoding standard NTSC video states
    assign visible = (ppu_x < 9'd256) && (ppu_y < 9'd240);
    assign hblank  = (ppu_x >= 9'd256) && (ppu_x <= 9'd340);
    assign vblank  = (ppu_y >= 9'd241) && (ppu_y <= 9'd260);

endmodule