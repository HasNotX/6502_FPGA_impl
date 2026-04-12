module ram (
    input        clock,
    input        wren,
    input [15:0] address,
    input  [7:0] data,
    output reg [7:0] q
);

reg [7:0] mem [0:65535];
integer i;

initial begin
    // Initialize memory with NOP (EA)
    for (i = 0; i < 65536; i = i + 1)
        mem[i] = 8'hEA;

    // ── DATA PREPARATION ───────────────────────────────────────
    // Values chosen to test bitmasking (e.g., $AA & $55 = $00)
    
    mem[16'h0010] = 8'h55;   // Zero Page data
    mem[16'h0060] = 8'h0F; 
    
    mem[16'h1000] = 8'hF0;   // Absolute data
    mem[16'h1005] = 8'h80;   // Absolute,X (indexed $1000 + X=5)
    mem[16'h1003] = 8'h00;   // Absolute,Y (indexed $1000 + Y=3)

    // Indirect X pointer ($20 + X=5 = $25) -> Points to $5000
    mem[16'h0025] = 8'h00;   // ptr_lo
    mem[16'h0026] = 8'h50;   // ptr_hi
    mem[16'h5000] = 8'hC0;   // Final value for (Indirect,X)

    // Indirect Y pointer ($40) -> Points to $3000 (+ Y=3 = $3003)
    mem[16'h0040] = 8'h00;   // ptr_lo
    mem[16'h0041] = 8'h30;   // ptr_hi
    mem[16'h3003] = 8'h80;   // Final value for (Indirect),Y

    // ── TEST PROGRAM ───────────────────────────────────────────
    // Initial State: A=$00, X=$05, Y=$03
    
    // 1. Setup: Load A with $FF using ADC (since A starts at 0)
    mem[16'hFFFC] = 8'h69; mem[16'hFFFD] = 8'hFF; // A = $FF

    // 2. AND #$AA (Immediate - $29) 
    // Result: $FF & $AA = $AA (N flag should set)
    mem[16'hFFFE] = 8'h29; mem[16'hFFFF] = 8'hAA; 

    // 3. AND $10 (Zero Page - $25)
    // Result: $AA & $55 = $00 (Z flag should set)
    mem[16'h0000] = 8'h25; mem[16'h0001] = 8'h10;

    // 4. Setup: Re-load A with $0F
    mem[16'h0002] = 8'h69; mem[16'h0003] = 8'h0F; // A = $0F

    // 5. AND $10,X (Zero Page,X - $35) -> Addr $15
    // Result: $0F & $0F = $0F
    mem[16'h0004] = 8'h35; mem[16'h0005] = 8'h5B;

    // 6. AND $1000 (Absolute - $2D)
    // Result: $0F & $F0 = $00 (Z flag set)
    mem[16'h0006] = 8'h2D; mem[16'h0007] = 8'h00; mem[16'h0008] = 8'h10;

    // 7. Setup: Re-load A with $80
    mem[16'h0009] = 8'h69; mem[16'h000A] = 8'h80; // A = $80

    // 8. AND $1000,X (Absolute,X - $3D) -> Addr $1005
    // Result: $80 & $80 = $80 (N flag set)
    mem[16'h000B] = 8'h3D; mem[16'h000C] = 8'h00; mem[16'h000D] = 8'h10;

    // 9. AND $1000,Y (Absolute,Y - $39) -> Addr $1003
    // Result: $80 & $00 = $00
    mem[16'h000E] = 8'h39; mem[16'h000F] = 8'h00; mem[16'h0010] = 8'h10;

    // 10. Setup: Re-load A with $FF
    mem[16'h0011] = 8'h69; mem[16'h0012] = 8'hFF; // A = $FF

    // 11. AND ($20,X) (Indirect,X - $21) -> Ptr $25 -> Addr $5000
    // Result: $FF & $C0 = $C0 (N flag set)
    mem[16'h0013] = 8'h21; mem[16'h0014] = 8'h20;

    // 12. AND ($40),Y (Indirect,Y - $31) -> Ptr $40 -> Addr $3000 + 3 = $3003
    // Result: $C0 & $80 = $80 (N flag set)
    mem[16'h0015] = 8'h31; mem[16'h0016] = 8'h40;

end

always @(posedge clock) begin
    if (wren)
        mem[address] <= data;
    else
        q <= mem[address];
end

endmodule