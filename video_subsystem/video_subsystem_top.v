module video_subsystem_top (
    input  wire        clk_25mhz,
    input  wire        reset,

    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_data_in,
    output wire [7:0]  cpu_data_out,
    input  wire        cpu_read_n,
    input  wire        cpu_write_n,
    
    output wire [13:0] chr_addr,
    input  wire [7:0]  chr_data_in,
    output wire        chr_read_n,

    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire        vga_blank_n,
    output wire        vga_sync_n,
    output wire        vga_clk,
    
    output wire [7:0]  dbg_ctrl,
    output wire [7:0]  dbg_mask,
    output wire [14:0] dbg_vram_addr,
    output wire [7:0]  dbg_palette_00,
    output wire [7:0]  dbg_nt_latch,
    output wire        nmi_out
);

    wire [7:0] nes_x, nes_y;
    wire nes_visible;

    nes_vga_core vga_core (
        .clk_25mhz   (clk_25mhz),
        .reset       (reset),
        .vga_hsync   (vga_hsync),
        .vga_vsync   (vga_vsync),
        .vga_blank_n (vga_blank_n),
        .nes_x       (nes_x),
        .nes_y       (nes_y),
        .nes_visible (nes_visible)
    );

    assign vga_sync_n = 1'b0;
    assign vga_clk    = clk_25mhz;

    wire [14:0] bg_mem_addr;
    wire [7:0]  bg_mem_data;
    wire [3:0]  pixel_color_idx;

    wire is_rendering = nes_visible && dbg_mask[3];

    // =========================================================================
    // MASTER PHASE TRACKER: Perfectly maps 400-pixel VGA line to 341-pixel NES
    // =========================================================================
    reg [8:0] internal_x;
    reg [8:0] internal_y;
    reg phase;
    reg last_nes_visible;
    
    always @(posedge clk_25mhz or posedge reset) begin
        if (reset) begin
            internal_x <= 0;
            internal_y <= 0;
            phase <= 0;
            last_nes_visible <= 0;
        end else begin
            last_nes_visible <= nes_visible;
            
            // Hard Sync to VGA beam entering the active window
            if (nes_visible && !last_nes_visible) begin
                internal_x <= 9'd0;
                internal_y <= nes_y; // Syncs physical VGA Y to NES Y
                phase <= 1'b1;
            end else begin
                phase <= ~phase;
                if (phase == 1'b1) begin
                    // 399 accommodates the 800 VGA clocks per line
                    if (internal_x == 399) begin
                        internal_x <= 9'd0;
                        if (internal_y == 261) internal_y <= 0;
                        else internal_y <= internal_y + 1;
                    end else begin
                        internal_x <= internal_x + 1;
                    end
                end
            end
        end
    end
    wire nes_pixel_tick = phase;

    // VBlank mapped directly to NES coordinates, not physical VGA bounds
    wire vblank_pulse       = (nes_pixel_tick && internal_y == 241 && internal_x == 1);
    wire clear_vblank_pulse = (nes_pixel_tick && internal_y == 261 && internal_x == 1);
    wire sprite0_hit_pulse  = nes_visible && (nes_y == 8'd30) && (nes_x == 8'd64);

    // Loopy Routing Nets
    wire [14:0] active_v_reg;
    wire [2:0]  fine_x_scroll;
    
    assign dbg_vram_addr = active_v_reg; 
    assign dbg_nt_latch  = 8'h00;        

    ppu_bg_render bg_render (
        .clk             (clk_25mhz),
        .reset           (reset),
        .nes_pixel_tick  (nes_pixel_tick),
        .internal_x      (internal_x),
        .internal_y      (internal_y),
        .nes_x           (nes_x),
        .nes_y           (nes_y),
        .nes_visible     (is_rendering), 
        .ppu_ctrl_reg    (dbg_ctrl),       
        .active_v_reg    (active_v_reg),  
        .fine_x_scroll   (fine_x_scroll), 
        .bg_mem_addr     (bg_mem_addr),
        .bg_mem_data     (bg_mem_data),
        .pixel_color_idx (pixel_color_idx)
    );

    wire [4:0] dac_palette_addr = (pixel_color_idx[1:0] == 2'b00) ? 5'h00 : {1'b0, pixel_color_idx};
    wire [7:0] nes_color_code;

    ppu_core ppu_inst (
        .clk                (clk_25mhz), 
        .reset              (reset),
        .nes_pixel_tick     (nes_pixel_tick),
        .internal_x         (internal_x),
        .internal_y         (internal_y),
        
        .vblank_pulse       (vblank_pulse),
        .clear_vblank_pulse (clear_vblank_pulse), 
        .sprite0_hit_pulse  (sprite0_hit_pulse),  
        .nmi_out            (nmi_out),
        
        .cpu_addr           (cpu_addr),
        .cpu_data_in        (cpu_data_in),
        .cpu_data_out       (cpu_data_out),
        .cpu_read_n         (cpu_read_n),
        .cpu_write_n        (cpu_write_n),
        
        .chr_addr           (chr_addr),
        .chr_data_in        (chr_data_in),
        .chr_read_n         (chr_read_n),
        
        .dbg_ctrl           (dbg_ctrl),
        .dbg_mask           (dbg_mask),
        .active_v_reg       (active_v_reg),
        .fine_x_scroll      (fine_x_scroll),
        
        .nes_x              (nes_x),
        .nes_visible        (is_rendering),
        .bg_mem_addr        (bg_mem_addr),
        .bg_mem_data        (bg_mem_data),
        
        .dac_palette_addr   (dac_palette_addr),
        .dac_palette_data   (nes_color_code),
        .dbg_palette_00     (dbg_palette_00)
    );

    wire [9:0] vga_r_10, vga_g_10, vga_b_10;
    nes_palette_lut palette_lut (
        .clk            (clk_25mhz),
        .reset          (reset),
        .nes_color_code (nes_color_code[5:0]),
        .vga_r          (vga_r_10),
        .vga_g          (vga_g_10),
        .vga_b          (vga_b_10)
    );

    assign vga_r = vga_blank_n ? vga_r_10[9:2] : 8'h00;
    assign vga_g = vga_blank_n ? vga_g_10[9:2] : 8'h00;
    assign vga_b = vga_blank_n ? vga_b_10[9:2] : 8'h00;

endmodule