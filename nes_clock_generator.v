/*
 * File: nes_clock_generator.v
 * Description: Takes the 25.175 MHz master pixel clock and generates 
 * synchronous clock enable (CE) pulses for the PPU and CPU using 
 * 32-bit fractional phase accumulators.
 */

module nes_clock_generator (
    input  wire clk_25mhz,
    input  wire reset,
    
    output reg  cpu_ce,
    output reg  ppu_ce
);

    // 32-bit Phase Accumulators
    reg [31:0] cpu_acc;
    reg [31:0] ppu_acc;

    // Fractional increments calculated for 25.175 MHz base
    localparam CPU_INC = 32'd305335403; // Generates ~1.789773 MHz
    localparam PPU_INC = 32'd916006211; // Generates ~5.369318 MHz

    always @(posedge clk_25mhz or posedge reset) begin
        if (reset) begin
            cpu_acc <= 32'd0;
            ppu_acc <= 32'd0;
            cpu_ce  <= 1'b0;
            ppu_ce  <= 1'b0;
        end else begin
            // Add increments to accumulators
            {cpu_ce, cpu_acc} <= {1'b0, cpu_acc} + {1'b0, CPU_INC};
            {ppu_ce, ppu_acc} <= {1'b0, ppu_acc} + {1'b0, PPU_INC};
            
            // The carry-out bit of the addition naturally becomes the Clock Enable pulse.
            // Since it only stays high for one 25MHz cycle when rolling over, 
            // it perfectly steps the downstream modules.
        end
    end

endmodule
