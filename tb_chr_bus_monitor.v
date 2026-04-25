`timescale 1ns / 1ps

/*
 * File: tb_chr_bus_monitor.v
 * Description: Industrial-grade top-level testbench for CHR-ROM bus arbitration.
 * Executes the actual game ROM to configure the PPU, and deep-probes
 * the internal memory arbiter to expose bus collisions between the Background
 * Primer and the Sprite Engine during HBlank.
 */

module tb_chr_bus_monitor();

    reg clk_50mhz;
    reg [3:0] key;
    reg [9:0] sw;
    
    // Output nets
    wire [9:0] ledr;
    wire [6:0] hex0, hex1, hex2, hex3, hex4, hex5;
    wire [7:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs, vga_blank_n, vga_sync_n, vga_clk;

    // Instantiate the top-level NES hardware
    nes_top uut (
        .CLOCK_50   (clk_50mhz),
        .KEY        (key),
        .SW         (sw),
        .LEDR       (ledr),
        .HEX0       (hex0),
        .HEX1       (hex1),
        .HEX2       (hex2),
        .HEX3       (hex3),
        .HEX4       (hex4),
        .HEX5       (hex5),
        .VGA_R      (vga_r),
        .VGA_G      (vga_g),
        .VGA_B      (vga_b),
        .VGA_HS     (vga_hs),
        .VGA_VS     (vga_vs),
        .VGA_BLANK_N(vga_blank_n),
        .VGA_SYNC_N (vga_sync_n),
        .VGA_CLK    (vga_clk)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk_50mhz = 0;
        forever #10 clk_50mhz = ~clk_50mhz; // 50 MHz
    end

    // -------------------------------------------------------------------------
    // Stimulus & Lifecycle
    // -------------------------------------------------------------------------
    initial begin
        // Trigger Reset (KEY[3] is active-low)
        key = 4'b0111; 
        sw  = 10'b0000000000;
        #500;
        key = 4'b1111; 

        // Wait for VGA to complete one full frame to ensure OAM DMA is complete 
        // and the game engine has written to the PPU control registers.
        $display("Waiting for Frame 1 to complete (Allowing CPU to boot and DMA)...");
        wait (uut.video_engine.nes_y == 8'd240);
        wait (uut.video_engine.nes_y == 8'd0); 
        
        // Log active rendering and HBlank on a mid-screen scanline (e.g., Scanline 120)
        $display("Monitoring Bus Arbitration on Scanline 120...");
        wait (uut.video_engine.nes_y == 8'd120);
        
        // Run long enough to capture the end of line 120, HBlank, and start of 121
        #100000; 
        $display("Simulation Complete. Check chr_bus_telemetry.txt");
        $stop;
    end

    // -------------------------------------------------------------------------
    // Deep Hardware Probes
    // -------------------------------------------------------------------------
    // Using hierarchical paths to bypass module boundaries and monitor the internal state
    wire [7:0]  probe_nes_x      = uut.video_engine.nes_x;
    wire [7:0]  probe_nes_y      = uut.video_engine.nes_y;
    wire        probe_visible    = uut.video_engine.nes_visible;
    wire [14:0] probe_bg_addr    = uut.video_engine.bg_mem_addr;
    wire [13:0] probe_chr_addr   = uut.video_engine.chr_addr;
    wire [7:0]  probe_ppu_ctrl   = uut.video_engine.dbg_ctrl;
    
    // Probe the sprite fetch flag driving the arbiter
    wire        probe_is_fetch   = uut.video_engine.ppu_inst.is_fetching; 

    // -------------------------------------------------------------------------
    // Telemetry Extraction
    // -------------------------------------------------------------------------
    integer file_out;
    initial begin
        file_out = $fopen("chr_bus_telemetry.txt", "w");
        $fdisplay(file_out, "NES_Y | NES_X | VISIBLE | PPU_CTRL | SPR_FETCH_FLAG | BG_ADDR_REQ | FINAL_CHR_BUS");
    end

    // Log strictly at the 25MHz pixel clock rate
    always @(posedge uut.clk_25mhz) begin
        // Only log during the target scanline window
        if (key[3] == 1'b1 && probe_nes_y >= 8'd120 && probe_nes_y <= 8'd121) begin
            $fdisplay(file_out, "%5d | %5d | %7b | %8b | %14b | %11h | %13h", 
                      probe_nes_y, probe_nes_x, probe_visible, probe_ppu_ctrl, probe_is_fetch, probe_bg_addr, probe_chr_addr);
        end
    end

endmodule