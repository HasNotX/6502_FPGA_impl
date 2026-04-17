module MOS_6502_CPU (
    input clk, reset,
    inout [7:0] data_bus,
    output reg [15:0] address_bus,
    output read_write_n
);

wire [15:0] PC;
wire [7:0] inst_reg, accum, X, Y, s_pointer, s_reg, operand_lo, operand_hi, ptr_lo, ptr_hi;
wire [3:0] addr_mode, alu_op;
wire [1:0] extra_cycles, dest_reg;
wire [2:0] addr_sel;
wire [7:0] mem_q;

assign read_write_n = 1'b1; // Logic for this test is Read-Only
// This makes the internal memory data visible on the external data_bus for the TB
assign data_bus = (read_write_n) ? mem_q : 8'bz; 

// Address Generation Logic
reg [15:0] eff_addr;
always @(*) begin
    case (addr_mode)
        4'd2: eff_addr = {8'h00, operand_lo}; // ZP
        4'd4: eff_addr = {8'h00, operand_lo + X}; // ZPX
        4'd3: eff_addr = {operand_hi, operand_lo}; // ABS
        4'd5: eff_addr = {operand_hi, operand_lo} + {8'h00, X}; // ABSX
        4'd6: eff_addr = {operand_hi, operand_lo} + {8'h00, Y}; // ABSY
        4'd7: eff_addr = {8'h00, operand_lo + X}; // (IND, X)
        4'd8: eff_addr = {8'h00, operand_lo};     // (IND), Y
        default: eff_addr = PC;
    endcase
end

always @(*) begin
    case (addr_sel)
        3'd0: address_bus = PC;
        3'd1: address_bus = eff_addr;
        3'd3: address_bus = (fsm_inst.state == 5'd27 || fsm_inst.state == 5'd28) ? 16'hFFFD : 16'hFFFC;
        3'd4: begin 
            if (addr_mode == 4'd8) address_bus = {ptr_hi, ptr_lo} + {8'h00, Y};
            else address_bus = {ptr_hi, ptr_lo};
        end
        default: address_bus = PC;
    endcase
end

// Instance name is now exactly 'fsm_inst' to match the Testbench
cpu_fsm fsm_inst (
    .clk(clk), .reset(reset), .data_in(mem_q), .extra_cycles_in(extra_cycles), 
    .alu_op_in(alu_op), .dest_reg_in(dest_reg), .addr_mode_in(addr_mode),
    .PC(PC), .inst_reg(inst_reg), .accum(accum), .X(X), .Y(Y), 
    .s_pointer(s_pointer), .s_reg(s_reg), .operand_lo(operand_lo), 
    .operand_hi(operand_hi), .addr_sel(addr_sel), .ptr_lo(ptr_lo), .ptr_hi(ptr_hi)
);

cpu_decoder dec_inst (
    .inst_reg(inst_reg), .addr_mode(addr_mode), .extra_cycles(extra_cycles), 
    .alu_op(alu_op), .dest_reg(dest_reg)
);

ram mem_inst (
    .address(address_bus), .clock(clk), .data(data_bus), .wren(1'b0), .q(mem_q)
);

endmodule