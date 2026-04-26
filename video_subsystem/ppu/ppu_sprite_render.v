/*
 * File: ppu_sprite_render.v
 * Description: HIGH-SPEED OAM Sprite Evaluation and Rendering Pipeline.
 * Architected with independent down-counters, shift registers, and a strict 
 * 4-Phase timing pipeline synchronized via an internal 341-cycle tracker.
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

    output wire [3:0]  sprite_color_idx,
    output wire        sprite_bg_priority,
    output wire        sprite0_active,
    output wire        is_fetching      
);

    // -------------------------------------------------------------------------
    // Phase Tracking (Internal 341-Cycle PPU Clock)
    // -------------------------------------------------------------------------
    reg [7:0] last_nes_x;
    reg       phase;
    always @(posedge clk) begin
        last_nes_x <= nes_x;
        // Divide-by-2 of 25MHz to match NES pixel rate (12.5 MHz)
        if (nes_x != last_nes_x) phase <= 1'b1;
        else                     phase <= ~phase;
    end
    wire nes_pixel_tick = phase;

    reg [8:0] internal_x;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            internal_x <= 9'd0;
        end else if (nes_pixel_tick) begin
            if (nes_visible) begin
                internal_x <= {1'b0, nes_x};
            end else begin
                // Local counting during HBlank (341 NES cycles per line)
                if (internal_x == 9'd340) internal_x <= 9'd0; 
                else                      internal_x <= internal_x + 9'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Secondary OAM (Evaluation Buffers)
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
    // Active Rendering Buffers
    // -------------------------------------------------------------------------
    reg [7:0] active_spr_x       [0:7];
    reg [7:0] active_spr_attr    [0:7];
    reg [7:0] active_spr_pat_lo  [0:7];
    reg [7:0] active_spr_pat_hi  [0:7];
    reg       active_spr_is_zero [0:7];
    reg [3:0] active_sprite_count;
    
    reg [5:0] oam_scan_idx;
    reg [3:0] fetch_idx;
    reg [5:0] eval_state; 

    reg [7:0] latched_y;
    reg [7:0] latched_tile;
    reg [7:0] latched_attr;
    
    wire [14:0] base_pat_addr = {2'b00, ppu_ctrl_reg[3], 12'd0};
    wire [7:0]  next_nes_y    = nes_y + 8'd1;

    localparam S_IDLE            = 6'd0,
               S_CLEAR_OAM       = 6'd1,
               
               S_EVAL_Y_REQ      = 6'd2,
               S_EVAL_Y_WAIT1    = 6'd3,
               S_EVAL_Y_WAIT2    = 6'd4,
               S_EVAL_Y_CHK      = 6'd5,
               
               S_EVAL_TILE_WAIT1 = 6'd6,
               S_EVAL_TILE_WAIT2 = 6'd7,
               S_EVAL_TILE_LATCH = 6'd8,
               
               S_EVAL_ATTR_WAIT1 = 6'd9,
               S_EVAL_ATTR_WAIT2 = 6'd10,
               S_EVAL_ATTR_LATCH = 6'd11,
               
               S_EVAL_X_WAIT1    = 6'd12,
               S_EVAL_X_WAIT2    = 6'd13,
               S_EVAL_X_LATCH    = 6'd14,
               
               S_EVAL_DONE       = 6'd15, 
               
               S_FETCH_REQ       = 6'd16,
               S_FETCH_LO_WAIT1  = 6'd17,
               S_FETCH_LO_WAIT2  = 6'd18,
               S_FETCH_LO_WAIT3  = 6'd19,
               S_FETCH_LO_LATCH  = 6'd20,
               
               S_FETCH_HI_WAIT1  = 6'd21,
               S_FETCH_HI_WAIT2  = 6'd22,
               S_FETCH_HI_WAIT3  = 6'd23,
               S_FETCH_HI_LATCH  = 6'd24;

    assign is_fetching = (eval_state >= S_FETCH_REQ && eval_state <= S_FETCH_HI_LATCH);

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 1, 2 & 3: Evaluation and Fetch FSM
    // ─────────────────────────────────────────────────────────────────────────
    integer k;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            eval_state        <= S_IDLE;
            eval_sprite_count <= 4'd0;
            oam_scan_idx      <= 6'd0;
            oam_addr          <= 8'd0;
            fetch_idx         <= 4'd0;
        end else if (nes_pixel_tick) begin
            
            // Phase 1: Clear Secondary OAM (Cycles 1-64)
            if (internal_x == 9'd1) begin
                eval_state        <= S_CLEAR_OAM;
                eval_sprite_count <= 4'd0;
                oam_scan_idx      <= 6'd0;
                fetch_idx         <= 4'd0;
                for (k = 0; k < 8; k = k + 1) begin
                    eval_spr_x[k]       <= 8'hFF;
                    eval_spr_tile[k]    <= 8'hFF;
                    eval_spr_attr[k]    <= 8'hFF;
                    eval_spr_pat_lo[k]  <= 8'h00;
                    eval_spr_pat_hi[k]  <= 8'h00;
                    eval_spr_is_zero[k] <= 1'b0;
                end
            end
            
            // Phase 2: Start Evaluation (Cycles 65-256)
            else if (internal_x == 9'd65) begin
                eval_state <= S_EVAL_Y_REQ;
            end
            
            // Phase 3: Start Fetching (Cycles 257-319)
            else if (internal_x == 9'd257) begin
                if (eval_sprite_count > 4'd0) eval_state <= S_FETCH_REQ;
                else                          eval_state <= S_IDLE;
            end
            
            // FSM Execution
            else begin
                case (eval_state)
                    S_IDLE: ; 
                    S_CLEAR_OAM: ;
                    
                    // --- Byte 0: Y Coordinate ---
                    S_EVAL_Y_REQ: begin
                        oam_addr   <= {oam_scan_idx, 2'b00};
                        eval_state <= S_EVAL_Y_WAIT1;
                    end
                    S_EVAL_Y_WAIT1: eval_state <= S_EVAL_Y_WAIT2;
                    S_EVAL_Y_WAIT2: eval_state <= S_EVAL_Y_CHK;
                    
                    S_EVAL_Y_CHK: begin
                        latched_y <= oam_data;
                        if ({1'b0, next_nes_y} >= ({1'b0, oam_data} + 9'd1) && 
                            {1'b0, next_nes_y} <  ({1'b0, oam_data} + 9'd9) && 
                            oam_data < 8'd240 && 
                            eval_sprite_count < 4'd8) begin
                            
                            oam_addr   <= {oam_scan_idx, 2'b01};
                            eval_state <= S_EVAL_TILE_WAIT1;
                        end else begin
                            if (oam_scan_idx == 6'd63) begin
                                eval_state <= S_EVAL_DONE;
                            end else begin
                                oam_scan_idx <= oam_scan_idx + 6'd1;
                                oam_addr     <= {oam_scan_idx + 6'd1, 2'b00};
                                eval_state   <= S_EVAL_Y_WAIT1;
                            end
                        end
                    end
                    
                    // --- Byte 1: Tile Index ---
                    S_EVAL_TILE_WAIT1: eval_state <= S_EVAL_TILE_WAIT2;
                    S_EVAL_TILE_WAIT2: eval_state <= S_EVAL_TILE_LATCH;
                    S_EVAL_TILE_LATCH: begin
                        latched_tile <= oam_data;
                        oam_addr     <= {oam_scan_idx, 2'b10}; 
                        eval_state   <= S_EVAL_ATTR_WAIT1;
                    end
                    
                    // --- Byte 2: Attributes ---
                    S_EVAL_ATTR_WAIT1: eval_state <= S_EVAL_ATTR_WAIT2;
                    S_EVAL_ATTR_WAIT2: eval_state <= S_EVAL_ATTR_LATCH;
                    S_EVAL_ATTR_LATCH: begin
                        latched_attr <= oam_data;
                        oam_addr     <= {oam_scan_idx, 2'b11}; 
                        eval_state   <= S_EVAL_X_WAIT1;
                    end
                    
                    // --- Byte 3: X Coordinate ---
                    S_EVAL_X_WAIT1: eval_state <= S_EVAL_X_WAIT2;
                    S_EVAL_X_WAIT2: eval_state <= S_EVAL_X_LATCH;
                    S_EVAL_X_LATCH: begin
                        eval_spr_x[eval_sprite_count]       <= oam_data;
                        eval_spr_attr[eval_sprite_count]    <= latched_attr;
                        eval_spr_tile[eval_sprite_count]    <= latched_tile;
                        eval_spr_y_diff[eval_sprite_count]  <= (next_nes_y - latched_y - 8'd1);
                        eval_spr_is_zero[eval_sprite_count] <= (oam_scan_idx == 6'd0);
                        
                        eval_sprite_count <= eval_sprite_count + 4'd1;
                        
                        if (oam_scan_idx == 6'd63) begin
                            eval_state <= S_EVAL_DONE;
                        end else begin
                            oam_scan_idx <= oam_scan_idx + 6'd1;
                            oam_addr     <= {oam_scan_idx + 6'd1, 2'b00};
                            eval_state   <= S_EVAL_Y_WAIT1;
                        end
                    end
                    
                    S_EVAL_DONE: ; // Wait for internal_x 257
                    
                    // --- Phase 3: CHR Fetches (Clamp before 320) ---
                    S_FETCH_REQ: begin
                        if (eval_spr_attr[fetch_idx][7]) 
                            chr_addr <= base_pat_addr[13:0] | ({6'd0, eval_spr_tile[fetch_idx]} << 4) | (7 - eval_spr_y_diff[fetch_idx]);
                        else
                            chr_addr <= base_pat_addr[13:0] | ({6'd0, eval_spr_tile[fetch_idx]} << 4) | eval_spr_y_diff[fetch_idx];
                            
                        eval_state <= S_FETCH_LO_WAIT1;
                    end
                    
                    S_FETCH_LO_WAIT1: eval_state <= S_FETCH_LO_WAIT2;
                    S_FETCH_LO_WAIT2: eval_state <= S_FETCH_LO_WAIT3;
                    S_FETCH_LO_WAIT3: eval_state <= S_FETCH_LO_LATCH;
                    
                    S_FETCH_LO_LATCH: begin
                        // Horizontal flip resolution occurs during latch
                        if (eval_spr_attr[fetch_idx][6])
                            eval_spr_pat_lo[fetch_idx] <= {chr_data[0], chr_data[1], chr_data[2], chr_data[3], chr_data[4], chr_data[5], chr_data[6], chr_data[7]};
                        else
                            eval_spr_pat_lo[fetch_idx] <= chr_data;
                            
                        chr_addr <= chr_addr + 14'd8; 
                        eval_state <= S_FETCH_HI_WAIT1;
                    end
                    
                    S_FETCH_HI_WAIT1: eval_state <= S_FETCH_HI_WAIT2;
                    S_FETCH_HI_WAIT2: eval_state <= S_FETCH_HI_WAIT3;
                    S_FETCH_HI_WAIT3: eval_state <= S_FETCH_HI_LATCH;
                    
                    S_FETCH_HI_LATCH: begin
                        if (eval_spr_attr[fetch_idx][6])
                            eval_spr_pat_hi[fetch_idx] <= {chr_data[0], chr_data[1], chr_data[2], chr_data[3], chr_data[4], chr_data[5], chr_data[6], chr_data[7]};
                        else
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
    end

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 4: Down-Counters and Shift Registers
    // ─────────────────────────────────────────────────────────────────────────
    integer j;
    reg [7:0] active_render_y;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_render_y <= 8'hFF;
            active_sprite_count <= 4'd0;
            for (j = 0; j < 8; j = j + 1) begin
                active_spr_x[j]       <= 8'd0;
                active_spr_attr[j]    <= 8'd0;
                active_spr_pat_lo[j]  <= 8'd0;
                active_spr_pat_hi[j]  <= 8'd0;
                active_spr_is_zero[j] <= 1'b0;
            end
            
        end else if (nes_pixel_tick) begin
            // Transfer on start of line
            if (internal_x == 9'd0 && nes_y != active_render_y) begin
                active_render_y <= nes_y;
                active_sprite_count <= eval_sprite_count;
                for (j = 0; j < 8; j = j + 1) begin
                    active_spr_x[j]       <= eval_spr_x[j];
                    active_spr_attr[j]    <= eval_spr_attr[j];
                    active_spr_pat_lo[j]  <= eval_spr_pat_lo[j];
                    active_spr_pat_hi[j]  <= eval_spr_pat_hi[j];
                    active_spr_is_zero[j] <= eval_spr_is_zero[j];
                end
            end
            
            // Decrement down-counters and shift active pixels
            else if (nes_visible) begin
                for (j = 0; j < 8; j = j + 1) begin
                    if (j < active_sprite_count) begin
                        if (active_spr_x[j] > 8'd0) begin
                            active_spr_x[j] <= active_spr_x[j] - 8'd1;
                        end else begin
                            active_spr_pat_lo[j] <= {active_spr_pat_lo[j][6:0], 1'b0};
                            active_spr_pat_hi[j] <= {active_spr_pat_hi[j][6:0], 1'b0};
                        end
                    end
                end
            end
        end
    end

    // ─────────────────────────────────────────────────────────────────────────
    // Priority Encoder (Pixel Output)
    // ─────────────────────────────────────────────────────────────────────────
    reg [3:0] color_mux;
    reg       priority_mux;
    reg       is_zero_mux;
    
    always @(*) begin
        color_mux    = 4'b0000;
        priority_mux = 1'b0;
        is_zero_mux  = 1'b0;
        
        // Priority encoded to honor lowest OAM index
        if (active_sprite_count > 0 && active_spr_x[0] == 0 && {active_spr_pat_hi[0][7], active_spr_pat_lo[0][7]} != 2'b00) begin
            color_mux    = {active_spr_attr[0][1:0], active_spr_pat_hi[0][7], active_spr_pat_lo[0][7]};
            priority_mux = active_spr_attr[0][5];
            is_zero_mux  = active_spr_is_zero[0];
        end else if (active_sprite_count > 1 && active_spr_x[1] == 0 && {active_spr_pat_hi[1][7], active_spr_pat_lo[1][7]} != 2'b00) begin
            color_mux    = {active_spr_attr[1][1:0], active_spr_pat_hi[1][7], active_spr_pat_lo[1][7]};
            priority_mux = active_spr_attr[1][5];
            is_zero_mux  = active_spr_is_zero[1];
        end else if (active_sprite_count > 2 && active_spr_x[2] == 0 && {active_spr_pat_hi[2][7], active_spr_pat_lo[2][7]} != 2'b00) begin
            color_mux    = {active_spr_attr[2][1:0], active_spr_pat_hi[2][7], active_spr_pat_lo[2][7]};
            priority_mux = active_spr_attr[2][5];
        end else if (active_sprite_count > 3 && active_spr_x[3] == 0 && {active_spr_pat_hi[3][7], active_spr_pat_lo[3][7]} != 2'b00) begin
            color_mux    = {active_spr_attr[3][1:0], active_spr_pat_hi[3][7], active_spr_pat_lo[3][7]};
            priority_mux = active_spr_attr[3][5];
        end else if (active_sprite_count > 4 && active_spr_x[4] == 0 && {active_spr_pat_hi[4][7], active_spr_pat_lo[4][7]} != 2'b00) begin
            color_mux    = {active_spr_attr[4][1:0], active_spr_pat_hi[4][7], active_spr_pat_lo[4][7]};
            priority_mux = active_spr_attr[4][5];
        end else if (active_sprite_count > 5 && active_spr_x[5] == 0 && {active_spr_pat_hi[5][7], active_spr_pat_lo[5][7]} != 2'b00) begin
            color_mux    = {active_spr_attr[5][1:0], active_spr_pat_hi[5][7], active_spr_pat_lo[5][7]};
            priority_mux = active_spr_attr[5][5];
        end else if (active_sprite_count > 6 && active_spr_x[6] == 0 && {active_spr_pat_hi[6][7], active_spr_pat_lo[6][7]} != 2'b00) begin
            color_mux    = {active_spr_attr[6][1:0], active_spr_pat_hi[6][7], active_spr_pat_lo[6][7]};
            priority_mux = active_spr_attr[6][5];
        end else if (active_sprite_count > 7 && active_spr_x[7] == 0 && {active_spr_pat_hi[7][7], active_spr_pat_lo[7][7]} != 2'b00) begin
            color_mux    = {active_spr_attr[7][1:0], active_spr_pat_hi[7][7], active_spr_pat_lo[7][7]};
            priority_mux = active_spr_attr[7][5];
        end

        sprite_color_idx   = nes_visible ? color_mux : 4'b0000;
        sprite_bg_priority = nes_visible ? priority_mux : 1'b0;
        sprite0_active     = nes_visible ? is_zero_mux : 1'b0;
    end

endmodule