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
    input  wire        ppu_ce,
    input  wire [8:0]  ppu_x,
    input  wire [8:0]  ppu_y,
    input  wire        ppu_visible,
    input  wire [4:0]  ppu_color_idx, // 5-bit width
    input  wire [7:0]  vga_nes_x,
    output reg  [4:0]  vga_color_idx  // 5-bit width
);
    // Expand the internal memory block to 5 bits
    reg [4:0] buffer_a [0:255];
    reg [4:0] buffer_b [0:255];
    wire write_to_a = (ppu_y[0] == 1'b0);

    always @(posedge clk) begin
        if (ppu_ce && ppu_visible && (ppu_x < 9'd256)) begin
            if (write_to_a) buffer_a[ppu_x[7:0]] <= ppu_color_idx;
            else            buffer_b[ppu_x[7:0]] <= ppu_color_idx;
        end
    end

    always @(posedge clk) begin
        if (write_to_a) vga_color_idx <= buffer_b[vga_nes_x];
        else            vga_color_idx <= buffer_a[vga_nes_x];
    end
endmodule