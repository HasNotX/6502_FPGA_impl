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
        // Removed the 65,536 iteration for-loop. 
        // Uninitialized addresses will safely default to 8'h00 (BRK).

        // =====================================================================
        // ZEROPAGE SCRATCH DATA
        // =====================================================================
        // ZP $10 = $55  (LDX ZP, LDY ZP targets)
        mem[16'h0010] = 8'h55;
        // ZP $20 = $66  (LDY ZP,X  with X=1 → reads ZP $21)
        mem[16'h0020] = 8'hAA;   // dummy
        mem[16'h0021] = 8'h66;   // LDY $20,X with X=1
        // ZP $30 = $77  (LDX ZP,Y  with Y=2 → reads ZP $32)
        mem[16'h0030] = 8'hBB;   // dummy
        mem[16'h0031] = 8'hBB;   // dummy
        mem[16'h0032] = 8'h77;   // LDX $30,Y with Y=2

        // Absolute address $0200 = $88  (LDX ABS, LDY ABS targets)
        mem[16'h0200] = 8'h88;
        // Absolute,Y $0200 + 3 = $0203 = $99  (LDX ABS,Y with Y=3)
        mem[16'h0203] = 8'h99;
        // Absolute,X $0200 + 4 = $0204 = $AA  (LDY ABS,X with X=4)
        mem[16'h0204] = 8'hAA;

        // IRQ/BRK vector
        mem[16'hFFFE] = 8'h00;   // PCL → $8500
        mem[16'hFFFF] = 8'h85;   // PCH

        // =====================================================================
        // PROGRAM START  $8000
        // =====================================================================
        // ── TEST 1: LDX Immediate (already working, keep as sanity check) ────
        mem[16'h8000] = 8'hA2; mem[16'h8001] = 8'h11; // LDX #$11

        // ── TEST 2: LDX Zero Page  ($A6)  → X = $55 ─────────────────────────
        mem[16'h8002] = 8'hA6; mem[16'h8003] = 8'h10; // LDX $10

        // ── TEST 3: LDY Immediate (sanity check) ────────────────────────────
        mem[16'h8004] = 8'hA0; mem[16'h8005] = 8'h01; // LDY #$01  (Y=1 for next test)

        // ── TEST 4: LDY Zero Page  ($A4)  → Y = $55 ─────────────────────────
        mem[16'h8006] = 8'hA4; mem[16'h8007] = 8'h10; // LDY $10

        // ── TEST 5: LDY Zero Page,X ($B4) → Y=$66  (X still $55, need X=1) ──
        // Reset X to 1 first
        mem[16'h8008] = 8'hA2; mem[16'h8009] = 8'h01; // LDX #$01
        mem[16'h800A] = 8'hB4; mem[16'h800B] = 8'h20; // LDY $20,X → Y=$66

        // ── TEST 6: LDX Zero Page,Y ($B6) → X=$77  (Y still $66... need Y=2) ─
        // Reset Y to 2 first
        mem[16'h800C] = 8'hA0; mem[16'h800D] = 8'h02; // LDY #$02
        mem[16'h800E] = 8'hB6; mem[16'h800F] = 8'h30; // LDX $30,Y → X=$77

        // ── TEST 7: LDX Absolute ($AE) → X=$88 ──────────────────────────────
        mem[16'h8010] = 8'hAE; mem[16'h8011] = 8'h00; mem[16'h8012] = 8'h02; // LDX $0200

        // ── TEST 8: LDY Absolute ($AC) → Y=$88 ──────────────────────────────
        mem[16'h8013] = 8'hAC; mem[16'h8014] = 8'h00; mem[16'h8015] = 8'h02; // LDY $0200

        // ── TEST 9: LDX Absolute,Y ($BE) → X=$99  (need Y=3) ────────────────
        mem[16'h8016] = 8'hA0; mem[16'h8017] = 8'h03; // LDY #$03
        mem[16'h8018] = 8'hBE; mem[16'h8019] = 8'h00; mem[16'h801A] = 8'h02; // LDX $0200,Y → X=$99

        // ── TEST 10: LDY Absolute,X ($BC) → Y=$AA  (need X=4) ───────────────
        mem[16'h801B] = 8'hA2; mem[16'h801C] = 8'h04; // LDX #$04
        mem[16'h801D] = 8'hBC; mem[16'h801E] = 8'h00; mem[16'h801F] = 8'h02; // LDY $0200,X → Y=$AA

        // ── TEST 11: BRK ($00) ───────────────────────────────────────────────
        // Load known values into A, X, Y so we can confirm they survive BRK
        mem[16'h8020] = 8'hA9; mem[16'h8021] = 8'hBB; // LDA #$BB
        mem[16'h8022] = 8'h00;                        // BRK
        mem[16'h8023] = 8'h00;                        // BRK padding byte (skipped)

        // ── BRK handler at $8500 ─────────────────────────────────────────────
        // The handler loads $CC into A to prove we reached it, then RTI back.
        // RTI will return to $8024 (the byte after BRK padding).
        mem[16'h8500] = 8'hA9; mem[16'h8501] = 8'hCC; // LDA #$CC
        mem[16'h8502] = 8'h40;                        // RTI → returns to $8024

        // ── After RTI returns to $8024 ────────────────────────────────────────
        mem[16'h8024] = 8'hA9; mem[16'h8025] = 8'hDD; // LDA #$DD  (confirm RTI worked)

        // ── Infinite loop ─────────────────────────────────────────────────────
        mem[16'h8026] = 8'h4C;
        mem[16'h8027] = 8'h26; mem[16'h8028] = 8'h80; // JMP $8026

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