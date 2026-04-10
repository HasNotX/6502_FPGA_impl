module cpu_decoder (
    input      [7:0]  inst_reg,
    input      [7:0]  operand_lo,
    input      [7:0]  operand_hi,
    output reg [2:0]  addr_mode,
    output reg [1:0]  extra_cycles,
    output reg [3:0]  alu_op,
    output reg [1:0]  dest_reg,
    output reg        is_store,
    output reg [15:0] effective_addr,
    output reg        addr_ready
);

localparam ALU_PASS = 4'd0,
           ALU_ADD  = 4'd1,
           ALU_SUB  = 4'd2;

localparam DEST_A = 2'd0,
           DEST_X = 2'd1,
           DEST_Y = 2'd2;

localparam MODE_IMPLICIT   = 3'd0,
           MODE_IMMEDIATE  = 3'd1,
           MODE_ZEROPAGE   = 3'd2,
           MODE_ABSOLUTE   = 3'd3,
           MODE_ZEROPAGE_X = 3'd4,
           MODE_ABSOLUTE_X = 3'd5,
           MODE_ABSOLUTE_Y = 3'd6;

// ── Opcode decode ─────────────────────────────────────────────
always @(*) begin
    addr_mode    = MODE_IMPLICIT;
    extra_cycles = 2'd0;
    alu_op       = ALU_PASS;
    dest_reg     = DEST_A;
    is_store     = 1'b0;

    case (inst_reg)
        8'hA9: begin   // LDA immediate
            addr_mode    = MODE_IMMEDIATE;
            extra_cycles = 2'd1;
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end
        8'hA5: begin   // LDA zero page
            addr_mode    = MODE_ZEROPAGE;
            extra_cycles = 2'd2;
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end
        8'hAD: begin   // LDA absolute
            addr_mode    = MODE_ABSOLUTE;
            extra_cycles = 2'd3;
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end
        8'hB5: begin   // LDA zero page,X
            addr_mode    = MODE_ZEROPAGE_X;
            extra_cycles = 2'd2;
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end
        8'hBD: begin   // LDA absolute,X
            addr_mode    = MODE_ABSOLUTE_X;
            extra_cycles = 2'd3;
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end
        8'hB9: begin   // LDA absolute,Y
            addr_mode    = MODE_ABSOLUTE_Y;
            extra_cycles = 2'd3;
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end
		  8'hA1: begin   // LDA Indirect, X
            addr_mode    = MODE_INDIRECT_X;
            extra_cycles = 2'd3;
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end
		  8'hB1: begin   // LDA Indirect, Y
            addr_mode    = MODE_INDIRECT_Y;
            extra_cycles = 2'd3;
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end
    endcase
end

// ── Effective address calculation ─────────────────────────────
always @(*) begin
    effective_addr = 16'h0000;
    addr_ready     = 1'b0;

    case (addr_mode)
        MODE_IMMEDIATE: begin
            effective_addr = 16'h0000;
            addr_ready     = 1'b1;
        end
        MODE_ZEROPAGE: begin
            effective_addr = {8'h00, operand_lo};
            addr_ready     = 1'b1;
        end
        MODE_ABSOLUTE: begin
            effective_addr = {operand_hi, operand_lo};
            addr_ready     = 1'b1;
        end
        MODE_ZEROPAGE_X: begin
            effective_addr = {8'h00, operand_lo};  // X added in top module
            addr_ready     = 1'b1;
        end
        MODE_ABSOLUTE_X: begin
            effective_addr = {operand_hi, operand_lo};  // X added in top module
            addr_ready     = 1'b1;
        end
        MODE_ABSOLUTE_Y: begin
            effective_addr = {operand_hi, operand_lo};  // Y added in top module
            addr_ready     = 1'b1;
        end
		  MODE_INDIRECT_X: begin
            effective_addr = {operand_hi, operand_lo};  // Y added in top module
            addr_ready     = 1'b1;
        end
        MODE_IMPLICIT: begin
            effective_addr = 16'h0000;
            addr_ready     = 1'b0;
        end
    endcase
end

endmodule