`timescale 1ns/1ps
module MOS_6502_CPU_tb;

reg  clk, reset;
wire [7:0]  data_bus;
wire [15:0] address_bus;
wire        read_write_n;
 
MOS_6502_CPU dut (
    .clk(clk), .reset(reset),
    .data_bus(data_bus),
    .address_bus(address_bus),
    .read_write_n(read_write_n)
);
 
// 10 ns clock
always #5 clk = ~clk;
 
// Convenience aliases
wire [7:0]  A   = dut.fsm_inst.accum;
wire [7:0]  X   = dut.fsm_inst.X;
wire [7:0]  Y   = dut.fsm_inst.Y;
wire [7:0]  SR  = dut.fsm_inst.s_reg;
wire [15:0] PC  = dut.fsm_inst.PC;
wire [5:0]  ST  = dut.fsm_inst.state;
 
integer pass_count, fail_count;
 
task check;
    input [8*32-1:0] name;
    input [7:0] got, expected;
    begin
        if (got === expected) begin
            $display("  PASS  %-30s  got %02X", name, got);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL  %-30s  got %02X  expected %02X", name, got, expected);
            fail_count = fail_count + 1;
        end
    end
endtask
 
// Run for N clock cycles
task run;
    input integer n;
    integer k;
    begin
        for (k = 0; k < n; k = k + 1) @(posedge clk);
    end
endtask
 
initial begin
    clk        = 0;
    reset      = 1;
    pass_count = 0;
    fail_count = 0;
 
    // Hold reset for several cycles
    run(5);
    reset = 0;
 
    // ── Give the CPU enough cycles to run the full test program ───────────
    // Program has ~11 tests, each at most ~20 cycles; BRK path ~40 cycles.
    // 600 cycles is generous.
    run(600);
 
    $display("");
    $display("============================================================");
    $display("  CPU REGISTER STATE after 600 cycles");
    $display("  A=%02X  X=%02X  Y=%02X  SR=%08b  PC=%04X", A, X, Y, SR, PC);
    $display("============================================================");
    $display("");
    $display("  Expected after full test sequence:");
    $display("    LDX #$11            X=$11");
    $display("    LDX ZP $10          X=$55");
    $display("    LDY #$01            Y=$01");
    $display("    LDY ZP $10          Y=$55");
    $display("    LDX #$01; LDY ZP,X  Y=$66");
    $display("    LDY #$02; LDX ZP,Y  X=$77");
    $display("    LDX ABS $0200       X=$88");
    $display("    LDY ABS $0200       Y=$88");
    $display("    LDY #$03; LDX ABS,Y X=$99");
    $display("    LDX #$04; LDY ABS,X Y=$AA");
    $display("    LDA #$BB; BRK; (handler: LDA #$CC); RTI; LDA #$DD");
    $display("      → A=$DD  X=$04  Y=$AA");
    $display("");
 
    $display("  --- Register Checks ---");
    // After all tests complete the final state should be:
    check("A after RTI+LDA #$DD",  A, 8'hDD);
    check("X after LDX #$04",      X, 8'h04);
    check("Y after LDY ABS,X=$AA", Y, 8'hAA);
 
    $display("");
    $display("  --- Totals: %0d passed, %0d failed ---", pass_count, fail_count);
    $display("============================================================");
    $finish;
end
 
// Optional waveform dump
initial begin
    $dumpfile("MOS_6502_CPU_tb.vcd");
    $dumpvars(0, MOS_6502_CPU_tb);
end
 
 endmodule