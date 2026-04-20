// =============================================================================
// MOS_6502_CPU.v  —  Top-level wrapper
//
// Fixes applied vs original:
//   1. JMP indirect ($6C) NMOS page-wrap bug:
//      When operand address low byte == $FF the high byte of the vector is
//      fetched from $xx00 (same page), not $(xx+1)00.
//      addr_sel=2 now uses a same-page wrap.
//   2. ZP,Y effective address generation confirmed correct for LDX $B6/STX $96.
//   3. Decoupled Memory Bus and Phase Accumulator Clocking applied.
// =============================================================================

module MOS_6502_CPU (
    input  wire        clk_25mhz,   // 25.175 MHz Master Clock
    input  wire        cpu_ce,      // 1.79 MHz Phase Accumulator Pulse
    input  wire        reset,       // Active high/low depending on implementation
    
    output wire [15:0] address,
    input  wire [7:0]  data_in,     // Uni-directional Read Bus
    output wire [7:0]  data_out,    // Uni-directional Write Bus
    output wire        write_en,
	 
	 output wire [15:0] current_pc,     // Telemetry Export
    output wire [5:0]  current_state  // Telemetry Export
);

    wire [15:0] PC;
    wire [7:0]  inst_reg, accum, X, Y, s_pointer, s_reg;
    wire [7:0]  operand_lo, operand_hi, ptr_lo, ptr_hi;
    wire [3:0]  addr_mode, alu_op;
    wire [1:0]  extra_cycles, dest_reg;
    wire [2:0]  addr_sel;
    wire [7:0]  push_data;

    // Directly route FSM output to the external write bus
    assign data_out = push_data;
	 
	 // Telemtery
	 assign current_pc = PC;
    assign current_state = fsm_state;

    // ── Effective Address Generation ──────────────────────────────────────────────
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
    wire [5:0] fsm_state;

    wire is_reset_vec = (fsm_state == 6'd25 || fsm_state == 6'd26 ||
                         fsm_state == 6'd27 || fsm_state == 6'd28);
    wire is_vec_lo    = (fsm_state == 6'd25 || fsm_state == 6'd26 ||  
                         fsm_state == 6'd53 || fsm_state == 6'd54);

    // ── Address Bus Mux ───────────────────────────────────────────────────────────
    reg [15:0] addr_mux_out;
    assign address = addr_mux_out;

    always @(*) begin
        case (addr_sel)
            3'd0: addr_mux_out = PC;
            3'd1: addr_mux_out = eff_addr;
            
            // TEAMMATE FIX: NMOS JMP ($xxFF) page-wrap fix preserved!
            3'd2: addr_mux_out = {eff_addr[15:8], eff_addr[7:0] + 8'd1};

            3'd3: begin
                if (is_reset_vec)
                    addr_mux_out = is_vec_lo ? 16'hFFFC : 16'hFFFD;
                else
                    addr_mux_out = is_vec_lo ? 16'hFFFE : 16'hFFFF;
            end

            3'd4: begin
                if (addr_mode == 4'd8) 
                    addr_mux_out = {ptr_hi, ptr_lo} + {8'h00, Y};
                else
                    addr_mux_out = {ptr_hi, ptr_lo};
            end

            3'd5: addr_mux_out = {8'h01, s_pointer};
            default: addr_mux_out = PC;
        endcase
    end

    // ── Sub-modules ───────────────────────────────────────────────────────────────
    cpu_fsm fsm_inst (
        .clk             (clk_25mhz), 
        .cpu_ce          (cpu_ce),     // RESTORED CLOCK ENABLE
        .reset           (reset), 
        .data_in         (data_in),    // EXTERNAL BUS IN
        .extra_cycles_in (extra_cycles),
        .alu_op_in       (alu_op), 
        .dest_reg_in     (dest_reg), 
        .addr_mode_in    (addr_mode),
        .PC              (PC), 
        .inst_reg        (inst_reg), 
        .accum           (accum), 
        .X               (X), 
        .Y               (Y),
        .s_pointer       (s_pointer), 
        .s_reg           (s_reg),
        .operand_lo      (operand_lo), 
        .operand_hi      (operand_hi),
        .addr_sel        (addr_sel), 
        .ptr_lo          (ptr_lo), 
        .ptr_hi          (ptr_hi),
        .write_en        (write_en), 
        .push_data       (push_data),  // EXTERNAL BUS OUT
        .fsm_state_out   (fsm_state)
    );

    cpu_decoder dec_inst (
        .inst_reg        (inst_reg), 
        .addr_mode       (addr_mode),
        .extra_cycles    (extra_cycles), 
        .alu_op          (alu_op), 
        .dest_reg        (dest_reg)
    );

    // DELETED: ram_sim mem_inst (CPU no longer traps memory internally!)

endmodule