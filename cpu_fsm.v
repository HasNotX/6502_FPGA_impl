module cpu_fsm (
    input        clk,
    input        reset,
    input  [7:0] data_in,
    input  [1:0] extra_cycles_in,
    input  [3:0] alu_op_in,
    input  [1:0] dest_reg_in,
    input [3:0] addr_mode_in,

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
    output reg [1:0]  addr_sel
);

// ── State encoding ────────────────────────────────────────────
reg [3:0] state;                    // expanded to 4 bits
localparam S_FETCH         = 4'd0,
           S_FETCH2        = 4'd1,
           S_DECODE        = 4'd2,
           S_EXECUTE       = 4'd3,
           S_WRITEBACK     = 4'd4,
           S_OPERAND_LO    = 4'd5,
           S_OPERAND_HI    = 4'd6,
           S_FETCH_WAIT    = 4'd7,
           S_OPERAND_WAIT  = 4'd8;  // new wait state for hi byte

// ── Address select encoding ───────────────────────────────────
localparam ADDR_PC    = 2'd0,
           ADDR_OP    = 2'd1,
           ADDR_STACK = 2'd2,
           ADDR_VEC   = 2'd3;

// ── Mirror decoder localparams ────────────────────────────────
localparam ALU_PASS = 4'd0,
           ALU_ADD  = 4'd1,
           ALU_SUB  = 4'd2;

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
reg [1:0] latched_extra_cycles;

// ── Sequential FSM ────────────────────────────────────────────
always @(posedge clk) begin
    if (reset) begin
        state                <= S_FETCH;
        PC                   <= 16'hFFFC;
        accum                <= 8'h00;
        X                    <= 8'h05;
        Y                    <= 8'h00;
        s_pointer            <= 8'hFD;
        inst_reg             <= 8'h00;
        s_reg                <= 8'h00;
        operand_lo           <= 8'h00;
        operand_hi           <= 8'h00;
        latched_extra_cycles <= 2'd0;
        result               <= 8'h00;
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
                    state <= S_OPERAND_WAIT;  // wait for RAM before hi byte
                else
                    state <= S_EXECUTE;
            end

            S_OPERAND_WAIT: begin
                state <= S_OPERAND_HI;        // RAM now has hi byte ready
            end

            S_OPERAND_HI: begin
                operand_hi <= data_in;
                PC         <= PC + 1;
                state      <= S_EXECUTE;
            end

            S_EXECUTE: begin
                case (addr_mode_in)
                    MODE_IMMEDIATE: begin
                        case (alu_op_in)
                            ALU_PASS: result = operand_lo;
                            ALU_ADD:  result = accum + operand_lo;
                            ALU_SUB:  result = accum - operand_lo;
                            default:  result = operand_lo;
                        endcase
                        case (dest_reg_in)
                            DEST_A: accum <= result;
                            DEST_X: X     <= result;
                            DEST_Y: Y     <= result;
                        endcase
                        s_reg[1] <= (result == 8'h00);
                        s_reg[7] <= result[7];
                        state <= S_FETCH;
                    end

                    MODE_ZEROPAGE,
                    MODE_ABSOLUTE,
						  MODE_ZEROPAGE_X,    // ← add these
						  MODE_ABSOLUTE_X,    // ← add these
						  MODE_ABSOLUTE_Y,
						  MODE_INDIRECT_X,
						  MODE_INDIRECT_Y: begin  // ← add these begin
                        state <= S_WRITEBACK;
                    end

                    default: state <= S_FETCH;
                endcase
            end

            S_WRITEBACK: begin
                case (alu_op_in)
                    ALU_PASS: result = data_in;
                    ALU_ADD:  result = accum + data_in;
                    ALU_SUB:  result = accum - data_in;
                    default:  result = data_in;
                endcase
                case (dest_reg_in)
                    DEST_A: accum <= result;
                    DEST_X: X     <= result;
                    DEST_Y: Y     <= result;
                endcase
                s_reg[1] <= (result == 8'h00);
                s_reg[7] <= result[7];
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

    endcase
end

endmodule