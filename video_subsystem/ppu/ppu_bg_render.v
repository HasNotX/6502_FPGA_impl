/*
 * File: ppu_bg_render.v
 * Description: Background rendering pipeline. Fetches Nametable, Attribute, 
 * and Pattern data, and outputs it pixel-by-pixel.
 * Includes synchronized 1-cycle wait states for BRAM latency compensation.
 */

module ppu_bg_render (
    input  wire        clk,
    input  wire        reset,
    
    input  wire [7:0]  nes_x,
    input  wire [7:0]  nes_y,
    input  wire        nes_visible,

    output reg  [14:0] bg_mem_addr,
    input  wire [7:0]  bg_mem_data,
    
    output wire [3:0]  pixel_color_idx,
    output wire [7:0]  dbg_nt_latch     // Telemetry Export
);

    reg [7:0] last_nes_x;
    always @(posedge clk) last_nes_x <= nes_x;
    
    // Pulse true for exactly one 25MHz cycle every time the NES pixel advances
    wire nes_pixel_tick = (nes_x != last_nes_x) && nes_visible;

    // Expanded to 4 bits to support the 9-state sequence
    reg [3:0] fetch_state; 
    
    reg [7:0] nametable_latch;
    reg [1:0] attr_latch; 
    reg [7:0] pattern_lo_latch;
    reg [7:0] pattern_hi_latch;

    assign dbg_nt_latch = nametable_latch;

    // Holding registers for the currently drawing tile
    reg [7:0] active_pat_lo;
    reg [7:0] active_pat_hi;
    reg [1:0] active_attr;

    // Look ahead 8 pixels to fetch the NEXT tile while rendering the current one
    wire [7:0] fetch_x = nes_x + 8'd8;
    wire [7:0] fetch_y = nes_y;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_state      <= 4'd0;
            bg_mem_addr      <= 15'd0;
            nametable_latch  <= 8'd0;
            attr_latch       <= 2'd0;
            pattern_lo_latch <= 8'd0;
            pattern_hi_latch <= 8'd0;
        end else if (nes_visible) begin
            // A full tile fetch takes 16 clock cycles. 
            // Trigger the 9-cycle fetch sequence at the start of a tile boundary.
            if (nes_pixel_tick && nes_x[2:0] == 3'd0) begin
                fetch_state <= 4'd1;
            end

            case (fetch_state)
                4'd0: ; // Idle
                
                // --- FETCH 1: NAMETABLE ---
                4'd1: begin
                    bg_mem_addr <= 15'h2000 | ({7'd0, fetch_y[7:3]} << 5) | {10'd0, fetch_x[7:3]};
                    fetch_state <= 4'd2;
                end
                4'd2: begin 
                    // BRAM Latency Wait
                    fetch_state <= 4'd3;
                end
                4'd3: begin
                    nametable_latch <= bg_mem_data; 
                    
                    // --- FETCH 2: ATTRIBUTE ---
                    bg_mem_addr <= 15'h23C0 | ({8'd0, fetch_y[7:5]} << 3) | {12'd0, fetch_x[7:5]};
                    fetch_state <= 4'd4;
                end
                4'd4: begin 
                    // BRAM Latency Wait
                    fetch_state <= 4'd5;
                end
                4'd5: begin
                    case ({fetch_y[4], fetch_x[4]})
                        2'b00: attr_latch <= bg_mem_data[1:0];
                        2'b01: attr_latch <= bg_mem_data[3:2];
                        2'b10: attr_latch <= bg_mem_data[5:4];
                        2'b11: attr_latch <= bg_mem_data[7:6];
                    endcase
                    
                    // --- FETCH 3: PATTERN LO ---
                    bg_mem_addr <= 15'h0000 | ({7'd0, nametable_latch} << 4) | {12'd0, fetch_y[2:0]};
                    fetch_state <= 4'd6;
                end
                4'd6: begin 
                    // BRAM Latency Wait
                    fetch_state <= 4'd7;
                end
                4'd7: begin
                    pattern_lo_latch <= bg_mem_data;
                    
                    // --- FETCH 4: PATTERN HI ---
                    bg_mem_addr <= 15'h0000 | ({7'd0, nametable_latch} << 4) | 15'd8 | {12'd0, fetch_y[2:0]};
                    fetch_state <= 4'd8; 
                end
                4'd8: begin 
                    // BRAM Latency Wait
                    fetch_state <= 4'd9;
                end
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

    // Load the fetched tile registers securely at the start of the 8-pixel boundary
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_pat_lo <= 8'd0;
            active_pat_hi <= 8'd0;
            active_attr   <= 2'd0;
        end else if (nes_visible) begin
            if (nes_pixel_tick && nes_x[2:0] == 3'd0) begin
                active_pat_lo <= pattern_lo_latch;
                active_pat_hi <= pattern_hi_latch;
                active_attr   <= attr_latch;
            end
        end
    end

    // Pixel Output Multiplexer
    wire [2:0] bit_sel = 3'd7 - nes_x[2:0];
    
    wire pat_bit_0 = active_pat_lo[bit_sel];
    wire pat_bit_1 = active_pat_hi[bit_sel];
    
    assign pixel_color_idx = (pat_bit_1 == 0 && pat_bit_0 == 0) ? 4'b0000 : {active_attr, pat_bit_1, pat_bit_0};

endmodule