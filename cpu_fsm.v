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
localparam S_FETCH            = 5'd0,
           S_FETCH_WAIT       = 5'd7,
           S_FETCH2           = 5'd1,
           S_DECODE           = 5'd2,
           S_OPERAND_LO       = 5'd5,
           S_OPERAND_WAIT     = 5'd8,
           S_OPERAND_HI       = 5'd6,
           S_EXECUTE          = 5'd3,
           // *** NEW: wait state so RAM output is valid before S_WRITEBACK ***
           S_WRITEBACK_WAIT   = 5'd15,
           S_WRITEBACK        = 5'd4,
           S_PTR_LO_WAIT      = 5'd10,
           S_PTR_LO           = 5'd9,
           S_PTR_HI_WAIT      = 5'd12,
           S_PTR_HI           = 5'd11,
           S_INDIRECT_WAIT    = 5'd14,
           S_INDIRECT_EXEC    = 5'd13,
           S_RESET_VEC_LO_WAIT = 5'd25,
           S_RESET_VEC_LO     = 5'd26,
           S_RESET_VEC_HI_WAIT = 5'd27,
           S_RESET_VEC_HI     = 5'd28;

task do_alu;
    input [7:0] operand;
    reg [8:0] full_res;
    reg [7:0] res;
    begin
        if (alu_op_in == 4'd6) begin // CMP
            full_res = {1'b0, accum} - {1'b0, operand};
            res = full_res[7:0];
            // C=1 if accum >= operand (no borrow), Z=1 if equal, N = result[7]
            s_reg[0] <= (accum >= operand); // Carry
            s_reg[1] <= (accum == operand); // Zero
            s_reg[7] <= res[7];             // Negative
        end else begin
            case (alu_op_in)
                4'd0: full_res = {1'b0, operand};                                          // PASS
                4'd1: full_res = {1'b0, accum} + {1'b0, operand} + {8'h00, s_reg[0]};     // ADC
                4'd3: full_res = {1'b0, accum & operand};                                  // AND
                default: full_res = {1'b0, operand};
            endcase
            res = full_res[7:0];
            if (dest_reg_in == 2'd0) accum <= res;
            if (dest_reg_in == 2'd1) X     <= res;
            if (dest_reg_in == 2'd2) Y     <= res;

            s_reg[1] <= (res == 8'h00);
            s_reg[7] <= res[7];
            if (alu_op_in == 4'd1) s_reg[0] <= full_res[8];
        end
    end
endtask

always @(posedge clk) begin
    if (reset) begin
        state     <= S_RESET_VEC_LO_WAIT;
        PC        <= 16'hFFFC;
        accum     <= 0; X <= 0; Y <= 0;
        s_reg     <= 0;
        s_pointer <= 8'hFD;
    end else begin
        case (state)
            // ---------------------------------------------------------------
            // Fetch: 3 states so synchronous RAM has time to respond
            // ---------------------------------------------------------------
            S_FETCH:      state <= S_FETCH_WAIT;   // present PC to address bus
            S_FETCH_WAIT: state <= S_FETCH2;        // RAM latches address, data on its way
            S_FETCH2: begin                          // data_in now valid
                inst_reg <= data_in;
                PC       <= PC + 1;
                state    <= S_DECODE;
            end

            // ---------------------------------------------------------------
            // Decode
            // ---------------------------------------------------------------
            S_DECODE:
                state <= (extra_cycles_in > 0) ? S_OPERAND_LO : S_EXECUTE;

            // ---------------------------------------------------------------
            // Operand fetch (1 or 2 bytes)
            // ---------------------------------------------------------------
            S_OPERAND_LO: begin
                operand_lo <= data_in;
                PC         <= PC + 1;
                // extra_cycles >= 3 means we need a second operand byte (ABS modes)
                state      <= (extra_cycles_in >= 3) ? S_OPERAND_WAIT : S_EXECUTE;
            end
            S_OPERAND_WAIT: state <= S_OPERAND_HI;
            S_OPERAND_HI: begin
                operand_hi <= data_in;
                PC         <= PC + 1;
                state      <= S_EXECUTE;
            end

            // ---------------------------------------------------------------
            // Execute
            // ---------------------------------------------------------------
            S_EXECUTE: begin
                if (addr_mode_in == 4'd1) begin            // Immediate
                    do_alu(operand_lo);
                    state <= S_FETCH;
                end else if (addr_mode_in == 4'd0) begin   // Implicit
                    if (inst_reg == 8'h38) s_reg[0] <= 1'b1; // SEC
                    if (inst_reg == 8'h18) s_reg[0] <= 1'b0; // CLC
                    state <= S_FETCH;
					  end else if (inst_reg == 8'h4C) begin  // JMP Absolute
						 PC    <= {operand_hi, operand_lo};
						 state <= S_FETCH;
                end else begin
                    // For indirect modes go fetch the pointer; otherwise
                    // present effective address and wait one cycle for RAM.
                    state <= (addr_mode_in >= 4'd7) ? S_PTR_LO_WAIT : S_WRITEBACK_WAIT;
                end
            end

            // *** NEW wait state: effective address is on bus, wait for RAM ***
            S_WRITEBACK_WAIT: state <= S_WRITEBACK;

            S_WRITEBACK: begin
                do_alu(data_in);
                state <= S_FETCH;
            end

            // ---------------------------------------------------------------
            // Indirect addressing (pointer fetch)
            // ---------------------------------------------------------------
            S_PTR_LO_WAIT: state <= S_PTR_LO;
            S_PTR_LO: begin ptr_lo <= data_in; state <= S_PTR_HI_WAIT; end
            S_PTR_HI_WAIT: state <= S_PTR_HI;
            S_PTR_HI: begin ptr_hi <= data_in; state <= S_INDIRECT_WAIT; end
            S_INDIRECT_WAIT: state <= S_INDIRECT_EXEC;
            S_INDIRECT_EXEC: begin do_alu(data_in); state <= S_FETCH; end

            // ---------------------------------------------------------------
            // Reset vector read
            // ---------------------------------------------------------------
            S_RESET_VEC_LO_WAIT: state <= S_RESET_VEC_LO;
            S_RESET_VEC_LO: begin PC[7:0]  <= data_in; state <= S_RESET_VEC_HI_WAIT; end
            S_RESET_VEC_HI_WAIT: state <= S_RESET_VEC_HI;
            S_RESET_VEC_HI: begin PC[15:8] <= data_in; state <= S_FETCH; end

            default: state <= S_FETCH;
        endcase
    end
end

// -----------------------------------------------------------------------
// Combinational address-select (drives address_bus mux in top level)
// -----------------------------------------------------------------------
always @(*) begin
    case (state)
        // PC on the bus whenever we are fetching opcode or operands
        S_FETCH,
        S_FETCH_WAIT,
        S_FETCH2,
        S_OPERAND_LO,
        S_OPERAND_WAIT,
        S_OPERAND_HI:        addr_sel = 3'd0; // PC

        // Present effective address for direct memory read/write
        // S_WRITEBACK_WAIT presents the address; S_WRITEBACK reads the data
        S_WRITEBACK_WAIT,
        S_WRITEBACK,
        S_PTR_LO_WAIT:       addr_sel = 3'd1; // eff_addr

        // Pointer / indirect address
        S_PTR_HI_WAIT,
        S_INDIRECT_WAIT,
        S_INDIRECT_EXEC:     addr_sel = 3'd4; // ptr addr

        // Reset vector
        S_RESET_VEC_LO_WAIT,
        S_RESET_VEC_LO,
        S_RESET_VEC_HI_WAIT,
        S_RESET_VEC_HI:      addr_sel = 3'd3; // vector

        default:             addr_sel = 3'd0;
    endcase
end

endmodule