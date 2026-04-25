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
    
    wire [3:0] bg_color_idx;
    wire [3:0] spr_color_idx;
    wire       spr_bg_priority;
    wire       spr0_active;

    wire is_rendering = nes_visible && dbg_mask[3];

    reg last_nes_visible;
    reg [7:0] last_nes_y;
    always @(posedge clk_25mhz) begin
        last_nes_visible <= nes_visible;
        last_nes_y       <= nes_y;
    end

    wire vblank_pulse       = !nes_visible && last_nes_visible && (last_nes_y == 8'd239);
    wire clear_vblank_pulse = nes_visible && !last_nes_visible && (nes_y == 8'd0);
    
    // ─────────────────────────────────────────────────────────────────────────
    // True Pixel Multiplexer & Sprite 0 Hit Detection
    // ─────────────────────────────────────────────────────────────────────────
    wire bg_opaque  = (bg_color_idx[1:0] != 2'b00);
    wire spr_opaque = (spr_color_idx[1:0] != 2'b00);
    
    reg [4:0] dac_palette_addr;
    always @(*) begin
        if (!is_rendering) begin
            dac_palette_addr = 5'h00;
        end else if (spr_opaque && (!bg_opaque || !spr_bg_priority)) begin
            dac_palette_addr = {1'b1, spr_color_idx}; // Sprite Palette Base
        end else if (bg_opaque) begin
            dac_palette_addr = {1'b0, bg_color_idx};  // BG Palette Base
        end else begin
            dac_palette_addr = 5'h00;                 // Universal Background
        end
    end
    
    wire true_sprite0_hit = nes_visible && bg_opaque && spr_opaque && spr0_active;

    ppu_bg_render bg_render (
        .clk             (clk_25mhz),
        .reset           (reset),
        .nes_x           (nes_x),
        .nes_y           (nes_y),
        .nes_visible     (is_rendering), 
        .ppu_ctrl_reg    (dbg_ctrl), 
        .bg_mem_addr     (bg_mem_addr),
        .bg_mem_data     (bg_mem_data),
        .pixel_color_idx (bg_color_idx),
        .dbg_nt_latch    (dbg_nt_latch)
    );

    wire [7:0] nes_color_code;

    ppu_core ppu_inst (
        .clk                (clk_25mhz), 
        .reset              (reset),
        .vblank_pulse       (vblank_pulse),
        .clear_vblank_pulse (clear_vblank_pulse), 
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
        .dbg_vram_addr      (dbg_vram_addr),
        .dbg_palette_00     (dbg_palette_00),
        
        // Pass rendering data back and forth
        .nes_x              (nes_x),
        .nes_y              (nes_y),
        .nes_visible        (nes_visible),
        .bg_mem_addr        (bg_mem_addr),
        .bg_mem_data        (bg_mem_data),
        .dac_palette_addr   (dac_palette_addr),
        .dac_palette_data   (nes_color_code),
        
        // Sprite subsystem connections
        .sprite_color_idx   (spr_color_idx),
        .sprite_bg_priority (spr_bg_priority),
        .sprite0_active     (spr0_active),
        .true_sprite0_hit   (true_sprite0_hit)
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

    reg vga_blank_n_d;
    reg nes_visible_d;
    always @(posedge clk_25mhz) begin
        vga_blank_n_d <= vga_blank_n;
        nes_visible_d <= nes_visible;
    end

    assign vga_r = (vga_blank_n_d && nes_visible_d) ? vga_r_10[9:2] : 8'h00;
    assign vga_g = (vga_blank_n_d && nes_visible_d) ? vga_g_10[9:2] : 8'h00;
    assign vga_b = (vga_blank_n_d && nes_visible_d) ? vga_b_10[9:2] : 8'h00;

endmodule