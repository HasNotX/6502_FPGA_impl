module ram (
    input  [15:0] address,
    input         clock,
    input  [7:0]  data,
    input         wren,
    output reg [7:0] q
);
    reg [7:0] mem [0:65535];
    initial begin
        // Reset Vector -> $0000
        mem[16'hFFFC] = 8'h00; mem[16'hFFFD] = 8'h00;
        
        // Data
        mem[16'h0020] = 8'h11;
        mem[16'h0025] = 8'h22;
        mem[16'h0100] = 8'h33;
        mem[16'h0105] = 8'h44;
        mem[16'h0102] = 8'h55;

        // Program
        mem[16'h0000] = 8'hA2; mem[16'h0001] = 8'h05; // LDX #$05
        mem[16'h0002] = 8'hA0; mem[16'h0003] = 8'h02; // LDY #$02
        mem[16'h0004] = 8'hA9; mem[16'h0005] = 8'hAA; // LDA #$AA
        mem[16'h0006] = 8'hC9; mem[16'h0007] = 8'hAA; // CMP #$AA  → Z=1,C=1
        mem[16'h0008] = 8'hA9; mem[16'h0009] = 8'h11; // LDA #$11
        mem[16'h000A] = 8'hC5; mem[16'h000B] = 8'h20; // CMP $20   → Z=1,C=1

        // *** Infinite loop instead of BRK — halts cleanly ***
        mem[16'h000C] = 8'h4C;  // JMP
        mem[16'h000D] = 8'h0C;  // low  byte -> $000C
        mem[16'h000E] = 8'h00;  // high byte -> $000C
    end
    always @(posedge clock) begin
        if (wren) mem[address] <= data;
        q <= mem[address];
    end
endmodule