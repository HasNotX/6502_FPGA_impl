module cpu_fsm (
    input clk, reset,
    input wire cpu_ce,
    input [7:0] data_in,
    input [1:0] extra_cycles_in,
    input [3:0] alu_op_in,
    input [1:0] dest_reg_in,
    input [3:0] addr_mode_in,
    output reg [15:0] PC,
    output reg [7:0] inst_reg, accum, X, Y, s_pointer, s_reg,
    output reg [7:0] operand_lo, operand_hi,
    output reg [2:0] addr_sel,
    output reg [7:0] ptr_lo, ptr_hi,
    output reg write_en,
    output reg [7:0] push_data,
	 output reg [5:0] state
);

reg [7:0] res;


localparam S_FETCH             = 6'd0,
           S_FETCH_WAIT        = 6'd7,
           S_FETCH2            = 6'd1,
           S_DECODE            = 6'd2,
           S_OPERAND_LO        = 6'd5,
           S_OPERAND_WAIT      = 6'd8,
           S_OPERAND_HI        = 6'd6,
           S_EXECUTE           = 6'd3,
           S_WRITEBACK_WAIT    = 6'd15,
           S_WRITEBACK         = 6'd4,
           S_PTR_LO_WAIT       = 6'd10,
           S_PTR_LO            = 6'd9,
           S_PTR_HI_WAIT       = 6'd12,
           S_PTR_HI            = 6'd11,
           S_INDIRECT_WAIT     = 6'd14,
           S_INDIRECT_EXEC     = 6'd13,
           S_RESET_VEC_LO_WAIT = 6'd25,
           S_RESET_VEC_LO      = 6'd26,
           S_RESET_VEC_HI_WAIT = 6'd27,
           S_RESET_VEC_HI      = 6'd28,
           S_PUSH_WAIT         = 6'd16,
           S_PUSH_EXEC         = 6'd17,
           S_PULL_WAIT         = 6'd18,
           S_PULL_EXEC         = 6'd19,
           S_RMW_READ          = 6'd20,
           S_RMW_WRITE         = 6'd21,
           S_RMW_WAIT          = 6'd22,
           S_STORE_WAIT        = 6'd23,
           S_STORE_EXEC        = 6'd24,
           S_STORE_IND_WAIT    = 6'd29,
           S_STORE_IND_EXEC    = 6'd30,
           S_JSR_PUSH_HI       = 6'd31,
           S_JSR_PUSH_LO       = 6'd32,
           S_JSR_JUMP          = 6'd33,
           S_RTS_INC_SP        = 6'd34,
           S_RTS_PULL_LO       = 6'd35,
           S_RTS_PULL_LO_WAIT  = 6'd36,
           S_RTS_PULL_HI       = 6'd37,
           S_RTS_PULL_HI_WAIT  = 6'd38,
           S_RTS_INC           = 6'd39,
           // JMP indirect
           S_JMP_IND_LO_WAIT   = 6'd40,
           S_JMP_IND_LO        = 6'd41,
           S_JMP_IND_HI_WAIT   = 6'd42,
           S_JMP_IND_HI        = 6'd43,
           // RTI
           S_RTI_PULL_SR_WAIT  = 6'd44,
           S_RTI_PULL_SR       = 6'd45,
           S_RTI_PULL_PCL_WAIT = 6'd46,
           S_RTI_PULL_PCL      = 6'd47,
           S_RTI_PULL_PCH_WAIT = 6'd48,
           S_RTI_PULL_PCH      = 6'd49,
           // ── BRK ─────────────────────────────────────────────
           // Push PCH, PCL, SR|$10, then load IRQ vector $FFFE/$FFFF
           S_BRK_PUSH_PCH      = 6'd50,
           S_BRK_PUSH_PCL      = 6'd51,
           S_BRK_PUSH_SR       = 6'd52,
           S_BRK_VEC_LO_WAIT   = 6'd53,
           S_BRK_VEC_LO        = 6'd54,
           S_BRK_VEC_HI_WAIT   = 6'd55,
           S_BRK_VEC_HI        = 6'd56;

// Addressing mode constants (must match decoder)
localparam MODE_IMPLICIT    = 4'd0,
           MODE_IMMEDIATE   = 4'd1,
           MODE_ZEROPAGE    = 4'd2,
           MODE_ABSOLUTE    = 4'd3,
           MODE_ZEROPAGE_X  = 4'd4,
           MODE_ABSOLUTE_X  = 4'd5,
           MODE_ABSOLUTE_Y  = 4'd6,
           MODE_INDIRECT_X  = 4'd7,
           MODE_INDIRECT_Y  = 4'd8,
           MODE_ACCUMULATOR = 4'd9,
           MODE_RELATIVE    = 4'd10,
           MODE_ZEROPAGE_Y  = 4'd11,
           MODE_INDIRECT_ABS= 4'd12;

// JSR return address = PC-1 (stable during push states)
wire [15:0] jsr_ret_addr = PC - 16'd1;

// BRK pushes PC+2 from the opcode fetch point.
// After S_FETCH2 PC has already advanced past the opcode (+1).
// BRK is a 2-byte instruction (opcode + padding byte) so the
// "return" address pushed is opcode_addr + 2 = current PC + 1.
wire [15:0] brk_ret_addr = PC + 16'd1;

wire is_store = (inst_reg == 8'h85 || inst_reg == 8'h95 ||
                 inst_reg == 8'h8D || inst_reg == 8'h9D ||
                 inst_reg == 8'h99 || inst_reg == 8'h81 ||
                 inst_reg == 8'h91 || inst_reg == 8'h86 ||
                 inst_reg == 8'h96 || inst_reg == 8'h8E ||
                 inst_reg == 8'h84 || inst_reg == 8'h94 ||
                 inst_reg == 8'h8C);

wire is_indirect_mode = (addr_mode_in == MODE_INDIRECT_X ||
                         addr_mode_in == MODE_INDIRECT_Y);

function branch_taken;
    input [7:0] opcode;
    input [7:0] sr;
    case (opcode)
        8'h90: branch_taken = ~sr[0];
        8'hB0: branch_taken =  sr[0];
        8'hF0: branch_taken =  sr[1];
        8'hD0: branch_taken = ~sr[1];
        8'h30: branch_taken =  sr[7];
        8'h10: branch_taken = ~sr[7];
        8'h50: branch_taken = ~sr[6];
        8'h70: branch_taken =  sr[6];
        default: branch_taken = 1'b0;
    endcase
endfunction

always @(posedge clk) begin
    if (reset) begin
        state     <= S_RESET_VEC_LO_WAIT;
        PC        <= 16'hFFFC;
        accum     <= 8'h00; X <= 8'h00; Y <= 8'h00;
        s_reg     <= 8'h00;
        s_pointer <= 8'hFD;
        write_en  <= 1'b0;
        push_data <= 8'h00;
    end else if(cpu_ce) begin  // FSM only runs when accumulator overflows (~1.79 MHz)
        case (state)

            // ─────────────────────────────────────────────────────────────
            // FETCH
            // ─────────────────────────────────────────────────────────────
            S_FETCH: begin
                write_en <= 1'b0;
                state    <= S_FETCH_WAIT;
            end
            S_FETCH_WAIT: state <= S_FETCH2;
            S_FETCH2: begin
                inst_reg <= data_in;
                PC       <= PC + 16'd1;
                state    <= S_DECODE;
            end

            // ─────────────────────────────────────────────────────────────
            // DECODE / OPERAND FETCH
            // ─────────────────────────────────────────────────────────────
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

            // ─────────────────────────────────────────────────────────────
            // EXECUTE
            // ─────────────────────────────────────────────────────────────
            S_EXECUTE: begin

                // ── IMMEDIATE (mode 1) ────────────────────────────────────
                if (addr_mode_in == MODE_IMMEDIATE) begin : exe_imm
                    reg [8:0] fr; reg [7:0] r; reg [7:0] cmp_src;
                    case (inst_reg)
                        8'hE0:   cmp_src = X;
                        8'hC0:   cmp_src = Y;
                        default: cmp_src = accum;
                    endcase
                    case (alu_op_in)
                        4'd1:    fr = {1'b0,accum} + {1'b0,operand_lo} + {8'h00,s_reg[0]};
                        4'd2:    fr = {1'b0,accum} + {1'b0,~operand_lo} + {8'h00,s_reg[0]};
                        4'd3:    fr = {1'b0, accum & operand_lo};
                        4'd9:    fr = {1'b0, accum | operand_lo};
                        4'd10:   fr = {1'b0, accum ^ operand_lo};
                        4'd6:    fr = {1'b0, cmp_src} - {1'b0, operand_lo};
                        4'd7:    fr = {1'b0, operand_lo} + 9'd1;
                        4'd8:    fr = {1'b0, operand_lo} - 9'd1;
                        default: fr = {1'b0, operand_lo};
                    endcase
                    r = fr[7:0];
                    if (alu_op_in == 4'd6) begin
                        s_reg[0] <= (cmp_src >= operand_lo);
                        s_reg[1] <= (r == 8'h00);
                        s_reg[7] <= r[7];
                    end else begin
                        if (dest_reg_in == 2'd0) accum <= r;
                        if (dest_reg_in == 2'd1) X     <= r;
                        if (dest_reg_in == 2'd2) Y     <= r;
                        s_reg[1] <= (r == 8'h00);
                        s_reg[7] <= r[7];
                        if (alu_op_in == 4'd1 || alu_op_in == 4'd2)
                            s_reg[0] <= fr[8];
                    end
                    state <= S_FETCH;

                // ── ACCUMULATOR (mode 9) ──────────────────────────────────
                end else if (addr_mode_in == MODE_ACCUMULATOR) begin
                    case (alu_op_in)
                        4'd11: begin s_reg[0] <= accum[0]; res = {1'b0, accum[7:1]}; end
                        4'd12: begin res = {accum[6:0], s_reg[0]}; s_reg[0] <= accum[7]; end
                        4'd13: begin res = {s_reg[0], accum[7:1]}; s_reg[0] <= accum[0]; end
                        4'd4:  begin s_reg[0] <= accum[7]; res = {accum[6:0], 1'b0}; end
                        default: res = accum;
                    endcase
                    accum    <= res;
                    s_reg[1] <= (res == 8'h00);
                    s_reg[7] <= res[7];
                    state    <= S_FETCH;

                // ── IMPLICIT (mode 0) ─────────────────────────────────────
                end else if (addr_mode_in == MODE_IMPLICIT) begin : exe_impl
                    reg [8:0] fr2; reg [7:0] r2; reg [7:0] src;
                    case (inst_reg)
                        8'h18: s_reg[0] <= 1'b0;
                        8'h38: s_reg[0] <= 1'b1;
                        8'h58: s_reg[2] <= 1'b0;
                        8'h78: s_reg[2] <= 1'b1;
                        8'hD8: s_reg[3] <= 1'b0;
                        8'hF8: s_reg[3] <= 1'b1;
                        8'hB8: s_reg[6] <= 1'b0;
                        8'h9A: s_pointer <= X;
                        8'h48: begin push_data <= accum; state <= S_PUSH_WAIT; end
                        8'h08: begin push_data <= s_reg; state <= S_PUSH_WAIT; end
                        8'h68, 8'h28: begin
                            s_pointer <= s_pointer + 8'd1;
                            state     <= S_PULL_WAIT;
                        end
                        // ── BRK ($00) ─────────────────────────────────────
                        // Push PCH of (PC+1), set B flag in pushed SR
                        8'h00: begin
                            push_data <= brk_ret_addr[15:8];
                            write_en  <= 1'b1;
                            state     <= S_BRK_PUSH_PCH;
                        end
                        // ── RTS ───────────────────────────────────────────
                        8'h60: begin
                            s_pointer <= s_pointer + 8'd1;
                            state     <= S_RTS_PULL_LO_WAIT;
                        end
                        // ── RTI ───────────────────────────────────────────
                        8'h40: begin
                            s_pointer <= s_pointer + 8'd1;
                            state     <= S_RTI_PULL_SR_WAIT;
                        end
                        8'hE8, 8'hCA,
                        8'hC8, 8'h88,
                        8'hAA, 8'hA8,
                        8'h8A, 8'h98,
                        8'hBA: begin
                            case (inst_reg)
                                8'hE8: src = X;
                                8'hCA: src = X;
                                8'hC8: src = Y;
                                8'h88: src = Y;
                                8'h8A: src = X;
                                8'h98: src = Y;
                                8'hBA: src = s_pointer;
                                default: src = accum;
                            endcase
                            case (alu_op_in)
                                4'd7:    fr2 = {1'b0,src} + 9'd1;
                                4'd8:    fr2 = {1'b0,src} - 9'd1;
                                default: fr2 = {1'b0,src};
                            endcase
                            r2 = fr2[7:0];
                            if (dest_reg_in == 2'd0) accum <= r2;
                            if (dest_reg_in == 2'd1) X     <= r2;
                            if (dest_reg_in == 2'd2) Y     <= r2;
                            s_reg[1] <= (r2 == 8'h00);
                            s_reg[7] <= r2[7];
                        end
                    endcase
                    if (inst_reg != 8'h48 && inst_reg != 8'h08 &&
                        inst_reg != 8'h68 && inst_reg != 8'h28 &&
                        inst_reg != 8'h60 && inst_reg != 8'h40 &&
                        inst_reg != 8'h00)
                        state <= S_FETCH;

                // ── JMP absolute (4C) ─────────────────────────────────────
                end else if (inst_reg == 8'h4C) begin
                    PC    <= {operand_hi, operand_lo};
                    state <= S_FETCH;

                // ── JMP indirect (6C) ─────────────────────────────────────
                end else if (inst_reg == 8'h6C) begin
                    state <= S_JMP_IND_LO_WAIT;

                // ── JSR absolute (20) ─────────────────────────────────────
                end else if (inst_reg == 8'h20) begin
                    push_data <= jsr_ret_addr[15:8];
                    write_en  <= 1'b1;
                    state     <= S_JSR_PUSH_HI;

                // ── BRANCH (mode 10) ──────────────────────────────────────
                end else if (addr_mode_in == MODE_RELATIVE) begin
                    if (branch_taken(inst_reg, s_reg))
                        PC <= PC + {{8{operand_lo[7]}}, operand_lo};
                    state <= S_FETCH;

                // ── STORE instructions ────────────────────────────────────
                end else if (is_store) begin
                    case (inst_reg)
                        8'h86, 8'h96, 8'h8E: push_data <= X;
                        8'h84, 8'h94, 8'h8C: push_data <= Y;
                        default:              push_data <= accum;
                    endcase
                    if (is_indirect_mode)
                        state <= S_PTR_LO_WAIT;
                    else
                        state <= S_STORE_WAIT;

                // ── RMW / READ-MODIFY-WRITE ───────────────────────────────
                end else begin
                    if ((alu_op_in == 4'd7  || alu_op_in == 4'd8  ||
                         alu_op_in == 4'd11 || alu_op_in == 4'd12 ||
                         alu_op_in == 4'd13 || alu_op_in == 4'd4) &&
                         dest_reg_in == 2'd3)
                        state <= is_indirect_mode ? S_PTR_LO_WAIT : S_RMW_WAIT;
                    else
                        state <= is_indirect_mode ? S_PTR_LO_WAIT : S_WRITEBACK_WAIT;
                end
            end // S_EXECUTE

            // ─────────────────────────────────────────────────────────────
            // BRK push sequence
            // Push PCH, PCL of (BRK_addr+2), then SR with B=1, I=1
            // then load IRQ vector from $FFFE/$FFFF
            // ─────────────────────────────────────────────────────────────
            S_BRK_PUSH_PCH: begin
                s_pointer <= s_pointer - 8'd1;
                push_data <= brk_ret_addr[7:0];   // PCL
                write_en  <= 1'b1;
                state     <= S_BRK_PUSH_PCL;
            end
            S_BRK_PUSH_PCL: begin
                s_pointer <= s_pointer - 8'd1;
                push_data <= s_reg | 8'h30;        // SR with B=1 and bit5=1
                write_en  <= 1'b1;
                state     <= S_BRK_PUSH_SR;
            end
            S_BRK_PUSH_SR: begin
                s_pointer <= s_pointer - 8'd1;
                write_en  <= 1'b0;
                s_reg[2]  <= 1'b1;                 // Set I flag in real SR
                s_reg[4]  <= 1'b1;                 // Set B flag in real SR
                state     <= S_BRK_VEC_LO_WAIT;
            end
            S_BRK_VEC_LO_WAIT: state <= S_BRK_VEC_LO;
            S_BRK_VEC_LO: begin
                PC[7:0] <= data_in;                // Load PCL from $FFFE
                state   <= S_BRK_VEC_HI_WAIT;
            end
            S_BRK_VEC_HI_WAIT: state <= S_BRK_VEC_HI;
            S_BRK_VEC_HI: begin
                PC[15:8] <= data_in;               // Load PCH from $FFFF
                state    <= S_FETCH;
            end

            // ─────────────────────────────────────────────────────────────
            // STORE
            // ─────────────────────────────────────────────────────────────
            S_STORE_WAIT:     begin write_en <= 1'b1; state <= S_STORE_EXEC; end
            S_STORE_EXEC:     begin write_en <= 1'b0; state <= S_FETCH;      end

            S_STORE_IND_WAIT: begin write_en <= 1'b1; state <= S_STORE_IND_EXEC; end
            S_STORE_IND_EXEC: begin write_en <= 1'b0; state <= S_FETCH;          end

            // ─────────────────────────────────────────────────────────────
            // PUSH / PULL
            // ─────────────────────────────────────────────────────────────
            S_PUSH_WAIT: begin write_en <= 1'b1; state <= S_PUSH_EXEC; end
            S_PUSH_EXEC: begin
                write_en  <= 1'b0;
                s_pointer <= s_pointer - 8'd1;
                state     <= S_FETCH;
            end

            S_PULL_WAIT: state <= S_PULL_EXEC;
            S_PULL_EXEC: begin
                if (inst_reg == 8'h68) begin
                    accum    <= data_in;
                    s_reg[1] <= (data_in == 8'h00);
                    s_reg[7] <= data_in[7];
                end else begin
                    s_reg <= data_in;
                end
                state <= S_FETCH;
            end

            // ─────────────────────────────────────────────────────────────
            // WRITEBACK
            // ─────────────────────────────────────────────────────────────
            S_WRITEBACK_WAIT: state <= S_WRITEBACK;
            S_WRITEBACK: begin : wb
                reg [8:0] fr3; reg [7:0] r3; reg [7:0] cmp_src;
                case (inst_reg)
                    8'hE4, 8'hEC: cmp_src = X;
                    8'hC4, 8'hCC: cmp_src = Y;
                    default:      cmp_src = accum;
                endcase
                case (alu_op_in)
                    4'd1:    fr3 = {1'b0,accum} + {1'b0,data_in} + {8'h00,s_reg[0]};
                    4'd2:    fr3 = {1'b0,accum} + {1'b0,~data_in} + {8'h00,s_reg[0]};
                    4'd3:    fr3 = {1'b0, accum & data_in};
                    4'd9:    fr3 = {1'b0, accum | data_in};
                    4'd10:   fr3 = {1'b0, accum ^ data_in};
                    4'd6:    fr3 = {1'b0, cmp_src} - {1'b0, data_in};
                    4'd7:    fr3 = {1'b0, data_in} + 9'd1;
                    4'd8:    fr3 = {1'b0, data_in} - 9'd1;
                    default: fr3 = {1'b0, data_in};
                endcase
                if (alu_op_in == 4'd1 || alu_op_in == 4'd2) s_reg[0] <= fr3[8];
                r3 = fr3[7:0];
                if (alu_op_in == 4'd5) begin          // BIT
                    s_reg[7] <= data_in[7];
                    s_reg[6] <= data_in[6];
                    s_reg[1] <= ((accum & data_in) == 8'h00);
                end else if (alu_op_in == 4'd6) begin  // CMP/CPX/CPY
                    s_reg[0] <= (cmp_src >= data_in);
                    s_reg[1] <= (r3 == 8'h00);
                    s_reg[7] <= r3[7];
                end else begin
                    if (dest_reg_in == 2'd0) accum <= r3;
                    if (dest_reg_in == 2'd1) X     <= r3;
                    if (dest_reg_in == 2'd2) Y     <= r3;
                    s_reg[1] <= (r3 == 8'h00);
                    s_reg[7] <= r3[7];
                end
                state <= S_FETCH;
            end

            // ─────────────────────────────────────────────────────────────
            // RMW
            // ─────────────────────────────────────────────────────────────
            S_RMW_WAIT: state <= S_RMW_READ;
            S_RMW_READ: begin : rmw_read
                reg [7:0] rmw_result;
                case (alu_op_in)
                    4'd4:  begin s_reg[0] <= data_in[7]; rmw_result = {data_in[6:0], 1'b0}; end
                    4'd11: begin s_reg[0] <= data_in[0]; rmw_result = {1'b0, data_in[7:1]}; end
                    4'd12: begin rmw_result = {data_in[6:0], s_reg[0]}; s_reg[0] <= data_in[7]; end
                    4'd13: begin rmw_result = {s_reg[0], data_in[7:1]}; s_reg[0] <= data_in[0]; end
                    4'd7:    rmw_result = data_in + 8'd1;
                    4'd8:    rmw_result = data_in - 8'd1;
                    default: rmw_result = data_in;
                endcase
                push_data <= rmw_result;
                s_reg[1]  <= (rmw_result == 8'h00);
                s_reg[7]  <= rmw_result[7];
                write_en  <= 1'b1;
                state     <= S_RMW_WRITE;
            end
            S_RMW_WRITE: begin write_en <= 1'b0; state <= S_FETCH; end

            // ─────────────────────────────────────────────────────────────
            // JSR push sequence
            // ─────────────────────────────────────────────────────────────
            S_JSR_PUSH_HI: begin
                s_pointer <= s_pointer - 8'd1;
                push_data <= jsr_ret_addr[7:0];
                write_en  <= 1'b1;
                state     <= S_JSR_PUSH_LO;
            end
            S_JSR_PUSH_LO: begin
                write_en  <= 1'b0;
                s_pointer <= s_pointer - 8'd1;
                state     <= S_JSR_JUMP;
            end
            S_JSR_JUMP: begin
                PC    <= {operand_hi, operand_lo};
                state <= S_FETCH;
            end

            // ─────────────────────────────────────────────────────────────
            // RTS pull sequence
            // ─────────────────────────────────────────────────────────────
            S_RTS_PULL_LO_WAIT: state <= S_RTS_PULL_LO;
            S_RTS_PULL_LO: begin
                operand_lo <= data_in;
                s_pointer  <= s_pointer + 8'd1;
                state      <= S_RTS_PULL_HI_WAIT;
            end
            S_RTS_PULL_HI_WAIT: state <= S_RTS_PULL_HI;
            S_RTS_PULL_HI: begin
                operand_hi <= data_in;
                state      <= S_RTS_INC;
            end
            S_RTS_INC: begin
                PC    <= {operand_hi, operand_lo} + 16'd1;
                state <= S_FETCH;
            end

            // ─────────────────────────────────────────────────────────────
            // JMP INDIRECT sequence
            // ─────────────────────────────────────────────────────────────
            S_JMP_IND_LO_WAIT: state <= S_JMP_IND_LO;
            S_JMP_IND_LO: begin
                ptr_lo <= data_in;
                state  <= S_JMP_IND_HI_WAIT;
            end
            S_JMP_IND_HI_WAIT: state <= S_JMP_IND_HI;
            S_JMP_IND_HI: begin
                PC    <= {data_in, ptr_lo};
                state <= S_FETCH;
            end

            // ─────────────────────────────────────────────────────────────
            // RTI sequence
            // ─────────────────────────────────────────────────────────────
            S_RTI_PULL_SR_WAIT: state <= S_RTI_PULL_SR;
            S_RTI_PULL_SR: begin
                s_reg     <= data_in;
                s_pointer <= s_pointer + 8'd1;
                state     <= S_RTI_PULL_PCL_WAIT;
            end
            S_RTI_PULL_PCL_WAIT: state <= S_RTI_PULL_PCL;
            S_RTI_PULL_PCL: begin
                operand_lo <= data_in;
                s_pointer  <= s_pointer + 8'd1;
                state      <= S_RTI_PULL_PCH_WAIT;
            end
            S_RTI_PULL_PCH_WAIT: state <= S_RTI_PULL_PCH;
            S_RTI_PULL_PCH: begin
                PC    <= {data_in, operand_lo};
                state <= S_FETCH;
            end

            // ─────────────────────────────────────────────────────────────
            // INDIRECT addressing (for LDA/STA (zp,X) etc.)
            // ─────────────────────────────────────────────────────────────
            S_PTR_LO_WAIT: state <= S_PTR_LO;
            S_PTR_LO: begin ptr_lo <= data_in; state <= S_PTR_HI_WAIT; end
            S_PTR_HI_WAIT: state <= S_PTR_HI;
            S_PTR_HI: begin ptr_hi <= data_in; state <= S_INDIRECT_WAIT; end
            S_INDIRECT_WAIT: state <= S_INDIRECT_EXEC;

            S_INDIRECT_EXEC: begin : ind_exec
                reg [8:0] fr4; reg [7:0] r4;
                if (is_store) begin
                    state <= S_STORE_IND_WAIT;
                end else begin
                    case (alu_op_in)
                        4'd1:    fr4 = {1'b0,accum} + {1'b0,data_in} + {8'h00,s_reg[0]};
                        4'd2:    fr4 = {1'b0,accum} + {1'b0,~data_in} + {8'h00,s_reg[0]};
                        4'd3:    fr4 = {1'b0, accum & data_in};
                        4'd9:    fr4 = {1'b0, accum | data_in};
                        4'd10:   fr4 = {1'b0, accum ^ data_in};
                        4'd6:    fr4 = {1'b0, accum} - {1'b0, data_in};
                        4'd7:    fr4 = {1'b0, data_in} + 9'd1;
                        4'd8:    fr4 = {1'b0, data_in} - 9'd1;
                        default: fr4 = {1'b0, data_in};
                    endcase
                    r4 = fr4[7:0];
                    if (alu_op_in == 4'd1 || alu_op_in == 4'd2) s_reg[0] <= fr4[8];
                    if (alu_op_in == 4'd6) begin
                        s_reg[0] <= (accum >= data_in);
                        s_reg[1] <= (r4 == 8'h00);
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
            end

            // ─────────────────────────────────────────────────────────────
            // RESET VECTOR FETCH
            // ─────────────────────────────────────────────────────────────
            S_RESET_VEC_LO_WAIT: state <= S_RESET_VEC_LO;
            S_RESET_VEC_LO: begin PC[7:0]  <= data_in; state <= S_RESET_VEC_HI_WAIT; end
            S_RESET_VEC_HI_WAIT: state <= S_RESET_VEC_HI;
            S_RESET_VEC_HI: begin PC[15:8] <= data_in; state <= S_FETCH; end

            default: state <= S_FETCH;
        endcase
    end
end

// ─────────────────────────────────────────────────────────────────────────
// ADDRESS SELECT (combinatorial)
// addr_sel encoding:
//   0 = PC
//   1 = eff_addr                   (zeropage / absolute effective address)
//   2 = eff_addr + 1               (high byte of absolute pair)
//   3 = reset/IRQ vector page      (decoded in top-level)
//   4 = {ptr_hi, ptr_lo} [+Y]      (indirect effective address)
//   5 = {8'h01, s_pointer}         (stack page)
// ─────────────────────────────────────────────────────────────────────────
always @(*) begin
    case (state)
        S_JSR_PUSH_HI, S_JSR_PUSH_LO:
            addr_sel = 3'd5;
        S_JSR_JUMP:
            addr_sel = 3'd0;
        S_RTS_PULL_LO_WAIT, S_RTS_PULL_LO,
        S_RTS_PULL_HI_WAIT, S_RTS_PULL_HI,
        S_RTS_INC:
            addr_sel = 3'd5;
        S_RTI_PULL_SR_WAIT,  S_RTI_PULL_SR,
        S_RTI_PULL_PCL_WAIT, S_RTI_PULL_PCL,
        S_RTI_PULL_PCH_WAIT, S_RTI_PULL_PCH:
            addr_sel = 3'd5;
        // BRK: pushes use stack; vector reads use addr_sel=3 (IRQ vector $FFFE/$FFFF)
        S_BRK_PUSH_PCH, S_BRK_PUSH_PCL, S_BRK_PUSH_SR:
            addr_sel = 3'd5;
        S_BRK_VEC_LO_WAIT, S_BRK_VEC_LO:
            addr_sel = 3'd3;   // $FFFE  (top-level decodes LO vs HI by state)
        S_BRK_VEC_HI_WAIT, S_BRK_VEC_HI:
            addr_sel = 3'd3;   // $FFFF
        // JMP indirect
        S_JMP_IND_LO_WAIT, S_JMP_IND_LO:
            addr_sel = 3'd1;
        S_JMP_IND_HI_WAIT, S_JMP_IND_HI:
            addr_sel = 3'd2;
        S_FETCH, S_FETCH_WAIT, S_FETCH2,
        S_OPERAND_LO, S_OPERAND_WAIT, S_OPERAND_HI:
            addr_sel = 3'd0;
        S_WRITEBACK_WAIT, S_WRITEBACK,
        S_PTR_LO_WAIT, S_PTR_LO,
        S_RMW_WAIT, S_RMW_READ, S_RMW_WRITE:
            addr_sel = 3'd1;
        S_PTR_HI_WAIT, S_PTR_HI:
            addr_sel = 3'd2;
        S_INDIRECT_WAIT, S_INDIRECT_EXEC:
            addr_sel = 3'd4;
        S_RESET_VEC_LO_WAIT, S_RESET_VEC_LO,
        S_RESET_VEC_HI_WAIT, S_RESET_VEC_HI:
            addr_sel = 3'd3;
        S_PUSH_WAIT, S_PUSH_EXEC,
        S_PULL_WAIT, S_PULL_EXEC:
            addr_sel = 3'd5;
        S_STORE_WAIT, S_STORE_EXEC:
            addr_sel = 3'd1;
        S_STORE_IND_WAIT, S_STORE_IND_EXEC:
            addr_sel = 3'd4;
        default:
            addr_sel = 3'd0;
    endcase
end

endmodule