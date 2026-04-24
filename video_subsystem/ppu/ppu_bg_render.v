module ppu_bg_render (
    input  wire        clk,
    input  wire        reset,
    
    input  wire [7:0]  nes_x,
    input  wire [7:0]  nes_y,
    input  wire        nes_visible,

    output reg  [14:0] bg_mem_addr,
    input  wire [7:0]  bg_mem_data,
    
    output wire [3:0]  pixel_color_idx 
);

    // Detect when nes_x advances (which happens every 2 clock cycles)
    reg [7:0] last_nes_x;
    always @(posedge clk) last_nes_x <= nes_x;
    wire nes_pixel_tick = (nes_x != last_nes_x) && nes_visible;

    reg [2:0] fetch_state;
    reg [2:0] last_fetch_state;
    always @(posedge clk) last_fetch_state <= fetch_state;
    
    reg [7:0] nametable_latch;
    reg [1:0] attr_latch; 
    reg [7:0] pattern_lo_latch;
    reg [7:0] pattern_hi_latch;

    // Holding registers for the currently drawing tile
    reg [7:0] active_pat_lo;
    reg [7:0] active_pat_hi;
    reg [1:0] active_attr;

    // We fetch the NEXT tile, so we look ahead by 8 pixels
    wire [7:0] fetch_x = nes_x + 8'd8;
    wire [7:0] fetch_y = nes_y;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_state <= 3'd0;
            bg_mem_addr <= 15'd0;
        end else if (nes_visible) begin
            // Trigger the 8-cycle fetch sequence at the start of a tile
            if (nes_pixel_tick && nes_x[2:0] == 3'd0) begin
                fetch_state <= 3'd1;
            end

            case (fetch_state)
                3'd0: ; // Idle
                
                3'd1: begin
                    bg_mem_addr <= 15'h2000 | ({7'd0, fetch_y[7:3]} << 5) | {10'd0, fetch_x[7:3]};
                    fetch_state <= 3'd2;
                end
                3'd2: begin
                    nametable_latch <= bg_mem_data; 
                    fetch_state <= 3'd3;
                end
                
                3'd3: begin
                    bg_mem_addr <= 15'h23C0 | ({8'd0, fetch_y[7:5]} << 3) | {12'd0, fetch_x[7:5]};
                    fetch_state <= 3'd4;
                end
                3'd4: begin
                    case ({fetch_y[4], fetch_x[4]})
                        2'b00: attr_latch <= bg_mem_data[1:0];
                        2'b01: attr_latch <= bg_mem_data[3:2];
                        2'b10: attr_latch <= bg_mem_data[5:4];
                        2'b11: attr_latch <= bg_mem_data[7:6];
                    endcase
                    fetch_state <= 3'd5;
                end
                
                3'd5: begin
                    bg_mem_addr <= 15'h0000 | ({7'd0, nametable_latch} << 4) | {12'd0, fetch_y[2:0]};
                    fetch_state <= 3'd6;
                end
                3'd6: begin
                    pattern_lo_latch <= bg_mem_data;
                    fetch_state <= 3'd7;
                end
                
                3'd7: begin
                    bg_mem_addr <= 15'h0000 | ({7'd0, nametable_latch} << 4) | 15'd8 | {12'd0, fetch_y[2:0]};
                    fetch_state <= 3'd0; 
                end
            endcase
        end else begin
            fetch_state <= 3'd0;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_pat_lo <= 0;
            active_pat_hi <= 0;
            active_attr   <= 0;
        end else if (nes_visible) begin
            // Capture pattern_hi on the cycle AFTER state 7
            if (last_fetch_state == 3'd7) begin
                pattern_hi_latch <= bg_mem_data;
            end
            
            // Load the active tile at the exact moment nes_x starts the new tile
            if (nes_pixel_tick && nes_x[2:0] == 3'd0) begin
                active_pat_lo <= pattern_lo_latch;
                active_pat_hi <= (last_fetch_state == 3'd7) ? bg_mem_data : pattern_hi_latch;
                active_attr   <= attr_latch;
            end
        end
    end

    // Multiplex the output pixel based on nes_x
    wire [2:0] bit_sel = 3'd7 - nes_x[2:0];
    
    wire pat_bit_0 = active_pat_lo[bit_sel];
    wire pat_bit_1 = active_pat_hi[bit_sel];
    
    assign pixel_color_idx = (pat_bit_1 == 0 && pat_bit_0 == 0) ? 4'b0000 : {active_attr, pat_bit_1, pat_bit_0};

endmodule