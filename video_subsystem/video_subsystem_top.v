module video_subsystem_top (
    input  wire        clk_25mhz,
    input  wire        reset,

    input  wire [2:0]  cpu_addr,
    input  wire [7:0]  cpu_data_in,
    output wire [7:0]  cpu_data_out,
    input  wire        cpu_read_n,
    input  wire        cpu_write_n,

    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire        vga_blank_n,
    output wire        vga_sync_n,
    output wire        vga_clk,
    
    // Telemetry
    output wire [7:0]  dbg_ctrl,
    output wire [7:0]  dbg_mask,
    output wire [14:0] dbg_vram_addr,
    output wire [7:0]  dbg_palette_00
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

    ppu_bg_render bg_render (
        .clk             (clk_25mhz),
        .reset           (reset),
        .nes_x           (nes_x),
        .nes_y           (nes_y),
        .nes_visible     (is_rendering), 
        .bg_mem_addr     (bg_mem_addr),
        .bg_mem_data     (bg_mem_data),
        .pixel_color_idx (pixel_color_idx)
    );

    wire [4:0] dac_palette_addr = (pixel_color_idx[1:0] == 2'b00) ? 5'h00 : {1'b0, pixel_color_idx};
    wire [7:0] nes_color_code;

    wire [13:0] chr_addr;
    wire        chr_read_n;
    wire [7:0]  chr_data_in = (chr_addr == 14'h0010) ? 8'h3C :
                              (chr_addr == 14'h0011) ? 8'h42 :
                              (chr_addr == 14'h0012) ? 8'hA5 :
                              (chr_addr == 14'h0013) ? 8'h81 :
                              (chr_addr == 14'h0014) ? 8'hA5 :
                              (chr_addr == 14'h0015) ? 8'h99 :
                              (chr_addr == 14'h0016) ? 8'h42 :
                              (chr_addr == 14'h0017) ? 8'h3C : 8'h00;

    ppu_core ppu_inst (
        .clk              (clk_25mhz), 
        .reset            (reset),
        .cpu_addr         (cpu_addr),
        .cpu_data_in      (cpu_data_in),
        .cpu_data_out     (cpu_data_out),
        .cpu_read_n       (cpu_read_n),
        .cpu_write_n      (cpu_write_n),
        .chr_addr         (chr_addr),
        .chr_data_in      (chr_data_in),
        .chr_read_n       (chr_read_n),
        .dbg_ctrl         (dbg_ctrl),
        .dbg_mask         (dbg_mask),
        .nes_visible      (is_rendering),
        .bg_mem_addr      (bg_mem_addr),
        .bg_mem_data      (bg_mem_data),
        .dac_palette_addr (dac_palette_addr),
        .dac_palette_data (nes_color_code),
        .dbg_vram_addr    (dbg_vram_addr),
        .dbg_palette_00   (dbg_palette_00)
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