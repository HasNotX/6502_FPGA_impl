`timescale 1ns/1ps
// =============================================================================
// MOS_6502_CPU_tb_klaus.v  —  Klaus Dörmann 6502 Functional Test testbench
// =============================================================================

module MOS_6502_CPU_tb;

// ── Parameters ───────────────────────────────────────────────────────────────
parameter KLAUS_HEX    = "klaus_dormann.hex";
parameter SUCCESS_PC   = 16'h3469;
parameter MAX_CYCLES   = 100_000_000;

// ── DUT ──────────────────────────────────────────────────────────────────────
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

// ── Convenience aliases ───────────────────────────────────────────────────────
wire [7:0]  A   = dut.fsm_inst.accum;
wire [7:0]  X   = dut.fsm_inst.X;
wire [7:0]  Y   = dut.fsm_inst.Y;
wire [7:0]  SR  = dut.fsm_inst.s_reg;
wire [15:0] PC  = dut.fsm_inst.PC;
wire [5:0]  ST  = dut.fsm_inst.fsm_state_out;
wire [7:0]  SP  = dut.fsm_inst.s_pointer;

// ── Clock ─────────────────────────────────────────────────────────────────────
always #5 clk = ~clk;

// ── Trap detector ─────────────────────────────────────────────────────────────
reg [15:0] prev_fetch_pc;
reg        prev_valid;
integer    cycle_count;

localparam S_FETCH = 6'd0;

always @(posedge clk) begin
    if (reset) begin
        prev_fetch_pc <= 16'hFFFF;
        prev_valid    <= 1'b0;
        cycle_count   <= 0;
    end else begin
        cycle_count <= cycle_count + 1;

        if (ST == S_FETCH) begin
            if (prev_valid && (PC === prev_fetch_pc)) begin
                $display("");
                if (PC === SUCCESS_PC) begin
                    $display("  ============================================================");
                    $display("  PASS  Klaus functional test PASSED at PC=%04X", PC);
                    $display("  All tests completed in %0d cycles.", cycle_count);
                    $display("  ============================================================");
                end else begin
                    $display("  ============================================================");
                    $display("  FAIL  CPU trapped at PC=%04X  (cycle %0d)", PC, cycle_count);
                    $display("  Registers: A=%02X X=%02X Y=%02X SP=%02X SR=%08b", A, X, Y, SP, SR);
                    $display("  Look up $%04X in Klaus's listing to identify the failing test.", PC);
                    $display("  ============================================================");
                end
                $finish;
            end
            prev_fetch_pc <= PC;
            prev_valid    <= 1'b1;
        end

        if (cycle_count >= MAX_CYCLES) begin
            $display("  TIMEOUT  %0d cycles elapsed without trap.  PC=%04X", MAX_CYCLES, PC);
            $finish;
        end
    end
end

// ── Progress heartbeat — every 5M cycles ─────────────────────────────────────
always @(posedge clk) begin
    if (!reset && (cycle_count % 5_000_000 == 0) && cycle_count > 0)
        $display("  [%0dM cycles] PC=%04X  A=%02X X=%02X Y=%02X SP=%02X SR=%08b",
            cycle_count / 1_000_000, PC, A, X, Y, SP, SR);
end

// ── Early fetch trace — first 20 cycles ──────────────────────────────────────
always @(posedge clk) begin
    if (!reset && cycle_count < 20)
        $display("cyc=%0d state=%0d addr=%04X data=%02X PC=%04X",
            cycle_count, dut.fsm_inst.state,
            dut.address_bus, dut.mem_q, dut.fsm_inst.PC);
end

// ── BRK push debug (state 52 = S_BRK_PUSH_SR) ────────────────────────────────
always @(posedge clk) begin
    if (dut.fsm_inst.state == 6'd52)
        $display("BRK SR push: PC=%04X ret=%04X SR_pushed=%02X (%08b) SR_live=%02X (%08b)",
            dut.fsm_inst.PC, dut.fsm_inst.brk_ret_addr,
            dut.fsm_inst.push_data, dut.fsm_inst.push_data,
            dut.fsm_inst.s_reg,     dut.fsm_inst.s_reg);
end

// ── RTI debug (state 45 = S_RTI_PULL_SR) ─────────────────────────────────────
always @(posedge clk) begin
    if (dut.fsm_inst.state == 6'd45)
        $display("RTI SR pull: raw=%02X (%08b) -> SR_after=%02X (%08b)",
            dut.mem_q, dut.mem_q,
            (dut.mem_q | 8'h20) & 8'hEF,
            (dut.mem_q | 8'h20) & 8'hEF);
end

// ── IRQ handler entry ─────────────────────────────────────────────────────────
always @(posedge clk) begin
    if (PC == 16'h37ab && ST == S_FETCH)
        $display("IRQ handler entered: SR=%02X (%08b)  I(bit2) should=1",
            SR, SR);
end

// ── Focused instruction trace in the $3700-$3800 region ──────────────────────
// Shows every opcode fetch and full register state leading up to the trap.
// The opcode byte at each PC helps cross-reference Klaus's listing.
always @(posedge clk) begin
    if (ST == S_FETCH && PC >= 16'h3700 && PC <= 16'h3800)
        $display("FETCH %04X op=%02X  A=%02X X=%02X Y=%02X SP=%02X SR=%08b",
            PC, dut.mem_q, A, X, Y, SP, SR);
end

// ── Stack spy — every stack-page write and relevant reads ────────────────────
// Write: fires whenever write_en is asserted on page $01xx.
// Read:  fires only during states that pull from the stack (PLA/PLP/RTS/RTI).
// This lets you verify that BRK and JSR push the correct bytes in the correct
// order to the correct addresses, and that RTI/RTS pull them back correctly.
always @(posedge clk) begin
    if (dut.write_en && dut.address_bus[15:8] == 8'h01)
        $display("STACK WR  addr=%04X  data=%02X  SP=%02X",
            dut.address_bus, dut.push_data, SP);
end

always @(posedge clk) begin
    if (!dut.write_en && dut.address_bus[15:8] == 8'h01
        && (dut.fsm_inst.state == 6'd19   // S_PULL_EXEC
         || dut.fsm_inst.state == 6'd37   // S_RTS_PULL_HI
         || dut.fsm_inst.state == 6'd35   // S_RTS_PULL_LO
         || dut.fsm_inst.state == 6'd45   // S_RTI_PULL_SR
         || dut.fsm_inst.state == 6'd47   // S_RTI_PULL_PCL
         || dut.fsm_inst.state == 6'd49)) // S_RTI_PULL_PCH
        $display("STACK RD  addr=%04X  data=%02X  SP=%02X",
            dut.address_bus, dut.mem_q, SP);
end

// ── Load Klaus binary ─────────────────────────────────────────────────────────
initial begin
    $readmemh(KLAUS_HEX, dut.mem_inst.mem);
    $display("  Loaded %s into RAM.", KLAUS_HEX);
end

// ── Verify vectors after load ─────────────────────────────────────────────────
initial begin
    #1;
    $display("  Vectors: FFFC=%02X FFFD=%02X (reset->$%02X%02X)  FFFE=%02X FFFF=%02X (IRQ->$%02X%02X)",
        dut.mem_inst.mem[16'hFFFC], dut.mem_inst.mem[16'hFFFD],
        dut.mem_inst.mem[16'hFFFD], dut.mem_inst.mem[16'hFFFC],
        dut.mem_inst.mem[16'hFFFE], dut.mem_inst.mem[16'hFFFF],
        dut.mem_inst.mem[16'hFFFF], dut.mem_inst.mem[16'hFFFE]);
end

// ── Reset sequence ────────────────────────────────────────────────────────────
initial begin
    clk   = 0;
    reset = 1;
    repeat(8) @(posedge clk);
    reset = 0;
    $display("  Reset released.  CPU running Klaus Dormann functional test...");
    $display("  Target pass address: $%04X", SUCCESS_PC);
    $display("");
end

// ── Waveform dump — leave commented out to avoid huge VCD files ──────────────
//initial begin
//    $dumpfile("MOS_6502_CPU_tb.vcd");
//    $dumpvars(0, MOS_6502_CPU_tb);
//end

endmodule