`timescale 1ns / 1ps

/*
 * File: tb_sprite_analyzer.v
 * Description: Deep-probe logic analyzer for the Sprite Rendering Pipeline.
 * Dumps the exact state of OAM RAM, the evaluation buffers, and the 
 * active rendering registers to pinpoint sprite fracturing.
 */

module tb_sprite_analyzer();

    reg clk_50mhz;
    reg [3:0] key;
    reg [9:0] sw;
    
    wire [9:0] ledr;
    wire [6:0] hex0, hex1, hex2, hex3, hex4, hex5;
    wire [7:0] vga_r, vga_g, vga_b;
    wire vga_hs, vga_vs, vga_blank_n, vga_sync_n, vga_clk;

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

    initial begin
        clk_50mhz = 0;
        forever #10 clk_50mhz = ~clk_50mhz; 
    end

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------
    initial begin
        key = 4'b0111; 
        sw  = 10'b0000000000;
        #500;
        key = 4'b1111; 

        $display("Booting CPU and waiting for Frame 0 DMA...");
        
        // Wait for Frame 0 to complete (CPU Boots & OAM DMA Fires)
        wait (uut.video_engine.nes_y == 8'd239);
        wait (uut.video_engine.nes_y == 8'd0); 
        
        $display("Frame 1 reached. Scanning for Mario on Scanline 200...");
        
        // Lock onto Scanline 200 (Where Mario's sprite resides)
        wait (uut.video_engine.nes_y == 8'd200);
        
        // Run long enough to capture the HBlank evaluation and the start of line 201
        #60000; 
        $display("Simulation Complete. Check sprite_telemetry.txt");
        $stop;
    end

    // -------------------------------------------------------------------------
    // Deep Hardware Probes
    // -------------------------------------------------------------------------
    wire [7:0]  probe_nes_x       = uut.video_engine.nes_x;
    wire [7:0]  probe_nes_y       = uut.video_engine.nes_y;
    wire        probe_eval_start  = uut.video_engine.ppu_inst.spr_render.eval_start;
    wire [4:0]  probe_eval_state  = uut.video_engine.ppu_inst.spr_render.eval_state;
    wire [3:0]  probe_eval_count  = uut.video_engine.ppu_inst.spr_render.eval_sprite_count;
    wire [3:0]  probe_act_count   = uut.video_engine.ppu_inst.spr_render.active_sprite_count;
    
    // Arrays
    wire [7:0]  eval_spr_x_0      = uut.video_engine.ppu_inst.spr_render.eval_spr_x[0];
    wire [7:0]  eval_spr_tile_0   = uut.video_engine.ppu_inst.spr_render.eval_spr_tile[0];
    wire [7:0]  eval_spr_pat_lo_0 = uut.video_engine.ppu_inst.spr_render.eval_spr_pat_lo[0];
    wire [7:0]  eval_spr_pat_hi_0 = uut.video_engine.ppu_inst.spr_render.eval_spr_pat_hi[0];
    
    wire [7:0]  act_spr_x_0       = uut.video_engine.ppu_inst.spr_render.active_spr_x[0];
    wire [7:0]  act_spr_pat_lo_0  = uut.video_engine.ppu_inst.spr_render.active_spr_pat_lo[0];

    // -------------------------------------------------------------------------
    // Telemetry Extraction
    // -------------------------------------------------------------------------
    integer file_out;
    initial begin
        file_out = $fopen("sprite_telemetry.txt", "w");
        $fdisplay(file_out, "X   | Y   | STATE | EVAL_CNT | ACT_CNT | EVAL_X[0] | EVAL_TILE[0] | EVAL_PAT_LO[0] | ACT_PAT_LO[0]");
    end

    always @(posedge uut.clk_25mhz) begin
        if (key[3] == 1'b1 && probe_nes_y >= 8'd200 && probe_nes_y <= 8'd201) begin
            
            // Log significant state changes or pixel boundaries
            if (probe_eval_start || probe_eval_state == 10 || probe_nes_x == 0 || probe_nes_x == 128) begin
                $fdisplay(file_out, "%3d | %3d |   %2d  |    %d     |    %d    |    %3d    |      %h      |    %b   |   %b", 
                          probe_nes_x, probe_nes_y, probe_eval_state, probe_eval_count, probe_act_count, 
                          eval_spr_x_0, eval_spr_tile_0, eval_spr_pat_lo_0, act_spr_pat_lo_0);
            end
        end
    end

endmodule