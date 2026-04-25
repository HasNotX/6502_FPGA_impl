/*
 * File: nes_top.v
 * Description: Top-level integration module for the NES architecture.
 * Implements System Bus multiplexing for CPU and DMA OAM transfers.
 */

module nes_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire        VGA_CLK
);

    wire clk_25mhz;
    wire pll_locked;
    
    vga_pll pll_inst (
        .refclk   (CLOCK_50),
        .rst      (1'b0),          
        .outclk_0 (clk_25mhz),
        .locked   (pll_locked)
    );

    wire raw_reset_btn = ~KEY[3]; 
    wire clean_reset_btn;
    
    button_debouncer btn_db_inst (
        .clk        (clk_25mhz),
        .button_in  (raw_reset_btn),
        .button_out (clean_reset_btn)
    );

    wire sys_reset = (~pll_locked) | clean_reset_btn;

    wire cpu_ce_raw;
    wire ppu_ce;
    
    nes_clock_generator clk_gen (
        .clk_25mhz (clk_25mhz),
        .reset     (sys_reset),
        .cpu_ce    (cpu_ce_raw),
        .ppu_ce    (ppu_ce)
    );

    // =========================================================================
    // SYSTEM BUS ARBITRATOR (CPU vs DMA)
    // =========================================================================
    wire        dma_active;
    wire [15:0] dma_addr;
    wire [7:0]  dma_data_out;
    wire        dma_we;
    
    // Halt the CPU entirely while DMA owns the bus
    wire cpu_ce = cpu_ce_raw & ~dma_active;

    wire [15:0] cpu_address;
    wire [7:0]  cpu_data_out;
    wire [7:0]  cpu_data_in;
    wire        cpu_write_en;
    
    wire [15:0] sys_address  = dma_active ? dma_addr     : cpu_address;
    wire [7:0]  sys_data_out = dma_active ? dma_data_out : cpu_data_out;
    wire        sys_write_en = dma_active ? dma_we       : cpu_write_en;

    wire [15:0] cpu_pc;          
    wire [5:0]  cpu_state;       
    wire        ppu_nmi; 

    MOS_6502_CPU cpu_inst (
        .clk_25mhz     (clk_25mhz),
        .cpu_ce        (cpu_ce),
        .reset         (sys_reset), 
        .nmi_in        (ppu_nmi),
        .address       (cpu_address),
        .data_in       (cpu_data_in),
        .data_out      (cpu_data_out),
        .write_en      (cpu_write_en),
        .current_pc    (cpu_pc),     
        .current_state (cpu_state)   
    );

    // =========================================================================
    // MEMORY MAP DECODING
    // =========================================================================
    wire work_ram_cs = (sys_address < 16'h2000); 
    wire ppu_cs      = (sys_address >= 16'h2000 && sys_address <= 16'h3FFF);
    wire prg_rom_cs  = (sys_address >= 16'h8000);
    
    wire [7:0] work_ram_data_out; 
    wire [7:0] ppu_data_out;
    wire [7:0] prg_data_out;
    
    assign cpu_data_in = ppu_cs      ? ppu_data_out :
                         prg_rom_cs  ? prg_data_out :
                         work_ram_cs ? work_ram_data_out : 8'h00;

    wire work_ram_we = sys_write_en && work_ram_cs;
    work_ram cpu_ram (
        .clk  (clk_25mhz),
        .addr (sys_address[10:0]),
        .din  (sys_data_out),
        .we   (work_ram_we),
        .dout (work_ram_data_out)
    );

    prg_rom cart_prg (
        .clk  (clk_25mhz),
        .addr (sys_address[14:0]),
        .dout (prg_data_out)
    );

    wire [13:0] chr_addr;
    wire [7:0]  chr_data_out;
    wire        chr_read_n;
    
    chr_rom cart_chr (
        .clk  (clk_25mhz),
        .addr (chr_addr[12:0]),
        .dout (chr_data_out)
    );

    // =========================================================================
    // DMA CONTROLLER
    // =========================================================================
    reg cpu_we_last;
    always @(posedge clk_25mhz) begin
        if (sys_reset) cpu_we_last <= 1'b0;
        else           cpu_we_last <= cpu_write_en;
    end
    wire cpu_write_pulse = cpu_write_en && !cpu_we_last;
    wire dma_start = cpu_write_pulse && (cpu_address == 16'h4014);

    nes_dma dma_inst (
        .clk          (clk_25mhz),
        .reset        (sys_reset),
        .dma_start    (dma_start),
        .page_in      (cpu_data_out),
        .ram_data_in  (work_ram_data_out),
        .dma_active   (dma_active),
        .dma_addr     (dma_addr),
        .dma_data_out (dma_data_out),
        .dma_we       (dma_we)
    );

    // =========================================================================
    // VIDEO SUBSYSTEM
    // =========================================================================
    reg sys_we_last;
    always @(posedge clk_25mhz) begin
        if (sys_reset) sys_we_last <= 1'b0;
        else           sys_we_last <= sys_write_en;
    end
    wire sys_write_pulse = sys_write_en && !sys_we_last;
    wire ppu_write_n = ~(sys_write_pulse && ppu_cs);

    wire sys_read_active = ~sys_write_en && ppu_cs;
    reg sys_re_last;
    always @(posedge clk_25mhz) begin
        if (sys_reset) sys_re_last <= 1'b0;
        else           sys_re_last <= sys_read_active;
    end
    wire sys_read_pulse = sys_read_active && !sys_re_last;
    wire ppu_read_n  = ~sys_read_pulse;
    
    wire [7:0]  ppu_dbg_ctrl;
    wire [7:0]  ppu_dbg_mask;
    wire [14:0] dbg_vram_addr;
    wire [7:0]  dbg_palette_00;
    wire [7:0]  dbg_nt_latch;
    
    // NEW: Wires extracted for telemetry
    wire [7:0]  dbg_nes_x;
    wire [7:0]  dbg_nes_y;
    wire [7:0]  ppu_dbg_status;

    video_subsystem_top video_engine (
        .clk_25mhz      (clk_25mhz),
        .reset          (sys_reset),
        .cpu_addr       (sys_address[2:0]),
        .cpu_data_in    (sys_data_out),
        .cpu_data_out   (ppu_data_out),
        .cpu_read_n     (ppu_read_n),
        .cpu_write_n    (ppu_write_n),
        
        .chr_addr       (chr_addr),      
        .chr_data_in    (chr_data_out),  
        .chr_read_n     (chr_read_n),    
        
        .vga_r          (VGA_R),
        .vga_g          (VGA_G),
        .vga_b          (VGA_B),
        .vga_hsync      (VGA_HS),
        .vga_vsync      (VGA_VS),
        .vga_blank_n    (VGA_BLANK_N),
        .vga_sync_n     (VGA_SYNC_N),
        .vga_clk        (VGA_CLK),
        
        .dbg_ctrl       (ppu_dbg_ctrl),
        .dbg_mask       (ppu_dbg_mask),
        .dbg_vram_addr  (dbg_vram_addr),
        .dbg_palette_00 (dbg_palette_00),
        .dbg_nt_latch   (dbg_nt_latch),
        .nmi_out        (ppu_nmi),
        
        // NEW: Telemetry ports mapped
        .dbg_nes_x      (dbg_nes_x),
        .dbg_nes_y      (dbg_nes_y),
        .dbg_status     (ppu_dbg_status)
    );

    // =========================================================================
    // TELEMETRY
    // =========================================================================
    assign LEDR[9] = pll_locked;
    assign LEDR[8] = dma_active; 
    assign LEDR[7] = ppu_cs; 
    assign LEDR[6] = 1'b0;
    assign LEDR[5:0] = cpu_state; 
    
    // -------------------------------------------------------------------------
    // Hardware Telemetry Controller
    // -------------------------------------------------------------------------
    debug_top telemetry_inst (
        .sw             (SW),
        
        .cpu_pc         (cpu_pc),            
        .cpu_data       (cpu_data_in),       
        
        .ppu_vram_addr  (dbg_vram_addr),     
        .ppu_palette_00 (dbg_palette_00),    
        
        .nes_x          (dbg_nes_x),         
        .nes_y          (dbg_nes_y),         
        
        .ppu_ctrl       (ppu_dbg_ctrl),      
        .ppu_status     (ppu_dbg_status),    
        
        .hex0           (HEX0),
        .hex1           (HEX1),
        .hex2           (HEX2),
        .hex3           (HEX3),
        .hex4           (HEX4),
        .hex5           (HEX5)
    );

endmodule

// =============================================================================
// Sub-Module: Synchronous Button Debouncer
// =============================================================================
module button_debouncer (
    input  wire clk,
    input  wire button_in,
    output reg  button_out
);
    reg [19:0] counter; 
    reg sync_0;
    reg sync_1;

    always @(posedge clk) begin
        sync_0 <= button_in;
        sync_1 <= sync_0;

        if (sync_1 == button_out) begin
            counter <= 20'd0;
        end else begin
            counter <= counter + 1'b1;
            if (counter == 20'hFFFFF) begin
                button_out <= sync_1;
                counter <= 20'd0;
            end
        end
    end
endmodule