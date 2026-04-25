/*
 * File: ppu_bg_render.v
 * Description: Hardware-accurate phase-shifted background rendering engine.
 * Upgraded with 16-bit shift registers for seamless Fine X scrolling and
 * divide-by-2 phase tracking to maintain integer scaling through HBlank.
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
    // Stable Pixel Tick (Div-by-2 of 25MHz to match NES pixel rate)
    // -------------------------------------------------------------------------
    reg [7:0] last_nes_x;
    reg       phase;
    
    always @(posedge clk) begin
        last_nes_x <= nes_x;
        // Resynchronize the phase on active edges, toggle during HBlank
        if (nes_x != last_nes_x) begin
            phase <= 1'b1;
        end else begin
            phase <= ~phase;
        end
    end
    wire nes_pixel_tick = phase;

    // -------------------------------------------------------------------------
    // Internal X/Y Tracking for HBlank & Split Scrolling
    // -------------------------------------------------------------------------
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
            
            if (nes_visible && nes_y == 8'd0 && nes_x == 8'd0 && nes_pixel_tick) begin
                active_y <= {1'b0, loopy_scroll_y};
            end
            else if (loopy_scroll_y != last_loopy_y || loopy_scroll_x != last_loopy_x) begin
                active_y <= {1'b0, loopy_scroll_y};
            end
            else if (internal_x == 9'd255 && nes_pixel_tick) begin
                active_y <= active_y + 9'd1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Coordinate Math & Hardware-Accurate Phase Shift
    // -------------------------------------------------------------------------
    wire [8:0] wrapped_x = (internal_x >= 9'd256) ? (internal_x - 9'd320) : internal_x;
    
    wire [8:0] true_y  = active_y;
    wire [8:0] fetch_y = (true_y >= 9'd240) ? (true_y - 9'd240) : true_y;
    wire nt_y_cross    = (true_y >= 9'd240);

    // Base fetch address isolated from fine X
    wire [9:0] fetch_x_sum = {1'b0, wrapped_x} + {2'b00, loopy_scroll_x};
    wire [7:0] fetch_x     = fetch_x_sum[7:0];
    wire nt_x_cross        = fetch_x_sum[8];

    wire final_nt_x = loopy_nt_x ^ nt_x_cross;
    wire final_nt_y = loopy_nt_y ^ nt_y_cross;

    wire [14:0] active_nt_base = 15'h2000 | ({13'd0, final_nt_y, final_nt_x} << 10);
    wire [14:0] base_pat_addr  = {2'b00, ppu_ctrl_reg[4], 12'd0};

    // -------------------------------------------------------------------------
    // Memory Fetch Pipeline
    // -------------------------------------------------------------------------
    reg [3:0] fetch_state; 
    reg [7:0] nametable_latch;
    reg [1:0] attr_latch; 
    reg [7:0] pattern_lo_latch;
    reg [7:0] pattern_hi_latch;

    assign dbg_nt_latch = nametable_latch;

    wire is_active_window = nes_visible || (internal_x >= 9'd320 && internal_x <= 9'd336);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_state <= 4'd0;
            bg_mem_addr <= 15'd0;
        end else if (is_active_window) begin
            if (nes_pixel_tick && wrapped_x[2:0] == 3'd0) begin
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

    // -------------------------------------------------------------------------
    // 16-Bit Hardware Shift Registers
    // -------------------------------------------------------------------------
    reg [15:0] shift_pat_lo;
    reg [15:0] shift_pat_hi;
    reg [15:0] shift_attr_lo;
    reg [15:0] shift_attr_hi;

    wire load_shift_regs = (nes_pixel_tick && wrapped_x[2:0] == 3'd0 && internal_x != 9'd0 && is_active_window);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            shift_pat_lo  <= 16'd0;
            shift_pat_hi  <= 16'd0;
            shift_attr_lo <= 16'd0;
            shift_attr_hi <= 16'd0;
        end else if (nes_pixel_tick && is_active_window) begin
            
            // Shift registers continuously push left
            shift_pat_lo  <= {shift_pat_lo[14:0], 1'b0};
            shift_pat_hi  <= {shift_pat_hi[14:0], 1'b0};
            shift_attr_lo <= {shift_attr_lo[14:0], 1'b0};
            shift_attr_hi <= {shift_attr_hi[14:0], 1'b0};
            
            // Reload lower byte every 8 pixels (Except at X=0 to prevent overwrite)
            if (load_shift_regs) begin
                shift_pat_lo[7:0]  <= pattern_lo_latch;
                shift_pat_hi[7:0]  <= pattern_hi_latch;
                shift_attr_lo[7:0] <= {8{attr_latch[0]}};
                shift_attr_hi[7:0] <= {8{attr_latch[1]}};
            end
        end
    end

    // -------------------------------------------------------------------------
    // Pixel Output Multiplexer
    // -------------------------------------------------------------------------
    wire [3:0] fine_x  = loopy_scroll_x[2:0];
    wire [3:0] bit_sel = 4'd15 - fine_x;
    
    wire pat_bit_0  = shift_pat_lo[bit_sel];
    wire pat_bit_1  = shift_pat_hi[bit_sel];
    wire attr_bit_0 = shift_attr_lo[bit_sel];
    wire attr_bit_1 = shift_attr_hi[bit_sel];
    
    assign pixel_color_idx = (pat_bit_1 == 0 && pat_bit_0 == 0) ?
                             4'b0000 : {attr_bit_1, attr_bit_0, pat_bit_1, pat_bit_0};

endmodule