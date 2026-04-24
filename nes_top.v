/*
 * File: nes_top.v
 * Description: Top-level integration module for the NES architecture.
 * Connects the 6502 CPU, System RAM, and the Video Subsystem Wrapper.
 * Handles the System Bus arbitration and address decoding.
 */

module nes_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    
    // Debug & Status
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    
    // VGA Outputs 
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire        VGA_CLK
);

    // =========================================================================
    // 1. Master Clock Generation
    // =========================================================================
    wire clk_25mhz;
    wire pll_locked;
    
    vga_pll pll_inst (
        .refclk   (CLOCK_50),
        .rst      (1'b0),          
        .outclk_0 (clk_25mhz),
        .locked   (pll_locked)
    );

    // =========================================================================
    // 2. Global Reset Architecture
    // =========================================================================
    wire raw_reset_btn = ~KEY[3];  // Active high physical button press
    wire clean_reset_btn;
    
    button_debouncer btn_db_inst (
        .clk        (clk_25mhz),
        .button_in  (raw_reset_btn),
        .button_out (clean_reset_btn)
    );

    wire sys_reset = (~pll_locked) | clean_reset_btn;

    // =========================================================================
    // 3. System Clocks & Timing
    // =========================================================================
    wire cpu_ce;
    wire ppu_ce;
    
    nes_clock_generator clk_gen (
        .clk_25mhz (clk_25mhz),
        .reset     (sys_reset),
        .cpu_ce    (cpu_ce),
        .ppu_ce    (ppu_ce)
    );

    // =========================================================================
    // 4. Main System Bus & CPU Instantiation
    // =========================================================================
    wire [15:0] cpu_address;
    wire [7:0]  cpu_data_out;
    wire [7:0]  cpu_data_in;
    wire        cpu_write_en;
    wire [15:0] cpu_pc;          
    wire [5:0]  cpu_state;       

    MOS_6502_CPU cpu_inst (
        .clk_25mhz     (clk_25mhz),
        .cpu_ce        (cpu_ce),
        .reset         (sys_reset), 
        .address       (cpu_address),
        .data_in       (cpu_data_in),
        .data_out      (cpu_data_out),
        .write_en      (cpu_write_en),
        .current_pc    (cpu_pc),     
        .current_state (cpu_state)   
    );

    // =========================================================================
    // 5. Memory Map Decoding & Multiplexing
    // =========================================================================
    wire [7:0] ram_data_out; 
    wire [7:0] ppu_data_out;
    
    wire ram_cs = (cpu_address < 16'h2000) || (cpu_address >= 16'h8000); 
    wire ppu_cs = (cpu_address >= 16'h2000 && cpu_address <= 16'h3FFF);
    
    assign cpu_data_in = ppu_cs ? ppu_data_out : ram_data_out;
    
    wire ram_write_en = cpu_write_en && ram_cs;

    ram system_ram (
        .clk      (clk_25mhz),
        .addr     (cpu_address),
        .data_in  (cpu_data_out),
        .write_en (ram_write_en),
        .data_out (ram_data_out)
    );

    // =========================================================================
    // 6. Video Subsystem Integration
    // =========================================================================
    reg cpu_we_last;
    always @(posedge clk_25mhz) begin
        if (sys_reset) cpu_we_last <= 1'b0;
        else           cpu_we_last <= cpu_write_en;
    end
    wire cpu_write_pulse = cpu_write_en && !cpu_we_last;

    wire ppu_write_n = ~(cpu_write_pulse && ppu_cs);
    wire ppu_read_n  = ~(~cpu_write_en && ppu_cs);
    
    wire [7:0]  ppu_dbg_ctrl;
    wire [7:0]  ppu_dbg_mask;
    wire [14:0] dbg_vram_addr;  // NEW
    wire [7:0]  dbg_palette_00; // NEW

    video_subsystem_top video_engine (
        .clk_25mhz    (clk_25mhz),
        .reset        (sys_reset),
        .cpu_addr     (cpu_address[2:0]),
        .cpu_data_in  (cpu_data_out),
        .cpu_data_out (ppu_data_out),
        .cpu_read_n   (ppu_read_n),
        .cpu_write_n  (ppu_write_n),
        
        .vga_r        (VGA_R),
        .vga_g        (VGA_G),
        .vga_b        (VGA_B),
        .vga_hsync    (VGA_HS),
        .vga_vsync    (VGA_VS),
        .vga_blank_n  (VGA_BLANK_N),
        .vga_sync_n   (VGA_SYNC_N),
        .vga_clk      (VGA_CLK),
        
        .dbg_ctrl       (ppu_dbg_ctrl),
        .dbg_mask       (ppu_dbg_mask),
        .dbg_vram_addr  (dbg_vram_addr),
        .dbg_palette_00 (dbg_palette_00)
    );

    // =========================================================================
    // 7. Hardware Telemetry & Debug Displays
    // =========================================================================
    assign LEDR[9] = pll_locked;
    assign LEDR[8] = cpu_write_pulse; 
    assign LEDR[7] = ppu_cs; 
    assign LEDR[6] = 1'b0;
    assign LEDR[5:0] = cpu_state; 
    
    // SW[9] = 0: Show CPU Program Counter
    // SW[9] = 1: Show PPU Palette[0] Data and VRAM Address
    wire [15:0] hex_display_data = SW[9] ? {1'b0, dbg_vram_addr} : cpu_pc;
    wire [7:0]  hex_display_high = SW[9] ? dbg_palette_00 : 8'h00;

    hex_decoder hex5_inst (.hex_in(hex_display_high[7:4]), .segments(HEX5));
    hex_decoder hex4_inst (.hex_in(hex_display_high[3:0]), .segments(HEX4));
    hex_decoder hex3_inst (.hex_in(hex_display_data[15:12]), .segments(HEX3));
    hex_decoder hex2_inst (.hex_in(hex_display_data[11:8]),  .segments(HEX2));
    hex_decoder hex1_inst (.hex_in(hex_display_data[7:4]),   .segments(HEX1));
    hex_decoder hex0_inst (.hex_in(hex_display_data[3:0]),   .segments(HEX0));

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