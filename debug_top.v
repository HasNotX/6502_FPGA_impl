/*
 * File: debug_top.v
 * Description: Industrial-grade hardware telemetry multiplexer.
 * Routes internal hardware state to the 7-segment displays
 * based on slide switch page configurations.
 */

module debug_top (
    input  wire [9:0]  sw,

    // Page 00: CPU State
    input  wire [15:0] cpu_pc,
    input  wire [7:0]  cpu_data,

    // Page 01: PPU Memory / Registers
    input  wire [14:0] ppu_vram_addr,
    input  wire [7:0]  ppu_palette_00,

    // Page 02: PPU Coordinates / VGA
    input  wire [7:0]  nes_x,
    input  wire [7:0]  nes_y,
    
    // Page 03: PPU Control & Status
    input  wire [7:0]  ppu_ctrl,
    input  wire [7:0]  ppu_status,

    // Output to 7-segment displays
    output wire [6:0]  hex0,
    output wire [6:0]  hex1,
    output wire [6:0]  hex2,
    output wire [6:0]  hex3,
    output wire [6:0]  hex4,
    output wire [6:0]  hex5
);

    reg [23:0] active_display_data;

    // Hardware Page Multiplexer
    always @(*) begin
        case (sw[3:0])
            4'b0000: begin 
                // SW[4] toggles between PC-only or PC + Data
                if (sw[4]) begin
                    active_display_data = {cpu_pc, cpu_data};
                end else begin
                    active_display_data = {8'h00, cpu_pc};
                end
            end
            
            4'b0001: begin 
                // HEX5-2: VRAM Addr, HEX1-0: Palette 00
                active_display_data = {1'b0, ppu_vram_addr, ppu_palette_00};
            end
            
            4'b0010: begin 
                // HEX5-4: nes_y, HEX3-2: nes_x, HEX1-0: 00
                active_display_data = {nes_y, nes_x, 8'h00};
            end
            
            4'b0011: begin 
                // HEX5-4: Control, HEX3-2: Status, HEX1-0: 00
                active_display_data = {ppu_ctrl, ppu_status, 8'h00};
            end
            
            default: begin
                // 'E' for Empty/Error page
                active_display_data = 24'hEEEEEE; 
            end
        endcase
    end

    // Hex Decoder Instantiations
    debug_hex_decoder dec5 (.din(active_display_data[23:20]), .dout(hex5));
    debug_hex_decoder dec4 (.din(active_display_data[19:16]), .dout(hex4));
    debug_hex_decoder dec3 (.din(active_display_data[15:12]), .dout(hex3));
    debug_hex_decoder dec2 (.din(active_display_data[11:8]),  .dout(hex2));
    debug_hex_decoder dec1 (.din(active_display_data[7:4]),   .dout(hex1));
    debug_hex_decoder dec0 (.din(active_display_data[3:0]),   .dout(hex0));

endmodule

/*
 * Module: debug_hex_decoder
 * Description: Converts a 4-bit nibble into a 7-segment display output.
 * Uses active-low logic.
 */
module debug_hex_decoder (
    input  wire [3:0] din,
    output reg  [6:0] dout
);
    always @(*) begin
        case (din)
            4'h0: dout = 7'b1000000;
            4'h1: dout = 7'b1111001;
            4'h2: dout = 7'b0100100;
            4'h3: dout = 7'b0110000;
            4'h4: dout = 7'b0011001;
            4'h5: dout = 7'b0010010;
            4'h6: dout = 7'b0000010;
            4'h7: dout = 7'b1111000;
            4'h8: dout = 7'b0000000;
            4'h9: dout = 7'b0010000;
            4'hA: dout = 7'b0001000;
            4'hB: dout = 7'b0000011;
            4'hC: dout = 7'b1000110;
            4'hD: dout = 7'b0100001;
            4'hE: dout = 7'b0000110;
            4'hF: dout = 7'b0001110;
            default: dout = 7'b1111111;
        endcase
    end
endmodule