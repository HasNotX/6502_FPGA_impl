module cpu_decoder (
    input      [7:0]  inst_reg,
    input      [7:0]  operand_lo,    // ← first  operand byte fetched by FSM
    input      [7:0]  operand_hi,    // ← second operand byte fetched by FSM

    output reg [1:0]  addr_mode,
    output reg [1:0]  extra_cycles,
    output reg [3:0]  alu_op,
    output reg [1:0]  dest_reg,
    output reg        is_store,
    output reg [15:0] effective_addr,
    output reg        addr_ready
);

// ── Addressing mode encoding ─────────────────────────────────────────
localparam MODE_IMPLICIT  = 2'd0,
           MODE_IMMEDIATE = 2'd1,
           MODE_ZEROPAGE  = 2'd2,
           MODE_ABSOLUTE  = 2'd3;

// ── ALU operation encoding ───────────────────────────────────────────
localparam ALU_PASS = 4'd0,    // just pass value through (used by LDA)
           ALU_ADD  = 4'd1,    // ADC
           ALU_SUB  = 4'd2;    // SBC

// ── Destination register encoding ───────────────────────────────────
localparam DEST_A = 2'd0,
           DEST_X = 2'd1,
           DEST_Y = 2'd2;

// ── Decoder logic ────────────────────────────────────────────────────
always @(*) begin
    // Safe defaults — prevents accidental latches
    addr_mode    = MODE_IMPLICIT;
    extra_cycles = 2'd0;
    alu_op       = ALU_PASS;
    dest_reg     = DEST_A;
    is_store     = 1'b0;

    case (inst_reg)

        8'hA9: begin   // LDA #immediate        e.g. LDA #$42
            addr_mode    = MODE_IMMEDIATE;
            extra_cycles = 2'd1;   // 1 more fetch for the operand byte
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end

        8'hA5: begin   // LDA zero page         e.g. LDA $10
            addr_mode    = MODE_ZEROPAGE;
            extra_cycles = 2'd2;   // fetch zp address, then fetch value at that address
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end

        8'hAD: begin   // LDA absolute          e.g. LDA $1234
            addr_mode    = MODE_ABSOLUTE;
            extra_cycles = 2'd3;   // fetch low byte, fetch high byte, fetch value
            alu_op       = ALU_PASS;
            dest_reg     = DEST_A;
            is_store     = 1'b0;
        end

        // default is already set above — unknown opcode does nothing
    endcase
end

// Addressing Mode Logic______________________

always @(*) begin
    effective_addr = 16'h0000;
    addr_ready     = 1'b0;

    case (addr_mode)

        MODE_IMMEDIATE: begin
            // No address needed at all — the operand IS the value
            // The FSM just reads the next byte directly off the data bus
            effective_addr = 16'h0000;   // unused
            addr_ready     = 1'b1;
        end

        MODE_ZEROPAGE: begin
            // Operand byte gives you the low byte of address
            // High byte is always 0x00
            // e.g. LDA $10 → read from address 0x0010
            effective_addr = {8'h00, operand_lo};   // add operand_lo to port list
            addr_ready     = 1'b1;
        end

        MODE_ABSOLUTE: begin
            // Two operand bytes build the full 16-bit address
            // First fetch = low byte, second fetch = high byte
            // e.g. LDA $1234 → low=$34, high=$12 → address=0x1234
            effective_addr = {operand_hi, operand_lo};  // add both to port list
            addr_ready     = 1'b1;
        end

        MODE_IMPLICIT: begin
            // No address needed — instruction operates on registers only
            // e.g. TAX just moves A to X, no memory involved
            effective_addr = 16'h0000;
            addr_ready     = 1'b0;
        end

    endcase
end

endmodule