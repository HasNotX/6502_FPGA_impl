/*
 * File: ppu_sprite_render.v
 * Description: Cycle-accurate sprite rendering engine and multiplexer.
 * Handles Phase 3 CHR-ROM fetches and visible scanline pixel shifting.
 */

module ppu_sprite_render (
    input  wire        clk,
    input  wire        reset,
    input  wire        ppu_ce,
    
    input  wire [8:0]  ppu_x,
    input  wire [8:0]  ppu_y,
    input  wire [7:0]  ppu_ctrl_reg,
    
    // Interface to Secondary OAM
    output reg  [4:0]  sec_oam_addr,
    input  wire [7:0]  sec_oam_data,
    
    // Interface to CHR-ROM Bus (Active Dots 257-320)
    output reg  [13:0] chr_addr,
    input  wire [7:0]  chr_data,
    
    // Output Pixel and Collision Flags
    output wire [3:0]  sprite_pixel_idx,
    output wire        sprite_priority,
    output wire        sprite_0_hit_pulse,
    
    // State from Evaluation Engine
    input  wire        sprite_0_active,
    input  wire [3:0]  bg_pixel_idx,
    input  wire        rendering_enabled
);

    wire [13:0] base_sprite_addr = {1'b0, ppu_ctrl_reg[3], 12'd0};
    wire sprite_height_16 = ppu_ctrl_reg[5];

    // Bank of 8 Sprite Registers
    reg [7:0] sprite_x       [0:7];
    reg [7:0] sprite_attr    [0:7];
    reg [7:0] sprite_pat_lo  [0:7];
    reg [7:0] sprite_pat_hi  [0:7];

    reg [2:0] fetch_index;
    reg [7:0] latched_y;
    reg [7:0] latched_tile;
    reg [7:0] latched_attr;
    reg [7:0] latched_x;

    wire even_dot = ~ppu_x[0];

    // -------------------------------------------------------------------------
    // Phase 3: Secondary OAM to CHR-ROM Fetch Pipeline (Dots 257-320)
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sec_oam_addr <= 5'd0;
            chr_addr     <= 14'd0;
            fetch_index  <= 3'd0;
            latched_y    <= 8'd0;
            latched_tile <= 8'd0;
            latched_attr <= 8'd0;
            latched_x    <= 8'd0;
        end else if (ppu_ce && rendering_enabled) begin
            
            if (ppu_x == 9'd256) begin
                sec_oam_addr <= 5'd0;
                fetch_index  <= 3'd0;
            end
            
            else if (ppu_x >= 9'd257 && ppu_x <= 9'd320) begin
                case (ppu_x[2:0])
                    3'd1: begin // Dot 1: Read Y
                        sec_oam_addr <= {fetch_index, 2'd1};
                        latched_y    <= sec_oam_data;
                    end
                    3'd2: ; // Wait
                    3'd3: begin // Dot 3: Read Tile
                        sec_oam_addr <= {fetch_index, 2'd2};
                        latched_tile <= sec_oam_data;
                    end
                    3'd4: ; // Wait
                    3'd5: begin // Dot 5: Read Attribute
                        sec_oam_addr <= {fetch_index, 2'd3};
                        latched_attr <= sec_oam_data;
                    end
                    3'd6: ; // Wait
                    3'd7: begin // Dot 7: Read X & Request CHR Lo
                        latched_x <= sec_oam_data;
                        
                        // Calculate Vertical Flip and Address
                        begin : chr_addr_calc
                            wire [3:0] y_offset = (ppu_y - latched_y);
                            wire [3:0] active_y = latched_attr[7] ? (sprite_height_16 ? 4'd15 - y_offset : 4'd7 - y_offset) : y_offset;
                            
                            if (sprite_height_16) begin
                                chr_addr <= {1'b0, latched_tile[0], latched_tile[7:1], active_y[3], 1'b0, active_y[2:0]};
                            end else begin
                                chr_addr <= base_sprite_addr | ({6'd0, latched_tile} << 4) | {11'd0, active_y[2:0]};
                            end
                        end
                    end
                    3'd0: begin // Dot 8: Latch CHR Lo & Request CHR Hi
                        sprite_pat_lo[fetch_index] <= chr_data;
                        chr_addr <= chr_addr | 14'd8; 
                        
                        // Latch remaining attributes for this sprite
                        sprite_x[fetch_index]    <= latched_x;
                        sprite_attr[fetch_index] <= latched_attr;
                        
                        // The CHR Hi byte will be latched on Dot 2 of the NEXT cycle 
                        // (or Dot 258/322 for boundary alignment)
                        fetch_index <= fetch_index + 1'b1;
                    end
                endcase
                
                // Latch CHR Hi slightly offset due to the 8-dot pipeline wrapping
                if (ppu_x[2:0] == 3'd2 && ppu_x > 9'd258) begin
                    sprite_pat_hi[fetch_index - 1'b1] <= chr_data;
                end
            end
            
            // Final CHR Hi latch for the 8th sprite
            else if (ppu_x == 9'd322) begin
                sprite_pat_hi[7] <= chr_data;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Visible Render Pipeline (Dots 1-256)
    // -------------------------------------------------------------------------
    reg [3:0] active_pixel;
    reg       active_priority;
    reg       is_sprite_0;

    integer i;
    always @(*) begin
        active_pixel    = 4'd0;
        active_priority = 1'b0;
        is_sprite_0     = 1'b0;
        
        for (i = 7; i >= 0; i = i - 1) begin
            if (ppu_x >= sprite_x[i] && ppu_x < (sprite_x[i] + 8)) begin
                begin : pixel_mux
                    wire [2:0] x_offset = ppu_x - sprite_x[i];
                    wire [2:0] bit_sel  = sprite_attr[i][6] ? x_offset : ~x_offset; // Horizontal Flip
                    
                    wire p0 = sprite_pat_lo[i][bit_sel];
                    wire p1 = sprite_pat_hi[i][bit_sel];
                    
                    if (p0 | p1) begin
                        active_pixel    = {sprite_attr[i][1:0], p1, p0};
                        active_priority = sprite_attr[i][5];
                        if (i == 0) is_sprite_0 = 1'b1;
                    end
                end
            end
        end
    end

    assign sprite_pixel_idx = active_pixel;
    assign sprite_priority  = active_priority;

    // Sprite 0 Hit Logic
    wire bg_is_opaque = (bg_pixel_idx[1:0] != 2'b00);
    wire sp_is_opaque = (active_pixel[1:0] != 2'b00);
    
    assign sprite_0_hit_pulse = rendering_enabled && sprite_0_active && is_sprite_0 &&
                                bg_is_opaque && sp_is_opaque && (ppu_x < 9'd256);

endmodule