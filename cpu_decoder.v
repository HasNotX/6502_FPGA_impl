module cpu_decoder (
    input      [7:0]  inst_reg,
    output reg [3:0]  addr_mode,
    output reg [1:0]  extra_cycles,
    output reg [3:0]  alu_op,
    output reg [1:0]  dest_reg
);

localparam [3:0] ALU_PASS = 0, ALU_ADD = 1, ALU_SUB = 2,
                 ALU_AND  = 3, ALU_ASL = 4, ALU_BIT = 5,
                 ALU_CMP  = 6, ALU_INC = 7, ALU_DEC = 8,
                 ALU_ORA  = 9, ALU_EOR = 10, ALU_LSR = 11,
                 ALU_ROL  = 12, ALU_ROR = 13;

localparam [1:0] DEST_A = 0, DEST_X = 1, DEST_Y = 2, DEST_NONE = 3;

localparam [3:0] MODE_IMPLICIT    = 0,  MODE_IMMEDIATE  = 1,
                 MODE_ZEROPAGE    = 2,  MODE_ABSOLUTE   = 3,
                 MODE_ZEROPAGE_X  = 4,  MODE_ABSOLUTE_X = 5,
                 MODE_ABSOLUTE_Y  = 6,  MODE_INDIRECT_X = 7,
                 MODE_INDIRECT_Y  = 8,  MODE_ACCUMULATOR= 9,
                 MODE_RELATIVE    = 10, MODE_ZEROPAGE_Y = 11,
                 MODE_INDIRECT_ABS= 12;

always @(*) begin
    addr_mode    = MODE_IMPLICIT;
    extra_cycles = 2'd0;
    alu_op       = ALU_PASS;
    dest_reg     = DEST_A;

    case (inst_reg)

        // NOP
        8'hEA: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end

        // BRK
        8'h00: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end

        // Stack ops
        8'h48: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // PHA
        8'h08: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // PHP
        8'h68: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_A;    end // PLA
        8'h28: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // PLP

        // ORA
        8'h09: begin addr_mode = MODE_IMMEDIATE;  alu_op = ALU_ORA; extra_cycles = 2'd1; end
        8'h05: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_ORA; extra_cycles = 2'd2; end
        8'h15: begin addr_mode = MODE_ZEROPAGE_X; alu_op = ALU_ORA; extra_cycles = 2'd2; end
        8'h0D: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_ORA; extra_cycles = 2'd3; end
        8'h1D: begin addr_mode = MODE_ABSOLUTE_X; alu_op = ALU_ORA; extra_cycles = 2'd3; end
        8'h19: begin addr_mode = MODE_ABSOLUTE_Y; alu_op = ALU_ORA; extra_cycles = 2'd3; end
        8'h01: begin addr_mode = MODE_INDIRECT_X; alu_op = ALU_ORA; extra_cycles = 2'd1; end
        8'h11: begin addr_mode = MODE_INDIRECT_Y; alu_op = ALU_ORA; extra_cycles = 2'd1; end

        // EOR
        8'h49: begin addr_mode = MODE_IMMEDIATE;  alu_op = ALU_EOR; extra_cycles = 2'd1; end
        8'h45: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_EOR; extra_cycles = 2'd2; end
        8'h55: begin addr_mode = MODE_ZEROPAGE_X; alu_op = ALU_EOR; extra_cycles = 2'd2; end
        8'h4D: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_EOR; extra_cycles = 2'd3; end
        8'h5D: begin addr_mode = MODE_ABSOLUTE_X; alu_op = ALU_EOR; extra_cycles = 2'd3; end
        8'h59: begin addr_mode = MODE_ABSOLUTE_Y; alu_op = ALU_EOR; extra_cycles = 2'd3; end
        8'h41: begin addr_mode = MODE_INDIRECT_X; alu_op = ALU_EOR; extra_cycles = 2'd1; end
        8'h51: begin addr_mode = MODE_INDIRECT_Y; alu_op = ALU_EOR; extra_cycles = 2'd1; end

        // AND
        8'h29: begin addr_mode = MODE_IMMEDIATE;  alu_op = ALU_AND; extra_cycles = 2'd1; end
        8'h25: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_AND; extra_cycles = 2'd2; end
        8'h35: begin addr_mode = MODE_ZEROPAGE_X; alu_op = ALU_AND; extra_cycles = 2'd2; end
        8'h2D: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_AND; extra_cycles = 2'd3; end
        8'h3D: begin addr_mode = MODE_ABSOLUTE_X; alu_op = ALU_AND; extra_cycles = 2'd3; end
        8'h39: begin addr_mode = MODE_ABSOLUTE_Y; alu_op = ALU_AND; extra_cycles = 2'd3; end
        8'h21: begin addr_mode = MODE_INDIRECT_X; alu_op = ALU_AND; extra_cycles = 2'd1; end
        8'h31: begin addr_mode = MODE_INDIRECT_Y; alu_op = ALU_AND; extra_cycles = 2'd1; end

        // ADC
        8'h69: begin addr_mode = MODE_IMMEDIATE;  alu_op = ALU_ADD; extra_cycles = 2'd1; end
        8'h65: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_ADD; extra_cycles = 2'd2; end
        8'h75: begin addr_mode = MODE_ZEROPAGE_X; alu_op = ALU_ADD; extra_cycles = 2'd2; end
        8'h6D: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_ADD; extra_cycles = 2'd3; end
        8'h7D: begin addr_mode = MODE_ABSOLUTE_X; alu_op = ALU_ADD; extra_cycles = 2'd3; end
        8'h79: begin addr_mode = MODE_ABSOLUTE_Y; alu_op = ALU_ADD; extra_cycles = 2'd3; end
        8'h61: begin addr_mode = MODE_INDIRECT_X; alu_op = ALU_ADD; extra_cycles = 2'd1; end
        8'h71: begin addr_mode = MODE_INDIRECT_Y; alu_op = ALU_ADD; extra_cycles = 2'd1; end

        // LSR
        8'h4A: begin addr_mode = MODE_ACCUMULATOR; alu_op = ALU_LSR; dest_reg = DEST_A;    end
        8'h46: begin addr_mode = MODE_ZEROPAGE;    alu_op = ALU_LSR; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h56: begin addr_mode = MODE_ZEROPAGE_X;  alu_op = ALU_LSR; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h4E: begin addr_mode = MODE_ABSOLUTE;    alu_op = ALU_LSR; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'h5E: begin addr_mode = MODE_ABSOLUTE_X;  alu_op = ALU_LSR; dest_reg = DEST_NONE; extra_cycles = 2'd3; end

        // ROL
        8'h2A: begin addr_mode = MODE_ACCUMULATOR; alu_op = ALU_ROL; dest_reg = DEST_A;    end
        8'h26: begin addr_mode = MODE_ZEROPAGE;    alu_op = ALU_ROL; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h36: begin addr_mode = MODE_ZEROPAGE_X;  alu_op = ALU_ROL; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h2E: begin addr_mode = MODE_ABSOLUTE;    alu_op = ALU_ROL; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'h3E: begin addr_mode = MODE_ABSOLUTE_X;  alu_op = ALU_ROL; dest_reg = DEST_NONE; extra_cycles = 2'd3; end

        // ROR
        8'h6A: begin addr_mode = MODE_ACCUMULATOR; alu_op = ALU_ROR; dest_reg = DEST_A;    end
        8'h66: begin addr_mode = MODE_ZEROPAGE;    alu_op = ALU_ROR; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h76: begin addr_mode = MODE_ZEROPAGE_X;  alu_op = ALU_ROR; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h6E: begin addr_mode = MODE_ABSOLUTE;    alu_op = ALU_ROR; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'h7E: begin addr_mode = MODE_ABSOLUTE_X;  alu_op = ALU_ROR; dest_reg = DEST_NONE; extra_cycles = 2'd3; end

        // INC
        8'hE6: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_INC; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hF6: begin addr_mode = MODE_ZEROPAGE_X; alu_op = ALU_INC; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hEE: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_INC; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'hFE: begin addr_mode = MODE_ABSOLUTE_X; alu_op = ALU_INC; dest_reg = DEST_NONE; extra_cycles = 2'd3; end

        // DEC
        8'hC6: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_DEC; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hD6: begin addr_mode = MODE_ZEROPAGE_X; alu_op = ALU_DEC; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hCE: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_DEC; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'hDE: begin addr_mode = MODE_ABSOLUTE_X; alu_op = ALU_DEC; dest_reg = DEST_NONE; extra_cycles = 2'd3; end

        // JMP absolute
        8'h4C: begin addr_mode = MODE_ABSOLUTE;      extra_cycles = 2'd3; dest_reg = DEST_NONE; end
        // JMP indirect
        8'h6C: begin addr_mode = MODE_INDIRECT_ABS;  extra_cycles = 2'd3; dest_reg = DEST_NONE; end

        // RTI
        8'h40: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end

        // INX / DEX / INY / DEY
        8'hE8: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_X; alu_op = ALU_INC; end
        8'hCA: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_X; alu_op = ALU_DEC; end
        8'hC8: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_Y; alu_op = ALU_INC; end
        8'h88: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_Y; alu_op = ALU_DEC; end

        // LDA
        8'hA9: begin addr_mode = MODE_IMMEDIATE;  extra_cycles = 2'd1; dest_reg = DEST_A; end
        8'hA5: begin addr_mode = MODE_ZEROPAGE;   extra_cycles = 2'd2; dest_reg = DEST_A; end
        8'hAD: begin addr_mode = MODE_ABSOLUTE;   extra_cycles = 2'd3; dest_reg = DEST_A; end
        8'hB5: begin addr_mode = MODE_ZEROPAGE_X; extra_cycles = 2'd2; dest_reg = DEST_A; end
        8'hBD: begin addr_mode = MODE_ABSOLUTE_X; extra_cycles = 2'd3; dest_reg = DEST_A; end
        8'hB9: begin addr_mode = MODE_ABSOLUTE_Y; extra_cycles = 2'd3; dest_reg = DEST_A; end
        8'hA1: begin addr_mode = MODE_INDIRECT_X; extra_cycles = 2'd1; dest_reg = DEST_A; end
        8'hB1: begin addr_mode = MODE_INDIRECT_Y; extra_cycles = 2'd1; dest_reg = DEST_A; end

        // LDX
        8'hA2: begin addr_mode = MODE_IMMEDIATE;  extra_cycles = 2'd1; dest_reg = DEST_X; end
        8'hA6: begin addr_mode = MODE_ZEROPAGE;   extra_cycles = 2'd2; dest_reg = DEST_X; end
        8'hB6: begin addr_mode = MODE_ZEROPAGE_Y; extra_cycles = 2'd2; dest_reg = DEST_X; end
        8'hAE: begin addr_mode = MODE_ABSOLUTE;   extra_cycles = 2'd3; dest_reg = DEST_X; end
        8'hBE: begin addr_mode = MODE_ABSOLUTE_Y; extra_cycles = 2'd3; dest_reg = DEST_X; end

        // LDY
        8'hA0: begin addr_mode = MODE_IMMEDIATE;  extra_cycles = 2'd1; dest_reg = DEST_Y; end
        8'hA4: begin addr_mode = MODE_ZEROPAGE;   extra_cycles = 2'd2; dest_reg = DEST_Y; end
        8'hB4: begin addr_mode = MODE_ZEROPAGE_X; extra_cycles = 2'd2; dest_reg = DEST_Y; end
        8'hAC: begin addr_mode = MODE_ABSOLUTE;   extra_cycles = 2'd3; dest_reg = DEST_Y; end
        8'hBC: begin addr_mode = MODE_ABSOLUTE_X; extra_cycles = 2'd3; dest_reg = DEST_Y; end

        // Register Transfers
        8'hAA: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_X; end
        8'hA8: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_Y; end
        8'h8A: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_A; end
        8'h98: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_A; end
        8'hBA: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_X; end
        8'h9A: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end

        // CMP
        8'hC9: begin addr_mode = MODE_IMMEDIATE;  alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd1; end
        8'hC5: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hD5: begin addr_mode = MODE_ZEROPAGE_X; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hCD: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'hDD: begin addr_mode = MODE_ABSOLUTE_X; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'hD9: begin addr_mode = MODE_ABSOLUTE_Y; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'hC1: begin addr_mode = MODE_INDIRECT_X; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd1; end
        8'hD1: begin addr_mode = MODE_INDIRECT_Y; alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd1; end

        // Status flags
        8'h18: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // CLC
        8'h38: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // SEC
        8'h58: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // CLI
        8'h78: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // SEI
        8'hD8: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // CLD
        8'hF8: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // SED
        8'hB8: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end // CLV

        // CPX
        8'hE0: begin addr_mode = MODE_IMMEDIATE;  alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd1; end
        8'hE4: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hEC: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd3; end

        // CPY
        8'hC0: begin addr_mode = MODE_IMMEDIATE;  alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd1; end
        8'hC4: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'hCC: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_CMP; dest_reg = DEST_NONE; extra_cycles = 2'd3; end

        // STA
        8'h85: begin addr_mode = MODE_ZEROPAGE;   dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h95: begin addr_mode = MODE_ZEROPAGE_X; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h8D: begin addr_mode = MODE_ABSOLUTE;   dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'h9D: begin addr_mode = MODE_ABSOLUTE_X; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'h99: begin addr_mode = MODE_ABSOLUTE_Y; dest_reg = DEST_NONE; extra_cycles = 2'd3; end
        8'h81: begin addr_mode = MODE_INDIRECT_X; dest_reg = DEST_NONE; extra_cycles = 2'd1; end
        8'h91: begin addr_mode = MODE_INDIRECT_Y; dest_reg = DEST_NONE; extra_cycles = 2'd1; end

        // STX
        8'h86: begin addr_mode = MODE_ZEROPAGE;   dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h96: begin addr_mode = MODE_ZEROPAGE_Y; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h8E: begin addr_mode = MODE_ABSOLUTE;   dest_reg = DEST_NONE; extra_cycles = 2'd3; end

        // STY
        8'h84: begin addr_mode = MODE_ZEROPAGE;   dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h94: begin addr_mode = MODE_ZEROPAGE_X; dest_reg = DEST_NONE; extra_cycles = 2'd2; end
        8'h8C: begin addr_mode = MODE_ABSOLUTE;   dest_reg = DEST_NONE; extra_cycles = 2'd3; end

        // BIT
        8'h24: begin addr_mode = MODE_ZEROPAGE; extra_cycles = 2'd2; alu_op = ALU_BIT; dest_reg = DEST_NONE; end
        8'h2C: begin addr_mode = MODE_ABSOLUTE; extra_cycles = 2'd3; alu_op = ALU_BIT; dest_reg = DEST_NONE; end

        // BRANCHES
        8'h90: begin addr_mode = MODE_RELATIVE; extra_cycles = 2'd1; alu_op = ALU_PASS; end // BCC
        8'hB0: begin addr_mode = MODE_RELATIVE; extra_cycles = 2'd1; alu_op = ALU_PASS; end // BCS
        8'hF0: begin addr_mode = MODE_RELATIVE; extra_cycles = 2'd1; alu_op = ALU_PASS; end // BEQ
        8'hD0: begin addr_mode = MODE_RELATIVE; extra_cycles = 2'd1; alu_op = ALU_PASS; end // BNE
        8'h30: begin addr_mode = MODE_RELATIVE; extra_cycles = 2'd1; alu_op = ALU_PASS; end // BMI
        8'h10: begin addr_mode = MODE_RELATIVE; extra_cycles = 2'd1; alu_op = ALU_PASS; end // BPL
        8'h50: begin addr_mode = MODE_RELATIVE; extra_cycles = 2'd1; alu_op = ALU_PASS; end // BVC
        8'h70: begin addr_mode = MODE_RELATIVE; extra_cycles = 2'd1; alu_op = ALU_PASS; end // BVS

        // ASL
        8'h0A: begin addr_mode = MODE_ACCUMULATOR; extra_cycles = 2'd0; alu_op = ALU_ASL; dest_reg = DEST_A;    end
        8'h06: begin addr_mode = MODE_ZEROPAGE;    extra_cycles = 2'd2; alu_op = ALU_ASL; dest_reg = DEST_NONE; end
        8'h16: begin addr_mode = MODE_ZEROPAGE_X;  extra_cycles = 2'd2; alu_op = ALU_ASL; dest_reg = DEST_NONE; end
        8'h0E: begin addr_mode = MODE_ABSOLUTE;    extra_cycles = 2'd3; alu_op = ALU_ASL; dest_reg = DEST_NONE; end
        8'h1E: begin addr_mode = MODE_ABSOLUTE_X;  extra_cycles = 2'd3; alu_op = ALU_ASL; dest_reg = DEST_NONE; end

        // SBC
        8'hE9: begin addr_mode = MODE_IMMEDIATE;  alu_op = ALU_SUB; extra_cycles = 2'd1; dest_reg = DEST_A; end
        8'hE5: begin addr_mode = MODE_ZEROPAGE;   alu_op = ALU_SUB; extra_cycles = 2'd2; dest_reg = DEST_A; end
        8'hF5: begin addr_mode = MODE_ZEROPAGE_X; alu_op = ALU_SUB; extra_cycles = 2'd2; dest_reg = DEST_A; end
        8'hED: begin addr_mode = MODE_ABSOLUTE;   alu_op = ALU_SUB; extra_cycles = 2'd3; dest_reg = DEST_A; end
        8'hFD: begin addr_mode = MODE_ABSOLUTE_X; alu_op = ALU_SUB; extra_cycles = 2'd3; dest_reg = DEST_A; end
        8'hF9: begin addr_mode = MODE_ABSOLUTE_Y; alu_op = ALU_SUB; extra_cycles = 2'd3; dest_reg = DEST_A; end
        8'hE1: begin addr_mode = MODE_INDIRECT_X; alu_op = ALU_SUB; extra_cycles = 2'd1; dest_reg = DEST_A; end
        8'hF1: begin addr_mode = MODE_INDIRECT_Y; alu_op = ALU_SUB; extra_cycles = 2'd1; dest_reg = DEST_A; end

        // JSR
        8'h20: begin addr_mode = MODE_ABSOLUTE; extra_cycles = 2'd3; dest_reg = DEST_NONE; end

        // RTS
        8'h60: begin addr_mode = MODE_IMPLICIT; dest_reg = DEST_NONE; end

        default: begin dest_reg = DEST_NONE; end
    endcase
end
endmodule