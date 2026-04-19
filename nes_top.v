/*
 * File: nes_top.v
 * Description: Top-level integration module for the NES architecture.
 * Connects the 6502 CPU, Ricoh 2C02 PPU Registers, System RAM, and 
 * handles the System Bus arbitration and address decoding.
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
    
    // VGA Outputs (Disabled until Phase 2 Video Subsystem Integration)
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire        VGA_CLK
);

    wire reset = ~KEY[3]; // Active high reset
    
    // Turn off unused HEX displays for now
    assign HEX0 = 7'b1111111;
    assign HEX1 = 7'b1111111;
    assign HEX2 = 7'b1111111;
    assign HEX3 = 7'b1111111;
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;

    // VGA disabled for Phase 1 to prevent un-driven pin warnings
    assign VGA_R = 8'h00;
    assign VGA_G = 8'h00;
    assign VGA_B = 8'h00;
    assign VGA_HS = 1'b0;
    assign VGA_VS = 1'b0;
    assign VGA_BLANK_N = 1'b0;
    assign VGA_SYNC_N = 1'b0;
    assign VGA_CLK = 1'b0;

    // =========================================================================
    // 1. Master Clock Generation
    // =========================================================================
    wire clk_25mhz;
    wire pll_locked;
    
    vga_pll pll_inst (
        .refclk   (CLOCK_50),
        .rst      (reset),
        .outclk_0 (clk_25mhz),
        .locked   (pll_locked)
    );

    wire cpu_ce;
    wire ppu_ce;
    
    nes_clock_generator clk_gen (
        .clk_25mhz (clk_25mhz),
        .reset     (reset),
        .cpu_ce    (cpu_ce),
        .ppu_ce    (ppu_ce)
    );

    // =========================================================================
    // 2. Main System Bus & CPU Instantiation
    // =========================================================================
    wire [15:0] cpu_address;
    wire [7:0]  cpu_data_out;
    wire [7:0]  cpu_data_in;
    wire        cpu_write_en;

    MOS_6502_CPU cpu_inst (
        .clk_25mhz (clk_25mhz),
        .cpu_ce    (cpu_ce),
        .reset     (reset),
        .address   (cpu_address),
        .data_in   (cpu_data_in),
        .data_out  (cpu_data_out),
        .write_en  (cpu_write_en)
    );

    // Memory Map Decoding
    // Standard NES RAM is $0000-$07FF (mirrored).
    // For Phase 1 testing, we route the upper Cartridge ROM space ($8000+) to RAM 
    // so we can load assembly programs into the RAM file and execute them.
    wire ram_cs = (cpu_address < 16'h2000) || (cpu_address >= 16'h8000); 
    wire ppu_cs = (cpu_address >= 16'h2000 && cpu_address <= 16'h3FFF);

    // Data Multiplexer (The Router)
    wire [7:0] ram_data_out;
    wire [7:0] ppu_data_out;
    
    assign cpu_data_in = ppu_cs ? ppu_data_out : ram_data_out;

    // =========================================================================
    // 3. System RAM Integration
    // =========================================================================
    wire ram_write_en = cpu_write_en && ram_cs;

    ram system_ram (
        .clk      (clk_25mhz),
        .addr     (cpu_address),
        .data_in  (cpu_data_out),
        .write_en (ram_write_en),
        .data_out (ram_data_out)
    );

    // =========================================================================
    // 4. PPU Register Integration
    // =========================================================================
    // Edge detector: Converts the CPU's 14-cycle wide write enable into a 
    // single 25MHz pulse to safely trigger the synchronous PPU registers.
    reg cpu_we_last;
    always @(posedge clk_25mhz) begin
        if (reset) cpu_we_last <= 1'b0;
        else       cpu_we_last <= cpu_write_en;
    end
    wire cpu_write_pulse = cpu_write_en && !cpu_we_last;

    wire ppu_write_n = ~(cpu_write_pulse && ppu_cs);
    wire ppu_read_n  = ~(~cpu_write_en && ppu_cs);
    
    // PPU registers are mirrored every 8 bytes across the $2000-$3FFF space
    wire [2:0] ppu_reg_addr = cpu_address[2:0];

    // Dummy Cartridge CHR-ROM interface for Phase 1
    wire [13:0] chr_addr;
    wire [7:0]  chr_data_in = 8'h00;
    wire        chr_read_n;

    ppu_core ppu_inst (
        .clk          (clk_25mhz),
        .reset        (reset),
        .cpu_addr     (ppu_reg_addr),
        .cpu_data_in  (cpu_data_out),
        .cpu_data_out (ppu_data_out),
        .cpu_read_n   (ppu_read_n),
        .cpu_write_n  (ppu_write_n),
        .chr_addr     (chr_addr),
        .chr_data_in  (chr_data_in),
        .chr_read_n   (chr_read_n)
    );

    // =========================================================================
    // 5. Hardware Telemetry
    // =========================================================================
    assign LEDR[9] = pll_locked;
    assign LEDR[8] = cpu_write_pulse; // Will flash brightly when CPU writes
    assign LEDR[7] = ppu_cs;          // Will glow when CPU talks to PPU
    assign LEDR[6:0] = 7'b0000000;

endmodule