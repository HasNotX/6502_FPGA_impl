module MOS_6502_CPU (
    input        clk,
    input        reset,
    inout  [7:0] data_bus,
    output reg [15:0] address_bus,
    output       read_write_n
);

// ── Internal wires from FSM ───────────────────────────────────
wire [15:0] PC;
wire [7:0]  inst_reg;
wire [7:0]  accum;
wire [7:0]  X;
wire [7:0]  Y;
wire [7:0]  s_pointer;
wire [2:0]  bus_sel;
wire [2:0]  addr_sel;
wire [7:0]  s_reg;
wire [7:0]  operand_lo;
wire [7:0]  operand_hi;

// ── Decoder wires ─────────────────────────────────────────────
wire [3:0]  addr_mode;
wire [1:0]  extra_cycles;
wire [3:0]  alu_op;
wire [1:0]  dest_reg;
wire        is_store;
wire [15:0] effective_addr;
wire        addr_ready;
wire [7:0]  ptr_lo;
wire [7:0]  ptr_hi;

// ── RAM wire ──────────────────────────────────────────────────
wire [7:0]  mem_q;

// ── Bus logic ─────────────────────────────────────────────────
reg  [7:0]  data_out;
reg  [7:0]  internal_bus;
reg  [15:0] operand_addr;

// single data_bus driver
assign data_bus = (!read_write_n) ? data_out : 8'bz;

// Internal bus mux
always @(*) begin
    case (bus_sel)
        3'b000:  internal_bus = accum;
        3'b001:  internal_bus = X;
        3'b010:  internal_bus = Y;
        default: internal_bus = 8'h00;
    endcase
end

// operand address with index register offset
always @(*) begin
    case (addr_mode)
        4'd4:    operand_addr = effective_addr + {8'h00, X};   // ZEROPAGE_X
        4'd5:    operand_addr = effective_addr + {8'h00, X};   // ABSOLUTE_X
        4'd6:    operand_addr = effective_addr + {8'h00, Y};   // ABSOLUTE_Y
        4'd7:    operand_addr = {8'h00, operand_lo + X};
        default: operand_addr = effective_addr;
    endcase
end

reg  [15:0] saved_ptr_addr;

// Capture pointer address while it's stable during S_PTR_LO_WAIT
always @(posedge clk) begin
    if (fsm_inst.state == 4'd10)   // S_PTR_LO_WAIT — address bus = ADDR_OP = ptr base
        saved_ptr_addr <= operand_addr;
end


// ── Address bus mux ───────────────────────────────────────────
localparam ADDR_PC    = 3'd0,
           ADDR_OP    = 3'd1,
           ADDR_STACK = 3'd2,
           ADDR_VEC   = 3'd3,
           ADDR_PTR   = 3'd4;

always @(*) begin
    case (addr_sel)
        ADDR_PC:    address_bus = PC;
        ADDR_OP:    address_bus = operand_addr;
        ADDR_STACK: address_bus = {8'h01, s_pointer};
        ADDR_VEC:   address_bus = 16'hFFFC;
        ADDR_PTR: begin
				 if (fsm_inst.state == 4'd11 || fsm_inst.state == 4'd12)
					  address_bus = {8'h00, saved_ptr_addr[7:0] + 8'h01};  // zero-page wrap
				 else
					  address_bus = {ptr_hi, ptr_lo} +
										 (addr_mode == 4'd8 ? {8'h00, Y} : 16'h0000);
		end
        default:    address_bus = PC;
    endcase
end

// ── FSM instantiation ─────────────────────────────────────────
cpu_fsm fsm_inst (
    .clk             (clk),
    .reset           (reset),
    .data_in         (mem_q),
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
    .bus_sel         (bus_sel),
    .read_write_n    (read_write_n),
    .addr_sel        (addr_sel),
    .s_reg           (s_reg),
    .operand_lo      (operand_lo),
    .operand_hi      (operand_hi),
    .ptr_lo          (ptr_lo),
    .ptr_hi          (ptr_hi)
);

// ── Decoder instantiation ─────────────────────────────────────
cpu_decoder decoder_inst (
    .inst_reg      (inst_reg),
    .operand_lo    (operand_lo),
    .operand_hi    (operand_hi),
    .addr_mode     (addr_mode),
    .extra_cycles  (extra_cycles),
    .alu_op        (alu_op),
    .dest_reg      (dest_reg),
    .is_store      (is_store),
    .effective_addr(effective_addr),
    .addr_ready    (addr_ready)
);

// ── RAM instantiation ─────────────────────────────────────────
ram ram_inst (
    .address (address_bus),
    .clock   (clk),
    .data    (data_out),
    .wren    (!read_write_n),
    .q       (mem_q)
);

endmodule