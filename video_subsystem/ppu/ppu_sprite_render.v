module ppu_sprite_render (
    input  wire        clk,
    input  wire        reset,
    
    input  wire [7:0]  nes_x,
    input  wire [7:0]  nes_y,
    input  wire        nes_visible,
    input  wire [7:0]  ppu_ctrl_reg,

    output reg  [7:0]  oam_addr,
    input  wire [7:0]  oam_data,

    output reg  [13:0] chr_addr,
    input  wire [7:0]  chr_data,

    output reg  [3:0]  sprite_color_idx,
    output reg         sprite_bg_priority,
    output reg         sprite0_active,
    output wire        is_fetching      // NEW: Bus Arbitrator Flag
);

    reg last_nes_visible;
    always @(posedge clk) last_nes_visible <= nes_visible;
    
    // Trigger evaluation the exact cycle the VGA beam shuts off
    wire hblank_start = !nes_visible && last_nes_visible;

    reg [7:0] spr_x       [0:7];
    reg [7:0] spr_attr    [0:7];
    reg [7:0] spr_pat_lo  [0:7];
    reg [7:0] spr_pat_hi  [0:7];
    reg       spr_is_zero [0:7];

    reg [3:0] sprite_count;
    reg [5:0] oam_scan_idx;
    reg [3:0] eval_state;

    reg [7:0] latched_y;
    reg [7:0] latched_tile;
    reg [7:0] latched_attr;
    reg [7:0] latched_x;
    
    wire [14:0] base_pat_addr = {2'b00, ppu_ctrl_reg[3], 12'd0};
    wire [7:0]  next_nes_y    = nes_y + 8'd1;

    assign is_fetching = (eval_state != 4'd0);

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 1 & 2: OAM Evaluation (Runs at 25MHz during HBlank)
    // ─────────────────────────────────────────────────────────────────────────
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            eval_state   <= 4'd0;
            sprite_count <= 4'd0;
            oam_scan_idx <= 6'd0;
            oam_addr     <= 8'd0;
        end else begin
            if (hblank_start) begin
                eval_state   <= 4'd1;
                sprite_count <= 4'd0;
                oam_scan_idx <= 6'd0;
                oam_addr     <= 8'd0;
            end else begin
                case (eval_state)
                    4'd0: ; 
                    
                    4'd1: begin
                        oam_addr   <= {oam_scan_idx, 2'b00};
                        eval_state <= 4'd2;
                    end
                    4'd2: eval_state <= 4'd3; 
                    4'd3: begin
                        latched_y <= oam_data;
                        oam_addr  <= {oam_scan_idx, 2'b01};
                        eval_state <= 4'd4;
                    end
                    4'd4: eval_state <= 4'd5; 
                    4'd5: begin
                        // Safely evaluate Y distance using 9-bit math to prevent 255 wraparound
                        if ({1'b0, next_nes_y} >= {1'b0, latched_y} && 
                            {1'b0, next_nes_y} < ({1'b0, latched_y} + 9'd8) && 
                            latched_y < 8'd240 && 
                            sprite_count < 4'd8) begin
                            
                            latched_tile <= oam_data;
                            oam_addr     <= {oam_scan_idx, 2'b10};
                            eval_state   <= 4'd6;
                        end else begin
                            eval_state <= 4'd14; 
                        end
                    end
                    4'd6: eval_state <= 4'd7;
                    4'd7: begin
                        latched_attr <= oam_data;
                        oam_addr     <= {oam_scan_idx, 2'b11};
                        eval_state   <= 4'd8;
                    end
                    4'd8: eval_state <= 4'd9;
                    4'd9: begin
                        latched_x <= oam_data;
                        if (latched_attr[7]) // Vertical Flip
                            chr_addr <= base_pat_addr[13:0] | ({6'd0, latched_tile} << 4) | (7 - (next_nes_y - latched_y));
                        else
                            chr_addr <= base_pat_addr[13:0] | ({6'd0, latched_tile} << 4) | (next_nes_y - latched_y);
                        eval_state <= 4'd10;
                    end
                    4'd10: eval_state <= 4'd11;
                    4'd11: begin
                        spr_pat_lo[sprite_count] <= chr_data;
                        chr_addr <= chr_addr + 14'd8; 
                        eval_state <= 4'd12;
                    end
                    4'd12: eval_state <= 4'd13;
                    4'd13: begin
                        spr_pat_hi[sprite_count]  <= chr_data;
                        spr_x[sprite_count]       <= latched_x;
                        spr_attr[sprite_count]    <= latched_attr;
                        spr_is_zero[sprite_count] <= (oam_scan_idx == 6'd0);
                        
                        sprite_count <= sprite_count + 4'd1;
                        eval_state   <= 4'd14;
                    end
                    4'd14: begin
                        if (oam_scan_idx == 6'd63) begin
                            eval_state <= 4'd0; 
                        end else begin
                            oam_scan_idx <= oam_scan_idx + 6'd1;
                            eval_state   <= 4'd1;
                        end
                    end
                endcase
            end
        end
    end

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 3: Pixel Output Multiplexer
    // ─────────────────────────────────────────────────────────────────────────
    integer i;
    reg [3:0] active_color;
    reg       active_priority;
    reg       active_is_zero;
    
    always @(*) begin
        active_color    = 4'b0000;
        active_priority = 1'b0;
        active_is_zero  = 1'b0;
        
        if (nes_visible) begin
            for (i = 7; i >= 0; i = i - 1) begin
                if (i < sprite_count) begin
                    if (nes_x >= spr_x[i] && nes_x < (spr_x[i] + 8'd8)) begin
                        reg [2:0] x_offset;
                        if (spr_attr[i][6]) // Horizontal Flip
                            x_offset = (nes_x - spr_x[i]);
                        else
                            x_offset = 3'd7 - (nes_x - spr_x[i]);
                            
                        if ({spr_pat_hi[i][x_offset], spr_pat_lo[i][x_offset]} != 2'b00) begin
                            active_color    = {spr_attr[i][1:0], spr_pat_hi[i][x_offset], spr_pat_lo[i][x_offset]};
                            active_priority = spr_attr[i][5];
                            active_is_zero  = spr_is_zero[i];
                        end
                    end
                end
            end
        end
        sprite_color_idx   = active_color;
        sprite_bg_priority = active_priority;
        sprite0_active     = active_is_zero;
    end

endmodule