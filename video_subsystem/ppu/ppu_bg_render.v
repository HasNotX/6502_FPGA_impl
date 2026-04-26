/*
 * File: ppu_bg_render.v
 * Description: Cycle-accurate background rendering engine.
 * Fixed Shift Register Primer Fetches to eliminate Horizontal Wrap-Around.
 */

module ppu_bg_render (
    input  wire        clk,
    input  wire        reset,
    
    input  wire [7:0]  nes_x,
    input  wire [7:0]  nes_y,
    input  wire        nes_visible,
    input  wire        is_vblank, // Global VBlank flag
    input  wire [7:0]  ppu_ctrl_reg,
    
    input  wire [14:0] active_v_reg, 
    input  wire [2:0]  fine_x_scroll, 

    output reg  [14:0] bg_mem_addr,
    input  wire [7:0]  bg_mem_data,
    
    output wire [3:0]  pixel_color_idx   
);

    reg [7:0] last_nes_x;
    reg       phase;
    always @(posedge clk) begin
        last_nes_x <= nes_x;
        if (nes_x != last_nes_x) phase <= 1'b1;
        else                     phase <= ~phase;
    end
    wire nes_pixel_tick = phase;

    reg [8:0] internal_x;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            internal_x <= 9'd0;
        end else if (nes_pixel_tick) begin
            if (nes_visible) internal_x <= {1'b0, nes_x};
            else begin
                if (internal_x == 9'd340) internal_x <= 9'd0; 
                else                      internal_x <= internal_x + 9'd1;
            end
        end
    end

    wire [14:0] base_pat_addr  = {2'b00, ppu_ctrl_reg[4], 12'd0};

    reg [7:0] nametable_latch;
    reg [1:0] attr_latch; 
    reg [7:0] pattern_lo_latch;
    reg [7:0] pattern_hi_latch;

    // The Primer Window: Fetches the first two tiles of the NEXT scanline during HBlank
    wire is_primer_window = (internal_x >= 9'd320 && internal_x <= 9'd336);
    wire pipeline_active  = !is_vblank && (nes_visible || is_primer_window);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bg_mem_addr <= 15'd0;
        end else if (pipeline_active && nes_pixel_tick) begin
            case (internal_x[2:0])
                3'd0: bg_mem_addr <= 15'h2000 | (active_v_reg & 15'h0FFF); 
                3'd1: ; 
                3'd2: begin 
                    nametable_latch <= bg_mem_data; 
                    bg_mem_addr <= 15'h23C0 | (active_v_reg & 15'h0C00) | ({9'd0, active_v_reg[9:7]} << 3) | {12'd0, active_v_reg[4:2]};
                end
                3'd3: ; 
                3'd4: begin 
                    case ({active_v_reg[6], active_v_reg[1]})
                        2'b00: attr_latch <= bg_mem_data[1:0];
                        2'b01: attr_latch <= bg_mem_data[3:2];
                        2'b10: attr_latch <= bg_mem_data[5:4];
                        2'b11: attr_latch <= bg_mem_data[7:6];
                    endcase
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | {12'd0, active_v_reg[14:12]};
                end
                3'd5: ; 
                3'd6: begin 
                    pattern_lo_latch <= bg_mem_data; 
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | 15'd8 | {12'd0, active_v_reg[14:12]};
                end
                3'd7: begin 
                    pattern_hi_latch <= bg_mem_data; 
                end
            endcase
        end
    end

    reg [15:0] shift_pat_lo;
    reg [15:0] shift_pat_hi;
    reg [15:0] shift_attr_lo;
    reg [15:0] shift_attr_hi;

    // Shift continuously during the visible scanline
    wire do_shift = (nes_pixel_tick && nes_visible);
    // Load new tiles every 8 pixels, AND during the HBlank primer window
    wire load_now = (nes_pixel_tick && pipeline_active && internal_x[2:0] == 3'd0 && internal_x != 9'd0);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            shift_pat_lo  <= 16'd0;
            shift_pat_hi  <= 16'd0;
            shift_attr_lo <= 16'd0;
            shift_attr_hi <= 16'd0;
        end else if (do_shift && load_now) begin
            // Active render + Load: Shift upper byte 1 bit, snap new tile into lower byte
            shift_pat_lo  <= {shift_pat_lo[14:7], pattern_lo_latch};
            shift_pat_hi  <= {shift_pat_hi[14:7], pattern_hi_latch};
            shift_attr_lo <= {shift_attr_lo[14:7], {8{attr_latch[0]}}};
            shift_attr_hi <= {shift_attr_hi[14:7], {8{attr_latch[1]}}};
        end else if (do_shift) begin
            // Active render: Standard 1-bit pixel shift
            shift_pat_lo  <= {shift_pat_lo[14:0], 1'b0};
            shift_pat_hi  <= {shift_pat_hi[14:0], 1'b0};
            shift_attr_lo <= {shift_attr_lo[14:0], 1'b0};
            shift_attr_hi <= {shift_attr_hi[14:0], 1'b0};
        end else if (load_now) begin
            // Primer window: Shift entire byte left, load new tile
            shift_pat_lo  <= {shift_pat_lo[7:0], pattern_lo_latch};
            shift_pat_hi  <= {shift_pat_hi[7:0], pattern_hi_latch};
            shift_attr_lo <= {shift_attr_lo[7:0], {8{attr_latch[0]}}};
            shift_attr_hi <= {shift_attr_hi[7:0], {8{attr_latch[1]}}};
        end
    end

    // Priority Mux selecting pixel dynamically based on Fine X Scroll
    wire [3:0] bit_sel = 4'd15 - fine_x_scroll; 
    
    wire pat_bit_0  = shift_pat_lo[bit_sel];
    wire pat_bit_1  = shift_pat_hi[bit_sel];
    wire attr_bit_0 = shift_attr_lo[bit_sel];
    wire attr_bit_1 = shift_attr_hi[bit_sel];
    
    assign pixel_color_idx = (pat_bit_1 == 0 && pat_bit_0 == 0) ?
                             4'b0000 : {attr_bit_1, attr_bit_0, pat_bit_1, pat_bit_0};

endmodule