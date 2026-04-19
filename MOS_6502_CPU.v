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

// ── Effective Address Generation ──────────────────────────────────────────
// Covers all addressing modes.  ZP,Y is mode 11 (used by LDX $B6 / STX $96).
// ABS,Y is mode 6 (used by LDX $BE and existing instructions).
// ─────────────────────────────────────────────────────────────────────────
reg [15:0] eff_addr;
always @(*) begin
    case (addr_mode)
        4'd1:  eff_addr = PC;                                         // Immediate (not normally used for eff_addr)
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

// ── Address Bus Mux ───────────────────────────────────────────────────────
// addr_sel:
//   0 = PC
//   1 = eff_addr
//   2 = eff_addr + 1
//   3 = vector page ($FFF*) — LO/HI discriminated by FSM state
//   4 = {ptr_hi, ptr_lo} [+ Y for indirect,Y]
//   5 = stack page $01xx
// ─────────────────────────────────────────────────────────────────────────

// Expose FSM state so we can distinguish reset vs IRQ/BRK vector reads.
// Reset vector states: S_RESET_VEC_LO_WAIT=25, S_RESET_VEC_LO=26,
//                      S_RESET_VEC_HI_WAIT=27, S_RESET_VEC_HI=28
// BRK vector states:   S_BRK_VEC_LO_WAIT=53,  S_BRK_VEC_LO=54,
//                      S_BRK_VEC_HI_WAIT=55,   S_BRK_VEC_HI=56
wire [5:0] fsm_state = fsm_inst.state;

wire is_reset_vec = (fsm_state == 6'd25 || fsm_state == 6'd26 ||
                     fsm_state == 6'd27 || fsm_state == 6'd28);
wire is_brk_vec   = (fsm_state == 6'd53 || fsm_state == 6'd54 ||
                     fsm_state == 6'd55 || fsm_state == 6'd56);

// LO byte states for reset/IRQ vectors
wire is_vec_lo    = (fsm_state == 6'd25 || fsm_state == 6'd26 ||  // reset LO
                     fsm_state == 6'd53 || fsm_state == 6'd54);   // BRK LO

always @(*) begin
    case (addr_sel)
        3'd0: address_bus = PC;
        3'd1: address_bus = eff_addr;
        3'd2: address_bus = eff_addr + 16'd1;
        3'd3: begin
            // Vector page: reset uses $FFFC/$FFFD, BRK/IRQ uses $FFFE/$FFFF
            if (is_reset_vec)
                address_bus = is_vec_lo ? 16'hFFFC : 16'hFFFD;
            else // BRK vector
                address_bus = is_vec_lo ? 16'hFFFE : 16'hFFFF;
        end
        3'd4: begin
            if (addr_mode == 4'd8) // (Indirect),Y — add Y to resolved pointer
                address_bus = {ptr_hi, ptr_lo} + {8'h00, Y};
            else
                address_bus = {ptr_hi, ptr_lo}; // (Indirect,X) or JMP indirect result
        end
        3'd5: address_bus = {8'h01, s_pointer}; // Stack page
        default: address_bus = PC;
    endcase
end

// ── Sub-modules ───────────────────────────────────────────────────────────
cpu_fsm fsm_inst (
    .clk(clk), .reset(reset), .data_in(mem_q),
    .extra_cycles_in(extra_cycles),
    .alu_op_in(alu_op), .dest_reg_in(dest_reg), .addr_mode_in(addr_mode),
    .PC(PC), .inst_reg(inst_reg), .accum(accum), .X(X), .Y(Y),
    .s_pointer(s_pointer), .s_reg(s_reg),
    .operand_lo(operand_lo), .operand_hi(operand_hi),
    .addr_sel(addr_sel), .ptr_lo(ptr_lo), .ptr_hi(ptr_hi),
    .write_en(write_en), .push_data(push_data)
);

cpu_decoder dec_inst (
    .inst_reg(inst_reg), .addr_mode(addr_mode),
    .extra_cycles(extra_cycles), .alu_op(alu_op), .dest_reg(dest_reg)
);

ram mem_inst (
    .clk(clk),
    .addr(address_bus),
    .data_in(push_data),
    .write_en(write_en),
    .data_out(mem_q)
);

endmodule