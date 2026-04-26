/*
 * File: ping_pong_line_buffer_tb.v
 * Description: Verification testbench for the Ping-Pong buffer.
 * Simulates PPU writes and VGA reads to verify buffer swapping integrity.
 */

`timescale 1ns/1ps

module ping_pong_line_buffer_tb;

    reg clk;
    reg ppu_ce;
    reg [8:0] ppu_x;
    reg [8:0] ppu_y;
    reg ppu_visible;
    reg [3:0] ppu_color_idx;
    
    reg [7:0] vga_nes_x;
    wire [3:0] vga_color_idx;

    ping_pong_line_buffer uut (
        .clk(clk),
        .ppu_ce(ppu_ce),
        .ppu_x(ppu_x),
        .ppu_y(ppu_y),
        .ppu_visible(ppu_visible),
        .ppu_color_idx(ppu_color_idx),
        .vga_nes_x(vga_nes_x),
        .vga_color_idx(vga_color_idx)
    );

    // 25.175 MHz Clock
    always #19.86 clk = ~clk;

    initial begin
        $dumpfile("ping_pong.vcd");
        $dumpvars(0, ping_pong_line_buffer_tb);

        clk = 0;
        ppu_ce = 0;
        ppu_x = 0;
        ppu_y = 0;
        ppu_visible = 0;
        ppu_color_idx = 0;
        vga_nes_x = 0;

        #100;
        @(posedge clk);
        
        $display("Simulating PPU Line 0 Write (Buffer A)...");
        ppu_visible <= 1;
        ppu_y <= 9'd0; // write_to_a = 1
        
        // Write to pixel 10
        ppu_x <= 9'd10;
        ppu_color_idx <= 4'hA;
        ppu_ce <= 1;
        @(posedge clk);
        ppu_ce <= 0;
        @(posedge clk);
        
        $display("Simulating PPU Line 1 Transition (Swap to Buffer B)...");
        ppu_y <= 9'd1; // write_to_a = 0
        
        // VGA attempts to read pixel 10 (Should pull from Buffer A now)
        vga_nes_x <= 8'd10;
        @(posedge clk); // Allow address to register
        @(posedge clk); // Allow data to output
        
        if (vga_color_idx == 4'hA) begin
            $display("[PASS] VGA successfully read data from isolated buffer.");
        end else begin
            $display("[FAIL] Data mismatch. Expected A, got %h", vga_color_idx);
        end

        #500;
        $display("Simulation Complete.");
        $finish;
    end

endmodule