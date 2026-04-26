/*
 * File: ppu_bg_render.v
 * Description: Cycle-accurate phase-shifted background rendering engine.
 * Employs hardware-accurate Y-coordinate tracking and 10-bit X-wrap logic.
 */

module ppu_bg_render (
    input  wire        clk,
    input  wire        reset,
    
    input  wire [7:0]  nes_x,
    input  wire [7:0]  nes_y,
    input  wire        nes_visible,
    input  wire [7:0]  ppu_ctrl_reg,
    
    input  wire [7:0]  loopy_scroll_x,
    input  wire [7:0]  loopy_scroll_y,
    input  wire        loopy_nt_x,
    input  wire        loopy_nt_y,

    output reg  [14:0] bg_mem_addr,
    input  wire [7:0]  bg_mem_data,
    
    output wire [3:0]  pixel_color_idx,
    output wire [7:0]  dbg_nt_latch    
);

    // -------------------------------------------------------------------------
    // Phase Tracking
    // -------------------------------------------------------------------------
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
            if (nes_visible) begin
                internal_x <= {1'b0, nes_x};
            end else begin
                if (internal_x == 9'd399) internal_x <= 9'd0;
                else                      internal_x <= internal_x + 9'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Hardware-Accurate Y-Coordinate Tracking
    // -------------------------------------------------------------------------
    reg [8:0] active_y;
    reg       active_nt_y;
    reg [7:0] last_loopy_y;
    reg [7:0] last_loopy_x;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_y     <= 9'd0;
            active_nt_y  <= 1'b0;
            last_loopy_y <= 8'd0;
            last_loopy_x <= 8'd0;
        end else begin
            last_loopy_y <= loopy_scroll_y;
            last_loopy_x <= loopy_scroll_x;
            
            // Frame start reset
            if (nes_visible && nes_y == 8'd0 && nes_x == 8'd0 && nes_pixel_tick) begin
                active_y    <= {1'b0, loopy_scroll_y};
                active_nt_y <= loopy_nt_y;
            end
            // CPU Mid-Frame Scroll Write ($2006)
            else if (loopy_scroll_y != last_loopy_y || loopy_scroll_x != last_loopy_x) begin
                active_y    <= {1'b0, loopy_scroll_y};
                active_nt_y <= loopy_nt_y;
            end
            // Hardware Scanline Increment (End of visible line)
            else if (internal_x == 9'd256 && nes_pixel_tick) begin
                if (active_y == 9'd239) begin
                    active_y    <= 9'd0;
                    active_nt_y <= ~active_nt_y;
                end else if (active_y == 9'd255) begin
                    active_y <= 9'd0; // Wraps to 0 without flipping NT
                end else begin
                    active_y <= active_y + 9'd1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 10-Bit Coordinate Math (Fixes 512 Wrap)
    // -------------------------------------------------------------------------
    wire [9:0] phase_x    = {1'b0, internal_x} + 10'd8;
    wire [9:0] true_x_sum = phase_x + {2'b00, loopy_scroll_x};
    wire [7:0] fetch_x    = true_x_sum[7:0];
    wire nt_x_cross       = true_x_sum[8] ^ true_x_sum[9]; // XOR 256 and 512 bits

    wire [7:0] fetch_y    = active_y[7:0];
    
    wire final_nt_x = loopy_nt_x ^ nt_x_cross;
    wire final_nt_y = active_nt_y;

    wire [14:0] active_nt_base = 15'h2000 | ({13'd0, final_nt_y, final_nt_x} << 10);
    wire [14:0] base_pat_addr  = {2'b00, ppu_ctrl_reg[4], 12'd0};

    // -------------------------------------------------------------------------
    // Synchronous 8-Tick Pipeline
    // -------------------------------------------------------------------------
    reg [7:0] nametable_latch;
    reg [1:0] attr_latch; 
    reg [7:0] pattern_lo_latch;
    reg [7:0] pattern_hi_latch;

    assign dbg_nt_latch = nametable_latch;

    wire is_primer_window = (internal_x >= 9'd320 && internal_x <= 9'd336);
    wire pipeline_active  = nes_visible || is_primer_window;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bg_mem_addr <= 15'd0;
        end else if (pipeline_active && nes_pixel_tick) begin
            case (phase_x[2:0])
                3'd0: begin 
                    bg_mem_addr <= active_nt_base | ({7'd0, fetch_y[7:3]} << 5) | {10'd0, fetch_x[7:3]};
                end
                3'd1: ;
                3'd2: begin 
                    nametable_latch <= bg_mem_data;
                    bg_mem_addr <= (active_nt_base | 15'h03C0) | ({8'd0, fetch_y[7:5]} << 3) | {12'd0, fetch_x[7:5]};
                end
                3'd3: ;
                3'd4: begin 
                    case ({fetch_y[4], fetch_x[4]})
                        2'b00: attr_latch <= bg_mem_data[1:0];
                        2'b01: attr_latch <= bg_mem_data[3:2];
                        2'b10: attr_latch <= bg_mem_data[5:4];
                        2'b11: attr_latch <= bg_mem_data[7:6];
                    endcase
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | {12'd0, fetch_y[2:0]};
                end
                3'd5: ;
                3'd6: begin 
                    pattern_lo_latch <= bg_mem_data;
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | 15'd8 | {12'd0, fetch_y[2:0]};
                end
                3'd7: begin 
                    pattern_hi_latch <= bg_mem_data;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Industrial Shift Registers
    // -------------------------------------------------------------------------
    reg [15:0] shift_pat_lo;
    reg [15:0] shift_pat_hi;
    reg [15:0] shift_attr_lo;
    reg [15:0] shift_attr_hi;

    wire load_now = (nes_pixel_tick && pipeline_active && phase_x[2:0] == 3'd0 && internal_x != 9'd0);
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            shift_pat_lo  <= 16'd0;
            shift_pat_hi  <= 16'd0;
            shift_attr_lo <= 16'd0;
            shift_attr_hi <= 16'd0;
        end else if (nes_pixel_tick && pipeline_active) begin
            if (load_now) begin
                shift_pat_lo  <= {shift_pat_lo[14:7], pattern_lo_latch};
                shift_pat_hi  <= {shift_pat_hi[14:7], pattern_hi_latch};
                shift_attr_lo <= {shift_attr_lo[14:7], {8{attr_latch[0]}}};
                shift_attr_hi <= {shift_attr_hi[14:7], {8{attr_latch[1]}}};
            end else begin
                shift_pat_lo  <= {shift_pat_lo[14:0], 1'b0};
                shift_pat_hi  <= {shift_pat_hi[14:0], 1'b0};
                shift_attr_lo <= {shift_attr_lo[14:0], 1'b0};
                shift_attr_hi <= {shift_attr_hi[14:0], 1'b0};
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output Multiplexer
    // -------------------------------------------------------------------------
    wire [3:0] fine_x  = loopy_scroll_x[2:0];
    wire [3:0] bit_sel = 4'd15 - fine_x; 
    
    wire pat_bit_0  = shift_pat_lo[bit_sel];
    wire pat_bit_1  = shift_pat_hi[bit_sel];
    wire attr_bit_0 = shift_attr_lo[bit_sel];
    wire attr_bit_1 = shift_attr_hi[bit_sel];
    
    assign pixel_color_idx = (pat_bit_1 == 0 && pat_bit_0 == 0) ? 4'b0000 : {attr_bit_1, attr_bit_0, pat_bit_1, pat_bit_0};

endmodule