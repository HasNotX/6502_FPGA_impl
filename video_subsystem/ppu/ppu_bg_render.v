module ppu_bg_render (
    input  wire        clk,
    input  wire        reset,
    
    input  wire [7:0]  nes_x,
    input  wire [7:0]  nes_y,
    input  wire        nes_visible,
    input  wire [7:0]  ppu_ctrl_reg,
    
    input  wire [14:0] active_v_reg, 
    input  wire [2:0]  fine_x_scroll, 

    output reg  [14:0] bg_mem_addr,
    input  wire [7:0]  bg_mem_data,
    
    output wire [3:0]  pixel_color_idx   
);

    reg [7:0] last_nes_x;
    always @(posedge clk) last_nes_x <= nes_x;
    wire nes_pixel_tick = (nes_x != last_nes_x) && nes_visible;

    reg [3:0] fetch_state;
    reg [7:0] nametable_latch;
    reg [1:0] attr_latch; 
    reg [7:0] pattern_lo_latch;
    reg [7:0] pattern_hi_latch;

    wire [14:0] base_pat_addr = {2'b00, ppu_ctrl_reg[4], 12'd0};

    // FSM runs EXACTLY as it did in your original code
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            fetch_state <= 4'd0;
            bg_mem_addr <= 15'd0;
        end else if (nes_visible) begin
            if (nes_pixel_tick && nes_x[2:0] == 3'd0) begin
                fetch_state <= 4'd1;
            end

            case (fetch_state)
                4'd0: ;
                4'd1: begin
                    bg_mem_addr <= 15'h2000 | (active_v_reg & 15'h0FFF); 
                    fetch_state <= 4'd2;
                end
                4'd2: fetch_state <= 4'd3;
                4'd3: begin
                    nametable_latch <= bg_mem_data;
                    bg_mem_addr <= 15'h23C0 | (active_v_reg & 15'h0C00) | ({9'd0, active_v_reg[9:7]} << 3) | {12'd0, active_v_reg[4:2]};
                    fetch_state <= 4'd4;
                end
                4'd4: fetch_state <= 4'd5;
                4'd5: begin
                    case ({active_v_reg[6], active_v_reg[1]})
                        2'b00: attr_latch <= bg_mem_data[1:0];
                        2'b01: attr_latch <= bg_mem_data[3:2];
                        2'b10: attr_latch <= bg_mem_data[5:4];
                        2'b11: attr_latch <= bg_mem_data[7:6];
                    endcase
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | {12'd0, active_v_reg[14:12]};
                    fetch_state <= 4'd6;
                end
                4'd6: fetch_state <= 4'd7;
                4'd7: begin
                    pattern_lo_latch <= bg_mem_data;
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | 15'd8 | {12'd0, active_v_reg[14:12]};
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

    // 16-Bit Multiplexer (Allows smooth scrolling without HBlank fetches)
    reg [15:0] active_pat_lo;
    reg [15:0] active_pat_hi;
    reg [1:0]  active_attr_0;
    reg [1:0]  active_attr_1;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            active_pat_lo <= 16'd0;
            active_pat_hi <= 16'd0;
            active_attr_0 <= 2'd0;
            active_attr_1 <= 2'd0;
        end else if (nes_visible) begin
            if (nes_pixel_tick && nes_x[2:0] == 3'd0) begin
                active_pat_lo <= {active_pat_lo[7:0], pattern_lo_latch};
                active_pat_hi <= {active_pat_hi[7:0], pattern_hi_latch};
                active_attr_0 <= {active_attr_0[0], attr_latch[0]};
                active_attr_1 <= {active_attr_1[0], attr_latch[1]};
            end
        end
    end

    // Selects pixel dynamically across the 16-bit register
    wire [3:0] mux_sel = nes_x[2:0] + fine_x_scroll;
    wire [3:0] bit_idx = 4'd15 - mux_sel;

    wire pat_bit_0  = active_pat_lo[bit_idx];
    wire pat_bit_1  = active_pat_hi[bit_idx];
    wire attr_bit_0 = (bit_idx >= 8) ? active_attr_0[1] : active_attr_0[0];
    wire attr_bit_1 = (bit_idx >= 8) ? active_attr_1[1] : active_attr_1[0];
    
    assign pixel_color_idx = (pat_bit_1 == 0 && pat_bit_0 == 0) ?
                             4'b0000 : {attr_bit_1, attr_bit_0, pat_bit_1, pat_bit_0};

endmodule