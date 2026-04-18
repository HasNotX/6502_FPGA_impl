module cpu_fsm (
    input clk, reset,
    input [7:0] data_in,
    input [1:0] extra_cycles_in,
    input [3:0] alu_op_in,
    input [1:0] dest_reg_in,
    input [3:0] addr_mode_in,
    output reg [15:0] PC,
    output reg [7:0] inst_reg, accum, X, Y, s_pointer, s_reg,
    output reg [7:0] operand_lo, operand_hi,
    output reg [2:0] addr_sel,
    output reg [7:0] ptr_lo, ptr_hi
);

reg [4:0] state;
localparam S_FETCH             = 5'd0,
           S_FETCH_WAIT        = 5'd7,
           S_FETCH2            = 5'd1,
           S_DECODE            = 5'd2,
           S_OPERAND_LO        = 5'd5,
           S_OPERAND_WAIT      = 5'd8,
           S_OPERAND_HI        = 5'd6,
           S_EXECUTE           = 5'd3,
           S_WRITEBACK_WAIT    = 5'd15,
           S_WRITEBACK         = 5'd4,
           S_PTR_LO_WAIT       = 5'd10,
           S_PTR_LO            = 5'd9,
           S_PTR_HI_WAIT       = 5'd12,
           S_PTR_HI            = 5'd11,
           S_INDIRECT_WAIT     = 5'd14,
           S_INDIRECT_EXEC     = 5'd13,
           S_RESET_VEC_LO_WAIT = 5'd25,
           S_RESET_VEC_LO      = 5'd26,
           S_RESET_VEC_HI_WAIT = 5'd27,
           S_RESET_VEC_HI      = 5'd28;

// Helper macro-style inline ALU via named block
// We use a single always block with named begin/end blocks per call site

always @(posedge clk) begin
    if (reset) begin
        state     <= S_RESET_VEC_LO_WAIT;
        PC        <= 16'hFFFC;
        accum     <= 8'h00; X <= 8'h00; Y <= 8'h00;
        s_reg     <= 8'h00;
        s_pointer <= 8'hFD;
    end else begin
        case (state)

            S_FETCH:      state <= S_FETCH_WAIT;
            S_FETCH_WAIT: state <= S_FETCH2;
            S_FETCH2: begin
                inst_reg <= data_in;
                PC       <= PC + 16'd1;
                state    <= S_DECODE;
            end

            S_DECODE: state <= (extra_cycles_in > 0) ? S_OPERAND_LO : S_EXECUTE;

            S_OPERAND_LO: begin
                operand_lo <= data_in;
                PC         <= PC + 16'd1;
                state      <= (extra_cycles_in >= 3) ? S_OPERAND_WAIT : S_EXECUTE;
            end
            S_OPERAND_WAIT: state <= S_OPERAND_HI;
            S_OPERAND_HI: begin
                operand_hi <= data_in;
                PC         <= PC + 16'd1;
                state      <= S_EXECUTE;
            end

            S_EXECUTE: begin
                if (addr_mode_in == 4'd1) begin : exe_imm
                    reg [8:0] fr; reg [7:0] r;
                    case (alu_op_in)
                        4'd1:    fr = {1'b0,accum} + {1'b0,operand_lo} + {8'h00,s_reg[0]};
                        4'd3:    fr = {1'b0, accum & operand_lo};
                        4'd9:    fr = {1'b0, accum | operand_lo}; // ORA
                        4'd10:   fr = {1'b0, accum ^ operand_lo}; // EOR
                        4'd6:    fr = {1'b0,accum} - {1'b0,operand_lo};
                        4'd7:    fr = {1'b0,operand_lo} + 9'd1;
                        4'd8:    fr = {1'b0,operand_lo} - 9'd1;
                        default: fr = {1'b0,operand_lo};
                    endcase
                    r = fr[7:0];
                    if (alu_op_in == 4'd6) begin // CMP
                        s_reg[0] <= (accum >= operand_lo);
                        s_reg[1] <= (accum == operand_lo);
                        s_reg[7] <= r[7];
                    end else begin
                        if (dest_reg_in == 2'd0) accum <= r;
                        if (dest_reg_in == 2'd1) X     <= r;
                        if (dest_reg_in == 2'd2) Y     <= r;
                        s_reg[1] <= (r == 8'h00);
                        s_reg[7] <= r[7];
                        if (alu_op_in == 4'd1) s_reg[0] <= fr[8];
                    end
                    state <= S_FETCH;
                end else if (addr_mode_in == 4'd0) begin : exe_impl
                    // Implicit mode - inline ALU for register ops
                    reg [8:0] fr2; reg [7:0] r2; reg [7:0] src;
                    case (inst_reg)
                        8'h18: s_reg[0] <= 1'b0; // CLC
                        8'h38: s_reg[0] <= 1'b1; // SEC
                        8'h58: s_reg[2] <= 1'b0; // CLI
                        8'h78: s_reg[2] <= 1'b1; // SEI
                        8'hD8: s_reg[3] <= 1'b0; // CLD
                        8'hF8: s_reg[3] <= 1'b1; // SED
                        8'hB8: s_reg[6] <= 1'b0; // CLV
                        8'h9A: s_pointer <= X;   // TXS
                        8'hE8, 8'hCA,
                        8'hC8, 8'h88,
                        8'hAA, 8'hA8,
                        8'h8A, 8'h98,
                        8'hBA: begin
                            // Select source register
                            case (inst_reg)
                                8'hE8: src = X;
                                8'hCA: src = X;
                                8'hC8: src = Y;
                                8'h88: src = Y;
                                8'h8A: src = X;
                                8'h98: src = Y;
                                8'hBA: src = s_pointer;
                                default: src = accum; // TAX, TAY
                            endcase
                            // Compute result
                            case (alu_op_in)
                                4'd7:    fr2 = {1'b0,src} + 9'd1; // INC
                                4'd8:    fr2 = {1'b0,src} - 9'd1; // DEC
                                default: fr2 = {1'b0,src};        // PASS
                            endcase
                            r2 = fr2[7:0];
                            // Write destination
                            if (dest_reg_in == 2'd0) accum <= r2;
                            if (dest_reg_in == 2'd1) X     <= r2;
                            if (dest_reg_in == 2'd2) Y     <= r2;
                            s_reg[1] <= (r2 == 8'h00);
                            s_reg[7] <= r2[7];
                        end
                    endcase
                    state <= S_FETCH;
                end else if (inst_reg == 8'h4C) begin // JMP Absolute
                    PC    <= {operand_hi, operand_lo};
                    state <= S_FETCH;
                end else begin
                    state <= (addr_mode_in >= 4'd7) ? S_PTR_LO_WAIT : S_WRITEBACK_WAIT;
                end
            end

            S_WRITEBACK_WAIT: state <= S_WRITEBACK;

            S_WRITEBACK: begin : wb
                reg [8:0] fr3; reg [7:0] r3;
                case (alu_op_in)
                    4'd1:    fr3 = {1'b0,accum} + {1'b0,data_in} + {8'h00,s_reg[0]};
                    4'd3:    fr3 = {1'b0, accum & data_in};
                    4'd9:    fr3 = {1'b0, accum | data_in}; // ORA
                    4'd10:   fr3 = {1'b0, accum ^ data_in}; // EOR
                    4'd6:    fr3 = {1'b0,accum} - {1'b0,data_in};
                    4'd7:    fr3 = {1'b0,data_in} + 9'd1;
                    4'd8:    fr3 = {1'b0,data_in} - 9'd1;
                    default: fr3 = {1'b0,data_in};
                endcase
                r3 = fr3[7:0];
                if (alu_op_in == 4'd6) begin
                    s_reg[0] <= (accum >= data_in);
                    s_reg[1] <= (accum == data_in);
                    s_reg[7] <= r3[7];
                end else begin
                    if (dest_reg_in == 2'd0) accum <= r3;
                    if (dest_reg_in == 2'd1) X     <= r3;
                    if (dest_reg_in == 2'd2) Y     <= r3;
                    s_reg[1] <= (r3 == 8'h00);
                    s_reg[7] <= r3[7];
                    if (alu_op_in == 4'd1) s_reg[0] <= fr3[8];
                end
                state <= S_FETCH;
            end

            S_PTR_LO_WAIT: state <= S_PTR_LO;
            S_PTR_LO: begin ptr_lo <= data_in; state <= S_PTR_HI_WAIT; end
            S_PTR_HI_WAIT: state <= S_PTR_HI;
            S_PTR_HI: begin ptr_hi <= data_in; state <= S_INDIRECT_WAIT; end
            S_INDIRECT_WAIT: state <= S_INDIRECT_EXEC;

            S_INDIRECT_EXEC: begin : ind_exec
                reg [8:0] fr4; reg [7:0] r4;
                case (alu_op_in)
                    4'd1:    fr4 = {1'b0,accum} + {1'b0,data_in} + {8'h00,s_reg[0]};
                    4'd3:    fr4 = {1'b0, accum & data_in};
                    4'd9:    fr4 = {1'b0, accum | data_in}; // ORA
                    4'd10:   fr4 = {1'b0, accum ^ data_in}; // EOR
                    4'd6:    fr4 = {1'b0,accum} - {1'b0,data_in};
                    4'd7:    fr4 = {1'b0,data_in} + 9'd1;
                    4'd8:    fr4 = {1'b0,data_in} - 9'd1;
                    default: fr4 = {1'b0,data_in};
                endcase
                r4 = fr4[7:0];
                if (alu_op_in == 4'd6) begin
                    s_reg[0] <= (accum >= data_in);
                    s_reg[1] <= (accum == data_in);
                    s_reg[7] <= r4[7];
                end else begin
                    if (dest_reg_in == 2'd0) accum <= r4;
                    if (dest_reg_in == 2'd1) X     <= r4;
                    if (dest_reg_in == 2'd2) Y     <= r4;
                    s_reg[1] <= (r4 == 8'h00);
                    s_reg[7] <= r4[7];
                    if (alu_op_in == 4'd1) s_reg[0] <= fr4[8];
                end
                state <= S_FETCH;
            end

            S_RESET_VEC_LO_WAIT: state <= S_RESET_VEC_LO;
            S_RESET_VEC_LO: begin PC[7:0]  <= data_in; state <= S_RESET_VEC_HI_WAIT; end
            S_RESET_VEC_HI_WAIT: state <= S_RESET_VEC_HI;
            S_RESET_VEC_HI: begin PC[15:8] <= data_in; state <= S_FETCH; end

            default: state <= S_FETCH;
        endcase
    end
end

always @(*) begin
    case (state)
        S_FETCH, S_FETCH_WAIT, S_FETCH2,
        S_OPERAND_LO, S_OPERAND_WAIT, S_OPERAND_HI:
            addr_sel = 3'd0;
        S_WRITEBACK_WAIT, S_WRITEBACK, S_PTR_LO_WAIT:
            addr_sel = 3'd1;
        S_PTR_HI_WAIT, S_INDIRECT_WAIT, S_INDIRECT_EXEC:
            addr_sel = 3'd4;
        S_RESET_VEC_LO_WAIT, S_RESET_VEC_LO,
        S_RESET_VEC_HI_WAIT, S_RESET_VEC_HI:
            addr_sel = 3'd3;
        default: addr_sel = 3'd0;
    endcase
end

endmodule