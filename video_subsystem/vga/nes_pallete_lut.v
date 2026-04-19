/*
 * File: nes_palette_lut.v
 * Description: Synchronous Look-Up Table (LUT) mapping the 6-bit NES 
 * internal color codes to 30-bit physical VGA RGB signals (10 bits per channel).
 * The 8-bit standard NTSC RGB values are shifted left by 2 bits to scale to the
 * 10-bit DAC resolution of the DE10-Standard board.
 */

module nes_palette_lut (
    input  wire       clk,
    input  wire       reset,
    input  wire [5:0] nes_color_code,
    
    output reg  [9:0] vga_r,
    output reg  [9:0] vga_g,
    output reg  [9:0] vga_b
);

    // Internal registers for 8-bit RGB
    reg [7:0] r_8;
    reg [7:0] g_8;
    reg [7:0] b_8;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_8 <= 8'h00;
            g_8 <= 8'h00;
            b_8 <= 8'h00;
        end else begin
            case (nes_color_code)
                // Row 0: Dark colors
                6'h00: begin r_8 <= 8'h54; g_8 <= 8'h54; b_8 <= 8'h54; end
                6'h01: begin r_8 <= 8'h00; g_8 <= 8'h1E; b_8 <= 8'h74; end
                6'h02: begin r_8 <= 8'h08; g_8 <= 8'h10; b_8 <= 8'h90; end
                6'h03: begin r_8 <= 8'h30; g_8 <= 8'h00; b_8 <= 8'h88; end
                6'h04: begin r_8 <= 8'h44; g_8 <= 8'h00; b_8 <= 8'h64; end
                6'h05: begin r_8 <= 8'h5C; g_8 <= 8'h00; b_8 <= 8'h30; end
                6'h06: begin r_8 <= 8'h54; g_8 <= 8'h04; b_8 <= 8'h00; end
                6'h07: begin r_8 <= 8'h3C; g_8 <= 8'h18; b_8 <= 8'h00; end
                6'h08: begin r_8 <= 8'h20; g_8 <= 8'h2A; b_8 <= 8'h00; end
                6'h09: begin r_8 <= 8'h08; g_8 <= 8'h3A; b_8 <= 8'h00; end
                6'h0A: begin r_8 <= 8'h00; g_8 <= 8'h40; b_8 <= 8'h00; end
                6'h0B: begin r_8 <= 8'h00; g_8 <= 8'h3C; b_8 <= 8'h00; end
                6'h0C: begin r_8 <= 8'h00; g_8 <= 8'h32; b_8 <= 8'h3C; end
                6'h0D: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end
                6'h0E: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end
                6'h0F: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end

                // Row 1: Medium colors
                6'h10: begin r_8 <= 8'h98; g_8 <= 8'h96; b_8 <= 8'h98; end
                6'h11: begin r_8 <= 8'h08; g_8 <= 8'h4C; b_8 <= 8'hC4; end
                6'h12: begin r_8 <= 8'h30; g_8 <= 8'h32; b_8 <= 8'hEC; end
                6'h13: begin r_8 <= 8'h5C; g_8 <= 8'h1E; b_8 <= 8'hE4; end
                6'h14: begin r_8 <= 8'h88; g_8 <= 8'h14; b_8 <= 8'hB0; end
                6'h15: begin r_8 <= 8'hA0; g_8 <= 8'h14; b_8 <= 8'h64; end
                6'h16: begin r_8 <= 8'h98; g_8 <= 8'h22; b_8 <= 8'h20; end
                6'h17: begin r_8 <= 8'h78; g_8 <= 8'h3C; b_8 <= 8'h00; end
                6'h18: begin r_8 <= 8'h54; g_8 <= 8'h5A; b_8 <= 8'h00; end
                6'h19: begin r_8 <= 8'h28; g_8 <= 8'h72; b_8 <= 8'h00; end
                6'h1A: begin r_8 <= 8'h08; g_8 <= 8'h7C; b_8 <= 8'h00; end
                6'h1B: begin r_8 <= 8'h00; g_8 <= 8'h76; b_8 <= 8'h28; end
                6'h1C: begin r_8 <= 8'h00; g_8 <= 8'h66; b_8 <= 8'h78; end
                6'h1D: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end
                6'h1E: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end
                6'h1F: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end

                // Row 2: Light colors
                6'h20: begin r_8 <= 8'hEC; g_8 <= 8'hEE; b_8 <= 8'hEC; end
                6'h21: begin r_8 <= 8'h4C; g_8 <= 8'h9A; b_8 <= 8'hEC; end
                6'h22: begin r_8 <= 8'h78; g_8 <= 8'h7C; b_8 <= 8'hEC; end
                6'h23: begin r_8 <= 8'hB0; g_8 <= 8'h62; b_8 <= 8'hEC; end
                6'h24: begin r_8 <= 8'hE4; g_8 <= 8'h54; b_8 <= 8'hEC; end
                6'h25: begin r_8 <= 8'hEC; g_8 <= 8'h58; b_8 <= 8'hB4; end
                6'h26: begin r_8 <= 8'hEC; g_8 <= 8'h6A; b_8 <= 8'h64; end
                6'h27: begin r_8 <= 8'hD4; g_8 <= 8'h88; b_8 <= 8'h20; end
                6'h28: begin r_8 <= 8'hA0; g_8 <= 8'hAA; b_8 <= 8'h00; end
                6'h29: begin r_8 <= 8'h74; g_8 <= 8'hC4; b_8 <= 8'h00; end
                6'h2A: begin r_8 <= 8'h4C; g_8 <= 8'hD0; b_8 <= 8'h20; end
                6'h2B: begin r_8 <= 8'h38; g_8 <= 8'hCC; b_8 <= 8'h6C; end
                6'h2C: begin r_8 <= 8'h38; g_8 <= 8'hB4; b_8 <= 8'hCC; end
                6'h2D: begin r_8 <= 8'h3C; g_8 <= 8'h3C; b_8 <= 8'h3C; end
                6'h2E: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end
                6'h2F: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end

                // Row 3: Pale colors
                6'h30: begin r_8 <= 8'hEC; g_8 <= 8'hEE; b_8 <= 8'hEC; end
                6'h31: begin r_8 <= 8'hA8; g_8 <= 8'hCC; b_8 <= 8'hEC; end
                6'h32: begin r_8 <= 8'hBC; g_8 <= 8'hBC; b_8 <= 8'hEC; end
                6'h33: begin r_8 <= 8'hD4; g_8 <= 8'hB2; b_8 <= 8'hEC; end
                6'h34: begin r_8 <= 8'hEC; g_8 <= 8'hAE; b_8 <= 8'hEC; end
                6'h35: begin r_8 <= 8'hEC; g_8 <= 8'hAE; b_8 <= 8'hD4; end
                6'h36: begin r_8 <= 8'hEC; g_8 <= 8'hB4; b_8 <= 8'hB0; end
                6'h37: begin r_8 <= 8'hE4; g_8 <= 8'hC4; b_8 <= 8'h90; end
                6'h38: begin r_8 <= 8'hCC; g_8 <= 8'hD2; b_8 <= 8'h78; end
                6'h39: begin r_8 <= 8'hB4; g_8 <= 8'hDE; b_8 <= 8'h78; end
                6'h3A: begin r_8 <= 8'hA8; g_8 <= 8'hE2; b_8 <= 8'h90; end
                6'h3B: begin r_8 <= 8'h98; g_8 <= 8'hE2; b_8 <= 8'hB4; end
                6'h3C: begin r_8 <= 8'hA0; g_8 <= 8'hD6; b_8 <= 8'hE4; end
                6'h3D: begin r_8 <= 8'hA0; g_8 <= 8'hA2; b_8 <= 8'hA0; end
                6'h3E: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end
                6'h3F: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end

                default: begin r_8 <= 8'h00; g_8 <= 8'h00; b_8 <= 8'h00; end
            endcase
        end
    end

    // Scale 8-bit to 10-bit by shifting left 2 and padding with zeros
    always @(*) begin
        vga_r = {r_8, 2'b00};
        vga_g = {g_8, 2'b00};
        vga_b = {b_8, 2'b00};
    end

endmodule
