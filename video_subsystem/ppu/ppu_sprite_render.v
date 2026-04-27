module ppu_sprite_render (
    input  wire        clk,
    input  wire        reset,
    input  wire        ppu_ce,
    
    input  wire [8:0]  ppu_x,
    input  wire [8:0]  ppu_y,
    input  wire [7:0]  ppu_ctrl_reg,
    
    output reg  [4:0]  sec_oam_addr,
    input  wire [7:0]  sec_oam_data,
    
    output reg  [13:0] chr_addr,
    input  wire [7:0]  chr_data,
    
    output wire [3:0]  sprite_pixel_idx,
    output wire        sprite_priority,
    output wire        sprite_0_hit_pulse,
    
    input  wire        sprite_0_active,
    input  wire [3:0]  bg_pixel_idx,
    input  wire        rendering_enabled
);

    wire [13:0] base_sprite_addr = {1'b0, ppu_ctrl_reg[3], 12'd0};
    wire sprite_height_16 = ppu_ctrl_reg[5];

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

    reg [3:0] y_offset;
    reg [3:0] active_y;

    wire [8:0] full_y_offset = ppu_y - {1'b0, latched_y};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sec_oam_addr <= 5'd0;
            chr_addr     <= 14'd0;
            fetch_index  <= 3'd0;
            latched_y    <= 8'd0;
            latched_tile <= 8'd0;
            latched_attr <= 8'd0;
            latched_x    <= 8'd0;
            y_offset     <= 4'd0;
            active_y     <= 4'd0;
        end else if (ppu_ce && rendering_enabled) begin
            
            if (ppu_x == 9'd256) begin
                sec_oam_addr <= 5'd0; 
                fetch_index  <= 3'd0;
            end
            
            else if (ppu_x >= 9'd257 && ppu_x <= 9'd320) begin
                case (ppu_x[2:0])
                    3'd1: begin 
                        latched_y    <= sec_oam_data;
                        sec_oam_addr <= {fetch_index, 2'd1}; 
                    end
                    3'd2: begin 
                        latched_tile <= sec_oam_data;
                        sec_oam_addr <= {fetch_index, 2'd2}; 
                    end
                    3'd3: begin 
                        latched_attr <= sec_oam_data;
                        sec_oam_addr <= {fetch_index, 2'd3}; 
                    end
                    3'd4: begin 
                        latched_x <= sec_oam_data;
                        
                        y_offset = full_y_offset[3:0];
                        active_y = latched_attr[7] ? (sprite_height_16 ? 4'd15 - y_offset : 4'd7 - y_offset) : y_offset;
                        
                        if (sprite_height_16) begin
                            chr_addr <= {1'b0, latched_tile[0], latched_tile[7:1], active_y[3], 1'b0, active_y[2:0]};
                        end else begin
                            chr_addr <= base_sprite_addr | ({6'd0, latched_tile} << 4) | {11'd0, active_y[2:0]};
                        end
                    end
                    3'd5: begin 
                    end
                    3'd6: begin 
                        sprite_pat_lo[fetch_index] <= chr_data;
                        chr_addr <= chr_addr | 14'd8; 
                    end
                    3'd7: begin 
                    end
                    3'd0: begin 
                        sprite_pat_hi[fetch_index] <= chr_data;
                        sprite_x[fetch_index]      <= latched_x;
                        sprite_attr[fetch_index]   <= latched_attr;
                        
                        fetch_index  <= fetch_index + 1'b1;
                        
                        sec_oam_addr <= {fetch_index + 1'b1, 2'd0}; 
                    end
                endcase
            end
        end
    end

    reg [3:0] active_pixel;
    reg       active_priority;
    reg       is_sprite_0;

    reg [2:0] x_offset;
    reg [2:0] bit_sel;
    reg       p0;
    reg       p1;

    integer i;
    always @(*) begin
        active_pixel    = 4'd0;
        active_priority = 1'b0;
        is_sprite_0     = 1'b0;
        
        for (i = 7; i >= 0; i = i - 1) begin
            // PATCHED: Pad sprite_x to 9 bits to prevent 8-bit overflow artifacts on the right edge
            if (ppu_x >= {1'b0, sprite_x[i]} && ppu_x < ({1'b0, sprite_x[i]} + 9'd8)) begin
                
                x_offset = ppu_x[2:0] - sprite_x[i][2:0];
                bit_sel  = sprite_attr[i][6] ? x_offset : ~x_offset; 
                
                p0 = sprite_pat_lo[i][bit_sel];
                p1 = sprite_pat_hi[i][bit_sel];
                
                if (p0 | p1) begin
                    active_pixel    = {sprite_attr[i][1:0], p1, p0};
                    active_priority = sprite_attr[i][5];
                    if (i == 0) is_sprite_0 = 1'b1;
                end
            end
        end
    end

    assign sprite_pixel_idx = active_pixel;
    assign sprite_priority  = active_priority;

    wire bg_is_opaque = (bg_pixel_idx[1:0] != 2'b00);
    wire sp_is_opaque = (active_pixel[1:0] != 2'b00);
    
    assign sprite_0_hit_pulse = rendering_enabled && sprite_0_active && is_sprite_0 &&
                                bg_is_opaque && sp_is_opaque && (ppu_x < 9'd256);

endmodule