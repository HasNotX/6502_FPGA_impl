/*
 * File: ping_pong_line_buffer.v
 * Description: Dual-port Ping-Pong buffer isolating the NTSC PPU rendering
 * domain from the VGA display domain. 
 * Prevents screen tearing by guaranteeing the VGA DAC only reads from a 
 * fully completed scanline buffer.
 */

`timescale 1ns/1ps

module ping_pong_line_buffer (
    input  wire        clk,
    
    // PPU Write Domain (Gated by ppu_ce)
    input  wire        ppu_ce,
    input  wire [8:0]  ppu_x,
    input  wire [8:0]  ppu_y,
    input  wire        ppu_visible,
    input  wire [3:0]  ppu_color_idx,
    
    // VGA Read Domain (Continuous 25.175 MHz)
    input  wire [7:0]  vga_nes_x,
    output reg  [3:0]  vga_color_idx
);

    // Two independent memory blocks for Ping-Pong operation
    reg [3:0] buffer_a [0:255];
    reg [3:0] buffer_b [0:255];

    // Ping-Pong Toggle: Flips exactly at the start of every new PPU scanline
    wire write_to_a = (ppu_y[0] == 1'b0);

    // -------------------------------------------------------------------------
    // PPU Write Port
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (ppu_ce && ppu_visible && (ppu_x < 9'd256)) begin
            if (write_to_a) begin
                buffer_a[ppu_x[7:0]] <= ppu_color_idx;
            end else begin
                buffer_b[ppu_x[7:0]] <= ppu_color_idx;
            end
        end
    end

    // -------------------------------------------------------------------------
    // VGA Read Port
    // -------------------------------------------------------------------------
    // The VGA engine reads from the opposite buffer that the PPU is writing.
    // The output is registered to absorb the standard 1-cycle BRAM latency.
    always @(posedge clk) begin
        if (write_to_a) begin
            vga_color_idx <= buffer_b[vga_nes_x];
        end else begin
            vga_color_idx <= buffer_a[vga_nes_x];
        end
    end

endmodule