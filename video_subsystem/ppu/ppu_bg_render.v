/*
 * File: ppu_bg_render.v
 * Description: Cycle-accurate phase-shifted background rendering engine.
 * Implements a staggered 8-tick pipeline native to the NTSC PPU timing.
 */

module ppu_bg_render (
    input  wire        clk,
    input  wire        reset,
    input  wire        ppu_ce,
    
    input  wire [8:0]  ppu_x,
    input  wire [8:0]  ppu_y,
    input  wire        ppu_visible,
    input  wire [7:0]  ppu_ctrl_reg,
    input  wire [7:0]  ppu_mask_reg,
    
    input  wire [14:0] active_v_reg, 
    input  wire [2:0]  fine_x_scroll, 

    output reg  [14:0] bg_mem_addr,
    input  wire [7:0]  bg_mem_data,
    
    output wire [3:0]  pixel_color_idx,
    output wire [7:0]  dbg_nt_latch    
);

    wire is_primer_window = (ppu_x >= 9'd320 && ppu_x <= 9'd336);
    wire pipeline_active  = ppu_visible || is_primer_window;

    // -------------------------------------------------------------------------
    // Staggered 8-Tick Pipeline (Absorbs 2-cycle BRAM latency)
    // -------------------------------------------------------------------------
    wire [14:0] base_pat_addr = {2'b00, ppu_ctrl_reg[4], 12'd0};
    reg [7:0] nametable_latch;
    reg [1:0] attr_latch; 
    reg [7:0] pattern_lo_latch;
    reg [7:0] pattern_hi_latch;
    
    assign dbg_nt_latch = nametable_latch;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bg_mem_addr <= 15'd0;
        end else if (ppu_ce && pipeline_active) begin
            case (ppu_x[2:0])
                // Tick 0: Request Nametable byte
                3'd0: bg_mem_addr <= 15'h2000 | (active_v_reg & 15'h0FFF); 
                
                // Tick 1: Wait for BRAM
                3'd1: ;
                
                // Tick 2: Latch Nametable, Request Attribute byte
                3'd2: begin 
                    nametable_latch <= bg_mem_data;
                    bg_mem_addr <= 15'h23C0 | (active_v_reg & 15'h0C00) | ({9'd0, active_v_reg[9:7]} << 3) | {12'd0, active_v_reg[4:2]};
                end
                
                // Tick 3: Wait for BRAM
                3'd3: ;
                
                // Tick 4: Latch Attribute, Request Pattern Lo byte
                3'd4: begin 
                    case ({active_v_reg[6], active_v_reg[1]})
                        2'b00: attr_latch <= bg_mem_data[1:0];
                        2'b01: attr_latch <= bg_mem_data[3:2];
                        2'b10: attr_latch <= bg_mem_data[5:4];
                        2'b11: attr_latch <= bg_mem_data[7:6];
                    endcase
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | {12'd0, active_v_reg[14:12]};
                end
                
                // Tick 5: Wait for BRAM
                3'd5: ;
                
                // Tick 6: Latch Pattern Lo, Request Pattern Hi byte
                3'd6: begin 
                    pattern_lo_latch <= bg_mem_data;
                    bg_mem_addr <= base_pat_addr | ({7'd0, nametable_latch} << 4) | 15'd8 | {12'd0, active_v_reg[14:12]};
                end
                
                // Tick 7: Wait for BRAM
                3'd7: ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 16-Bit Shift Registers
    // -------------------------------------------------------------------------
    reg [15:0] shift_pat_lo;
    reg [15:0] shift_pat_hi;
    reg [15:0] shift_attr_lo;
    reg [15:0] shift_attr_hi;

    wire do_shift = (ppu_ce && pipeline_active && ppu_x != 9'd0);
    wire load_now = (do_shift && ppu_x[2:0] == 3'd0);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            shift_pat_lo  <= 16'd0;
            shift_pat_hi  <= 16'd0;
            shift_attr_lo <= 16'd0;
            shift_attr_hi <= 16'd0;
            pattern_hi_latch <= 8'd0;
        end else if (do_shift) begin
            if (load_now) begin
                pattern_hi_latch <= bg_mem_data;
                shift_pat_lo  <= {shift_pat_lo[14:7], pattern_lo_latch};
                shift_pat_hi  <= {shift_pat_hi[14:7], bg_mem_data};
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

    wire [3:0] bit_sel = 4'd15 - fine_x_scroll;
    wire pat_bit_0  = shift_pat_lo[bit_sel];
    wire pat_bit_1  = shift_pat_hi[bit_sel];
    wire attr_bit_0 = shift_attr_lo[bit_sel];
    wire attr_bit_1 = shift_attr_hi[bit_sel];

    // NEW: Check if PPUMASK[1] requires us to blank the leftmost 8 pixels
    wire clip_bg = (~ppu_mask_reg[1]) && (ppu_x < 9'd8);

    // Update the assignment to force 4'b0000 (Universal Background Color) if clipped
    assign pixel_color_idx = (clip_bg || (pat_bit_1 == 0 && pat_bit_0 == 0)) ?
                             4'b0000 : {attr_bit_1, attr_bit_0, pat_bit_1, pat_bit_0};
endmodule