`timescale 1ns/1ps
module ram (
    input            clk,
    input [15:0]     addr,
    input [7:0]      data_in,
    input            write_en,
    output reg [7:0] data_out
);

    reg [7:0] mem [0:65535];

    initial begin
        // Uninitialized addresses will safely default to 8'h00 (BRK).

        // =====================================================================
        // PROGRAM START  $8000: "HELLO PPU"
        // =====================================================================
        
        // 1. Write $AB to PPUCTRL ($2000)
        mem[16'h8000] = 8'hA9; mem[16'h8001] = 8'hAB; // LDA #$AB
        mem[16'h8002] = 8'h8D; mem[16'h8003] = 8'h00; mem[16'h8004] = 8'h20; // STA $2000
        
        // 2. Write $CD to PPUMASK ($2001)
        mem[16'h8005] = 8'hA9; mem[16'h8006] = 8'hCD; // LDA #$CD
        mem[16'h8007] = 8'h8D; mem[16'h8008] = 8'h01; mem[16'h8009] = 8'h20; // STA $2001

        // 3. Trap the CPU in an infinite loop
        mem[16'h800A] = 8'h4C; mem[16'h800B] = 8'h0A; mem[16'h800C] = 8'h80; // JMP $800A

        // =====================================================================
        // RESET VECTOR → $8000
        // =====================================================================
        mem[16'hFFFC] = 8'h00;
        mem[16'hFFFD] = 8'h80;
    end

    always @(posedge clk) begin
        if (write_en) begin
            mem[addr]  <= data_in;
            data_out   <= data_in;
        end else begin
            data_out <= mem[addr];
        end
    end
endmodule