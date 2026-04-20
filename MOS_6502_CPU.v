// =============================================================================
// MOS_6502_CPU.v  —  Top-level wrapper
//
// Fixes applied vs original:
//   1. JMP indirect ($6C) NMOS page-wrap bug:
//      When operand address low byte == $FF the high byte of the vector is
//      fetched from $xx00 (same page), not $(xx+1)00. addr_sel=2 now uses
//      a same-page wrap:  {eff_addr[15:8], eff_addr[7:0] + 8'd1}
//      instead of the plain  eff_addr + 16'd1.
//      This matches what the real NMOS 6502 does and what Klaus's test
//      exercises at the indirect-JMP test section.
//   2. ZP,Y effective address generation confirmed correct for LDX $B6/STX $96.
//   3. Comments updated throughout.
// =============================================================================

module MOS_6502_CPU (
    input clk, reset,
    inout [7:0] data_bus,
    output reg [15:0] address_bus,
    output wire read_write_n
);

wire [15:0] PC;
wire [7:0]  inst_reg, accum, X, Y, s_pointer, s_reg;
wire [7:0]  operand_lo, operand_hi, ptr_lo, ptr_hi;
wire [3:0]  addr_mode, alu_op;
wire [1:0]  extra_cycles, dest_reg;
wire [2:0]  addr_sel;
wire [7:0]  mem_q;
wire        write_en;
wire [7:0]  push_data;

assign read_write_n = ~write_en;
assign data_bus     = write_en ? push_data : mem_q;

// ── Effective Address Generation ──────────────────────────────────────────────
// All addressing mode → effective address mappings.
// ZP,Y is mode 11 (LDX $B6 / STX $96).
// ABS,Y is mode 6.
// (Indirect,X): pointer base = {$00, ZP + X}  — wraps in ZP automatically
//               because operand_lo + X is computed as 8-bit.
// (Indirect),Y: pointer base = {$00, ZP}       — Y is added to resolved ptr
//               in the address mux (addr_sel=4 path).
// JMP Indirect: pointer base = {operand_hi, operand_lo} (mode 12).
// ─────────────────────────────────────────────────────────────────────────────
reg [15:0] eff_addr;
always @(*) begin
    case (addr_mode)
        4'd1:  eff_addr = PC;                                         // Immediate
        4'd2:  eff_addr = {8'h00, operand_lo};                        // Zero Page
        4'd4:  eff_addr = {8'h00, operand_lo + X};                    // Zero Page,X
        4'd11: eff_addr = {8'h00, operand_lo + Y};                    // Zero Page,Y
        4'd3:  eff_addr = {operand_hi, operand_lo};                   // Absolute
        4'd5:  eff_addr = {operand_hi, operand_lo} + {8'h00, X};      // Absolute,X
        4'd6:  eff_addr = {operand_hi, operand_lo} + {8'h00, Y};      // Absolute,Y
        4'd7:  eff_addr = {8'h00, operand_lo + X};                    // (Indirect,X) pointer fetch
        4'd8:  eff_addr = {8'h00, operand_lo};                        // (Indirect),Y pointer fetch
        4'd12: eff_addr = {operand_hi, operand_lo};                   // JMP Indirect pointer base
        default: eff_addr = PC;
    endcase
end

// ── FSM state for vector disambiguation ──────────────────────────────────────
// fsm_state is driven by the dedicated fsm_state_out port on cpu_fsm.
// Reset vector states: 25-28.  BRK/IRQ vector states: 53-56.
wire [5:0] fsm_state;   // connected to fsm_inst.fsm_state_out below

wire is_reset_vec = (fsm_state == 6'd25 || fsm_state == 6'd26 ||
                     fsm_state == 6'd27 || fsm_state == 6'd28);

// is_vec_lo: true during the LOW-byte fetch for either reset or BRK vector
wire is_vec_lo    = (fsm_state == 6'd25 || fsm_state == 6'd26 ||  // reset LO
                     fsm_state == 6'd53 || fsm_state == 6'd54);   // BRK LO

// ── Address Bus Mux ───────────────────────────────────────────────────────────
// addr_sel:
//   0 = PC
//   1 = eff_addr
//   2 = eff_addr + 1 with SAME-PAGE wrap  (fixes NMOS JMP indirect bug)
//   3 = vector page ($FFFC/$FFFD or $FFFE/$FFFF)
//   4 = {ptr_hi, ptr_lo} [+ Y for (indirect),Y]
//   5 = stack $01xx
// ─────────────────────────────────────────────────────────────────────────────
always @(*) begin
    case (addr_sel)
        3'd0: address_bus = PC;
        3'd1: address_bus = eff_addr;

        // ── NMOS JMP ($xxFF) page-wrap fix ───────────────────────────────
        // The real NMOS 6502 increments only the low byte when fetching the
        // second byte of a JMP indirect vector.  If operand is $xxFF the high
        // byte comes from $xx00, not $(xx+1)00.
        // Using same-page wrap here replicates that behaviour for all callers
        // of addr_sel=2.  The only other caller is the ptr_hi fetch during
        // indirect addressing, which also benefits from the same wrap for
        // the (zp,X) case at $FF.
        3'd2: address_bus = {eff_addr[15:8], eff_addr[7:0] + 8'd1};

        3'd3: begin
            if (is_reset_vec)
                address_bus = is_vec_lo ? 16'hFFFC : 16'hFFFD;
            else
                address_bus = is_vec_lo ? 16'hFFFE : 16'hFFFF;
        end

        3'd4: begin
            if (addr_mode == 4'd8) // (Indirect),Y — add Y to resolved pointer
                address_bus = {ptr_hi, ptr_lo} + {8'h00, Y};
            else
                address_bus = {ptr_hi, ptr_lo};
        end

        3'd5: address_bus = {8'h01, s_pointer};

        default: address_bus = PC;
    endcase
end

// ── Sub-modules ───────────────────────────────────────────────────────────────
cpu_fsm fsm_inst (
    .clk(clk), .reset(reset), .data_in(mem_q),
    .extra_cycles_in(extra_cycles),
    .alu_op_in(alu_op), .dest_reg_in(dest_reg), .addr_mode_in(addr_mode),
    .PC(PC), .inst_reg(inst_reg), .accum(accum), .X(X), .Y(Y),
    .s_pointer(s_pointer), .s_reg(s_reg),
    .operand_lo(operand_lo), .operand_hi(operand_hi),
    .addr_sel(addr_sel), .ptr_lo(ptr_lo), .ptr_hi(ptr_hi),
    .write_en(write_en), .push_data(push_data),
    .fsm_state_out(fsm_state)   // drives vector-mux disambiguation logic
);

cpu_decoder dec_inst (
    .inst_reg(inst_reg), .addr_mode(addr_mode),
    .extra_cycles(extra_cycles), .alu_op(alu_op), .dest_reg(dest_reg)
);

ram_sim mem_inst (
    .clk(clk),
    .addr(address_bus),
    .data_in(push_data),
    .write_en(write_en),
    .data_out(mem_q)
);

endmodule