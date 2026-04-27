module nes_clock_generator(
    input  wire clk_25mhz,
    input  wire reset,
    output reg  cpu_ce,
    output reg  ppu_ce
);

    // 1. Generate the Base PPU Clock (5.369 MHz NTSC Target)
    reg [31:0] ppu_acc;
    localparam PPU_INC = 32'd916029601; 

    reg [1:0] cpu_div;

    always @(posedge clk_25mhz or posedge reset) begin
        if (reset) begin
            ppu_acc <= 32'd0;
            ppu_ce  <= 1'b0;
            cpu_ce  <= 1'b0;
            cpu_div <= 2'd0;
        end else begin
            // Fractional Accumulator for the PPU Phase
            {ppu_ce, ppu_acc} <= {1'b0, ppu_acc} + {1'b0, PPU_INC};

            // 2. Hard-locked 1:3 CPU Divider
            // The CPU clock enable ONLY fires strictly in phase with the PPU
            cpu_ce <= 1'b0; 
            
            if (ppu_ce) begin
                if (cpu_div == 2'd2) begin
                    cpu_div <= 2'd0;
                    cpu_ce  <= 1'b1; // Fires exactly once every 3 PPU ticks
                end else begin
                    cpu_div <= cpu_div + 2'd1;
                end
            end
        end
    end

endmodule