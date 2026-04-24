// =============================================================================
// ram_fpga.v  —  Quartus / Intel FPGA BRAM wrapper
//
// This module infers a true single-port M10K (Cyclone) or MLAB BRAM block.
// Contains hardcoded initialization to configure the PPU and draw a graphic.
// =============================================================================

`timescale 1ns/1ps

module ram (
    input            clk,
    input  [15:0]    addr,
    input  [7:0]     data_in,
    input            write_en,
    output reg [7:0] data_out
);

    reg [7:0] mem [0:65535];

    initial begin
        // Reset Vectors
        mem[16'hFFFC] = 8'h00; mem[16'hFFFD] = 8'h80;

        // $8000: Turn off screen (PPUCTRL, PPUMASK = $00)
        mem[16'h8000] = 8'hA9; mem[16'h8001] = 8'h00;                        // LDA #$00
        mem[16'h8002] = 8'h8D; mem[16'h8003] = 8'h00; mem[16'h8004] = 8'h20; // STA $2000
        mem[16'h8005] = 8'h8D; mem[16'h8006] = 8'h01; mem[16'h8007] = 8'h20; // STA $2001

        // $8008: Load Palette Address $3F00
        mem[16'h8008] = 8'hA9; mem[16'h8009] = 8'h3F;                        // LDA #$3F
        mem[16'h800A] = 8'h8D; mem[16'h800B] = 8'h06; mem[16'h800C] = 8'h20; // STA $2006
        mem[16'h800D] = 8'hA9; mem[16'h800E] = 8'h00;                        // LDA #$00
        mem[16'h800F] = 8'h8D; mem[16'h8010] = 8'h06; mem[16'h8011] = 8'h20; // STA $2006

        // $8012: Write Palette ($0F Black bg, $15 Pink tile)
        mem[16'h8012] = 8'hA9; mem[16'h8013] = 8'h0F;                        // LDA #$0F
        mem[16'h8014] = 8'h8D; mem[16'h8015] = 8'h07; mem[16'h8016] = 8'h20; // STA $2007
        mem[16'h8017] = 8'hA9; mem[16'h8018] = 8'h15;                        // LDA #$15
        mem[16'h8019] = 8'h8D; mem[16'h801A] = 8'h07; mem[16'h801B] = 8'h20; // STA $2007

        // $801C: Write Nametable Tile 1 at Center $21F0 (Row 15, Col 16)
        mem[16'h801C] = 8'hA9; mem[16'h801D] = 8'h21;                        // LDA #$21
        mem[16'h801E] = 8'h8D; mem[16'h801F] = 8'h06; mem[16'h8020] = 8'h20; // STA $2006
        mem[16'h8021] = 8'hA9; mem[16'h8022] = 8'hF0;                        // LDA #$F0
        mem[16'h8023] = 8'h8D; mem[16'h8024] = 8'h06; mem[16'h8025] = 8'h20; // STA $2006
        mem[16'h8026] = 8'hA9; mem[16'h8027] = 8'h01;                        // LDA #$01 (Tile ID 1)
        mem[16'h8028] = 8'h8D; mem[16'h8029] = 8'h07; mem[16'h802A] = 8'h20; // STA $2007

        // $802B: Set Scroll to 0,0
        mem[16'h802B] = 8'hA9; mem[16'h802C] = 8'h00;                        // LDA #$00
        mem[16'h802D] = 8'h8D; mem[16'h802E] = 8'h05; mem[16'h802F] = 8'h20; // STA $2005
        mem[16'h8030] = 8'h8D; mem[16'h8031] = 8'h05; mem[16'h8032] = 8'h20; // STA $2005

        // $8033: Enable Background: PPUMASK = $0A
        mem[16'h8033] = 8'hA9; mem[16'h8034] = 8'h0A;                        // LDA #$0A
        mem[16'h8035] = 8'h8D; mem[16'h8036] = 8'h01; mem[16'h8037] = 8'h20; // STA $2001

        // $8038: Infinite Loop
        mem[16'h8038] = 8'h4C; mem[16'h8039] = 8'h38; mem[16'h803A] = 8'h80; // JMP $8038
    end

    always @(posedge clk) begin
        if (write_en) begin
            mem[addr]  <= data_in;
            data_out   <= data_in;   // write-through so FSM sees written data immediately
        end else begin
            data_out <= mem[addr];   // registered read — 1-cycle latency
        end
    end

endmodule