`timescale 1ns / 1ps

/*
 * File: tb_ppu_vga_sync.v
 * Description: Cycle-accurate testbench to diagnose VGA to PPU synchronization.
 * Probes the internal HBlank counting, scanline increments, and shift register
 * priming logic to expose coordinate shifting and vertical wrapping.
 */

module tb_ppu_vga_sync();

    reg clk_25mhz;
    reg reset;

    // -------------------------------------------------------------------------
    // DUT Interconnect Wires
    // -------------------------------------------------------------------------
    wire vga_hsync, vga_vsync, vga_blank_n;
    wire [7:0] nes_x;
    wire [7:0] nes_y;
    wire nes_visible;

    reg  [7:0] ppu_ctrl_reg;
    reg  [7:0] loopy_scroll_x;
    reg  [7:0] loopy_scroll_y;
    reg        loopy_nt_x;
    reg        loopy_nt_y;
    
    wire [14:0] bg_mem_addr;
    reg  [7:0]  bg_mem_data;
    wire [3:0]  pixel_color_idx;
    wire [7:0]  dbg_nt_latch;

    // -------------------------------------------------------------------------
    // Subsystem Instantiations
    // -------------------------------------------------------------------------
    nes_vga_core uut_vga (
        .clk_25mhz   (clk_25mhz),
        .reset       (reset),
        .vga_hsync   (vga_hsync),
        .vga_vsync   (vga_vsync),
        .vga_blank_n (vga_blank_n),
        .nes_x       (nes_x),
        .nes_y       (nes_y),
        .nes_visible (nes_visible)
    );

    ppu_bg_render uut_bg (
        .clk             (clk_25mhz),
        .reset           (reset),
        .nes_x           (nes_x),
        .nes_y           (nes_y),
        .nes_visible     (nes_visible),
        .ppu_ctrl_reg    (ppu_ctrl_reg),
        .loopy_scroll_x  (loopy_scroll_x),
        .loopy_scroll_y  (loopy_scroll_y),
        .loopy_nt_x      (loopy_nt_x),
        .loopy_nt_y      (loopy_nt_y),
        .bg_mem_addr     (bg_mem_addr),
        .bg_mem_data     (bg_mem_data),
        .pixel_color_idx (pixel_color_idx),
        .dbg_nt_latch    (dbg_nt_latch)
    );

    // -------------------------------------------------------------------------
    // Clock Generation & Stimulus
    // -------------------------------------------------------------------------
    initial begin
        clk_25mhz = 0;
        // ~25.175 MHz pixel clock -> ~39.72 ns period
        forever #19.86 clk_25mhz = ~clk_25mhz;
    end

    initial begin
        reset = 1;
        ppu_ctrl_reg   = 8'h00;
        loopy_scroll_x = 8'd0;
        loopy_scroll_y = 8'd0;
        loopy_nt_x     = 1'b0;
        loopy_nt_y     = 1'b0;
        bg_mem_data    = 8'hAA; // Dummy alternating pattern to track shifts
        
        #200 reset = 0;

        // Run the simulation until the 4th NES scanline begins
        wait (nes_y == 8'd4);
        #10000;
        $display("Simulation Complete. Check simulation_telemetry.txt");
        $stop;
    end

    // -------------------------------------------------------------------------
    // Deep Hardware Probes & Telemetry Extraction
    // -------------------------------------------------------------------------
    wire [8:0]  probe_internal_x = uut_bg.internal_x;
    wire [8:0]  probe_active_y   = uut_bg.active_y;
    wire [3:0]  probe_state      = uut_bg.fetch_state;
    wire [15:0] probe_shift_lo   = uut_bg.shift_pat_lo;
    
    integer file_out;
    initial begin
        file_out = $fopen("simulation_telemetry.txt", "w");
        $fdisplay(file_out, "TIME | VIS | NES_X | NES_Y | INT_X | ACT_Y | STATE | ADDR | SHIFT_LO");
    end

    always @(posedge clk_25mhz) begin
        if (!reset && uut_bg.nes_pixel_tick) begin
            
            // 1. Detect Vertical Double-Counting (End of physical scanlines)
            if (probe_internal_x == 9'd255) begin
                $display("[SCANLINE END] Physical Line Done. NES_Y: %d | ACTIVE_Y stepping to: %d", nes_y, probe_active_y + 1);
            end

            // 2. Track Horizontal Right-Shift & Pipeline Priming
            if (nes_visible && nes_x < 8) begin
                $fdisplay(file_out, "ACTIVE PIXEL %0d: nes_y=%d, active_y=%d, shift_lo=%b, color_out=%b", 
                          nes_x, nes_y, probe_active_y, probe_shift_lo, pixel_color_idx);
            end
            
            // 3. Track HBlank Primer Fetching
            if (!nes_visible && probe_internal_x >= 315 && probe_internal_x <= 345) begin
                $fdisplay(file_out, "HBLANK FETCH: int_x=%d, state=%d, addr=%h, shift_lo=%b", 
                          probe_internal_x, probe_state, bg_mem_addr, probe_shift_lo);
            end
        end
    end

endmodule