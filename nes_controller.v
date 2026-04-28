/*
 * File: nes_controller.v
 * Description: Cycle-accurate NES Joypad 1 Interface ($4016).
 * Handles the strobe latch and 8-bit serial shift output required by standard NES games.
 */

module nes_controller (
    input  wire       clk,
    input  wire       reset,
    
    // CPU Interface
    input  wire       ctrl_write_pulse,
    input  wire       ctrl_read_pulse,
    input  wire [7:0] cpu_data_in,
    output wire [7:0] cpu_data_out,
    
    // Physical Button States (Active High)
    // Map: {Right, Left, Down, Up, Start, Select, B, A}
    input  wire [7:0] button_state
);

    reg [7:0] shift_reg;
    reg       strobe;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            strobe    <= 1'b0;
            shift_reg <= 8'h00;
        end else begin
            // CPU writes to $4016 to control the strobe latch
            if (ctrl_write_pulse) begin
                strobe <= cpu_data_in[0];
            end

            // When strobe is high, continuously latch the physical buttons.
            // When strobe goes low, freeze the state and prepare to shift.
            if (strobe) begin
                shift_reg <= button_state;
            end else if (ctrl_read_pulse) begin
                // Shift right, padding with 0s. The LSB is sent to the CPU.
                shift_reg <= {1'b0, shift_reg[7:1]};
            end
        end
    end

    // The NES CPU expects the button state on Data Bus Bit 0.
    // The upper bits are technically open bus, but 0 is safe for compatibility.
    assign cpu_data_out = {7'b0000000, shift_reg[0]};

endmodule