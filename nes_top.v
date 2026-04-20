/*
 * File: nes_top.v
 * Description: Top-level integration module for the NES architecture.
 * Connects the 6502 CPU, Ricoh 2C02 PPU Registers, System RAM, and 
 * handles the System Bus arbitration and address decoding.
 * Includes a robust, debounced global reset architecture.
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
        .rst      (1'b0),          // THE FIX: The PLL is never reset by the user
        .outclk_0 (clk_25mhz),
        .locked   (pll_locked)
    );

    // =========================================================================
    // 2. Global Reset Architecture
    // =========================================================================
    wire raw_reset_btn = ~KEY[3];  // Active high physical button press
    wire clean_reset_btn;
    
    // Debounce the physical button against the 25MHz clock
    button_debouncer btn_db_inst (
        .clk        (clk_25mhz),
        .button_in  (raw_reset_btn),
        .button_out (clean_reset_btn)
    );

    // Unified System Reset:
    // The system is held in reset IF the PLL is currently unstable OR the user 
    // is holding the physical reset button.
    wire sys_reset = (~pll_locked) | clean_reset_btn;

    // =========================================================================
    // 3. System Clocks & Timing
    // =========================================================================
    wire cpu_ce;
    wire ppu_ce;
    
    nes_clock_generator clk_gen (
        .clk_25mhz (clk_25mhz),
        .reset     (sys_reset),    // Uses unified reset
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
    wire [15:0] cpu_pc;          // NEW
    wire [5:0]  cpu_state;       // NEW

    MOS_6502_CPU cpu_inst (
        .clk_25mhz     (clk_25mhz),
        .cpu_ce        (cpu_ce),
        .reset         (sys_reset), 
        .address       (cpu_address),
        .data_in       (cpu_data_in),
        .data_out      (cpu_data_out),
        .write_en      (cpu_write_en),
        .current_pc    (cpu_pc),     // NEW
        .current_state (cpu_state)   // NEW
    );

    // KLAUS TEST OVERRIDE: Give the CPU 100% pure RAM access.
    // Comment out the PPU multiplexer.
    /* wire ram_cs = (cpu_address < 16'h2000) || (cpu_address >= 16'h8000); 
    wire ppu_cs = (cpu_address >= 16'h2000 && cpu_address <= 16'h3FFF);
    assign cpu_data_in = ppu_cs ? ppu_data_out : ram_data_out;
    wire ram_write_en = cpu_write_en && ram_cs;
    */
    
    // Direct RAM wiring for Klaus Test:
    wire ppu_cs = 1'b0;
    assign cpu_data_in = ram_data_out; 
    wire ram_write_en = cpu_write_en;

    ram #(
        .INIT_FILE("klaus_dormann.hex")
    ) system_ram (
        .clk      (clk_25mhz),
        .addr     (cpu_address),
        .data_in  (cpu_data_out),
        .write_en (ram_write_en),
        .data_out (ram_data_out)
    );

    // =========================================================================
    // 6. PPU Register Integration
    // =========================================================================
    reg cpu_we_last;
    always @(posedge clk_25mhz) begin
        if (sys_reset) cpu_we_last <= 1'b0;
        else           cpu_we_last <= cpu_write_en;
    end
    wire cpu_write_pulse = cpu_write_en && !cpu_we_last;

    wire ppu_write_n = ~(cpu_write_pulse && ppu_cs);
    wire ppu_read_n  = ~(~cpu_write_en && ppu_cs);
    
    wire [2:0] ppu_reg_addr = cpu_address[2:0];

    wire [13:0] chr_addr;
    wire [7:0]  chr_data_in = 8'h00;
    wire        chr_read_n;
    
    wire [7:0]  ppu_dbg_ctrl;
    wire [7:0]  ppu_dbg_mask;

    ppu_core ppu_inst (
        .clk          (clk_25mhz),
        .reset        (sys_reset), // Uses unified reset
        .cpu_addr     (ppu_reg_addr),
        .cpu_data_in  (cpu_data_out),
        .cpu_data_out (ppu_data_out),
        .cpu_read_n   (ppu_read_n),
        .cpu_write_n  (ppu_write_n),
        .chr_addr     (chr_addr),
        .chr_data_in  (chr_data_in),
        .chr_read_n   (chr_read_n),
        .dbg_ctrl     (ppu_dbg_ctrl),
        .dbg_mask     (ppu_dbg_mask)
    );

    // =========================================================================
    // 7. Hardware Telemetry & Debug Displays
    // =========================================================================
    assign LEDR[9] = pll_locked;
    assign LEDR[8] = cpu_write_pulse; 
    assign LEDR[7] = 1'b0; // PPU Disabled
    assign LEDR[6] = 1'b0;
    assign LEDR[5:0] = cpu_state; // FSM State on the bottom 6 LEDs
    
    assign HEX5 = 7'b1111111; // Off
    assign HEX4 = 7'b1111111; // Off

    // Display the 16-bit Program Counter!
    hex_decoder hex3_inst (.hex_in(cpu_pc[15:12]), .segments(HEX3));
    hex_decoder hex2_inst (.hex_in(cpu_pc[11:8]),  .segments(HEX2));
    hex_decoder hex1_inst (.hex_in(cpu_pc[7:4]),   .segments(HEX1));
    hex_decoder hex0_inst (.hex_in(cpu_pc[3:0]),   .segments(HEX0));

endmodule


// =============================================================================
// Sub-Module: Synchronous Button Debouncer
// =============================================================================
module button_debouncer (
    input  wire clk,
    input  wire button_in,
    output reg  button_out
);
    // 20-bit counter at 25MHz = ~41 milliseconds of required stability
    reg [19:0] counter; 
    
    // Dual flip-flop synchronizer to prevent metastability from the physical world
    reg sync_0;
    reg sync_1;

    always @(posedge clk) begin
        // Shift data into the synchronizer
        sync_0 <= button_in;
        sync_1 <= sync_0;

        if (sync_1 == button_out) begin
            // The button state matches our output, nothing to do
            counter <= 20'd0;
        end else begin
            // The button state has changed, start verifying it
            counter <= counter + 1'b1;
            
            if (counter == 20'hFFFFF) begin
                // The new state has been completely stable for 41ms. 
                // It is a legitimate press/release, not a mechanical bounce.
                button_out <= sync_1;
                counter <= 20'd0;
            end
        end
    end
endmodule