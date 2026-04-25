/*
 * Module: ppu_bg_render
 * Description: Hardware-accurate phase-shifted background rendering engine.
 * Implements 10-bit math for nametable wrapping and internal coordinate 
 * tracking to handle HBlank prefetching and mid-frame scroll splits.
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
    // Internal Pixel & Tick Tracking (Fix for HBlank Starvation)
    // -------------------------------------------------------------------------
    reg [7:0] last_nes_x;
    reg       local_tick;
    
    always @(posedge clk) begin
        last_nes_x <= nes_x;
        if (nes_x != last_nes_x)
            local_tick <= 1'b1;
        else
            local_tick <= ~local_tick;
    end
    wire nes_pixel_tick = local_tick;

    reg [8:0] internal_x;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            internal_x <= 9'd0;
        end else if (nes_pixel_tick) begin
            if (nes_visible) begin
                internal_x <= {1'b0, nes_x};
            end else begin
                internal_x <= internal_x + 9'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Y-Coordinate Tracking for Mid-Frame Splits (Fix for Absolute Coord Trap)
    // -------------------------------------------------------------------------
    reg [8:0] active_y;
    reg [7:0] last_loopy_y;
    reg [7:0] last_loopy_x;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_y     <= 9'd0;
            last_loopy_y <= 8'd0;
            last_loopy_x <= 8'd0;
        end else begin
            last_loopy_y <= loopy_scroll_y;
            last_loopy_x <= loopy_scroll_x;
            
            // Frame reset logic
            if (nes_visible && nes_y == 8'd0 && nes_x == 8'd0 && nes_pixel_tick) begin
                active_y <= {1'b0, loopy_scroll_y};
            end
            // Mid-frame scroll split (CPU write to $2006/$2005)
            else if (loopy_scroll_y != last_loopy_y || loopy_scroll_x != last_loopy_x) begin
                active_y <= {1'b0, loopy_scroll_y};
            end
            // Scanline increment at the end of active display
            else if (internal_x == 9'd255 && nes_pixel_tick) begin
                active_y <= active_y + 9'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Hardware-Accurate Phase-Shifted Coordinates
    // -------------------------------------------------------------------------
    // Wrap internal_x during HBlank to simulate nametable coordinate wrap for prefetch
    wire [8:0] wrapped_x = (internal_x >= 9'd256) ? (internal_x - 9'd320) : internal_x;
    
    wire [8:0] true_x = wrapped_x + {1'b0, loopy_scroll_x};
    wire [8:0] true_y = active_y;

    wire [8:0] fetch_y = (true_y >= 9'd240) ? (true_y - 9'd240) : true_y;
    wire nt_y_cross    = (true_y >= 9'd240);

    // FIX: 10-bit math to prevent nametable wrapping overflow
    wire [9:0] fetch_x_sum = {1'b0, true_x} + 10'd8;
    wire [7:0] fetch_x     = fetch_x_sum[7:0];
    wire nt_x_cross        = fetch_x_sum[8];

    // Combine the base nametable selection with the crossover logic
    wire final_nt_x = loopy_nt_x ^ nt_x_cross;
    wire final_nt_y = loopy_nt_y ^ nt_y_cross;

    wire [14:0] active_nt_base = 15'h2000 | ({13'd0, final_nt_y, final_nt_x} << 10);
    wire [14:0] base_pat_addr  = {2'b00, ppu_ctrl_reg[4], 12'd0};

    reg [3:0] fetch_state; 
    
    reg [7:0] nametable_latch;
    reg [1:0] attr_latch; 
    reg [7:0] pattern_lo_latch;
    reg [7:0] pattern_hi_latch;

    assign dbg_nt_latch = nametable_latch;

    reg [7:0] active_pat_lo;
    reg [7:0] active_pat_hi;
    reg [1:0] active_attr;
    
    // Prefetch window opens at internal_x 320 to prime the latches for the next scanline
    wire is_active_window = nes_visible || (internal_x >= 9'd320 && internal_x <= 9'd336);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_state <= 4'd0;
            bg_mem_addr <= 15'd0;
        end else if (is_active_window) begin
            if (nes_pixel_tick && true_x[2:0] == 3'd0) begin
                fetch_state <= 4'd1;
            end

            case (fetch_state)
                4'd0: ;
                4'd1: begin
                    bg_mem_addr <= active_nt_base |
                                ({7'd0, fetch_y[7:3]} << 5) | {10'd0, fetch_x[7:3]};
                    fetch_state <= 4'd2;
                end
                4'd2: fetch_state <= 4'd3;
                4'd3: begin
                    nametable_latch <= bg_mem_data;
                    bg_mem_addr <= (active_nt_base | 15'h03C0) | ({8'd0, fetch_y[7:5]} << 3) | {12'd0, fetch_x[7:5]};
                    fetch_state <= 4'd4;
                end
                4'd4: fetch_state <= 4'd5;
                4'd5: begin
                    case ({fetch_y[4], fetch_x[4]})
                        2'b00: attr_latch <= bg_mem_data[1:0];
                        2'b01: attr_latch <= bg_mem_data[3:2];
                        2'b10: attr_latch <= bg_mem_data[5:4];
                        2'b11: attr_latch <= bg_mem_data[7:6];
                    endcase
                    bg_mem_addr <= base_pat_addr |
                                ({7'd0, nametable_latch} << 4) | {12'd0, fetch_y[2:0]};
                    fetch_state <= 4'd6;
                end
                4'd6: fetch_state <= 4'd7;
                4'd7: begin
                    pattern_lo_latch <= bg_mem_data;
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | 15'd8 | {12'd0, fetch_y[2:0]};
                    fetch_state <= 4'd8;
                end
                4'd8: fetch_state <= 4'd9;
                4'd9: begin
                    pattern_hi_latch <= bg_mem_data;
                    fetch_state <= 4'd0;
                end
                default: fetch_state <= 4'd0;
            endcase
        end else begin
            fetch_state <= 4'd0;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_pat_lo <= 8'd0;
            active_pat_hi <= 8'd0;
            active_attr   <= 2'd0;
        end else if (is_active_window) begin
            if (nes_pixel_tick && true_x[2:0] == 3'd0) begin
                active_pat_lo <= pattern_lo_latch;
                active_pat_hi <= pattern_hi_latch;
                active_attr   <= attr_latch;
            end
        end
    end

    wire [2:0] bit_sel = 3'd7 - true_x[2:0];
    wire pat_bit_0 = active_pat_lo[bit_sel];
    wire pat_bit_1 = active_pat_hi[bit_sel];
    
    assign pixel_color_idx = (pat_bit_1 == 0 && pat_bit_0 == 0) ?
                             4'b0000 : {active_attr, pat_bit_1, pat_bit_0};

endmodule