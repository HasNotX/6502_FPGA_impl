/*
 * File: ppu_bg_render.v
 * Description: Phase-Shifted Background Renderer.
 * Aligns the memory fetch sequences dynamically with the scrolled coordinate
 * to perform perfect fine-pixel scrolling without a 16-bit shift register.
 */

module ppu_bg_render (
    input  wire        clk,
    input  wire        reset,
    
    input  wire [7:0]  nes_x,
    input  wire [7:0]  nes_y,
    input  wire        nes_visible,
    input  wire [7:0]  ppu_ctrl_reg,
    input  wire [7:0]  scroll_x,
    input  wire [7:0]  scroll_y,

    output reg  [14:0] bg_mem_addr,
    input  wire [7:0]  bg_mem_data,
    
    output wire [3:0]  pixel_color_idx,
    output wire [7:0]  dbg_nt_latch    
);

    reg [7:0] last_nes_x;
    always @(posedge clk) last_nes_x <= nes_x;
    wire nes_pixel_tick = (nes_x != last_nes_x);

    // ─────────────────────────────────────────────────────────────────────────
    // Phase-Shifted Coordinates
    // ─────────────────────────────────────────────────────────────────────────
    wire [8:0] true_x = {1'b0, nes_x} + {1'b0, scroll_x};
    wire [8:0] true_y = {1'b0, nes_y} + {1'b0, scroll_y};

    wire [8:0] fetch_y = (true_y >= 9'd240) ? (true_y - 9'd240) : true_y;
    wire nt_y_cross    = (true_y >= 9'd240);

    // Look ahead 8 pixels to pre-fetch the upcoming tile
    wire [8:0] fetch_x_sum = true_x + 9'd8;
    wire [7:0] fetch_x     = fetch_x_sum[7:0];
    wire nt_x_cross        = fetch_x_sum[8];

    // Dynamically calculate Nametable Base
    wire base_nt_bit_x = ppu_ctrl_reg[0] ^ nt_x_cross;
    wire base_nt_bit_y = ppu_ctrl_reg[1] ^ nt_y_cross;
    wire [14:0] active_nt_base = 15'h2000 | ({13'd0, base_nt_bit_y, base_nt_bit_x} << 10);
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

    // Enable pre-fetching during the late HBlank period
    wire is_active_window = nes_visible || (nes_x >= 8'd304);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_state <= 4'd0;
            bg_mem_addr <= 15'd0;
        end else if (is_active_window) begin
            // Trigger fetch exactly when the scrolled coordinate hits a tile boundary
            if (nes_pixel_tick && true_x[2:0] == 3'd0) begin
                fetch_state <= 4'd1;
            end

            case (fetch_state)
                4'd0: ; 
                4'd1: begin
                    bg_mem_addr <= active_nt_base | ({7'd0, fetch_y[7:3]} << 5) | {10'd0, fetch_x[7:3]};
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
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | {12'd0, fetch_y[2:0]};
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

    // Use the scrolled coordinate to mux the inner pixel
    wire [2:0] bit_sel = 3'd7 - true_x[2:0];
    
    wire pat_bit_0 = active_pat_lo[bit_sel];
    wire pat_bit_1 = active_pat_hi[bit_sel];
    
    assign pixel_color_idx = (pat_bit_1 == 0 && pat_bit_0 == 0) ? 4'b0000 : {active_attr, pat_bit_1, pat_bit_0};

endmodule