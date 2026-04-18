module ram (
    input  [15:0] address,
    input          clock,
    input  [7:0]  data,
    input          wren,
    output reg [7:0] q
);
    reg [7:0] mem [0:65535];

    initial begin
        // --- 1. Reset Vector ---
        // Points the CPU to start execution at $0000
        mem[16'hFFFC] = 8'h00; mem[16'hFFFD] = 8'h00; 

        // --- 2. Register Increment/Decrement Tests ($0000 - $0007) ---
        mem[16'h0000] = 8'hA2; mem[16'h0001] = 8'hFF; // LDX #$FF
        mem[16'h0002] = 8'hE8;                        // INX (X -> 00, Z=1, N=0)
        mem[16'h0003] = 8'hCA;                        // DEX (X -> FF, Z=0, N=1)
        mem[16'h0004] = 8'hA0; mem[16'h0005] = 8'h41; // LDY #$41
        mem[16'h0006] = 8'hC8;                        // INY (Y -> 42)
        mem[16'h0007] = 8'h88;                        // DEY (Y -> 41)

        // --- 3. NOP Test ($0008) ---
        mem[16'h0008] = 8'hEA;                        // NOP (PC should just go to 0009)

        // --- 4. ORA Tests ($0009 - $0010) ---
        mem[16'h0009] = 8'hA9; mem[16'h000A] = 8'h0F; // LDA #$0F (A = 0F)
        mem[16'h000B] = 8'h09; mem[16'h000C] = 8'hF0; // ORA #$F0 (A = FF, N=1, Z=0)
        // Absolute Mode ORA: ORing A with the value at $0020 (which is 00)
        mem[16'h000D] = 8'h0D; mem[16'h000E] = 8'h20; mem[16'h000F] = 8'h00; // ORA $0020 (A stays FF)

        // --- 5. EOR Tests ($0010 - $0018) ---
        mem[16'h0010] = 8'h49; mem[16'h0011] = 8'hAA; // EOR #$AA (FF ^ AA = 55, N=0, Z=0)
        // Absolute Mode EOR: XORing A with the value at $0021 (which is 55)
        mem[16'h0012] = 8'h4D; mem[16'h0013] = 8'h21; mem[16'h0014] = 8'h00; // EOR $0021 (55 ^ 55 = 00, Z=1)

        // --- 6. Final Trap Loop ---
        // Loops back to itself at $0015 forever
        mem[16'h0015] = 8'h4C; mem[16'h0016] = 8'h15; mem[16'h0017] = 8'h00; 

        // --- Data Memory for Absolute Modes ---
        mem[16'h0020] = 8'h00; // Used for ORA Absolute test
        mem[16'h0021] = 8'h55; // Used for EOR Absolute test
    end

    always @(posedge clock) begin
        if (wren) mem[address] <= data;
        q <= mem[address];
    end
endmodule