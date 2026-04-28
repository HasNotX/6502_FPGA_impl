////////////////////////////////////////////////////////////////////////////
// MOS_6502_CPU.v  —  Top-level wrapper
////////////////////////////////////////////////////////////////////////////

module MOS_6502_CPU (
    input  wire        clk_25mhz,   
    input  wire        cpu_ce,      
    input  wire        reset,       
    input  wire        nmi_in,        // NEW: Hardware NMI Line
    
    output wire [15:0] address,
    input  wire [7:0]  data_in,     
    output wire [7:0]  data_out,    
    output wire        write_en,
     
    output wire [15:0] current_pc,  
    output wire [5:0]  current_state 
);

    wire [15:0] PC;
    wire [7:0]  inst_reg, accum, X, Y, s_pointer, s_reg;
    wire [7:0]  operand_lo, operand_hi, ptr_lo, ptr_hi;
    wire [3:0]  addr_mode, alu_op;
    wire [1:0]  extra_cycles, dest_reg;
    wire [2:0]  addr_sel;
    wire [7:0]  push_data;
    
    wire nmi_active;                  // NEW: Flag from FSM

    assign data_out = push_data;
    assign current_pc = PC;
    assign current_state = fsm_state;

    // ── Effective Address Generation ──────────────────────────────────────────────
    reg [15:0] eff_addr;
    always @(*) begin
        case (addr_mode)
            4'd1:  eff_addr = PC;                                         
            4'd2:  eff_addr = {8'h00, operand_lo};                        
            4'd4:  eff_addr = {8'h00, operand_lo + X};                    
            4'd11: eff_addr = {8'h00, operand_lo + Y};                    
            4'd3:  eff_addr = {operand_hi, operand_lo};                   
            4'd5:  eff_addr = {operand_hi, operand_lo} + {8'h00, X};      
            4'd6:  eff_addr = {operand_hi, operand_lo} + {8'h00, Y};      
            4'd7:  eff_addr = {8'h00, operand_lo + X};                    
            4'd8:  eff_addr = {8'h00, operand_lo};                        
            4'd12: eff_addr = {operand_hi, operand_lo};                   
            default: eff_addr = PC;
        endcase
    end

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
            3'd2: addr_mux_out = {eff_addr[15:8], eff_addr[7:0] + 8'd1};

            3'd3: begin
                if (is_reset_vec)
                    addr_mux_out = is_vec_lo ? 16'hFFFC : 16'hFFFD;
                else if (nmi_active) // NEW: NMI Vector Hijack!
                    addr_mux_out = is_vec_lo ? 16'hFFFA : 16'hFFFB;
                else                 // Standard BRK/IRQ
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
        .cpu_ce          (cpu_ce),     
        .reset           (reset), 
        .nmi_in          (nmi_in),     // Plumbed to FSM
        .data_in         (data_in),    
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
        .push_data       (push_data),  
        .fsm_state_out   (fsm_state),
        .nmi_active_out  (nmi_active)  // Plumbed from FSM
    );

    cpu_decoder dec_inst (
        .inst_reg        (inst_reg), 
        .addr_mode       (addr_mode),
        .extra_cycles    (extra_cycles), 
        .alu_op          (alu_op), 
        .dest_reg        (dest_reg)
    );

endmodule