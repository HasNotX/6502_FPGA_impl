module cpu_fsm (
    input clk,
    input reset,
    input [7:0] data_in,

    // FSM outputs to top level
    output reg [15:0] PC,
    output reg [7:0]  inst_reg,
    output reg [7:0]  accum,
    output reg [7:0]  X,
    output reg [7:0]  Y,
    output reg [7:0]  s_pointer,
	 output reg [7:0] s_reg,
	 
    // Control signals
    output reg [2:0]  bus_sel,
    output reg        read_write_n,
    output reg [1:0]  addr_sel
);

// State encoding
reg [2:0] state;
localparam S_FETCH     = 3'd0,
           S_FETCH2    = 3'd1,
           S_DECODE    = 3'd2,
           S_EXECUTE   = 3'd3,
           S_WRITEBACK = 3'd4;

// Address select encoding (shared with top via output)
localparam ADDR_PC    = 2'd0,
           ADDR_OP    = 2'd1,
           ADDR_STACK = 2'd2,
           ADDR_VEC   = 2'd3;

// ── Sequential FSM ───────────────────────────────────────────────────
always @(posedge clk) begin
    if (reset) begin
        state     <= S_FETCH;
        PC        <= 16'hFFFC;
        accum     <= 8'h00;
        X         <= 8'h00;
        Y         <= 8'h00;
        s_pointer <= 8'hFD;
        inst_reg  <= 8'h00;
		  s_reg <= 8'h00;
		  
    end else begin
        case (state)
            S_FETCH: begin
                state <= S_FETCH2;
            end

            S_FETCH2: begin
                inst_reg <= data_in;
                PC       <= PC + 1;
                state    <= S_DECODE;
            end

            S_DECODE: begin
                state <= S_EXECUTE;
            end

            S_EXECUTE: begin
                state <= S_FETCH;
            end

            S_WRITEBACK: begin
                // placeholder
            end

            default: state <= S_FETCH;
        endcase
    end
end

// ── Combinational FSM outputs ────────────────────────────────────────
always @(*) begin
    // Safe defaults
    bus_sel      = 3'b000;
    read_write_n = 1'b1;
    addr_sel     = ADDR_PC;

    case (state)
        S_FETCH: begin
            addr_sel     = ADDR_PC;
            read_write_n = 1'b1;
        end

        S_FETCH2: begin
            addr_sel     = ADDR_PC;
            read_write_n = 1'b1;
        end

        S_EXECUTE: begin
            if (inst_reg == 8'hAA)      // TAX
                bus_sel = 3'b000;       // put accumulator on internal bus
        end

        S_WRITEBACK: begin
            // placeholder
        end

    endcase
end

endmodule