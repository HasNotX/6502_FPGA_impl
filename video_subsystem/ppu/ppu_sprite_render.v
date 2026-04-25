/*
 * File: ppu_sprite_render.v
 * Description: HIGH-SPEED OAM Sprite Evaluation and Rendering Pipeline.
 * Implements an industrial-grade Two-Phase pipeline with explicit 
 * Secondary OAM Double-Buffering to prevent live rendering corruption.
 */

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
    output wire        is_fetching      
);

    reg last_nes_visible;
    reg [7:0] last_nes_x;
    
    always @(posedge clk) begin
        last_nes_visible <= nes_visible;
        last_nes_x       <= nes_x;
    end
    
    wire hblank_start = !nes_visible && last_nes_visible;
    wire start_of_line = nes_visible && !last_nes_visible;
    
    // Trigger OAM scanning safely during active display
    wire eval_start   = nes_visible && (nes_x == 8'd64) && (last_nes_x == 8'd63);

    // -------------------------------------------------------------------------
    // Phase 1 & 2 Registers: Evaluation (Secondary OAM)
    // -------------------------------------------------------------------------
    reg [7:0] eval_spr_x       [0:7];
    reg [7:0] eval_spr_attr    [0:7];
    reg [7:0] eval_spr_tile    [0:7]; 
    reg [7:0] eval_spr_y_diff  [0:7]; 
    reg [7:0] eval_spr_pat_lo  [0:7];
    reg [7:0] eval_spr_pat_hi  [0:7];
    reg       eval_spr_is_zero [0:7];
    reg [3:0] eval_sprite_count;

    // -------------------------------------------------------------------------
    // Phase 3 Registers: Active Render Buffers
    // -------------------------------------------------------------------------
    reg [7:0] active_spr_x       [0:7];
    reg [7:0] active_spr_attr    [0:7];
    reg [7:0] active_spr_pat_lo  [0:7];
    reg [7:0] active_spr_pat_hi  [0:7];
    reg       active_spr_is_zero [0:7];
    reg [3:0] active_sprite_count;
    
    reg [5:0] oam_scan_idx;
    reg [3:0] fetch_idx;
    reg [4:0] eval_state;

    reg [7:0] latched_y;
    reg [7:0] latched_tile;
    reg [7:0] latched_attr;
    
    wire [14:0] base_pat_addr = {2'b00, ppu_ctrl_reg[3], 12'd0};
    wire [7:0]  next_nes_y    = nes_y + 8'd1;

    localparam S_IDLE            = 5'd0,
               S_EVAL_Y_REQ      = 5'd1,
               S_EVAL_Y_WAIT     = 5'd2,
               S_EVAL_Y_CHK      = 5'd3,
               S_EVAL_TILE_WAIT  = 5'd4,
               S_EVAL_TILE_LATCH = 5'd5,
               S_EVAL_ATTR_WAIT  = 5'd6,
               S_EVAL_ATTR_LATCH = 5'd7,
               S_EVAL_X_WAIT     = 5'd8,
               S_EVAL_X_LATCH    = 5'd9,
               S_EVAL_DONE       = 5'd10, 
               
               S_FETCH_REQ       = 5'd11,
               S_FETCH_LO_WAIT   = 5'd12,
               S_FETCH_LO_LATCH  = 5'd13,
               S_FETCH_HI_WAIT   = 5'd14,
               S_FETCH_HI_LATCH  = 5'd15;

    assign is_fetching = (eval_state >= S_FETCH_REQ && eval_state <= S_FETCH_HI_LATCH);

    // ─────────────────────────────────────────────────────────────────────────
    // FSM: Evaluation and Fetching
    // ─────────────────────────────────────────────────────────────────────────
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            eval_state        <= S_IDLE;
            eval_sprite_count <= 4'd0;
            oam_scan_idx      <= 6'd0;
            oam_addr          <= 8'd0;
            fetch_idx         <= 4'd0;
        end else begin
            case (eval_state)
                S_IDLE: begin
                    if (eval_start) begin
                        eval_state        <= S_EVAL_Y_REQ;
                        eval_sprite_count <= 4'd0;
                        oam_scan_idx      <= 6'd0;
                    end
                end
                
                S_EVAL_Y_REQ: begin
                    oam_addr   <= {oam_scan_idx, 2'b00};
                    eval_state <= S_EVAL_Y_WAIT;
                end
                S_EVAL_Y_WAIT: eval_state <= S_EVAL_Y_CHK;
                
                S_EVAL_Y_CHK: begin
                    latched_y <= oam_data;
                    if ({1'b0, next_nes_y} >= {1'b0, oam_data} && 
                        {1'b0, next_nes_y} < ({1'b0, oam_data} + 9'd8) && 
                        oam_data < 8'd240 && 
                        eval_sprite_count < 4'd8) begin
                        
                        oam_addr   <= {oam_scan_idx, 2'b01};
                        eval_state <= S_EVAL_TILE_WAIT;
                    end else begin
                        if (oam_scan_idx == 6'd63) begin
                            eval_state <= S_EVAL_DONE;
                        end else begin
                            oam_scan_idx <= oam_scan_idx + 6'd1;
                            oam_addr     <= {oam_scan_idx + 6'd1, 2'b00};
                            eval_state   <= S_EVAL_Y_WAIT;
                        end
                    end
                end
                
                S_EVAL_TILE_WAIT: eval_state <= S_EVAL_TILE_LATCH;
                S_EVAL_TILE_LATCH: begin
                    latched_tile <= oam_data;
                    oam_addr     <= {oam_scan_idx, 2'b10};
                    eval_state   <= S_EVAL_ATTR_WAIT;
                end
                
                S_EVAL_ATTR_WAIT: eval_state <= S_EVAL_ATTR_LATCH;
                S_EVAL_ATTR_LATCH: begin
                    latched_attr <= oam_data;
                    oam_addr     <= {oam_scan_idx, 2'b11};
                    eval_state   <= S_EVAL_X_WAIT;
                end
                
                S_EVAL_X_WAIT: eval_state <= S_EVAL_X_LATCH;
                S_EVAL_X_LATCH: begin
                    eval_spr_x[eval_sprite_count]       <= oam_data;
                    eval_spr_attr[eval_sprite_count]    <= latched_attr;
                    eval_spr_tile[eval_sprite_count]    <= latched_tile;
                    eval_spr_y_diff[eval_sprite_count]  <= (next_nes_y - latched_y);
                    eval_spr_is_zero[eval_sprite_count] <= (oam_scan_idx == 6'd0);
                    
                    eval_sprite_count <= eval_sprite_count + 4'd1;
                    
                    if (oam_scan_idx == 6'd63) begin
                        eval_state <= S_EVAL_DONE;
                    end else begin
                        oam_scan_idx <= oam_scan_idx + 6'd1;
                        oam_addr     <= {oam_scan_idx + 6'd1, 2'b00};
                        eval_state   <= S_EVAL_Y_WAIT;
                    end
                end
                
                S_EVAL_DONE: begin
                    if (hblank_start) begin
                        fetch_idx <= 4'd0;
                        if (eval_sprite_count > 4'd0) begin
                            eval_state <= S_FETCH_REQ;
                        end else begin
                            eval_state <= S_IDLE;
                        end
                    end
                end
                
                S_FETCH_REQ: begin
                    if (eval_spr_attr[fetch_idx][7]) 
                        chr_addr <= base_pat_addr[13:0] | ({6'd0, eval_spr_tile[fetch_idx]} << 4) | (7 - eval_spr_y_diff[fetch_idx]);
                    else
                        chr_addr <= base_pat_addr[13:0] | ({6'd0, eval_spr_tile[fetch_idx]} << 4) | eval_spr_y_diff[fetch_idx];
                        
                    eval_state <= S_FETCH_LO_WAIT;
                end
                
                S_FETCH_LO_WAIT: eval_state <= S_FETCH_LO_LATCH;
                S_FETCH_LO_LATCH: begin
                    eval_spr_pat_lo[fetch_idx] <= chr_data;
                    chr_addr <= chr_addr + 14'd8; 
                    eval_state <= S_FETCH_HI_WAIT;
                end
                
                S_FETCH_HI_WAIT: eval_state <= S_FETCH_HI_LATCH;
                S_FETCH_HI_LATCH: begin
                    eval_spr_pat_hi[fetch_idx]  <= chr_data;
                    
                    if (fetch_idx + 4'd1 == eval_sprite_count) begin
                        eval_state <= S_IDLE;
                    end else begin
                        fetch_idx  <= fetch_idx + 4'd1;
                        eval_state <= S_FETCH_REQ;
                    end
                end
            endcase
        end
    end

    // ─────────────────────────────────────────────────────────────────────────
    // The Double Buffer Transfer (Start of visible scanline)
    // ─────────────────────────────────────────────────────────────────────────
    integer j;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_sprite_count <= 4'd0;
            for (j = 0; j < 8; j = j + 1) begin
                active_spr_x[j]       <= 8'd0;
                active_spr_attr[j]    <= 8'd0;
                active_spr_pat_lo[j]  <= 8'd0;
                active_spr_pat_hi[j]  <= 8'd0;
                active_spr_is_zero[j] <= 1'b0;
            end
        end else if (start_of_line) begin
            active_sprite_count <= eval_sprite_count;
            for (j = 0; j < 8; j = j + 1) begin
                active_spr_x[j]       <= eval_spr_x[j];
                active_spr_attr[j]    <= eval_spr_attr[j];
                active_spr_pat_lo[j]  <= eval_spr_pat_lo[j];
                active_spr_pat_hi[j]  <= eval_spr_pat_hi[j];
                active_spr_is_zero[j] <= eval_spr_is_zero[j];
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
    reg [7:0] diff;
    reg [2:0] x_offset;
    
    // Verilog-2001 compliant structure (Variables explicitly declared outside block)
    always @(*) begin
        active_color    = 4'b0000;
        active_priority = 1'b0;
        active_is_zero  = 1'b0;
        diff            = 8'd0;
        x_offset        = 3'd0; 
        
        if (nes_visible) begin
            for (i = 7; i >= 0; i = i - 1) begin
                if (i < active_sprite_count) begin
                    if (nes_x >= active_spr_x[i] && nes_x < (active_spr_x[i] + 8'd8)) begin
                        
                        diff = nes_x - active_spr_x[i];
                        if (active_spr_attr[i][6]) // Horizontal Flip
                            x_offset = diff[2:0];
                        else
                            x_offset = 3'd7 - diff[2:0];
                            
                        if ({active_spr_pat_hi[i][x_offset], active_spr_pat_lo[i][x_offset]} != 2'b00) begin
                            active_color    = {active_spr_attr[i][1:0], active_spr_pat_hi[i][x_offset], active_spr_pat_lo[i][x_offset]};
                            active_priority = active_spr_attr[i][5];
                            active_is_zero  = active_spr_is_zero[i];
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