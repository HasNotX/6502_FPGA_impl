/*
 * File: hex_decoder.v
 * Description: Standard 4-bit hexadecimal to 7-segment display decoder.
 * Outputs are active-low for DE-series FPGA boards.
 */

module hex_decoder (
    input  wire [3:0] hex_in,
    output reg  [6:0] segments
);

    always @(*) begin
        case (hex_in)
            // 7-segment mapping: g_f_e_d_c_b_a (0 = ON, 1 = OFF)
            4'h0: segments = 7'b1000000;
            4'h1: segments = 7'b1111001;
            4'h2: segments = 7'b0100100;
            4'h3: segments = 7'b0110000;
            4'h4: segments = 7'b0011001;
            4'h5: segments = 7'b0010010;
            4'h6: segments = 7'b0000010;
            4'h7: segments = 7'b1111000;
            4'h8: segments = 7'b0000000;
            4'h9: segments = 7'b0010000;
            4'hA: segments = 7'b0001000;
            4'hB: segments = 7'b0000011;
            4'hC: segments = 7'b1000110;
            4'hD: segments = 7'b0100001;
            4'hE: segments = 7'b0000110;
            4'hF: segments = 7'b0001110;
            default: segments = 7'b1111111; // All OFF
        endcase
    end

endmodule