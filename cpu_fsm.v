module cpu_fsm (
    input        clk,
    input        reset,
    input  [7:0] data_in,
    input  [1:0] extra_cycles_in,
    input  [3:0] alu_op_in,
    input  [1:0] dest_reg_in,
    input  [3:0] addr_mode_in,

    output reg [15:0] PC,
    output reg [7:0]  inst_reg,
    output reg [7:0]  accum,
    output reg [7:0]  X,
    output reg [7:0]  Y,
    output reg [7:0]  s_pointer,
    output reg [7:0]  s_reg,

    output reg [7:0]  operand_lo,
    output reg [7:0]  operand_hi,

    output reg [2:0]  bus_sel,
    output reg        read_write_n,
    output reg [2:0]  addr_sel,
    output reg [7:0]  ptr_lo,
    output reg [7:0]  ptr_hi
);

// ── State encoding ────────────────────────────────────────────
reg [3:0] state;
localparam S_FETCH         = 4'd0,
           S_FETCH2        = 4'd1,
           S_DECODE        = 4'd2,
           S_EXECUTE       = 4'd3,
           S_WRITEBACK     = 4'd4,
           S_OPERAND_LO    = 4'd5,
           S_OPERAND_HI    = 4'd6,
           S_FETCH_WAIT    = 4'd7,
           S_OPERAND_WAIT  = 4'd8,
           S_PTR_LO        = 4'd9,
           S_PTR_LO_WAIT   = 4'd10,
           S_PTR_HI        = 4'd11,
           S_PTR_HI_WAIT   = 4'd12,
           S_INDIRECT_EXEC = 4'd13,
           S_INDIRECT_WAIT = 4'd14;

// ── Address select encoding ───────────────────────────────────
localparam ADDR_PC    = 3'd0,
           ADDR_OP    = 3'd1,
           ADDR_STACK = 3'd2,
           ADDR_VEC   = 3'd3,
           ADDR_PTR   = 3'd4;

// ── ALU / dest / mode localparams ────────────────────────────
localparam ALU_PASS = 4'd0,
           ALU_ADD  = 4'd1,
           ALU_SUB  = 4'd2,
			  ALU_AND  = 4'd3;

localparam DEST_A = 2'd0,
           DEST_X = 2'd1,
           DEST_Y = 2'd2;

localparam MODE_IMPLICIT   = 4'd0,
           MODE_IMMEDIATE  = 4'd1,
           MODE_ZEROPAGE   = 4'd2,
           MODE_ABSOLUTE   = 4'd3,
           MODE_ZEROPAGE_X = 4'd4,
           MODE_ABSOLUTE_X = 4'd5,
           MODE_ABSOLUTE_Y = 4'd6,
           MODE_INDIRECT_X = 4'd7,
           MODE_INDIRECT_Y = 4'd8;

// ── Internal registers ────────────────────────────────────────
reg [7:0] result;
reg [8:0] full_result;
reg [1:0] latched_extra_cycles;

// ── ALU task — used in all three execute states ───────────────
// operand is passed in; accum and s_reg[0] are read from current state
task do_alu;
    input [7:0] operand;
    begin
        case (alu_op_in)
            ALU_PASS: full_result = {1'b0, operand};
            ALU_ADD:  full_result = {1'b0, accum} + {1'b0, operand} + {8'h00, s_reg[0]};
            ALU_SUB:  full_result = {1'b0, accum} - {1'b0, operand};
            ALU_AND:  full_result = {1'b0, accum & operand};   // ← add this
            default:  full_result = {1'b0, operand};
        endcase
        result = full_result[7:0];

        case (dest_reg_in)
            DEST_A: accum <= result;
            DEST_X: X     <= result;
            DEST_Y: Y     <= result;
        endcase

        s_reg[0] <= (alu_op_in == ALU_ADD) ? full_result[8] : 1'b0;
        s_reg[1] <= (result == 8'h00);
        s_reg[6] <= (alu_op_in == ALU_ADD) ?
                    (~(accum[7] ^ operand[7]) & (accum[7] ^ full_result[7])) : 1'b0;
        s_reg[7] <= full_result[7];
    end
endtask

// ── Sequential FSM ────────────────────────────────────────────
always @(posedge clk) begin
    if (reset) begin
        state                <= S_FETCH;
        PC                   <= 16'hFFFC;
        accum                <= 8'h00;
        X                    <= 8'h05;
        Y                    <= 8'h03;
        s_pointer            <= 8'hFD;
        inst_reg             <= 8'h00;
        s_reg                <= 8'h00;
        operand_lo           <= 8'h00;
        operand_hi           <= 8'h00;
        latched_extra_cycles <= 2'd0;
        result               <= 8'h00;
        full_result          <= 9'h000;
        ptr_lo               <= 8'h00;
        ptr_hi               <= 8'h00;
    end else begin
        case (state)

            S_FETCH: begin
                state <= S_FETCH_WAIT;
            end

            S_FETCH_WAIT: begin
                state <= S_FETCH2;
            end

            S_FETCH2: begin
                inst_reg <= data_in;
                PC       <= PC + 1;
                state    <= S_DECODE;
            end

            S_DECODE: begin
                latched_extra_cycles <= extra_cycles_in;
                if (extra_cycles_in > 2'd0)
                    state <= S_OPERAND_LO;
                else
                    state <= S_EXECUTE;
            end

            S_OPERAND_LO: begin
                operand_lo <= data_in;
                PC         <= PC + 1;
                if (latched_extra_cycles >= 2'd3)
                    state <= S_OPERAND_WAIT;
                else
                    state <= S_EXECUTE;
            end

            S_OPERAND_WAIT: begin
                state <= S_OPERAND_HI;
            end

            S_OPERAND_HI: begin
                operand_hi <= data_in;
                PC         <= PC + 1;
                state      <= S_EXECUTE;
            end

            // ── EXECUTE ───────────────────────────────────────
            S_EXECUTE: begin
                case (addr_mode_in)
                    MODE_IMMEDIATE: begin
                        do_alu(operand_lo);
                        state <= S_FETCH;
                    end
                    MODE_ZEROPAGE,
                    MODE_ABSOLUTE,
                    MODE_ZEROPAGE_X,
                    MODE_ABSOLUTE_X,
                    MODE_ABSOLUTE_Y: begin
                        state <= S_WRITEBACK;
                    end
                    MODE_INDIRECT_X,
                    MODE_INDIRECT_Y: begin
                        state <= S_PTR_LO_WAIT;
                    end
                    default: state <= S_FETCH;
                endcase
            end

            // ── WRITEBACK (memory-addressed modes) ───────────
            S_WRITEBACK: begin
                do_alu(data_in);
                state <= S_FETCH;
            end

            // ── INDIRECT pointer fetch sequence ──────────────
            S_PTR_LO_WAIT: begin
                state <= S_PTR_LO;
            end

            S_PTR_LO: begin
                ptr_lo <= data_in;
                state  <= S_PTR_HI_WAIT;
            end

            S_PTR_HI_WAIT: begin
                state <= S_PTR_HI;
            end

            S_PTR_HI: begin
                ptr_hi <= data_in;
                state  <= S_INDIRECT_WAIT;
            end

            S_INDIRECT_WAIT: begin
                state <= S_INDIRECT_EXEC;
            end

            // ── INDIRECT EXEC (final memory value ready) ─────
            S_INDIRECT_EXEC: begin
                do_alu(data_in);
                state <= S_FETCH;
            end

            default: state <= S_FETCH;
        endcase
    end
end

// ── Combinational outputs ─────────────────────────────────────
always @(*) begin
    bus_sel      = 3'b000;
    read_write_n = 1'b1;
    addr_sel     = ADDR_PC;

    case (state)
        S_FETCH,
        S_FETCH_WAIT,
        S_FETCH2,
        S_DECODE,
        S_OPERAND_LO,
        S_OPERAND_WAIT,
        S_OPERAND_HI: begin
            addr_sel     = ADDR_PC;
            read_write_n = 1'b1;
        end

        S_EXECUTE: begin
            case (addr_mode_in)
                MODE_ZEROPAGE,
                MODE_ABSOLUTE,
                MODE_ZEROPAGE_X,
                MODE_ABSOLUTE_X,
                MODE_ABSOLUTE_Y,
                MODE_INDIRECT_X,
                MODE_INDIRECT_Y: begin
                    addr_sel     = ADDR_OP;
                    read_write_n = 1'b1;
                end
                default: begin
                    addr_sel     = ADDR_PC;
                    read_write_n = 1'b1;
                end
            endcase
        end

        S_WRITEBACK: begin
            addr_sel     = ADDR_OP;
            read_write_n = 1'b1;
        end

        S_PTR_LO_WAIT,
        S_PTR_LO: begin
            addr_sel     = ADDR_OP;
            read_write_n = 1'b1;
        end

        S_PTR_HI_WAIT,
        S_PTR_HI: begin
            addr_sel     = ADDR_PTR;
            read_write_n = 1'b1;
        end

        S_INDIRECT_WAIT,
        S_INDIRECT_EXEC: begin
            addr_sel     = ADDR_PTR;
            read_write_n = 1'b1;
        end

    endcase
end

endmodule