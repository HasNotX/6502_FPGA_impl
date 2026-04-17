module cpu_decoder (
    input      [7:0]  inst_reg,
    output reg [3:0]  addr_mode,
    output reg [1:0]  extra_cycles,
    output reg [3:0]  alu_op,
    output reg [1:0]  dest_reg
);

localparam ALU_PASS = 4'd0, ALU_ADD = 4'd1, ALU_SUB = 4'd2,
           ALU_AND  = 4'd3, ALU_ASL = 4'd4, ALU_BIT = 4'd5, ALU_CMP = 4'd6;

localparam DEST_A = 2'd0, DEST_X = 2'd1, DEST_Y = 2'd2, DEST_NONE = 2'd3;

localparam MODE_IMPLICIT = 4'd0, MODE_IMMEDIATE = 4'd1, MODE_ZEROPAGE = 4'd2,
           MODE_ABSOLUTE = 4'd3, MODE_ZEROPAGE_X = 4'd4, MODE_ABSOLUTE_X = 4'd5,
           MODE_ABSOLUTE_Y = 4'd6, MODE_INDIRECT_X = 4'd7, MODE_INDIRECT_Y = 4'd8,
           MODE_ACCUMULATOR = 4'd9, MODE_RELATIVE = 4'd10;

always @(*) begin
    addr_mode    = MODE_IMPLICIT;
    extra_cycles = 2'd0;
    alu_op       = ALU_PASS;
    dest_reg     = DEST_A;

    case (inst_reg)
	 
			//JMP 
			// In cpu_decoder, add to case statement:
			8'h4C: begin  // JMP Absolute
				 addr_mode    = MODE_ABSOLUTE;
				 extra_cycles = 2'd3;   // needs 2 operand bytes
				 dest_reg     = DEST_NONE;
				 alu_op       = ALU_PASS;
			end
			
        // LDA
        8'hA9: begin addr_mode = MODE_IMMEDIATE;  extra_cycles = 2'd1; end
        8'hA5: begin addr_mode = MODE_ZEROPAGE;   extra_cycles = 2'd2; end
        8'hAD: begin addr_mode = MODE_ABSOLUTE;   extra_cycles = 2'd3; end
        8'hB5: begin addr_mode = MODE_ZEROPAGE_X; extra_cycles = 2'd2; end
        8'hBD: begin addr_mode = MODE_ABSOLUTE_X; extra_cycles = 2'd3; end
        8'hB9: begin addr_mode = MODE_ABSOLUTE_Y; extra_cycles = 2'd3; end
        8'hA1: begin addr_mode = MODE_INDIRECT_X; extra_cycles = 2'd1; end
        8'hB1: begin addr_mode = MODE_INDIRECT_Y; extra_cycles = 2'd1; end
        
        // LDX / LDY
        8'hA2: begin addr_mode = MODE_IMMEDIATE; extra_cycles = 2'd1; dest_reg = DEST_X; end
        8'hA0: begin addr_mode = MODE_IMMEDIATE; extra_cycles = 2'd1; dest_reg = DEST_Y; end
        
        // CMP
        8'hC9: begin addr_mode = MODE_IMMEDIATE;  alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd1; end
        8'hC5: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hD5: begin addr_mode = MODE_ZEROPAGE_X; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hCD: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'hDD: begin addr_mode = MODE_ABSOLUTE_X; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'hD9: begin addr_mode = MODE_ABSOLUTE_Y; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'hC1: begin addr_mode = MODE_INDIRECT_X; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd1; end
        8'hD1: begin addr_mode = MODE_INDIRECT_Y; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd1; end

        // Set/Clear Instructions
        8'h18, 8'h38, 8'hD8, 8'hF8, 8'h58, 8'h78, 8'hB8: begin
            addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE;
        end
        default: begin dest_reg = DEST_NONE; end
    endcase
end
endmodule