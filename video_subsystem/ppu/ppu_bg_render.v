/* * File: ppu_bg_render.v
 * Description: Background rendering pipeline. Fetches Nametable, Attribute, 
 * and Pattern data, and shifts it out pixel-by-pixel.
 */

module ppu_bg_render (
    input  wire        clk,           // VGA Pixel Clock or dedicated PPU clock
    input  wire        reset,
    
    // VGA Coordinates from Timing Core
    input  wire [7:0]  nes_x,
    input  wire [7:0]  nes_y,
    input  wire        nes_visible,

    // Memory Bus Outputs (To ppu_core memory controller)
    output reg  [14:0] bg_mem_addr,
    
    // Memory Bus Inputs (Data returning from VRAM / CHR-ROM)
    input  wire [7:0]  bg_mem_data,
    
    // Output to Palette DAC
    output wire [3:0]  pixel_color_idx // 4-bit index to send to Palette RAM
);

    // -------------------------------------------------------------------------
    // The 8-Cycle Fetch State Machine
    // -------------------------------------------------------------------------
    reg [2:0] fetch_state;
    
    // Latches to hold data returning from memory
    reg [7:0] nametable_latch;
    reg [7:0] attr_latch;
    reg [7:0] pattern_lo_latch;
    reg [7:0] pattern_hi_latch;

    // 16-bit Shift Registers (Standard NES DSD practice)
    // 16 bits allow us to hold the current 8 pixels being drawn, 
    // while loading the next 8 pixels into the upper half.
    reg [15:0] bg_shift_pat_lo;
    reg [15:0] bg_shift_pat_hi;
    
    // Fine X scroll determines which bit of the shift register we are looking at
    wire [2:0] fine_x = nes_x[2:0];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_state <= 3'd0;
            bg_shift_pat_lo <= 16'd0;
            bg_shift_pat_hi <= 16'd0;
            bg_mem_addr <= 15'd0;
        end else if (nes_visible) begin
            
            // Shift registers shift left by 1 every visible pixel cycle
            bg_shift_pat_lo <= {bg_shift_pat_lo[14:0], 1'b0};
            bg_shift_pat_hi <= {bg_shift_pat_hi[14:0], 1'b0};

            // The Fetch Pipeline (Driven by the lowest 3 bits of X coordinate)
            case (fetch_state)
                // --- FETCH 1: NAMETABLE ---
                3'd0: begin
                    // Address = 0x2000 + (Y/8 * 32) + (X/8)
                    bg_mem_addr <= 15'h2000 | ({7'b0000000, nes_y[7:3]} << 5) | {10'd0, nes_x[7:3]};
                    fetch_state <= 3'd1;
                end
                3'd1: begin
                    nametable_latch <= bg_mem_data; // Data arrives
                    fetch_state <= 3'd2;
                end

                // --- FETCH 2: ATTRIBUTE TABLE (Simplified for now) ---
                3'd2: begin
                    // Address calculation for attributes is complex (1 byte covers 4x4 tiles).
                    // For the initial milestone, we fetch a dummy palette to ensure shapes render first.
                    bg_mem_addr <= 15'h23C0; 
                    fetch_state <= 3'd3;
                end
                3'd3: begin
                    attr_latch <= bg_mem_data;
                    fetch_state <= 3'd4;
                end

                // --- FETCH 3: PATTERN TABLE LOW ---
                3'd4: begin
                    // Address = 0x0000 (Pattern Table 0) + (Tile_ID * 16) + Fine_Y
                    // Fine_Y is the row of the pixel inside the 8x8 tile (nes_y % 8)
                    bg_mem_addr <= 15'h0000 | ({7'd0, nametable_latch} << 4) | {12'd0, nes_y[2:0]};
                    fetch_state <= 3'd5;
                end
                3'd5: begin
                    pattern_lo_latch <= bg_mem_data;
                    fetch_state <= 3'd6;
                end

                // --- FETCH 4: PATTERN TABLE HIGH ---
                3'd6: begin
                    // Same address as Low, but offset by +8 bytes
                    bg_mem_addr <= 15'h0000 | ({7'd0, nametable_latch} << 4) | 15'd8 | {12'd0, nes_y[2:0]};
                    fetch_state <= 3'd7;
                end
                3'd7: begin
                    pattern_hi_latch <= bg_mem_data;
                    
                    // The 8-cycle sequence is complete!
                    // Load the newly fetched tile into the upper 8 bits of the shift registers
                    bg_shift_pat_lo[7:0] <= pattern_lo_latch;
                    bg_shift_pat_hi[7:0] <= bg_mem_data;
                    
                    fetch_state <= 3'd0;
                end
            endcase
        end else begin
            // If we are in HBlank or VBlank, reset the fetch state
            fetch_state <= 3'd0;
        end
    end

    // -------------------------------------------------------------------------
    // Pixel Output Multiplexer
    // -------------------------------------------------------------------------
    // The current pixel is selected from the top half of the shift registers (bits 15-8).
    // We index into it using inverted fine_x (because pixels are drawn left to right, 
    // but bit 7 is the leftmost pixel).
    
    wire [3:0] bit_mux = 4'd15 - {1'b0, fine_x};
    
    wire pixel_bit_0 = bg_shift_pat_lo[bit_mux];
    wire pixel_bit_1 = bg_shift_pat_hi[bit_mux];
    
    // Combine the bits into a color index (0 to 3). 
    // A value of 0 means transparent (show background color).
    assign pixel_color_idx = {2'b00, pixel_bit_1, pixel_bit_0};

endmodule
